pub const Command = union(enum) {
    none,
    quit,
    play,
    pause,
    play_pause,
    enqueue: []const u8,
    clear,
    previous,
    next,
    seek_by: i64,
    seek_to: i64,
    tracklist,
};
pub const Response = union(enum) {
    succ,
    err,
    tracklist: []const []const u8,
};
