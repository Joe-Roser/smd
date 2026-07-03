const std = @import("std");
const event_sys = @import("zio").event_sys;

pub const Event = enum(u8) {
    quit,
    err_unrecoverable,

    low_tide,
    high_tide,

    zero,
    play,
    pause,

    clear,
};

pub const Client = event_sys.SPSCClient(Event, 128);
