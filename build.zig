const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ring buffer library unit
    const spsc_lib = b.addLibrary(.{
        .name = "spsc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("mods/spsc_queue.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // pw c abstraction to avoid ctranslate of pipewire
    const pw_audio_c = b.addTranslateC(.{
        .root_source_file = b.path("pw_audio/pw_audio.h"),
        .target = target,
        .optimize = optimize,
    });
    // pipewire module
    const pw_audio_mod = b.addModule("PipeWire", .{
        .root_source_file = b.path("mods/PipeWire.zig"),
        .target = target,
        .optimize = optimize,
    });
    pw_audio_mod.addImport("pw_c", pw_audio_c.createModule());
    pw_audio_mod.addCSourceFiles(.{
        .files = &.{"pw_audio/pw_audio.c"},
    });
    pw_audio_mod.linkSystemLibrary("libpipewire-0.3", .{});
    pw_audio_mod.linkLibrary(spsc_lib);

    // epoll
    const zio_mod = b.addModule("zio", .{
        .root_source_file = b.path("mods/zio.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    exe.root_module.addImport("pw_audio", pw_audio_mod);
    exe.root_module.addImport("ffmpeg", ffmpeg_c.createModule());
    exe.root_module.addImport("zio", zio_mod);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the exe");
    const run_art = b.addRunArtifact(exe);
    run_step.dependOn(&run_art.step);
}
