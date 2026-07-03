const std = @import("std");
const builtin = @import("builtin");

const Logger = @This();

const Level = enum {
    debug,
    err,
    info,

    fn toString(self: Level) []const u8 {
        return switch (self) {
            .debug => "[DEBUG] ",
            .err => "[ERROR] ",
            .info => "[INFO] ",
        };
    }
};
const builtin_level: Level = switch (builtin.mode) {
    .Debug => .debug,
    else => .err,
};

writer: *std.Io.Writer,
lock: u32 = 0,

pub fn init(w: *std.Io.Writer) Logger {
    return .{ .writer = w };
}
pub fn log(self: *Logger, comptime msg: []const u8, args: anytype, comptime level: Level) void {
    if (@intFromEnum(level) < @intFromEnum(builtin_level)) return;
    var lock = @atomicRmw(u32, &self.lock, .Add, 1, .acq_rel);
    while (lock != 0) {
        lock = @atomicLoad(u32, &self.lock, .acquire);
    }

    self.writer.print(level.toString() ++ msg ++ "\n", args) catch
        self.writer.print("Log faliure\n", .{}) catch {};
    _ = @atomicRmw(u32, &self.lock, .Sub, 1, .release);
}
