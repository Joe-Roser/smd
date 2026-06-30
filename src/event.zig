const std = @import("std");
const event_sys = @import("zio").event_sys;

pub const Event = enum(u8) {
    quit,
    err_unrecoverable,

    low_tide,
    high_tide,

    pause,
    play,
    song_end,
    song_path_loaded,
};

pub const Client = event_sys.Client(Event);
