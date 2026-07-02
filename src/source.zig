const std = @import("std");

const zio = @import("zio");
const event = @import("event.zig");
const ff = @import("ffmpeg");

const Logger = @import("Logger.zig");
const RB = @import("pw_audio").SPSC_f32;
const Client = event.Client;
const Epoll = zio.Epoll;

const FFState = struct {
    target_channels: i32 = 2,
    target_sample_rate: i32 = 48000,

    fmt_ctx: ?*ff.AVFormatContext = null,
    codec_ctx: ?*ff.AVCodecContext = null,
    swr: ?*ff.SwrContext = null,
    pkt: ?*ff.AVPacket = null,
    frame: ?*ff.AVFrame = null,
    stream_idx: c_int = -1,

    conv_buf: ?[*]u8 = null,
    conv_buffer_samples: i32 = 0,
    needs_resampling: bool = false,

    eof: bool = false,

    frame_unfinished: bool = false,
    frame_offset: u32 = 0,
    frame_len: u32 = 0,

    pub fn init() ?FFState {
        const pkt = ff.av_packet_alloc() orelse return null;
        errdefer ff.av_packet_free(&pkt);

        const frame = ff.av_frame_alloc() orelse return null;
        errdefer ff.av_frame_free(&frame);

        return .{
            .pkt = pkt,
            .frame = frame,
        };
    }
    pub fn deinit(self: *FFState) void {
        ff.av_packet_free(&self.pkt);
        ff.av_frame_free(&self.frame);
    }
    pub fn avError(err: i32) void {
        // TODO:
        _ = err;
    }

    fn initSong(self: *FFState, song_path: [*:0]const u8) !void {
        if (ff.avformat_open_input(&self.fmt_ctx, song_path, null, null) < 0) return error.FailedToLoad;
        errdefer ff.avformat_close_input(@ptrCast(&self.fmt_ctx));
        if (ff.avformat_find_stream_info(self.fmt_ctx.?, null) < 0) return;

        self.stream_idx = ff.av_find_best_stream(self.fmt_ctx.?, ff.AVMEDIA_TYPE_AUDIO, -1, -1, null, 0);
        if (self.stream_idx < 0) return error.FailedToFindStream;

        const stream = self.fmt_ctx.?.streams[@intCast(self.stream_idx)];

        const codec = ff.avcodec_find_decoder(stream.*.codecpar.*.codec_id) orelse return error.NoCodec;
        self.codec_ctx = ff.avcodec_alloc_context3(codec) orelse return error.NoCodec;
        errdefer ff.avcodec_free_context(&self.codec_ctx);

        if (ff.avcodec_parameters_to_context(self.codec_ctx, stream.*.codecpar) < 0) return;
        if (ff.avcodec_open2(self.codec_ctx, codec, null) < 0) return;

        var layout: ff.AVChannelLayout = undefined;
        _ = ff.av_channel_layout_default(&layout, self.target_channels);

        self.needs_resampling =
            !(self.codec_ctx.?.sample_fmt == ff.AV_SAMPLE_FMT_FLT and
                self.codec_ctx.?.sample_rate == self.target_sample_rate and
                self.codec_ctx.?.ch_layout.nb_channels == self.target_channels);

        if (self.needs_resampling) {
            if (ff.swr_alloc_set_opts2(
                &self.swr,
                &layout,
                ff.AV_SAMPLE_FMT_FLT,
                self.target_sample_rate,
                &self.codec_ctx.?.ch_layout,
                self.codec_ctx.?.sample_fmt,
                self.codec_ctx.?.sample_rate,
                0,
                null,
            ) < 0) return error.NoResampling;
            if (ff.swr_init(self.swr) < 0) return error.NoResampling;
        }
        errdefer if (self.swr) |_| ff.swr_free(&self.swr);

        self.eof = false;
    }
    pub fn deinitSong(self: *FFState) void {
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

    /// Returns either EOF (music file ended) or WouldBlock (failed to write whole frame)
    fn writeFrame(self: *FFState, rb: *RB) !void {
        // Try write previous frame data
        if (self.frame_unfinished) {
            const buf: [*]f32 = if (self.needs_resampling)
                @ptrCast(@alignCast(self.conv_buf.?))
            else
                @ptrCast(@alignCast(self.frame.?.data[0]));

            const w = rb.write(buf[self.frame_offset..self.frame_len]);
            self.frame_offset += w;

            if (self.frame_offset != self.frame_len) {
                return error.WouldBlock;
            }

            self.frame_unfinished = false;
            ff.av_frame_unref(self.frame);
        }

        // workaround to use continue if no frame data is here
        read_frame: switch (true) {
            true => {
                // TODO: Logic not very  well stated

                // Grab next frame, else grab next packet and next frame. If EOF, return so.
                const rec_frame = ff.avcodec_receive_frame(self.codec_ctx, self.frame);
                if (rec_frame < 0) {
                    // drop pkt
                    ff.av_packet_unref(self.pkt);

                    const read_frm = ff.av_read_frame(self.fmt_ctx, self.pkt);
                    if (read_frm < 0) {
                        if (self.eof) {
                            return error.EOF;
                        } else self.eof = true;
                    } else {
                        if (self.pkt.?.stream_index != self.stream_idx) continue :read_frame true;
                        if (ff.avcodec_send_packet(self.codec_ctx, self.pkt) < 0) continue :read_frame true;
                    }
                    continue :read_frame true;
                }

                var w: u32 = undefined;
                var n_floats: u32 = undefined;

                // Write frame data
                if (self.needs_resampling) {
                    const out_samples = ff.swr_get_out_samples(self.swr, self.frame.?.nb_samples);
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
                        @ptrCast(&self.frame.?.data[0]),
                        self.frame.?.nb_samples,
                    );
                    if (converted <= 0) continue :read_frame true;

                    n_floats = @intCast(converted * self.target_channels);
                    w = rb.write(@as([*]f32, @ptrCast(@alignCast(self.conv_buf.?)))[0..n_floats]);
                } else {
                    n_floats = @as(u32, @intCast(self.frame.?.nb_samples * self.target_channels));
                    const data: [*]f32 = @ptrCast(@alignCast(self.frame.?.data[0]));
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
            },
            false => unreachable,
        }
    }
};

pub const Source = struct {
    client: *Client,
    logger: *Logger,
    decoder: FFState,
    rb: *RB,
    title: ?[:0]const u8 = null,

    high_tide: u32,
    eof: bool,

    freezefd: zio.EventFd,
    defrostfd: zio.EventFd,

    pub fn init(client: *Client, logger: *Logger, rb: *RB) !Source {
        const high_tide_percent = 0.9;
        return .{
            .client = client,
            .logger = logger,
            .decoder = FFState.init() orelse return error.NoFFState,
            .rb = rb,

            .high_tide = @intFromFloat(@as(f32, @floatFromInt(rb._internal.capacity)) * high_tide_percent),
            .eof = true,

            .freezefd = try zio.EventFd.init(0, 0),
            .defrostfd = try zio.EventFd.init(0, 0),
        };
    }
    pub fn deinit(self: *Source) void {
        self.decoder.deinitSong();
        self.decoder.deinit();
    }

    pub fn err(self: *Source, erro: anyerror) void {
        self.logger.log("{any}", .{erro}, .err);
        self.client.broadcast_spinning(.err_unrecoverable);
    }

    pub fn run(self: *Source) void {
        var epoll = Epoll.init(.{}) catch |e|
            return self.err(e);
        defer epoll.deinit();
        epoll.add(self.client.fd.fd, Epoll.IN, .{ .u64 = 0 }) catch |e|
            return self.err(e);

        var events: [8]Epoll.Event = undefined;
        var epoll_wait: i32 = -1;
        loop: while (true) {
            const n = epoll.wait(&events, epoll_wait) catch
                continue :loop;

            for (events[0..n]) |ev|
                switch (ev.data.u64) {
                    0 => {
                        self.client.fd.read() catch {};

                        while (self.client.receive()) |r| {
                            switch (r) {
                                .quit, .err_unrecoverable => break :loop,
                                .clear => {
                                    self.freezefd.write() catch {};
                                    self.defrostfd.read() catch {};
                                },
                                .song_path_loaded => {
                                    self.decoder.initSong(self.title.?.ptr) catch |e|
                                        return self.err(e);

                                    self.logger.log("Loaded", .{}, .debug);
                                    self.eof = false;
                                    epoll_wait = 0;
                                },
                                .low_tide => {
                                    if (!self.eof) epoll_wait = 0;
                                },
                                .play, .pause => {},
                                .high_tide, .song_end, .zero => unreachable,
                            }
                        }
                    },
                    else => unreachable,
                };

            if (epoll_wait == 0) {
                for (0..5) |_| {
                    self.decoder.writeFrame(self.rb) catch |e| switch (e) {
                        error.EOF => {
                            self.decoder.deinitSong();
                            self.client.broadcast_spinning(.song_end);
                            self.eof = true;
                            epoll_wait = -1;
                            continue :loop;
                        },
                        error.WouldBlock => {
                            self.logger.log("Hit Block", .{}, .debug);
                            self.client.broadcast_spinning(.high_tide);
                            epoll_wait = -1;
                            continue :loop;
                        },
                    };
                    if (self.rb.fill() >= self.high_tide) {
                        self.client.broadcast_spinning(.high_tide);
                        epoll_wait = -1;
                        continue :loop;
                    }
                }
            }
        }
    }
};
