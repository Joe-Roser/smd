const std = @import("std");
const event = @import("event.zig");

const Client = event.Client;
const Logger = @import("Logger.zig");
const RB = @import("Audio").RB;
const Decoder = @import("Decoder.zig");
const Epoll = @import("zio/Epoll.zig");
const EventFd = @import("zio/Eventfd.zig");
const stdin = std.Io.File.stdin();
const Allocator = std.mem.Allocator;

const AudioState = enum(u8) { paused, playing };

pub const Control = @This();

client: *Client,
logger: *Logger,
rb: *RB,

queue: [2048][:0]const u8,
queue_current: u32,
queue_max: u32,

decoder: Decoder,
audio_state: AudioState,

high_tide: u32,
epoll_wait: i32,

ack_fd: EventFd,

pub fn init(client: *Client, logger: *Logger, rb: *RB, ack_fd: EventFd) ?Control {
    const high_tide_percent = 0.9;

    return .{
        .client = client,
        .logger = logger,
        .rb = rb,

        .queue = undefined,
        .queue_current = 0,
        .queue_max = 0,

        .decoder = Decoder.init() orelse return null,
        .audio_state = .paused,

        .high_tide = @intFromFloat(@as(f32, @floatFromInt(rb.capacity)) * high_tide_percent),
        .epoll_wait = -1,

        .ack_fd = ack_fd,
    };
}
pub fn deinit(self: *Control, alloc: Allocator) void {
    self.decoder.deinitSong();
    self.decoder.deinit();

    for (0..self.queue_max) |n| {
        alloc.free(self.queue[n]);
    }
}

