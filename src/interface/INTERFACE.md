pub const Messages = @import("interface");
const Interface = @This();

pub fn init(alloc: std.mem.Allocator) !*Interface;

pub fn deinit(self: *Interface, alloc: std.mem.Allocator) void;

pub fn poll(self: *Interface) Messages.Command;

pub fn respond(_: *Interface, cmd: Messages.Command, res: Messages.Response) void;

pub fn notify(self: *Interface, notification: Messages.Notification) void;
