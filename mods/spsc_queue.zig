const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const ring_buffer = extern struct {
    const cache_line_size = std.atomic.cache_line;
    const padding = [cache_line_size - @sizeOf(std.atomic.Value(u32))]u8;

    read_idx: std.atomic.Value(u32),

    write_idx: std.atomic.Value(u32),

    capacity: u32,
    mask: u32,
    ptr: [*]f32,
};

pub fn ring_init(num_pages: usize) !ring_buffer {
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

    const rb: ring_buffer = .{
        .read_idx = .init(0),
        .write_idx = .init(0),

        .capacity = cap,
        .mask = cap - 1,
        .ptr = @ptrCast(reserve.ptr),
    };

    return rb;
}

pub export fn ring_deinit(self: *ring_buffer) void {
    _ = linux.munmap(@ptrCast(self.ptr), self.capacity * @sizeOf(f32) * 2);
}

pub export fn ring_write(rb: *ring_buffer, src: [*]const f32, len: u32) u32 {
    const read = rb.read_idx.load(.acquire);
    const write = rb.write_idx.load(.monotonic);
    const free_size = rb.capacity - (write -% read);
    const count = @min(free_size, len);

    if (count == 0) return 0;

    const offset = write & rb.mask;

    @memcpy(
        rb.ptr[offset .. offset + count],
        src[0..count],
    );
    rb.write_idx.store(
        write +% count,
        .release,
    );

    return count;
}

pub export fn ring_read(rb: *ring_buffer, dst: [*]f32, len: u32) u32 {
    const write = rb.write_idx.load(.acquire);
    const read = rb.read_idx.load(.monotonic);
    const available = write -% read;
    const count = @min(available, len);

    if (count == 0) {
        return 0;
    }

    const offset = read & rb.mask;

    @memcpy(
        dst[0..count],
        rb.ptr[offset .. offset + count],
    );
    rb.read_idx.store(
        read +% count,
        .release,
    );

    return count;
}

pub export fn ring_reset(rb: *ring_buffer) void {
    rb.read_idx.store(0, .seq_cst);
    rb.write_idx.store(0, .seq_cst);
}

pub inline fn fill(rb: *ring_buffer) u32 {
    const w = rb.write_idx.load(.monotonic);
    const r = rb.read_idx.load(.monotonic);
    return w -% r;
}
