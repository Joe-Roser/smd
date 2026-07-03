const std = @import("std");
const event = @import("event.zig");

const Client = event.Client;
const Logger = @import("Logger.zig");
const RB = @import("pw_audio").SPSC_f32;
const Decoder = @import("Decoder.zig");
const Epoll = @import("zio").Epoll;
const stdin = std.Io.File.stdin();

pub const Queue = LinkedList([:0]const u8);
const AudioState = enum(u8) { paused, playing, eof };

pub const Control = @This();

client: *Client,
logger: *Logger,
rb: *RB,
queue: Queue,

decoder: Decoder,
audio_state: AudioState,

high_tide: u32,
epoll_wait: i32 = -1,

pub fn init(client: *Client, logger: *Logger, rb: *RB) ?Control {
    const high_tide_percent = 0.9;

    return .{
        .client = client,
        .logger = logger,
        .rb = rb,
        .queue = .init,

        .decoder = Decoder.init() orelse return null,
        .audio_state = .eof,

        .high_tide = @intFromFloat(@as(f32, @floatFromInt(rb._internal.capacity)) * high_tide_percent),
    };
}
pub fn deinit(self: *Control, alloc: std.mem.Allocator) void {
    self.decoder.deinitSong();
    self.decoder.deinit();

    while (self.queue.popFirst()) |n| {
        alloc.free(n.value);
        alloc.destroy(n);
    }
}

pub fn err(self: *Control, erro: anyerror) void {
    self.logger.log("{any}", .{erro}, .err);
    self.client.broadcast_spinning(.err_unrecoverable);
}

pub fn run(self: *Control, alloc: std.mem.Allocator) void {
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
                                while (self.queue.popFirst()) |path| {
                                    alloc.free(path.value);
                                    alloc.destroy(path);
                                }

                                break :loop;
                            },
                            .low_tide => {
                                if (self.audio_state != .eof) self.epoll_wait = 0;
                            },
                            .high_tide, .play, .pause, .clear, .zero, .quit => unreachable,
                        }
                    }
                },
                1 => {
                    var msg: [1024]u8 = undefined;
                    const m = std.os.linux.read(stdin.handle, &msg, msg.len);

                    if (std.mem.eql(u8, "q\n", msg[0..m])) {
                        self.client.broadcast_spinning(.quit);
                        while (self.queue.popFirst()) |path| {
                            alloc.free(path.value);
                            alloc.destroy(path);
                        }
                        break :loop;
                    }
                    if (std.mem.eql(u8, "pause\n", msg[0..m])) {
                        if (self.audio_state == .eof) continue :events;

                        self.audio_state = .paused;
                        self.client.broadcast_spinning(.pause);
                        continue :events;
                    }
                    if (std.mem.eql(u8, "play\n", msg[0..m])) {
                        if (self.audio_state == .eof) {
                            self.logger.log("Play Failed, EOF", .{}, .info);
                            continue :events;
                        }

                        self.audio_state = .playing;
                        self.client.broadcast_spinning(.play);
                        continue :events;
                    }
                    if (std.mem.startsWith(u8, msg[0..m], "path: ")) {
                        // TODO:Check the path
                        const path = msg[6 .. m - 1];
                        const path_dupe = alloc.dupeSentinel(u8, path, 0) catch |e|
                            return self.err(e);

                        const node = alloc.create(Queue.Node) catch |e|
                            return self.err(e);
                        node.* = .{ .value = path_dupe };

                        const first_item = self.queue.start;
                        self.queue.pushLast(node);

                        // If this is the first song in the queue, play it
                        if (first_item == null) {
                            self.decoder.initSong(self.queue.start.?.value) catch |e|
                                switch (e) {
                                    error.AV_NOENT => {
                                        self.logger.log("Song not found", .{}, .info);
                                        continue :events;
                                    },
                                    else => self.err(e),
                                };
                            self.logger.log("Loaded", .{}, .debug);
                            // eof was already set

                            self.client.broadcast_spinning(.play);
                            self.audio_state = .playing;
                            self.epoll_wait = 0;
                        }
                        continue :events;
                    }
                    if (std.mem.eql(u8, "clear\n", msg[0..m])) {
                        self.client.broadcast_spinning(.clear);
                        self.epoll_wait = -1;
                        self.audio_state = .eof;
                        while (self.queue.popFirst()) |path| {
                            alloc.free(path.value);
                            alloc.destroy(path);
                        }
                        self.rb.reset();
                        self.decoder.deinitSong();

                        self.client.broadcast_spinning(.pause);

                        self.logger.log("clear complete", .{}, .debug);
                        continue :events;
                    }
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

                    const ended = self.queue.popFirst().?;
                    alloc.free(ended.value);
                    alloc.destroy(ended);

                    load: while (self.queue.start) |path| {
                        // Try load next song
                        self.decoder.initSong(path.value) catch |e|
                            switch (e) {
                                error.AV_NOENT => {
                                    self.logger.log("Song not found: {s}", .{path.value}, .info);
                                    alloc.free(path.value);
                                    alloc.destroy(path);
                                    _ = self.queue.popFirst();
                                    continue :load;
                                },
                                else => return self.err(e),
                            };
                        continue :loop;
                    }

                    // if no song in queue
                    self.audio_state = .eof;
                    self.epoll_wait = -1;
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

fn LinkedList(comptime T: type) type {
    return struct {
        const List = @This();

        start: ?*Node = null,
        end: ?*Node = null,

        pub const init: List = .{};

        pub fn pushFirst(self: *List, item: *Node) void {
            if (self.start) |s| item.next = s else self.end = item;
            self.start = item;
        }
        pub fn pushLast(self: *List, item: *Node) void {
            if (self.end) |e| e.next = item else self.start = item;
            self.end = item;
        }

        pub fn popFirst(self: *List) ?*Node {
            const ret = self.start orelse return null;
            self.start = ret.next;
            if (self.start == null) self.end = null;
            return ret;
        }

        pub const Node = struct {
            value: T,
            next: ?*Node = null,

            pub fn pushNext(self: *Node, to_push: *Node) void {
                if (self.next) |n| to_push.next = n;
                self.next = to_push;
            }
            pub fn pushNth(self: *Node, to_push: *Node, n: usize) void {
                if (n == 0) self.pushNext(to_push);
                if (self.next) |next| next.pushNth(to_push, n - 1);
            }
        };
    };
}
