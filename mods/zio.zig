const std = @import("std");

pub const Epoll = @import("Epoll.zig");
pub const event_sys = @import("event_sys.zig");

pub fn eventfd(count: u32, flags: u32) !std.posix.fd_t {
    const fd = std.os.linux.eventfd(count, flags);

    const err = std.os.linux.errno(fd);
    return switch (err) {
        .SUCCESS => @intCast(fd),

        .INVAL => error.InvalidInputParams,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NODEV => error.SystemResources,
        .NOMEM => error.SystemResources,
        else => unreachable,
    };
}
