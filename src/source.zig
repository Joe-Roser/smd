const std = @import("std");

const zio = @import("zio");
const event = @import("event.zig");
const ff = @import("ffmpeg");

const Decoder = @import("Decoder.zig");
const Logger = @import("Logger.zig");
const RB = @import("pw_audio").SPSC_f32;
const Client = event.Client;
const Epoll = zio.Epoll;

pub const Source = @This();

client: *Client,
logger: *Logger,
decoder: Decoder,
rb: *RB,
title: ?[:0]const u8 = null,

high_tide: u32,
eof: bool,

freezefd: zio.EventFd,
defrostfd: zio.EventFd,

pub fn init(client: *Client, logger: *Logger, rb: *RB) !Source {
    const high_tide_percent = 0.9;
    return .{
        .client = client,
        .logger = logger,
        .decoder = Decoder.init() orelse return error.NoFFState,
        .rb = rb,

        .high_tide = @intFromFloat(@as(f32, @floatFromInt(rb._internal.capacity)) * high_tide_percent),
        .eof = true,

        .freezefd = try zio.EventFd.init(0, 0),
        .defrostfd = try zio.EventFd.init(0, 0),
    };
}
pub fn deinit(self: *Source) void {
    self.decoder.deinitSong();
    self.decoder.deinit();
}

pub fn err(self: *Source, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

pub fn run(self: *Source) void {
    var epoll = Epoll.init(.{}) catch |e|
        return self.err(e);
    defer epoll.deinit();
    epoll.add(self.client.fd.fd, Epoll.IN, .{ .u64 = 0 }) catch |e|
        return self.err(e);

    var events: [8]Epoll.Event = undefined;
    var epoll_wait: i32 = -1;
    loop: while (true) {
        const n = epoll.wait(&events, epoll_wait) catch
            continue :loop;

        for (events[0..n]) |ev|
            switch (ev.data.u64) {
                0 => {
                    self.client.fd.read() catch {};

                    while (self.client.receive()) |r| {
                        switch (r) {
                            .quit, .err_unrecoverable => break :loop,
                            .clear => {
                                self.freezefd.write() catch {};
                                self.defrostfd.read() catch {};
                            },
                            .song_path_loaded => {
                                self.decoder.initSong(self.title.?.ptr) catch |e|
                                    switch (e) {
                                        error.AV_NOENT => {
                                            self.logger.log("Song not found", .{}, .info);
                                            self.client.broadcast_spinning(.pause);
                                            continue;
                                        },
                                        else => self.err(e),
                                    };

                                self.logger.log("Loaded", .{}, .debug);
                                self.eof = false;
                                epoll_wait = 0;
                            },
                            .low_tide => {
                                if (!self.eof) epoll_wait = 0;
                            },
                            .play, .pause => {},
                            .high_tide, .song_end, .zero => unreachable,
                        }
                    }
                },
                else => unreachable,
            };

        if (epoll_wait == 0) {
            for (0..5) |_| {
                self.decoder.writeFrame(self.rb) catch |e| switch (e) {
                    error.EOF => {
                        self.decoder.deinitSong();
                        self.client.broadcast_spinning(.song_end);
                        self.eof = true;
                        epoll_wait = -1;
                        continue :loop;
                    },
                    error.WouldBlock => {
                        self.logger.log("Hit Block", .{}, .debug);
                        self.client.broadcast_spinning(.high_tide);
                        epoll_wait = -1;
                        continue :loop;
                    },
                    else => self.err(e),
                };
                if (self.rb.fill() >= self.high_tide) {
                    self.client.broadcast_spinning(.high_tide);
                    epoll_wait = -1;
                    continue :loop;
                }
            }
        }
    }
}
