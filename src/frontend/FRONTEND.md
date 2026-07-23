pub const Messages = @import("interface");
const Frontend = @This();

pub fn init(alloc: std.mem.Allocator) !*Frontend;

pub fn deinit(self: *Frontend, alloc: std.mem.Allocator) void;

pub fn getFd(self: *Frontend) std.posix.fd_t;

pub fn poll(self: *Frontend) Messages.Command;

pub fn respond(_: *Frontend, cmd: Messages.Command, res: Messages.Response) void;

pub fn notify(self: *Frontend, notification: Messages.Notification) void;
