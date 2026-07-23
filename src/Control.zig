const std = @import("std");
const event = @import("event.zig");

const Interface = @import("Interface");
const Client = event.Client;
const Logger = @import("Logger.zig");
const RB = @import("Audio").RB;
const Decoder = @import("Decoder.zig");
const Epoll = @import("zio/Epoll.zig");
const EventFd = @import("zio/Eventfd.zig");
const stdin = std.Io.File.stdin();
const Allocator = std.mem.Allocator;

// TODO: Add stopped
const AudioState = enum(u8) { paused, playing };
const DecoderState = enum(i32) { idle = -1, decoding = 0 };

const TL_LEN = 2048;

pub const Control = @This();

frontend: *Interface,
client: *Client,
logger: *Logger,
rb: *RB,

tl: [TL_LEN][:0]const u8,
tl_current: u32,
tl_max: u32,

decoder: Decoder,
audio_state: AudioState,

high_tide: u32,
decoder_state: DecoderState,

ack_fd: EventFd,

pub fn init(interface: *Interface, client: *Client, logger: *Logger, rb: *RB, ack_fd: EventFd) ?Control {
    const high_tide_percent = 0.9;

    return .{
        .frontend = interface,
        .client = client,
        .logger = logger,
        .rb = rb,

        .tl = undefined,
        .tl_current = 0,
        .tl_max = 0,

        .decoder = Decoder.init() orelse return null,
        .high_tide = @intFromFloat(@as(f32, @floatFromInt(rb.capacity)) * high_tide_percent),
        .decoder_state = .idle,
        .audio_state = .paused,

        .ack_fd = ack_fd,
    };
}
pub fn deinit(self: *Control, alloc: Allocator) void {
    self.decoder.deinitSong();
    self.decoder.deinit();

    for (0..self.tl_max) |n| {
        alloc.free(self.tl[n]);
    }
}

pub fn err(self: *Control, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

/// Initialise the next song in the decoder, repeating untill a song is loaded successfully.
/// returns true when song is loaded, and false if song path is bad.
pub fn initSong(self: *Control) !bool {
    load: while (self.tl_current < self.tl_max) {
        const path = self.tl[self.tl_current];
        // Try load next song
        self.decoder.initSong(path) catch |e| switch (e) {
            error.AV_NOENT => {
                self.tl_current += 1;
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
        const n = epoll.wait(&events, @intFromEnum(self.decoder_state)) catch
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
                                if (self.tl_current != self.tl_max) self.decoder_state = .decoding;
                            },
                            .high_tide, .play, .pause, .clear, .zero, .quit => unreachable,
                        }
                    }
                },
                1 => {
                    const cmd = self.frontend.poll();
                    switch (cmd) {
                        .none => {},
                        .quit => {
                            self.client.broadcast_spinning(.quit);
                            self.frontend.respond(cmd, .succ);
                            break :loop;
                        },
                        .get_property => |p| {
                            const prop = self.getProperty(p);
                            self.frontend.respond(cmd, .{ .property_set = prop });
                        },

                        .next => {
                            self.next() catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },
                        .previous => {
                            self.prev() catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },

                        .pause => {
                            self.pause();
                            self.frontend.respond(cmd, .succ);
                        },
                        .play_pause => {
                            self.playPause();
                            self.frontend.respond(cmd, .succ);
                        },
                        .stop => {
                            self.stop() catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },
                        .play => {
                            self.play();
                            self.frontend.respond(cmd, .succ);
                        },
                        .seek => |by| {
                            self.seek(by) catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },
                        .set_position => |to| {
                            self.setPosition(to.@"0", to.@"1") catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },

                        .open_uri => |path| {
                            self.openUri(alloc, path) catch |e|
                                return self.err(e);
                        },

                        // enqueue
                        //    self.enqueue(alloc, path) catch |e| {
                        //        switch (e) {
                        //            error.AV_NOENT => self.logger.log("Song not found", .{}, .info),
                        //            else => self.err(e),
                        //        }
                        //        self.interface.respond(cmd, .err);
                        //        continue :events;
                        //    };
                        //    self.interface.respond(cmd, .succ);
                        .clear => {
                            self.clear(alloc) catch |e|
                                return self.err(e);
                            self.frontend.respond(cmd, .succ);
                        },
                        .tracklist => {
                            self.frontend.respond(
                                cmd,
                                .{ .tracklist = self.tl[0..self.tl_max] },
                            );
                        },
                    }

                    continue :events;
                },
                else => unreachable,
            };

        if (self.decoder_state == .decoding) {
            for (0..5) |_| {
                const success = self.decoder.writeFrame(self.rb) catch |write_ret| switch (write_ret) {
                    error.WouldBlock => {
                        self.logger.log("Hit Block", .{}, .debug);
                        self.client.broadcast_spinning(.high_tide);
                        self.decoder_state = .idle;
                        continue :loop;
                    },
                    else => return self.err(write_ret),
                };
                if (!success) {
                    // Song hit eof
                    self.decoder.deinitSong();

                    self.tl_current += 1;

                    if (!(self.initSong() catch |e|
                        return self.err(e)))
                    {
                        // if no song in queue or all bad paths
                        self.audio_state = .paused;
                        self.decoder_state = .idle;
                    }
                    continue :loop;
                }
                if (self.rb.fill() >= self.high_tide) {
                    self.client.broadcast_spinning(.high_tide);
                    self.decoder_state = .idle;
                    continue :loop;
                }
            }
        }
    }
}

