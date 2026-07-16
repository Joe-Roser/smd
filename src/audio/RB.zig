const std = @import("std");

const posix = std.posix;
const linux = std.os.linux;
const Io = std.Io;

const RingBuffer = @This();

read_idx: std.atomic.Value(u32),
write_idx: std.atomic.Value(u32),

capacity: u32,
mask: u32,
ptr: [*]f32,

pub fn init(num_pages: usize) !RingBuffer {
    std.debug.assert(std.math.isPowerOfTwo(num_pages));

    const page_size = std.heap.pageSize();
    const bytes = num_pages * page_size;

    const total = bytes * 2;

    const reserve = try posix.mmap(
        null,
        total,
        .{},
        .{ .ANONYMOUS = true, .TYPE = .PRIVATE },
        -1,
        0,
    );
    errdefer _ = linux.munmap(reserve.ptr, total);

    const fd = try posix.memfd_create("ring", 0);
    defer _ = linux.close(fd);

    if (linux.ftruncate(fd, @intCast(bytes)) != 0)
        return error.FailedTruncate;

    var res = try posix.mmap(
        reserve.ptr,
        bytes,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    );

    res = try posix.mmap(
        @ptrFromInt(@intFromPtr(reserve.ptr) + bytes),
        bytes,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    );

    const cap = @as(u32, @intCast(bytes)) / @sizeOf(f32);

    const rb: RingBuffer = .{
        .read_idx = .init(0),
        .write_idx = .init(0),

        .capacity = cap,
        .mask = cap - 1,
        .ptr = @ptrCast(reserve.ptr),
    };

    return rb;
}
pub fn deinit(self: *RingBuffer) void {
    _ = linux.munmap(@ptrCast(self.ptr), self.capacity * @sizeOf(f32) * 2);
}

pub fn read(self: *RingBuffer, dst: []f32) u32 {
    const write_idx = self.write_idx.load(.acquire);
    const read_idx = self.read_idx.load(.monotonic);
    const available = write_idx -% read_idx;
    const count = @min(available, dst.len);

    if (count == 0) return 0;

    const offset = read_idx & self.mask;

    @memcpy(dst[0..count], self.ptr[offset .. offset + count]);
    self.read_idx.store(read_idx +% count, .release);

    return count;
}
pub inline fn write(self: *RingBuffer, src: []const f32) u32 {
    const read_idx = self.read_idx.load(.acquire);
    const write_idx = self.write_idx.load(.monotonic);
    const free_size = self.capacity - (write_idx -% read_idx);
    const count = @min(free_size, src.len);

    if (count == 0) return 0;

    const offset = write_idx & self.mask;

    @memcpy(self.ptr[offset .. offset + count], src[0..count]);
    self.write_idx.store(write_idx +% count, .release);

    return count;
}

pub inline fn fill(self: *RingBuffer) u32 {
    const w = self.write_idx.load(.monotonic);
    const r = self.read_idx.load(.monotonic);
    return w -% r;
}

pub inline fn reset(self: *RingBuffer) void {
    self.read_idx.store(0, .seq_cst);
    self.write_idx.store(0, .seq_cst);
}
