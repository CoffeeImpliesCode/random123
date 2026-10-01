//! A separate package that consumes the Random123 fork as a real dependency.
//!
//! It deliberately uses nothing but `b.dependency("random123", …).module(…)`:
//! the Zig module already links the compiled `librandom123` artifact and
//! carries the translated C declarations, so a downstream package needs no
//! extra wiring and no `dep.artifact` call.
//!
//! Run with `zig build run` from this directory.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("random123", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("random123", dep.module("random123"));

    const exe = b.addExecutable(.{ .name = "random123-consumer", .root_module = exe_mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.has_side_effects = true;
    if (b.args) |args| run.addArgs(args);

    // `b.step(...)` already returns a `*Build.Step`, and `dependOn` takes that
    // pointer directly -- there is no `.step` field to take the address of.
    // The install step is deliberately left alone: `b.installArtifact` above
    // already installs the executable, and making the default `zig build`
    // *run* it would turn an ordinary build into a side effect.
    b.step("run", "Run the consumer example against the Random123 fork").dependOn(&run.step);
}
