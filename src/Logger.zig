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
lock_v: u32 = 0,

pub fn init(w: *std.Io.Writer) Logger {
    return .{ .writer = w };
}
pub fn log(self: *Logger, comptime msg: []const u8, args: anytype, comptime level: Level) void {
    if (@intFromEnum(level) < @intFromEnum(builtin_level)) return;
    self.lock();
    defer self.unlock();

    self.writer.print(level.toString() ++ msg ++ "\n", args) catch
        self.writer.print("Log faliure\n", .{}) catch {};
}
pub inline fn print(self: *Logger, comptime msg: []const u8, args: anytype) void {
    self.writer.print(msg, args) catch {};
}
pub fn lock(self: *Logger) void {
    var l = @atomicRmw(u32, &self.lock_v, .Add, 1, .acq_rel);
    if (l != 0) {
        l = @atomicLoad(u32, &self.lock_v, .acquire);
        while (l != 1) {
            l = @atomicLoad(u32, &self.lock_v, .acquire);
        }
    }
}
pub inline fn unlock(self: *Logger) void {
    _ = @atomicRmw(u32, &self.lock_v, .Sub, 1, .release);
}
