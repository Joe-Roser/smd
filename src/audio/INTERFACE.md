pub const Params = struct {
    sample_rate: u32,
    channels: u32,
};

pub fn init(alloc: std.mem.Allocator, params: Params, rb: *RB) !*Audio;

pub fn deinit(self: *Audio, alloc: std.mem.Allocator) void;

pub fn clear(self: *Audio) void;

pub fn zero(self: *Audio) void;

pub fn play(self: *Audio) void;

pub fn pause(self: *Audio) void;

pub fn getFd(self: *Audio) std.posix.fd_t;

pub fn iterate(self: *Audio) void;
