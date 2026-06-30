const std = @import("std");
const zio = @import("zio.zig");
const Io = std.Io;

const eventfd = zio.eventfd;

pub fn Client(comptime Event: type) type {
    return struct {
        const Self = @This();
        const capacity = 256;
        const mask = capacity - 1;

        const num_clients = 2;

        events: [capacity]Event = undefined,
        reader_idx: u32 = 0,
        writer_idx: u32 = 0,

        asleep: u32 = 1,
        fd: std.posix.fd_t = undefined,

        lock: std.atomic.Value(u32) = .init(0),

        clients: [num_clients]*Self = undefined,

        pub const init: Self = .{};

        // Sort clients to avoid races/lockups
        pub fn setClients(self: *Self, clients_param: [num_clients]*Self) void {
            var clients = clients_param;
            inline for (0..num_clients) |n| {
                var max: usize = @intFromPtr(clients[n]);
                var max_idx: usize = n;

                inline for (n + 1..num_clients) |i| {
                    const v = @intFromPtr(clients[i]);
                    if (v > max) {
                        max = v;
                        max_idx = i;
                    }
                }
                self.clients[n] = clients[max_idx];
                clients[max_idx] = clients[n];
            }
        }

        pub fn broadcast(self: *Self, event: Event) !void {
            var writer_idxs: [num_clients]u32 = undefined;

            var lock = self.clients[0].lock.fetchAdd(1, .acq_rel);
            if (lock != 0) return error.WouldBlock;
            defer _ = self.clients[0].lock.fetchSub(1, .acq_rel);

            lock = self.clients[1].lock.fetchAdd(1, .acq_rel);
            if (lock != 0) return error.WouldBlock;
            defer _ = self.clients[1].lock.fetchSub(1, .acq_rel);

            inline for (self.clients, 0..) |client, i| {
                writer_idxs[i] = client.writer_idx;
                if (client.writer_idx -% client.reader_idx >= capacity) return error.WouldBlock;
            }

            inline for (self.clients, 0..) |client, i| {
                client.events[writer_idxs[i] & mask] = event;
                client.writer_idx +%= 1;

                if (@atomicLoad(u32, &client.reader_idx, .acquire) == writer_idxs[i] and @atomicLoad(u32, &client.asleep, .monotonic) == 1)
                    std.os.linux.write(client.fd, &@as(usize, 1), @sizeOf(usize));
            }
        }

        pub fn broadcast_spinning(self: *Self, event: Event) void {
            var lock = self.clients[0].lock.fetchAdd(1, .acq_rel);
            while (lock != 0) {
                _ = self.clients[0].lock.fetchSub(1, .acq_rel);
                lock = self.clients[0].lock.fetchAdd(1, .acq_rel);
            }
            defer _ = self.clients[0].lock.fetchSub(1, .acq_rel);

            lock = self.clients[1].lock.fetchAdd(1, .acq_rel);
            while (lock != 0) {
                _ = self.clients[1].lock.fetchSub(1, .acq_rel);
                lock = self.clients[1].lock.fetchAdd(1, .acq_rel);
            }
            defer _ = self.clients[1].lock.fetchSub(1, .acq_rel);

            inline for (self.clients) |client| {
                const writer = client.writer_idx;
                while (writer -% client.reader_idx >= capacity) {}

                client.events[writer & mask] = event;
                client.writer_idx +%= 1;

                if (@atomicLoad(u32, &client.reader_idx, .acquire) == writer and @atomicLoad(u32, &client.asleep, .monotonic) == 1) {
                    const msg: usize = 1;
                    _ = std.os.linux.write(client.fd, std.mem.asBytes(&msg), @sizeOf(usize));
                }
            }
        }

        pub fn receive(self: *Self) ?Event {
            if (self.reader_idx == @atomicLoad(u32, &self.writer_idx, .acquire)) return null;

            const ret = self.events[self.reader_idx & mask];
            _ = @atomicRmw(u32, &self.reader_idx, .Add, 1, .release);
            return ret;
        }
    };
}
const E = enum {};

test "setClients Correctness" {
    var c1: Client(E) = .{ .fd = try eventfd(0, 0) };
    var c2: Client(E) = .{ .fd = try eventfd(0, 0) };
    var c3: Client(E) = .{ .fd = try eventfd(0, 0) };

    c1.setClients(.{ &c2, &c3 });
    c2.setClients(.{ &c1, &c3 });
    c3.setClients(.{ &c1, &c2 });

    std.debug.assert(@intFromPtr(c1.clients[0]) > @intFromPtr(c1.clients[1]));
}
