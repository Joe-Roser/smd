const std = @import("std");
const Audio = @import("Audio");
const event = @import("event.zig");

const Logger = @import("Logger.zig");
const Epoll = @import("zio/Epoll.zig");
const EventFd = @import("zio/Eventfd.zig");
const Client = event.Client;
const RB = Audio.RB;

const Sink = @This();

client: *Client,
logger: *Logger,
rb: *RB,
audio: *Audio,
high_tide: bool,
low_tide: u32,

ack_fd: EventFd,

pub fn init(client: *Client, logger: *Logger, rb: *RB) !Sink {
    const low_tide_percent = 0.2;
    return .{
        .logger = logger,
        .client = client,
        .rb = rb,
        .audio = undefined,
        .high_tide = false,
        .low_tide = @intFromFloat(@as(f32, @floatFromInt(rb.capacity)) * low_tide_percent),
        .ack_fd = try .init(0, 0),
    };
}

pub fn err(self: *Sink, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

pub fn run(self: *Sink, alloc: std.mem.Allocator) void {
    self.audio = Audio.init(alloc, .{ .channels = 2, .sample_rate = 48000 }, self.rb) catch |e|
        return self.err(e);
    defer self.audio.deinit(alloc);
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

        for (events[0..n]) |evn| {
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
                                self.audio.zero();
                                self.audio.clear();
                                while (true) {
                                    self.ack_fd.write() catch {
                                        self.logger.log("ack write failed", .{}, .debug);
                                        continue;
                                    };
                                    break;
                                }
                                self.logger.log("sink cleared", .{}, .debug);
                                self.high_tide = false;
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
                        self.high_tide = false;
                    }
                },
                else => unreachable,
            }
        }
    }
}
