const std = @import("std");

const stdin = std.Io.File.stdin();
pub const Messages = @import("interface");
const Frontend = @This();

read_buffer: [2048]u8,

pub fn init(alloc: std.mem.Allocator) !*Frontend {
    return alloc.create(Frontend);
}
pub fn deinit(self: *Frontend, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn getFd(_: *Frontend) std.posix.fd_t {
    return stdin.handle;
}

pub fn poll(self: *Frontend) Messages.Command {
    // TODO: Errors
    const m = std.os.linux.read(stdin.handle, &self.read_buffer, self.read_buffer.len);
    const msg = std.mem.trim(u8, self.read_buffer[0..m], " \r\n");

    // quit
    if (std.mem.eql(u8, "q", msg)) {
        return .quit;
    } else if (std.mem.startsWith(u8, msg, "getProp ")) {
        const prop = std.meta.stringToEnum(Messages.DynamicProperty, msg[8..]);

        if (prop) |p| { // DynamicProperties
            return .{ .get_property = p };
        } else { // StaticProperties
            const static = std.meta.stringToEnum(Messages.StaticProperty, msg[8..]) orelse {
                std.debug.print("Property not recognised\n", .{});
                return .none;
            };
            switch (static) {
                // booleans
                .can_quit, .fullscreen, .can_set_fullscreen, .can_raise, .has_tracklist, .can_go_next, .can_go_previous, .can_play, .can_pause, .can_seek, .can_control => {
                    std.debug.print("{}\n", .{@intFromPtr(static.response()) == 1});
                },
                //
                .minimum_rate, .maximum_rate => {
                    std.debug.print("{}\n", .{@intFromPtr(static.response())});
                },
                .identity, .desktop_entry => {
                    std.debug.print("{s}\n", .{@as(*const []const u8, @ptrCast(@alignCast(static.response()))).*});
                },
                .supported_uri_schemes, .supported_mime_types => {
                    std.debug.print("{any}\n", .{@as(*const []const []const u8, @ptrCast(@alignCast(static.response()))).*});
                },
            }
        }
    } else if (std.mem.eql(u8, "next", msg)) {
        return .next;
    } else if (std.mem.eql(u8, "prev", msg)) {
        return .previous;
    } else if (std.mem.eql(u8, "pause", msg)) {
        return .pause;
    } else if (std.mem.eql(u8, "playPause", msg)) {
        return .play_pause;
    } else if (std.mem.eql(u8, "stop", msg)) {
        return .stop;
    } else if (std.mem.eql(u8, "play", msg)) {
        return .play;
    } else if (std.mem.startsWith(u8, msg, "seek ")) {
        const by = std.fmt.parseInt(i64, msg[7..], 10) catch {
            // std.debug.print("Invalid integer: {s}", .{msg[7..]}, .info);
            return .none;
        };

        return .{ .seek = by };
    } else if (std.mem.startsWith(u8, msg, "setPos ")) {
        const to = std.fmt.parseInt(i64, msg[7..], 10) catch {
            // std.debug.print("Invalid integer: {s}", .{msg[7..]}, .info);
            return .none;
        };
        // TODO: Tracklist number
        return .{ .set_position = .{ 0, to * 1_000_000 } };
    } else if (std.mem.startsWith(u8, msg, "open ")) {
        return .{ .open_uri = msg[5..] };
    } else if (std.mem.eql(u8, "clear", msg)) {
        return .clear;
    } else if (std.mem.eql(u8, "tracklist", msg)) {
        return .tracklist;
    }

    // No match
    return .none;
}

pub fn respond(_: *Frontend, cmd: Messages.Command, res: Messages.Response) void {
    switch (res) {
        .succ, .err => {
            std.debug.print("{any} - {any}\n", .{ cmd, res });
        },
        .property_response => |resp| switch (cmd.get_property) {
            .playback_status => {
                std.debug.print("{s}\n", .{@as(*const []const u8, @ptrCast(@alignCast(resp))).*});
            },
            .position => {
                std.debug.print("{}\n", .{@as(usize, @intFromPtr(resp))});
            },
            else => @panic("Oopa"),
        },
        .tracklist => |tl| {
            for (tl, 0..) |track, i| {
                std.debug.print("{}. {s}\n", .{ i, track });
            }
        },
    }
}

pub fn notify(self: *Frontend, notification: Messages.Notification) void {
    _ = self;
    std.debug.print("Notification: {any}", .{notification});
}
