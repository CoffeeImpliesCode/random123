// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//!
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
    // The parent build forwards its own selection verbatim, so the consumer
    // links the same artifact the parent installed.  `zig build` here without
    // the flag keeps the package's own default, which is the archive.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which bridge artifact to consume: static archive (default) or shared library",
    ) orelse .static;
    // Forwarded for the same reason as `linkage`: the parent selects the
    // dispatch shape, and a consumer build that quietly got the other one back
    // would exercise a configuration nobody chose.  Off by default, matching
    // the dependency.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Consume the runtime-loaded facade: dispatch through the loader instead of linking",
    ) orelse false;
    // Nullable, and forwarded as the selection it is rather than as a value
    // resolved here.  `-Daesni`'s default in the dependency is "follow the
    // target CPU", which is a decision that dependency makes from the target
    // it is handed; a null is dropped on the way in
    // (`lib/std/Build.zig:430-436`, `addUserInputOptionFromArg`), so a build
    // told nothing leaves that decision where it is.  Copying a default in
    // here instead would make the two disagree about the wrapper set on every
    // host whose CPU carries AES-NI, and a consumer would then prove a
    // configuration the dependency never built.
    const aesni = b.option(
        bool,
        "aesni",
        "Consume the AES-NI and ARS bridge wrappers (x86 only; default: follow the target CPU)",
    );

    const dep = b.dependency("random123", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
        .aesni = aesni,
    });

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
