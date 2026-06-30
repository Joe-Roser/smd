const std = @import("std");

const Logger = @This();

const Level = enum { debug, prod };
const level = switch (std.builtin.OptimizeMode) {
    .Debug => .debug,
    else => .prod,
};

writer: std.Io.Writer,
