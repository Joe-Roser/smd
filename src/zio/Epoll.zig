//! Epoll interface for linux
//! Allows for async IO

const std = @import("std");
const linux = std.os.linux;

const Epoll = @This();

pub const Event = linux.epoll_event;
pub const Data = linux.epoll_data;

pub const IN = linux.EPOLL.IN;
pub const OUT = linux.EPOLL.OUT;
pub const DHUP = linux.EPOLL.DHUP;
pub const PRI = linux.EPOLL.PRI;
pub const ERR = linux.EPOLL.ERR;
pub const HUP = linux.EPOLL.HUP;

pub const ET = linux.EPOLL.ET;
pub const ONESHOT = linux.EPOLL.ONESHOT;
pub const WAKEUP = linux.EPOLL.WAKEUP;
pub const EXCLUSIVE = linux.EPOLL.EXCLUSIVE;

const Error = error{
    InvalidInput,
    MaxHit,
    NoMem,
    InvalidFd,
    AlreadyExists,
    CausesLoop,
    NoEntryFound,
    Interrupted,
};

pub const Options = struct {
    cloexec: bool = false,
};

fd: i32,

pub fn init(options: Options) Error!Epoll {
    const flags: usize = if (options.cloexec) linux.EPOLL.CLOEXEC else 0;
    const fd: isize = @bitCast(linux.epoll_create1(flags));

    if (fd < 0) {
        return switch (linux.errno(@bitCast(fd))) {
            .INVAL => Error.InvalidInput,
            .MFILE, .NFILE => Error.MaxHit,
            .NOMEM => Error.NoMem,
            else => unreachable,
        };
    }

    return .{ .fd = @intCast(fd) };
}

pub fn deinit(self: *Epoll) void {
    _ = linux.close(self.fd);
}

pub fn add(self: *Epoll, fd: i32, flags: u32, data: Data) !void {
    var event: Event = .{
        .events = flags,
        .data = data,
    };

    const i: isize = @bitCast(linux.epoll_ctl(self.fd, linux.EPOLL.CTL_ADD, fd, &event));
    if (i < 0) {
        return switch (linux.errno(@bitCast(i))) {
            .BADFD => Error.InvalidFd,
            .EXIST => Error.AlreadyExists,
            .INVAL => Error.InvalidInput,
            .LOOP => Error.CausesLoop,
            .NOMEM => Error.NoMem,
            .NOSPC => Error.MaxHit,
            .PERM => Error.InvalidFd,
            else => unreachable,
        };
    }
}

pub fn modify(self: *Epoll, fd: i32, data: Data, flags: u32) !void {
    var event: Event = .{
        .events = flags,
        .data = data,
    };

    const i: isize = @bitCast(linux.epoll_ctl(self.fd, linux.EPOLL.CTL_MOD, fd, &event));
    if (i < 0) return switch (linux.errno(@bitCast(i))) {
        .BADF => Error.InvalidFd,
        .INVAL => Error.InvalidInput,
        .NOMEM => Error.NoMem,
        .NOENT => Error.NoEntryFound,
        else => unreachable,
    };
}

pub fn delete(self: *Epoll, fd: i32) !void {
    const i: isize = @bitCast(linux.epoll_ctl(self.fd, linux.EPOLL.CTL_DEL, fd, null));
    if (i < 0) return switch (linux.errno(@bitCast(i))) {
        .BADF => Error.InvalidFd,
        .INVAL => Error.InvalidInput,
        .NOMEM => Error.NoMem,
        .NOENT => Error.NoEntryFound,
        else => unreachable,
    };
}

pub fn wait(self: *Epoll, events: []Event, timeout: i32) !usize {
    const n: isize = @bitCast(linux.epoll_wait(self.fd, events.ptr, @intCast(events.len), timeout));

    return switch (linux.errno(@bitCast(n))) {
        .SUCCESS => @intCast(n),
        .BADF => Error.InvalidFd,
        .FAULT => Error.InvalidInput,
        .INTR => Error.Interrupted,
        .INVAL => Error.InvalidInput,
        else => unreachable,
    };
}
