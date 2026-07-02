const std = @import("std");
const pw_c = @import("pw_c");

pub const SPSC_f32 = @import("SPSC.zig");
pub const Params = pw_c.pw_audio_params;

const PwAudio = @This();

_internals: *pw_c.pw_audio_internals,

pub const Error = error{
    InitializationFailed,
};

pub fn init(params: Params, rb: *SPSC_f32) Error!PwAudio {
    const internals = pw_c.pw_audio_init(params, @ptrCast(rb)) orelse return error.InitializationFailed;

    return PwAudio{
        ._internals = internals,
    };
}
pub fn deinit(self: *PwAudio) void {
    pw_c.pw_audio_deinit(self._internals);
}

pub fn clear(self: *PwAudio) void {
    pw_c.pw_audio_clear(self._internals);
}

pub fn zero(self: *PwAudio) void {
    pw_c.pw_audio_zero(self._internals);
}
pub fn play(self: *PwAudio) void {
    pw_c.pw_audio_play(self._internals);
}
pub fn pause(self: *PwAudio) void {
    pw_c.pw_audio_pause(self._internals);
}

pub fn getFd(self: *PwAudio) std.posix.fd_t {
    return @as(std.posix.fd_t, @intCast(pw_c.pw_audio_get_fd(self._internals)));
}
pub fn iterate(self: *PwAudio) void {
    pw_c.pw_audio_iterate(self._internals);
}
pub fn mainLoopRun(self: *PwAudio) void {
    pw_c.pw_audio_main_loop_run(self._internals);
}
