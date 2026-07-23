const std = @import("std");

const Control = @import("Control.zig");
const Sink = @import("Sink.zig");

const Frontend = @import("Frontend");
const RB = @import("Audio").RB;
const Logger = @import("Logger.zig");
const Client = @import("event.zig").Client;

const AUDIO_BUFFER_PAGES = 128;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    const stdout = std.Io.File.stdout();
    var stdout_w = stdout.writer(io, &.{});
    var logger: Logger = .init(&stdout_w.interface);

    const frontend = try Frontend.init(alloc);
    defer frontend.deinit(alloc);

    var rb = try RB.init(AUDIO_BUFFER_PAGES);
    defer rb.deinit();

    // Inter thread communications via mpsc channels

    var ctrl_client: Client = .{ .peer = undefined, .fd = try .init(1, 0) };
    var sink_client: Client = .{ .peer = &ctrl_client, .fd = try .init(1, 0) };
    ctrl_client.peer = &sink_client;

    // Setting up threads

    var sink: Sink = try .init(&sink_client, &logger, &rb);
    var sink_handle = try io.concurrent(Sink.run, .{ &sink, alloc });
    errdefer sink_handle.cancel(io);

    var ctrl = Control.init(frontend, &ctrl_client, &logger, &rb, sink.ack_fd) orelse return error.NoCtrl;
    defer ctrl.deinit(alloc);
    ctrl.run(alloc);

    _ = sink_handle.await(io);
}
