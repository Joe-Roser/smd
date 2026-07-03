const std = @import("std");
const PW = @import("pw_audio");
const zio = @import("zio");
const event = @import("event.zig");

const Logger = @import("Logger.zig");
const RB = PW.SPSC_f32;
const Client = event.Client;
const Epoll = zio.Epoll;

const Sink = @This();

client: *Client,
logger: *Logger,
rb: *RB,
audio: PW,
high_tide: bool = false,
low_tide: u32,

pub fn init(client: *Client, logger: *Logger, rb: *RB) !Sink {
    const low_tide_percent = 0.2;
    return .{
        .logger = logger,
        .client = client,
        .rb = rb,
        .audio = undefined,
        .low_tide = @intFromFloat(@as(f32, @floatFromInt(rb._internal.capacity)) * low_tide_percent),
    };
}
pub fn deinit(self: *Sink) void {
    self.audio.deinit();
}

pub fn err(self: *Sink, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

pub fn run(self: *Sink) void {
    self.audio = PW.init(.{ .channels = 2, .sample_rate = 48000 }, self.rb) catch |e|
        return self.err(e);
    defer self.audio.deinit();
    self.audio.pause();

    var epoll = Epoll.init(.{}) catch |e|
        return self.err(e);
    defer epoll.deinit();
    epoll.add(self.client.fd.fd, Epoll.IN, .{ .u64 = 0 }) catch |e|
        return self.err(e);
    epoll.add(self.audio.getFd(), Epoll.IN, .{ .u64 = 1 }) catch |e|
        return self.err(e);

    var events: [8]Epoll.Event = undefined;
    loop: while (true) {
        const n = epoll.wait(&events, -1) catch
            continue :loop;
        std.debug.print("sink\n", .{});

        for (events[0..n]) |evn| {
            std.debug.print("{}\n", .{evn.data.u64});
            switch (evn.data.u64) {
                0 => {
                    self.client.fd.read() catch {};
                    self.client.sleep();

                    while (self.client.receive()) |r| {
                        switch (r) {
                            .quit, .err_unrecoverable => break :loop,
                            .zero => {
                                self.audio.zero();
                            },
                            .clear => {
                                self.audio.pause();
                                self.audio.clear();
                            },
                            .high_tide => {
                                self.high_tide = true;
                            },
                            .pause => {
                                self.audio.pause();
                            },
                            .play => {
                                self.audio.play();
                            },
                            .low_tide => unreachable,
                        }
                    }
                },
                1 => {
                    self.audio.iterate();
                    if (self.high_tide and self.rb.fill() <= self.low_tide) {
                        self.client.broadcast_spinning(.low_tide);
                    }
                },
                else => unreachable,
            }
        }
    }
}
