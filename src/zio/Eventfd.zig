const std = @import("std");

const EventFd = @This();

fd: std.posix.fd_t,

pub fn init(count: u32, flags: u32) !EventFd {
    const fd = std.os.linux.eventfd(count, flags);

    const err = std.os.linux.errno(fd);
    return switch (err) {
        .SUCCESS => .{ .fd = @intCast(fd) },

        .INVAL => error.InvalidInputParams,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NODEV => error.SystemResources,
        .NOMEM => error.SystemResources,
        else => unreachable,
    };
}

pub fn read(self: EventFd) !void {
    var buf: [8]u8 = undefined;
    if (@as(i32, @intCast(std.os.linux.read(self.fd, &buf, buf.len))) < 0) return error.ReadError;
}
pub fn write(self: EventFd) !void {
    const msg: usize = 1;
    if (@as(i32, @intCast(std.os.linux.write(self.fd, @ptrCast(&msg), @sizeOf(usize)))) < 0)
        return error.WriteError;
}