pub fn err(self: *Control, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

/// Initialise the next song in the decoder, repeating untill a song is loaded successfully.
/// returns true when song is loaded, and false if song path is bad.
pub fn initSong(self: *Control) !bool {
    load: while (self.queue_current < self.queue_max) {
        const path = self.queue[self.queue_current];
        self.logger.log("path: {s}", .{path}, .debug);
        // Try load next song
        self.decoder.initSong(path) catch |e| switch (e) {
            error.AV_NOENT => {
                self.queue_current += 1;
                self.logger.log("Song not found: {s}", .{path}, .info);
                continue :load;
            },
            else => return e,
        };
        return true;
    }
    return false;
}

pub fn run(self: *Control, alloc: Allocator) void {
    var epoll = Epoll.init(.{}) catch |e|
        return self.err(e);
    defer epoll.deinit();

    epoll.add(self.client.fd.fd, Epoll.IN, .{ .u64 = 0 }) catch |e|
        return self.err(e);
    epoll.add(stdin.handle, Epoll.IN, .{ .u64 = 1 }) catch |e|
        return self.err(e);

    var events: [8]Epoll.Event = undefined;

    loop: while (true) {
        const n = epoll.wait(&events, self.epoll_wait) catch
            continue :loop;

        events: for (events[0..n]) |ev|
            switch (ev.data.u64) {
                0 => {
                    self.client.fd.read() catch {};
                    self.client.sleep();

                    while (self.client.receive()) |r| {
                        switch (r) {
                            .err_unrecoverable => {
                                self.logger.log("Received: {}", .{r}, .info);

                                break :loop;
                            },
                            .low_tide => {
                                if (self.queue_current != self.queue_max) self.epoll_wait = 0;
                            },
                            .high_tide, .play, .pause, .clear, .zero, .quit => unreachable,
                        }
                    }
                },
                1 => {
                    var msg: [1024]u8 = undefined;
                    const m = std.os.linux.read(stdin.handle, &msg, msg.len);

                    // quit
                    if (std.mem.eql(u8, "q", msg[0 .. m - 1])) {
                        self.quit();
                        break :loop;
                    } else if (std.mem.eql(u8, "state", msg[0 .. m - 1])) {
                        self.logger.log("state: {}\ncurrent_track: {}/{}", .{
                            self.audio_state,
                            self.queue_current,
                            self.queue_max,
                        }, .info);
                    } else if (std.mem.eql(u8, "pause", msg[0 .. m - 1])) {
                        self.pause();
                    } else if (std.mem.eql(u8, "play", msg[0 .. m - 1])) {
                        self.play();
                    } else if (std.mem.eql(u8, "playPause", msg[0 .. m - 1])) {
                        self.playPause();
                    } else if (std.mem.startsWith(u8, msg[0 .. m - 1], "path: ")) {
                        self.enqueuePath(alloc, msg[6 .. m - 1]) catch |e|
                            switch (e) {
                                error.AV_NOENT => {
                                    self.logger.log("Song not found", .{}, .info);
                                },
                                else => self.err(e),
                            };
                    } else if (std.mem.eql(u8, "clear", msg[0 .. m - 1])) {
                        self.clear(alloc) catch |e|
                            return self.err(e);
                    } else if (std.mem.eql(u8, "prev", msg[0 .. m - 1])) {
                        self.prev() catch |e|
                            return self.err(e);
                    } else if (std.mem.eql(u8, "next", msg[0 .. m - 1])) {
                        self.next() catch |e|
                            return self.err(e);
                    } else if (std.mem.startsWith(u8, msg[0 .. m - 1], "seekBy ")) {
                        const by = std.fmt.parseInt(i64, msg[7 .. m - 1], 10) catch {
                            self.logger.log("Invalid integer: {s}", .{msg[7 .. m - 1]}, .info);
                            continue :events;
                        };

                        self.seekBy(by) catch |e|
                            return self.err(e);
                    } else if (std.mem.startsWith(u8, msg[0 .. m - 1], "seekTo ")) {
                        const to = std.fmt.parseInt(i64, msg[7 .. m - 1], 10) catch {
                            self.logger.log("Invalid integer: {s}", .{msg[7 .. m - 1]}, .info);
                            continue :events;
                        };
                        self.seekTo(to) catch |e|
                            return self.err(e);
                    } else if (std.mem.eql(u8, "tracklist", msg[0 .. m - 1])) {
                        self.tracklist();
                    }
                    continue :events;
                },
                else => unreachable,
            };

        if (self.epoll_wait == 0) {
            for (0..5) |_| {
                const success = self.decoder.writeFrame(self.rb) catch |write_ret| switch (write_ret) {
                    error.WouldBlock => {
                        self.logger.log("Hit Block", .{}, .debug);
                        self.client.broadcast_spinning(.high_tide);
                        self.epoll_wait = -1;
                        continue :loop;
                    },
                    else => return self.err(write_ret),
                };
                if (!success) {
                    // Song hit eof
                    self.decoder.deinitSong();

                    self.queue_current += 1;

                    if (!(self.initSong() catch |e|
                        return self.err(e)))
                    {
                        // if no song in queue or all bad paths
                        self.audio_state = .paused;
                        self.epoll_wait = -1;
                    }
                    continue :loop;
                }
                if (self.rb.fill() >= self.high_tide) {
                    self.client.broadcast_spinning(.high_tide);
                    self.epoll_wait = -1;
                    continue :loop;
                }
            }
        }
    }
}

fn quit(self: *Control) void {
    self.client.broadcast_spinning(.quit);
}
fn pause(self: *Control) void {
    if (self.audio_state == .paused) return;

    self.audio_state = .paused;
    self.client.broadcast_spinning(.pause);
}
fn play(self: *Control) void {
    if (self.queue_current == self.queue_max)
        // eof
        return;

    if (self.audio_state == .playing) return;

    self.audio_state = .playing;
    self.client.broadcast_spinning(.play);
}
fn playPause(self: *Control) void {
    std.debug.assert(self.audio_state == .playing or self.audio_state == .paused);
    if (self.queue_current == self.queue_max) return;

    if (self.audio_state == .playing) self.pause() else self.play();
}
fn enqueuePath(self: *Control, alloc: Allocator, path: []const u8) !void {
    // TODO:Check the path
    const path_dupe = try alloc.dupeSentinel(u8, path, 0);

    self.queue[self.queue_max] = path_dupe;
    const is_final_song = self.queue_current == self.queue_max;
    self.queue_max += 1;

    if (is_final_song) {
        if (try self.initSong()) {
            self.client.broadcast_spinning(.play);
            self.audio_state = .playing;
            self.epoll_wait = 0;
        }
    }
}
fn clear(self: *Control, alloc: Allocator) !void {
    self.client.broadcast_spinning(.clear);
    self.epoll_wait = -1;
    self.audio_state = .paused;

    for (0..self.queue_max) |n| {
        alloc.free(self.queue[n]);
    }
    self.queue_max = 0;
    self.queue_current = 0;

    self.decoder.deinitSong();

    try self.ack_fd.read();
    self.rb.reset();
}
fn prev(self: *Control) !void {
    if (self.queue_current == 0) return self.seekTo(0);

    self.client.broadcast_spinning(.clear);

    self.decoder.deinitSong();
    self.queue_current -= 1;
    const should_play = try self.initSong();

    try self.ack_fd.read();
    self.rb.reset();

    if (should_play) {
        self.client.broadcast_spinning(.play);
        self.epoll_wait = 0;
        self.audio_state = .playing;
    } else {
        self.epoll_wait = -1;
        self.audio_state = .paused;
    }
}
fn next(self: *Control) !void {
    if (self.queue_current == self.queue_max) return error.NoNext;

    self.client.broadcast_spinning(.clear);

    self.decoder.deinitSong();
    self.queue_current += 1;
    const should_play = try self.initSong();

    try self.ack_fd.read();
    self.rb.reset();

    if (should_play) self.client.broadcast_spinning(.play) else {
        self.epoll_wait = -1;
        self.audio_state = .paused;
    }
}
fn seekTo(self: *Control, to: i64) !void {
    if (self.queue_current == self.queue_max) return error.NoSongLoaded;
    if (to < 0) return error.CannotSeekToNegative;

    self.client.broadcast_spinning(.clear);

    const end = self.decoder.secondsToTimestamp(to) orelse unreachable;
    try self.decoder.seekTo(end);

    try self.ack_fd.read();
    self.rb.reset();

    self.client.broadcast_spinning(.play);
}
fn seekBy(self: *Control, by: i64) !void {
    if (self.queue_current == self.queue_max) return error.NoSongLoaded;

    self.client.broadcast_spinning(.clear);

    const now = self.decoder.pts;
    const end = (self.decoder.secondsToTimestamp(by) orelse unreachable) + now;
    try self.decoder.seekTo(end);

    try self.ack_fd.read();
    self.rb.reset();

    self.client.broadcast_spinning(.play);
}
fn tracklist(self: *Control) void {
    std.debug.print("Tracklist:\n", .{});
    for (0..self.queue_max) |n| {
        std.debug.print("{}. {s}", .{
            n,
            self.queue[n],
        });
        if (n == self.queue_current) std.debug.print("<\n", .{}) else std.debug.print("\n", .{});
    }
}
