const std = @import("std");

const EventFd = @import("zio/Eventfd.zig");

pub const Client = SPSCClient(Event, 128);
pub const Event = enum(u8) {
    quit,
    err_unrecoverable,

    low_tide,
    high_tide,

    zero,
    play,
    pause,

    clear,
};

pub fn SPSCClient(comptime E: type, comptime cap: u32) type {
    if (!std.math.isPowerOfTwo(cap)) @compileError("capacity must be power of 2");

    return struct {
        const Self = @This();
        const capacity = cap;
        const mask = cap - 1;

        events: [capacity]E = undefined,
        reader_idx: u32 = 0,
        writer_idx: u32 = 0,

        asleep: u32 = 1,
        fd: EventFd,

        peer: *Self,

        pub fn broadcast(self: *Self, event: E) !void {
            const writer_idx = self.peer.writer_idx;
            if (writer_idx -% self.peer.reader_idx >= capacity) return error.WouldBlock;

            self.peer.events[writer_idx & mask] = event;
            self.peer.writer_idx +%= 1;

            if (@atomicLoad(u32, &self.peer.asleep, .monotonic) == 1) {
                @atomicStore(u32, &self.peer.asleep, 0, .release);
                self.peer.fd.write() catch {};
            }
        }

        pub fn broadcast_spinning(self: *Self, event: E) void {
            const writer = @atomicLoad(u32, &self.peer.writer_idx, .acquire);
            while (writer -% @atomicLoad(u32, &self.peer.reader_idx, .acquire) >= capacity) {}

            self.peer.events[writer & mask] = event;
            _ = @atomicRmw(u32, &self.peer.writer_idx, .Add, 1, .acq_rel);

            if (@atomicLoad(u32, &self.peer.asleep, .monotonic) == 1) {
                @atomicStore(u32, &self.peer.asleep, 0, .release);
                self.peer.fd.write() catch {};
            }
        }

        pub fn receive(self: *Self) ?E {
            if (self.reader_idx == @atomicLoad(u32, &self.writer_idx, .acquire)) return null;

            const ret = self.events[self.reader_idx & mask];
            _ = @atomicRmw(u32, &self.reader_idx, .Add, 1, .release);
            return ret;
        }

        pub fn sleep(self: *Self) void {
            @atomicStore(u32, &self.asleep, 1, .release);
        }
    };
}
