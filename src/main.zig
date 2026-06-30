const std = @import("std");
const zio = @import("zio");
const event = @import("event.zig");

const sink = @import("sink.zig");
const source = @import("source.zig");

const RB = @import("pw_audio").SPSC_f32;
const Client = event.Client;
const Epoll = zio.Epoll;

const stdin = std.Io.File.stdin();

const AudioState = enum(u8) { paused, playing, eof };

const Main = struct {
    queue: *Queue,
    rb: *RB,
    client: *Client,
    source: *source.Source,
    sink: *sink.Sink,
    audio_state: AudioState,

    pub fn init(client: *Client, src: *source.Source, snk: *sink.Sink, queue: *Queue, rb: *RB) Main {
        return .{
            .client = client,
            .source = src,
            .sink = snk,
            .audio_state = .paused,
            .queue = queue,
            .rb = rb,
        };
    }

    fn run(self: *Main, alloc: std.mem.Allocator) void {
        var epoll = Epoll.init(.{}) catch
            return self.client.broadcast_spinning(.err_unrecoverable);
        defer epoll.deinit();
        epoll.add(self.client.fd, Epoll.IN, .{ .u64 = 0 }) catch
            return self.client.broadcast_spinning(.err_unrecoverable);
        epoll.add(stdin.handle, Epoll.IN, .{ .u64 = 1 }) catch
            return self.client.broadcast_spinning(.err_unrecoverable);

        var events: [4]Epoll.Event = undefined;

        loop: while (true) {
            const n = epoll.wait(&events, -1) catch
                continue :loop;

            events: for (events[0..n]) |e|
                switch (e.data.u64) {
                    0 => {
                        var buf: [8]u8 = undefined;
                        _ = std.os.linux.read(self.client.fd, &buf, buf.len);

                        while (self.client.receive()) |r| {
                            switch (r) {
                                .quit, .err_unrecoverable => {
                                    std.debug.print("Received: {}\n", .{r});
                                    if (self.source.title) |t| alloc.free(t);
                                    self.source.title = null;
                                    break :loop;
                                },
                                .song_end => {
                                    std.debug.print("Song End\n", .{});
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
                                .song_path_loaded, .pause, .play => unreachable,
                            }
                        }
                    },
                    1 => {
                        var msg: [1024]u8 = undefined;
                        const m = std.os.linux.read(stdin.handle, &msg, msg.len);

                        if (std.mem.eql(u8, "q\n", msg[0..m])) {
                            self.client.broadcast_spinning(.quit);
                            std.debug.print("Quit\n", .{});
                            if (self.source.title) |t| alloc.free(t);
                            self.source.title = null;
                            break :loop;
                        }
                        if (std.mem.eql(u8, "pause\n", msg[0..m])) {
                            self.audio_state = .paused;
                            self.client.broadcast_spinning(.pause);
                            continue :events;
                        }
                        if (std.mem.eql(u8, "play\n", msg[0..m])) {
                            if (self.audio_state == .eof) {
                                std.debug.print("Play Failed, EOF\n", .{});
                                continue :events;
                            }

                            self.audio_state = .playing;
                            self.client.broadcast_spinning(.play);
                            continue :events;
                        }
                        if (std.mem.startsWith(u8, msg[0..m], "path: ")) {
                            const path = msg[6 .. m - 1];
                            const path_dupe = alloc.dupeSentinel(u8, path, 0) catch
                                return self.client.broadcast_spinning(.err_unrecoverable);

                            if (self.source.title == null) {
                                self.source.title = path_dupe;
                                self.audio_state = .playing;
                                self.client.broadcast_spinning(.song_path_loaded);
                                self.client.broadcast_spinning(.play);
                            } else {
                                const node = alloc.create(Queue.Node) catch
                                    return self.client.broadcast_spinning(.err_unrecoverable);
                                node.value = path_dupe;

                                self.queue.pushLast(node);
                            }
                        }
                        if (std.mem.eql(u8, "clear\n", msg[0..m])) {
                            self.client.broadcast_spinning(.pause);
                            self.audio_state = .eof;
                            if (self.source.title) |t| alloc.free(t);
                            self.source.title = null;

                            while (self.queue.popFirst()) |node| {
                                alloc.free(node.value);
                                alloc.destroy(node);
                            }

                            var threaded = std.Io.Threaded.init_single_threaded;
                            threaded.io().sleep(.fromMilliseconds(10), .real) catch {};
                            // TODO: For this to be safe, we need to receive some kind of ack. figure out how to do this.
                            self.rb.reset();
                            std.debug.print("rb_fill: {}\n", .{self.rb.fill()});

                            continue :events;
                        }
                    },
                    else => unreachable,
                };
        }
    }
};

const Queue = LinkedList([:0]const u8);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var rb = try @import("pw_audio").SPSC_f32.init(128);
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
    for (&clients) |*c| c.fd = try zio.eventfd(0, 0);
    clients[0].setClients(.{ &clients[1], &clients[2] });
    clients[1].setClients(.{ &clients[0], &clients[2] });
    clients[2].setClients(.{ &clients[0], &clients[1] });

    // Setting up threads

    var src: source.Source = .init(&clients[1], &rb);
    var source_handle = try io.concurrent(source.Source.run, .{&src});
    errdefer source_handle.cancel(io);

    var snk: sink.Sink = .init(&clients[2], &rb);
    var sink_handle = try io.concurrent(sink.Sink.run, .{&snk});
    errdefer sink_handle.cancel(io);

    var mn = Main.init(&clients[0], &src, &snk, &queue, &rb);
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
