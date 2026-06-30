const std = @import("std");
const PW = @import("pw_audio");
const zio = @import("zio");
const event = @import("event.zig");

const RB = PW.SPSC_f32;
const Client = event.Client;
const Epoll = zio.Epoll;

pub const Sink = struct {
    client: *Client,
    rb: *RB,
    audio: PW = undefined,
    high_tide: bool = false,
    low_tide: u32,

    pub fn init(client: *Client, rb: *RB) Sink {
        const low_tide_percent = 0.2;
        return .{
            .client = client,
            .rb = rb,
            .low_tide = @intFromFloat(@as(f32, @floatFromInt(rb._internal.capacity)) * low_tide_percent),
        };
    }

    pub fn run(self: *Sink) void {
        var audio = PW.init(.{ .channels = 2, .sample_rate = 48000 }, self.rb) catch
            return self.client.broadcast_spinning(.err_unrecoverable);
        defer audio.deinit();

        audio.pause();

        var epoll = Epoll.init(.{}) catch
            return self.client.broadcast_spinning(.err_unrecoverable);
        defer epoll.deinit();
        epoll.add(self.client.fd, Epoll.IN, .{ .u64 = 0 }) catch
            return self.client.broadcast_spinning(.err_unrecoverable);
        epoll.add(audio.getFd(), Epoll.IN, .{ .u64 = 1 }) catch
            return self.client.broadcast_spinning(.err_unrecoverable);

        var events: [8]Epoll.Event = undefined;
        loop: while (true) {
            const n = epoll.wait(&events, -1) catch
                continue :loop;

            for (events[0..n]) |e| {
                switch (e.data.u64) {
                    0 => {
                        var buf: [8]u8 = undefined;
                        _ = std.os.linux.read(self.client.fd, &buf, buf.len);

                        while (self.client.receive()) |r| {
                            switch (r) {
                                .quit, .err_unrecoverable => break :loop,
                                .high_tide => {
                                    self.high_tide = true;
                                },
                                .pause => audio.pause(),
                                .play => audio.play(),
                                .song_path_loaded, .song_end => {},
                                .low_tide => unreachable,
                            }
                        }
                    },
                    1 => {
                        audio.iterate();
                        if (self.high_tide and self.rb.fill() <= self.low_tide) {
                            self.client.broadcast_spinning(.low_tide);
                        }
                    },
                    else => unreachable,
                }
            }
        }
    }
};
