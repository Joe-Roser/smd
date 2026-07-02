const std = @import("std");
const zio = @import("zio");
const event = @import("event.zig");

const Control = @import("Control.zig");
const Sink = @import("Sink.zig");
const Source = @import("Source.zig");

const RB = @import("pw_audio").SPSC_f32;
const Logger = @import("Logger.zig");
const Client = event.Client;
const Epoll = zio.Epoll;
const Queue = Control.Queue;

const stdin = std.Io.File.stdin();

const AudioState = enum(u8) { paused, playing, eof };

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

    var src: Source = try .init(&clients[1], &logger, &rb);
    var source_handle = try io.concurrent(Source.run, .{&src});
    errdefer source_handle.cancel(io);

    var snk: Sink = try .init(&clients[2], &logger, &rb);
    var sink_handle = try io.concurrent(Sink.run, .{&snk});
    errdefer sink_handle.cancel(io);

    var mn = Control.init(&clients[0], &logger, &src, &snk, &queue, &rb);
    mn.run(alloc);

    _ = source_handle.await(io);
    _ = sink_handle.await(io);
}
