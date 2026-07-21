const std = @import("std");

const stdin = std.Io.File.stdin();
pub const Messages = @import("interface");
const Interface = @This();

read_buffer: [2048]u8,

pub fn init(alloc: std.mem.Allocator) !*Interface {
    return alloc.create(Interface);
}
pub fn deinit(self: *Interface, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn poll(self: *Interface) Messages.Command {
    // TODO: Errors
    const m = std.os.linux.read(stdin.handle, &self.read_buffer, self.read_buffer.len);
    const msg = std.mem.trim(u8, self.read_buffer[0..m], " \r\n");

    // quit
    if (std.mem.eql(u8, "q", msg)) {
        return .quit;
    } else if (std.mem.eql(u8, "play", msg)) {
        return .play;
    } else if (std.mem.eql(u8, "pause", msg)) {
        return .pause;
    } else if (std.mem.eql(u8, "playPause", msg)) {
        return .play_pause;
    } else if (std.mem.startsWith(u8, msg, "path: ")) {
        return .{ .enqueue = msg[6..] };
    } else if (std.mem.eql(u8, "clear", msg)) {
        return .clear;
    } else if (std.mem.eql(u8, "prev", msg)) {
        return .previous;
    } else if (std.mem.eql(u8, "next", msg)) {
        return .next;
    } else if (std.mem.startsWith(u8, msg, "seekBy ")) {
        const by = std.fmt.parseInt(i64, msg[7..], 10) catch {
            // std.debug.print("Invalid integer: {s}", .{msg[7..]}, .info);
            return .none;
        };

        return .{ .seek_by = by };
    } else if (std.mem.startsWith(u8, msg, "seekTo ")) {
        const to = std.fmt.parseInt(i64, msg[7..], 10) catch {
            // std.debug.print("Invalid integer: {s}", .{msg[7..]}, .info);
            return .none;
        };
        return .{ .seek_to = to };
    } else if (std.mem.eql(u8, "tracklist", msg)) {
        return .tracklist;
    }

    // No match
    return .none;
}

pub fn respond(_: *Interface, cmd: Messages.Command, res: Messages.Response) void {
    switch (res) {
        .succ, .err => {
            std.debug.print("{any} - {any}\n", .{ cmd, res });
        },
        .tracklist => |tl| {
            for (tl, 0..) |track, i| {
                std.debug.print("{}. {s}\n", .{ i, track });
            }
        },
    }
}