fn getProperty(self: *Control, property: Interface.Messages.Property) *const anyopaque {
    switch (property) {
        // TODO: Add stopped support
        .playback_status => return @ptrCast(@as(*const []const u8, switch (self.audio_state) {
            .playing => &"playing",
            .paused => &"paused",
        })),
        .position => return @ptrFromInt(@as(usize, @intCast(self.decoder.positionMicros()))),
        else => std.debug.panic("Not implemented", .{}),
    }
}

// TODO: Add support for endless and repeat
fn next(self: *Control) !void {
    if (self.tl_current == self.tl_max) return;

    self.client.broadcast_spinning(.clear);

    self.decoder.deinitSong();
    self.tl_current += 1;
    const should_play = try self.initSong() and self.audio_state == .playing;

    try self.ack_fd.read();
    self.rb.reset();

    if (should_play) {
        self.client.broadcast_spinning(.play);
        self.decoder_state = .decoding;
    } else {
        self.decoder_state = .idle;
        self.audio_state = .paused;
    }
}
// TODO: Add support for endless and repeat
fn prev(self: *Control) !void {
    if (self.tl_current == 0) return self.setPosition(self.tl_current, 0);

    self.client.broadcast_spinning(.clear);

    self.decoder.deinitSong();
    self.tl_current -= 1;
    const should_play = try self.initSong() and self.audio_state == .playing;

    try self.ack_fd.read();
    self.rb.reset();

    if (should_play) {
        self.client.broadcast_spinning(.play);
        self.decoder_state = .decoding;
    } else {
        self.decoder_state = .idle;
        self.audio_state = .paused;
    }
}
fn pause(self: *Control) void {
    if (self.audio_state == .paused) return;

    self.audio_state = .paused;
    self.client.broadcast_spinning(.pause);
}
fn stop(self: *Control) !void {
    if (self.tl_current == self.tl_max) return;

    if (self.audio_state == .playing) self.pause();
    try self.setPosition(self.tl_current, 0);
}
fn playPause(self: *Control) void {
    std.debug.assert(self.audio_state == .playing or self.audio_state == .paused);
    if (self.tl_current == self.tl_max) return;

    if (self.audio_state == .playing) self.pause() else self.play();
}
fn play(self: *Control) void {
    if (self.tl_current == self.tl_max)
        // eof
        return;

    if (self.audio_state == .playing) return;

    self.audio_state = .playing;
    self.client.broadcast_spinning(.play);
}
fn clear(self: *Control, alloc: Allocator) !void {
    self.client.broadcast_spinning(.clear);
    self.decoder_state = .idle;
    self.audio_state = .paused;

    for (0..self.tl_max) |n| {
        alloc.free(self.tl[n]);
    }
    self.tl_max = 0;
    self.tl_current = 0;

    self.decoder.deinitSong();

    try self.ack_fd.read();
    self.rb.reset();
}
fn seek(self: *Control, by: i64) !void {
    // TODO: Add seeked signal support
    if (self.tl_current == self.tl_max) return error.NoSongLoaded;

    self.client.broadcast_spinning(.clear);

    const now = self.decoder.pts;
    const end = (self.decoder.microsToTimestamp(by) orelse unreachable) + now;
    if (end < 0) try self.decoder.seekTo(0) else try self.decoder.seekTo(end);

    try self.ack_fd.read();
    self.rb.reset();

    self.client.broadcast_spinning(.play);
    self.decoder_state = .decoding;
}
fn setPosition(self: *Control, track_id: u32, to: i64) !void {
    // TODO: Add seeked signal support

    // TODO:Use track_id:
    _ = track_id;

    if (self.tl_current == self.tl_max) return error.NoSongLoaded;
    if (to < 0) return;
    const end = self.decoder.microsToTimestamp(to) orelse unreachable;
    if (self.decoder.durationMicros() orelse 0 < end) return;

    self.client.broadcast_spinning(.clear);

    try self.decoder.seekTo(end);

    try self.ack_fd.read();
    self.rb.reset();

    self.client.broadcast_spinning(.play);
    self.decoder_state = .decoding;
}
fn openUri(self: *Control, alloc: Allocator, path: []const u8) !void {
    try self.clear(alloc);

    const path_dupe = try alloc.dupeSentinel(u8, path, 0);

    self.tl[self.tl_max] = path_dupe;
    self.tl_max += 1;

    if (try self.initSong()) {
        self.client.broadcast_spinning(.play);
        self.audio_state = .playing;
        self.decoder_state = .decoding;
    }
}

fn enqueue(self: *Control, alloc: Allocator, path: []const u8) !void {
    if (self.tl_max == 2048) return error.QueueFull;
    // TODO:Check the path
    const path_dupe = try alloc.dupeSentinel(u8, path, 0);

    self.tl[self.tl_max] = path_dupe;
    const is_final_song = self.tl_current == self.tl_max;
    self.tl_max += 1;

    if (is_final_song) {
        if (try self.initSong()) {
            self.client.broadcast_spinning(.play);
            self.audio_state = .playing;
            self.decoder_state = .decoding;
        }
    }
}
