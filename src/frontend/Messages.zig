pub const Command = union(enum) {
    none,
    quit,
    get_property: Property,

    next,
    previous,
    pause,
    play_pause,
    stop,
    play,
    seek: i64,
    set_position: struct { u32, i64 },
    open_uri: []const u8,

    clear,
    tracklist,
};
pub const Response = union(enum) {
    succ,
    err,
    property_set: *const anyopaque,
    tracklist: []const []const u8,
};
pub const Notification = union(enum) {
    proerty_changed: Property,
};

pub const Property = enum {
    playback_status,
    position,
    metadata,
    capabilities,
    loop_status,
    shuffle,
    volume,
};
pub const MimeTypes = .{
    "audio/mp3",
    "audio/flac",
};
pub const UriSchemes = .{
    "file",
};
