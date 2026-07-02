const std = @import("std");
const zio = @import("zio");
const event = @import("event.zig");

const sink = @import("sink.zig");
const source = @import("source.zig");

const RB = @import("pw_audio").SPSC_f32;
const Logger = @import("Logger.zig");
const Client = event.Client;
const Epoll = zio.Epoll;
const Queue = LinkedList([:0]const u8);

const stdin = std.Io.File.stdin();

const AudioState = enum(u8) { paused, playing, eof };

const Main = struct {
    client: *Client,
    logger: *Logger,
    audio_state: AudioState,
    queue: *Queue,

    source: *source.Source,
    sink: *sink.Sink,
    rb: *RB,

    pub fn init(client: *Client, logger: *Logger, src: *source.Source, snk: *sink.Sink, queue: *Queue, rb: *RB) Main {
        return .{
            .client = client,
            .logger = logger,
            .audio_state = .eof,
            .queue = queue,

            .source = src,
            .sink = snk,
            .rb = rb,
        };
    }

    pub fn err(self: *Main, erro: anyerror) void {
        self.logger.log("{any}", .{erro}, .err);
        self.client.broadcast_spinning(.err_unrecoverable);
    }

    fn run(self: *Main, alloc: std.mem.Allocator) void {
        var epoll = Epoll.init(.{}) catch |e|
            return self.err(e);
        defer epoll.deinit();
        epoll.add(self.client.fd.fd, Epoll.IN, .{ .u64 = 0 }) catch |e|
            return self.err(e);
        epoll.add(stdin.handle, Epoll.IN, .{ .u64 = 1 }) catch |e|
            return self.err(e);

        var events: [8]Epoll.Event = undefined;

        loop: while (true) {
            const n = epoll.wait(&events, -1) catch
                continue :loop;

            events: for (events[0..n]) |ev|
                switch (ev.data.u64) {
                    0 => {
                        self.client.fd.read() catch {};

                        while (self.client.receive()) |r| {
                            switch (r) {
                                .quit, .err_unrecoverable => {
                                    self.logger.log("Received: {}", .{r}, .info);
                                    if (self.source.title) |t| alloc.free(t);
                                    self.source.title = null;
                                    break :loop;
                                },
                                .song_end => {
                                    self.logger.log("Song End", .{}, .debug);
                                    if (self.queue.popFirst()) |song| {
                                        if (self.source.title) |t| alloc.free(t);
                                        self.source.title = song.value;
                                        alloc.destroy(song);

                                        self.client.broadcast_spinning(.song_path_loaded);
                                    } else {
                                        self.audio_state = .paused;
                                        self.client.broadcast_spinning(.pause);
                                    }
                                },
                                .low_tide, .high_tide => {},
                                .song_path_loaded, .play, .pause, .clear, .zero => unreachable,
                            }
                        }
                    },
                    1 => {
                        var msg: [1024]u8 = undefined;
                        const m = std.os.linux.read(stdin.handle, &msg, msg.len);

                        if (std.mem.eql(u8, "q\n", msg[0..m])) {
                            self.client.broadcast_spinning(.quit);
                            if (self.source.title) |t| alloc.free(t);
                            self.source.title = null;
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
                            const path = msg[6 .. m - 1];
                            const path_dupe = alloc.dupeSentinel(u8, path, 0) catch |e|
                                return self.err(e);

                            if (self.source.title == null) {
                                self.source.title = path_dupe;
                                self.audio_state = .playing;
                                self.client.broadcast_spinning(.song_path_loaded);
                                self.client.broadcast_spinning(.play);
                            } else {
                                const node = alloc.create(Queue.Node) catch |e|
                                    return self.err(e);
                                node.* = .{ .value = path_dupe };

                                self.queue.pushLast(node);
                            }
                            continue :events;
                        }
                        if (std.mem.eql(u8, "clear\n", msg[0..m])) {
                            self.client.broadcast_spinning(.clear);
                            self.audio_state = .eof;
                            while (self.queue.popFirst()) |path| {
                                alloc.free(path.value);
                                alloc.destroy(path);
                            }
                            self.source.freezefd.read() catch {};

                            // Source
                            //  clear the song there
                            //  make sure not decoding
                            //  clear the ring buffer

                            if (self.source.title) |t| alloc.free(t);
                            self.source.title = null;
                            self.source.rb.reset();
                            self.source.decoder.deinitSong();
                            self.source.eof = true;

                            self.client.broadcast_spinning(.pause);

                            self.source.defrostfd.write() catch {};
                            self.logger.log("clear complete", .{}, .debug);
                            continue :events;
                        }
                        self.logger.log("state - fill: {}, title: {?s}, high_tide?: {}", .{ self.rb.fill(), self.source.title, self.sink.high_tide }, .debug);
                    },
                    else => unreachable,
                };
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    const stdout = std.Io.File.stdout();
    var stdout_w = stdout.writer(io, &.{});
    var logger: Logger = .init(&stdout_w.interface);
    logger.log("Initialised Logger", .{}, .debug);

    var rb = try RB.init(128);
    defer rb.deinit();

    var queue: Queue = .init;
    defer {
        while (queue.popFirst()) |n| {
            alloc.free(n.value);
            alloc.destroy(n);
        }
    }

    // Inter thread communications via mpsc channels

    var clients: [3]Client = .{ .init, .init, .init };
    for (&clients) |*c| c.fd = try zio.EventFd.init(0, 0);
    clients[0].setClients(.{ &clients[1], &clients[2] });
    clients[1].setClients(.{ &clients[0], &clients[2] });
    clients[2].setClients(.{ &clients[0], &clients[1] });

    // Setting up threads

    var src: source.Source = try .init(&clients[1], &logger, &rb);
    var source_handle = try io.concurrent(source.Source.run, .{&src});
    errdefer source_handle.cancel(io);

    var snk: sink.Sink = try .init(&clients[2], &logger, &rb);
    var sink_handle = try io.concurrent(sink.Sink.run, .{&snk});
    errdefer sink_handle.cancel(io);

    var mn = Main.init(&clients[0], &logger, &src, &snk, &queue, &rb);
    mn.run(alloc);

    _ = source_handle.await(io);
    _ = sink_handle.await(io);
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
