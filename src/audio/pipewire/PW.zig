const std = @import("std");
const pw = @import("pw");

pub const RB = @import("RB");
pub const Params = struct {
    sample_rate: u32,
    channels: u32,
};
const State = enum { zero, play, paused };

const Audio = @This();

rb: *RB,
loop: *pw.pw_main_loop,
stream: *pw.pw_stream,

state: State,

const stream_events: pw.pw_stream_events = .{
    .process = struct {
        fn cb(userdata: ?*anyopaque) callconv(.c) void {
            const self: *Audio = @ptrCast(@alignCast(userdata.?));

            const b = pw.pw_stream_dequeue_buffer(self.stream) orelse return;

            const sb = b.*.buffer;
            var dst: [*]u8 = @ptrCast(sb.*.datas[0].data);
            // TODO: Use b.requested instead
            const size = sb.*.datas[0].maxsize;
            const num = size / @sizeOf(f32);

            if (self.state == .zero) {
                @memset(dst[0..size], 0);
                sb.*.datas[0].chunk.*.size = size;
                // TODO:
                _ = pw.pw_stream_queue_buffer(self.stream, b);
                return;
            }

            const arr: [*]f32 = @ptrCast(@alignCast(dst));
            const size_read = self.rb.read(arr[0..num]);
            sb.*.datas[0].chunk.*.size = size_read * @sizeOf(f32);
            // TODO:
            _ = pw.pw_stream_queue_buffer(self.stream, b);
        }
    }.cb,
};

pub fn init(alloc: std.mem.Allocator, params: Params, rb: *RB) !*Audio {
    var self = try alloc.create(Audio);
    errdefer alloc.destroy(self);

    pw.pw_init(null, null);
    errdefer pw.pw_deinit();

    self.rb = rb;
    self.loop = pw.pw_main_loop_new(null) orelse return error.NoLoop;
    errdefer pw.pw_main_loop_destroy(self.loop);

    const props = pw.pw_properties_new(
        pw.PW_KEY_MEDIA_TYPE,
        "Audio",
        pw.PW_KEY_MEDIA_CATEGORY,
        "Playback",
        pw.PW_KEY_MEDIA_ROLE,
        "Music",
        @as(?*anyopaque, null),
    );

    const loop = pw.pw_main_loop_get_loop(self.loop).?;
    self.stream = pw.pw_stream_new_simple(loop, "smd", props, &stream_events, self) orelse return error.NoStream;
    errdefer pw.pw_stream_destroy(self.stream);

    const audio_info = pw.spa_audio_info_raw{
        .format = pw.SPA_AUDIO_FORMAT_F32,
        .rate = params.sample_rate,
        .channels = params.channels,
    };

    var buf: [1024]u8 = undefined;
    var builder: pw.struct_spa_pod_builder = .{
        .data = &buf,
        .size = buf.len,
        ._padding = 0,
        .state = .{ .offset = 0, .flags = 0, .frame = null },
        .callbacks = .{ .funcs = null, .data = null },
    };

    var params_pod = pw.format_audio_raw_build_workaround(
        &builder,
        pw.SPA_PARAM_EnumFormat,
        &audio_info,
    ) orelse return error.NoParams;

    const res = pw.pw_stream_connect(
        self.stream,
        pw.PW_DIRECTION_OUTPUT,
        pw.PW_ID_ANY,
        pw.PW_STREAM_FLAG_AUTOCONNECT | pw.PW_STREAM_FLAG_MAP_BUFFERS,
        @ptrCast(&params_pod),
        1,
    );
    if (res < 0) return error.ConnectFailed;

    self.state = .paused;
    return self;
}
pub fn deinit(self: *Audio, alloc: std.mem.Allocator) void {
    pw.pw_stream_destroy(self.stream);
    pw.pw_main_loop_destroy(self.loop);
    pw.pw_deinit();
    alloc.destroy(self);
}

pub fn clear(self: *Audio) void {
    // TODO:
    _ = pw.pw_stream_flush(self.stream, false);
}

pub fn zero(self: *Audio) void {
    if (self.state == .zero) return;
    // TODO:
    if (self.state == .paused) _ = pw.pw_stream_set_active(self.stream, true);
    self.state = .zero;
}
pub fn play(self: *Audio) void {
    if (self.state == .play) return;
    // TODO:
    if (self.state == .paused) _ = pw.pw_stream_set_active(self.stream, true);
    self.state = .play;
}
pub fn pause(self: *Audio) void {
    if (self.state == .paused) return;
    // TODO:
    _ = pw.pw_stream_set_active(self.stream, false);
    self.state = .paused;
}

pub fn getFd(self: *Audio) std.posix.fd_t {
    return pw.pw_loop_get_fd(pw.pw_main_loop_get_loop(self.loop));
}
pub fn iterate(self: *Audio) void {
    // TODO:
    _ = pw.pw_loop_iterate(pw.pw_main_loop_get_loop(self.loop), 0);
}
