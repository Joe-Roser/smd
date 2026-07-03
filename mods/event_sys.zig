const std = @import("std");
const zio = @import("zio.zig");
const Io = std.Io;

const EventFd = zio.EventFd;

pub fn SPSCClient(comptime Event: type, comptime cap: u32) type {
    if (!std.math.isPowerOfTwo(cap)) @compileError("capacity must be power of 2");

    return struct {
        const Self = @This();
        const capacity = cap;
        const mask = cap - 1;

        events: [capacity]Event = undefined,
        reader_idx: u32 = 0,
        writer_idx: u32 = 0,

        asleep: u32 = 1,
        fd: EventFd,

        client: *Self,

        pub fn broadcast(self: *Self, event: Event) !void {
            const writer_idx = self.client.writer_idx;
            if (writer_idx -% self.client.reader_idx >= capacity) return error.WouldBlock;

            self.client.events[writer_idx & mask] = event;
            self.client.writer_idx +%= 1;

            if (@atomicLoad(u32, &self.client.asleep, .monotonic) == 1)
                self.client.fd.write() catch {};
        }

        pub fn broadcast_spinning(self: *Self, event: Event) void {
            const writer = self.client.writer_idx;
            while (writer -% self.client.reader_idx >= capacity) {
                std.debug.print(".", .{});
            }

            self.client.events[writer & mask] = event;
            self.client.writer_idx +%= 1;

            if (@atomicLoad(u32, &self.client.asleep, .monotonic) == 1) {
                self.client.fd.write() catch {};
            }
        }

        pub fn receive(self: *Self) ?Event {
            if (self.reader_idx == @atomicLoad(u32, &self.writer_idx, .acquire)) return null;

            const ret = self.events[self.reader_idx & mask];
            return ret;
        }

        pub fn sleep(self: *Self) void {
            @atomicStore(u32, &self.asleep, 1, .release);
        }
    };
}
