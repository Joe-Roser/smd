const std = @import("std");
pub const _internal_mod = @import("spsc_queue.zig");

const Io = std.Io;

const RingBuffer = @This();

_internal: _internal_mod.ring_buffer,

pub inline fn init(num_pages: usize) !RingBuffer {
    return .{
        ._internal = try _internal_mod.ring_init(num_pages),
    };
}
pub inline fn deinit(self: *RingBuffer) void {
    _internal_mod.ring_deinit(&self._internal);
}

pub inline fn write(self: *RingBuffer, src: []const f32) u32 {
    return _internal_mod.ring_write(&self._internal, src.ptr, @intCast(src.len));
}

pub inline fn fill(self: *RingBuffer) u32 {
    return _internal_mod.fill(&self._internal);
}

pub inline fn reset(self: *RingBuffer) void {
    _internal_mod.ring_reset(&self._internal);
}
