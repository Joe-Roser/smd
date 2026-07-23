pub const Command = union(enum) {
    none,
    quit,
    get_property: DynamicProperty,

    next,
    previous,
    pause,
    play_pause,
    stop,
    play,
    seek: i64,
    set_position: struct { u32, i64 },
    open_uri: []const u8,

    enqueue: []const u8,
    clear,
    tracklist,
};
pub const Response = union(enum) {
    succ,
    err,
    property_response: *const anyopaque,
    tracklist: []const []const u8,
};
pub const Notification = union(enum) {
    proerty_changed: DynamicProperty,
};

pub const DynamicProperty = enum {
    playback_status,
    loop_status,
    rate,
    shuffle,
    metadata,
    volume,
    position,
};
pub const StaticProperty = enum {
    // MPRIS
    can_quit,
    fullscreen,
    can_set_fullscreen,
    can_raise,
    has_tracklist,
    identity,
    desktop_entry,
    supported_uri_schemes,
    supported_mime_types,

    // MPRIS.Player
    minimum_rate,
    maximum_rate,
    can_go_next,
    can_go_previous,
    can_play,
    can_pause,
    can_seek,
    can_control,

    pub fn response(self: StaticProperty) *const anyopaque {
        return switch (self) {
            .fullscreen,
            .can_set_fullscreen,
            .has_tracklist,
            => &false,

            .can_quit,
            .can_raise,
            .can_go_next,
            .can_go_previous,
            .can_play,
            .can_pause,
            .can_seek,
            .can_control,
            => &true,

            // TODO:Should be floats
            .minimum_rate,
            .maximum_rate,
            => @ptrFromInt(44100),

            .identity => @ptrCast(&"smd-server"),
            .desktop_entry => @ptrCast(&""),
            .supported_uri_schemes => @ptrCast(&UriSchemes),
            .supported_mime_types => @ptrCast(&MimeTypes),
        };
    }
};
pub const MimeTypes: []const []const u8 = &.{
    "audio/mp3",
    "audio/flac",
};
pub const UriSchemes: []const []const u8 = &.{
    "file",
};
