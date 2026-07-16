const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ffmpeg
    const ffmpeg_c = b.addTranslateC(.{
        .root_source_file = b.path("ffmpeg/ffmpeg.h"),
        .target = target,
        .optimize = optimize,
    });
    ffmpeg_c.linkSystemLibrary("avformat", .{});
    ffmpeg_c.linkSystemLibrary("avcodec", .{});
    ffmpeg_c.linkSystemLibrary("avutil", .{});
    ffmpeg_c.linkSystemLibrary("swresample", .{});

    // smd executable
    const exe = b.addExecutable(.{
        .name = "smd",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("Audio", audio(b, target, optimize));
    exe.root_module.addImport("ffmpeg", ffmpeg_c.createModule());

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the exe");
    const run_art = b.addRunArtifact(exe);
    run_step.dependOn(&run_art.step);
}

fn audio(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const backend = b.option([]const u8, "audio", "The audio api used to output audio") orelse "pipewire";
    const rb = b.createModule(.{ .root_source_file = b.path("src/audio/RB.zig"), .target = target, .optimize = optimize });

    if (std.mem.eql(u8, "pipewire", backend)) {
        // pw c abstraction to avoid ctranslate of pipewire
        const pw_h = b.addTranslateC(.{
            .root_source_file = b.path("src/audio/pipewire/pw.h"),
            .target = target,
            .optimize = optimize,
        });
        pw_h.linkSystemLibrary("spa-0.2", .{});

        const pw_audio_mod = b.createModule(.{
            .root_source_file = b.path("src/audio/pipewire/PW.zig"),
            .target = target,
            .optimize = optimize,
        });

        pw_audio_mod.addImport("pw", pw_h.createModule());
        pw_audio_mod.addImport("RB", rb);
        pw_audio_mod.addCSourceFiles(.{ .files = &.{"src/audio/pipewire/pw.c"} });
        pw_audio_mod.linkSystemLibrary("libpipewire-0.3", .{});

        return pw_audio_mod;
    } else {
        std.debug.panic("Unrecognised audio backend supplied: {s}", .{backend});
    }
}
