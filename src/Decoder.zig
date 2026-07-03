const std = @import("std");
const ff = @import("ffmpeg");

const RB = @import("pw_audio").SPSC_f32;
const Decoder = @This();

target_channels: i32 = 2,
target_sample_rate: i32 = 48000,

fmt_ctx: ?*ff.AVFormatContext = null,
codec_ctx: ?*ff.AVCodecContext = null,
stream_idx: c_int = -1,

needs_resampling: bool = false,
swr: ?*ff.SwrContext = null,
conv_buf: ?[*]u8 = null,
conv_buffer_samples: i32 = 0,

pkt: *ff.AVPacket,
frame: *ff.AVFrame,

frame_unfinished: bool = false,
frame_offset: u32 = 0,
frame_len: u32 = 0,

pub fn init() ?Decoder {
    const pkt = ff.av_packet_alloc() orelse return null;
    errdefer ff.av_packet_free(&pkt);

    const frame = ff.av_frame_alloc() orelse return null;
    errdefer ff.av_frame_free(&frame);

    return .{
        .pkt = pkt,
        .frame = frame,
    };
}
pub fn deinit(self: *Decoder) void {
    ff.av_packet_free(&self.pkt);
    ff.av_frame_free(&self.frame);
}

/// Convert libav errors to zig errors
fn avError(err: i32) !void {
    if (err >= 0) return;
    return switch (err) {
        ff.AVERROR(ff.EAGAIN) => error.AV_AGAIN,
        ff.AVERROR(ff.ENOMEM) => error.AV_NOMEM,
        ff.AVERROR(ff.EINVAL) => error.AV_INVAL,
        ff.AVERROR(ff.EIO) => error.AV_IO,
        ff.AVERROR(ff.ENOENT) => error.AV_NOENT,
        ff.AVERROR(ff.EPERM) => error.AV_PERM,
        ff.AVERROR(ff.EACCES) => error.AV_ACCES,

        ff.AVERROR_BUG => error.AVERROR_BUG,
        ff.AVERROR_BUFFER_TOO_SMALL => error.AVERROR_BUFFER_TOO_SMALL,
        ff.AVERROR_EOF => error.AVERROR_EOF,
        ff.AVERROR_EXIT => error.AVERROR_EXIT,
        ff.AVERROR_EXTERNAL => error.AVERROR_EXTERNAL,
        ff.AVERROR_INVALIDDATA => error.AVERROR_INVALIDDATA,
        ff.AVERROR_PATCHWELCOME => error.AVERROR_PATCHWELCOME,

        ff.AVERROR_BUG2 => error.AVERROR_BUG2,
        ff.AVERROR_UNKNOWN => error.AVERROR_UNKNOWN,
        ff.AVERROR_EXPERIMENTAL => error.AVERROR_EXPERIMENTAL,
        ff.AVERROR_INPUT_CHANGED => error.AVERROR_INPUT_CHANGED,
        ff.AVERROR_OUTPUT_CHANGED => error.AVERROR_OUTPUT_CHANGED,

        else => error.UnknownAVError,
    };
}

pub fn initSong(self: *Decoder, song_path: [*:0]const u8) !void {
    try avError(ff.avformat_open_input(&self.fmt_ctx, song_path, null, null));
    errdefer ff.avformat_close_input(@ptrCast(&self.fmt_ctx));
    try avError(ff.avformat_find_stream_info(self.fmt_ctx.?, null));

    self.stream_idx = ff.av_find_best_stream(self.fmt_ctx.?, ff.AVMEDIA_TYPE_AUDIO, -1, -1, null, 0);
    try avError(self.stream_idx);

    const stream = self.fmt_ctx.?.streams[@intCast(self.stream_idx)];

    const codec = ff.avcodec_find_decoder(stream.*.codecpar.*.codec_id) orelse return error.NoCodec;
    self.codec_ctx = ff.avcodec_alloc_context3(codec) orelse return error.NoCodec;
    errdefer ff.avcodec_free_context(&self.codec_ctx);

    try avError(ff.avcodec_parameters_to_context(self.codec_ctx, stream.*.codecpar));
    try avError(ff.avcodec_open2(self.codec_ctx, codec, null));

    var layout: ff.AVChannelLayout = undefined;
    _ = ff.av_channel_layout_default(&layout, self.target_channels);

    self.needs_resampling =
        !(self.codec_ctx.?.sample_fmt == ff.AV_SAMPLE_FMT_FLT and
            self.codec_ctx.?.sample_rate == self.target_sample_rate and
            self.codec_ctx.?.ch_layout.nb_channels == self.target_channels);

    if (self.needs_resampling) {
        try avError(ff.swr_alloc_set_opts2(
            &self.swr,
            &layout,
            ff.AV_SAMPLE_FMT_FLT,
            self.target_sample_rate,
            &self.codec_ctx.?.ch_layout,
            self.codec_ctx.?.sample_fmt,
            self.codec_ctx.?.sample_rate,
            0,
            null,
        ));
        try avError(ff.swr_init(self.swr));
    }
    errdefer if (self.swr) |_| ff.swr_free(&self.swr);
}
pub fn deinitSong(self: *Decoder) void {
    if (self.conv_buf) |_| ff.av_freep(@ptrCast(&self.conv_buf.?));
    self.conv_buffer_samples = 0;

    if (self.swr) |_| ff.swr_free(&self.swr);
    self.swr = null;

    if (self.codec_ctx) |_| ff.avcodec_free_context(&self.codec_ctx);
    self.codec_ctx = null;
    if (self.fmt_ctx) |_| ff.avformat_close_input(&self.fmt_ctx);

    self.frame_unfinished = false;
    self.frame_len = 0;
    self.frame_offset = 0;
}

