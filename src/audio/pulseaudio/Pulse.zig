const std = @import("std");

pub const RB = @import("RB");
pub const Params = struct {
    sample_rate: u32,
    channels: u32,
};

const Audio = @This();

rb: *RB,

pub fn init(alloc: std.mem.Allocator, params: Params, rb: *RB) !*Audio {
    _ = alloc;
    _ = params;
    _ = rb;
    return error.Unimplemented;
}

pub fn deinit(self: *Audio, alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn clear(self: *Audio) void {
    _ = self;
}

pub fn zero(self: *Audio) void {
    _ = self;
}

pub fn play(self: *Audio) void {
    _ = self;
}

pub fn pause(self: *Audio) void {
    _ = self;
}

pub fn getFd(self: *Audio) std.posix.fd_t {
    _ = self;
    return 0;
}

pub fn iterate(self: *Audio) void {
    _ = self;
}