/// Loads a new frame.
/// Flushes on EOF. Should not be called after then, which should never happen because receive_frame should return EOF before then, and the whole loop should be stopped
fn receivePacket(self: *Decoder) !void {
    while (true) {
        const read_frm = ff.av_read_frame(self.fmt_ctx, self.pkt);
        if (read_frm == ff.AVERROR_EOF) {
            return avError(ff.avcodec_send_packet(self.codec_ctx, null));
        } else try avError(read_frm);

        defer ff.av_packet_unref(self.pkt);

        if (self.pkt.stream_index != self.stream_idx) continue;

        return avError(ff.avcodec_send_packet(self.codec_ctx, self.pkt));
    }
}
/// Grab next frame, else grab next packet and next frame. If EOF, return so.
fn receiveFrame(self: *Decoder) !void {
    while (true) {
        const rec_frame = ff.avcodec_receive_frame(self.codec_ctx, self.frame);
        if (rec_frame >= 0) return;

        if (rec_frame == ff.AVERROR_EOF) return error.EOF;
        if (rec_frame != ff.AVERROR(ff.EAGAIN)) try avError(rec_frame);
        // Only EAGAIN left

        try self.receivePacket();
    }
}

/// Writes a single frame from ffmpeg into the ring buffer.
/// Returns either void (Success), EOF (music file ended) or WouldBlock (failed to write whole frame).
/// Crashes if no song is initialised, or called after EOF
pub fn writeFrame(self: *Decoder, rb: *RB) !void {
    // Try write previous frame data
    if (self.frame_unfinished) {
        const buf: [*]f32 = if (self.needs_resampling)
            @ptrCast(@alignCast(self.conv_buf.?))
        else
            @ptrCast(@alignCast(self.frame.data[0]));

        const w = rb.write(buf[self.frame_offset..self.frame_len]);
        self.frame_offset += w;

        if (self.frame_offset != self.frame_len) {
            return error.WouldBlock;
        }

        self.frame_unfinished = false;
        ff.av_frame_unref(self.frame);
    }

    // workaround to use continue if no frame data is here
    while (true) {
        try self.receiveFrame();

        var w: u32 = undefined;
        var n_floats: u32 = undefined;

        // Write frame data
        if (self.needs_resampling) {
            const out_samples = ff.swr_get_out_samples(self.swr, self.frame.nb_samples);
            if (out_samples > self.conv_buffer_samples) {
                if (self.conv_buf) |*b| ff.av_freep(@ptrCast(b));
                var raw: ?[*]u8 = null;
                _ = ff.av_samples_alloc(&raw, null, self.target_channels, out_samples, ff.AV_SAMPLE_FMT_FLT, 0);
                self.conv_buf = raw;
                self.conv_buffer_samples = out_samples;
            }

            var out_ptr = self.conv_buf.?;
            const converted = ff.swr_convert(
                self.swr,
                @ptrCast(&out_ptr),
                out_samples,
                @ptrCast(&self.frame.data[0]),
                self.frame.nb_samples,
            );
            if (converted <= 0) continue;

            n_floats = @intCast(converted * self.target_channels);
            w = rb.write(@as([*]f32, @ptrCast(@alignCast(self.conv_buf.?)))[0..n_floats]);
        } else {
            n_floats = @as(u32, @intCast(self.frame.nb_samples * self.target_channels));
            const data: [*]f32 = @ptrCast(@alignCast(self.frame.data[0]));
            w = rb.write(data[0..n_floats]);
        }
        // If didnt write the whole frame, means there wasn't enough space, so keep frame around,
        // store relevant info, and return Block
        if (w != n_floats) {
            self.frame_offset = w;
            self.frame_len = n_floats;
            self.frame_unfinished = true;
            return error.WouldBlock;
        }

        ff.av_frame_unref(self.frame);
        break;
    }
}
