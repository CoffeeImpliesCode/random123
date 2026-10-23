// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//! Consumer package using Random123 through `dependency.module("random123")`.
//! The module supplies the bridge artifact; run this example with `zig build run`.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Preserve the dependency's linkage choice; static is its default.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which bridge artifact to consume: static archive (default) or shared library",
    ) orelse .static;
    // Preserve the dependency's runtime-loading choice; disabled by default.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Consume the runtime-loaded facade: dispatch through the loader instead of linking",
    ) orelse false;
    // Forward null so the dependency selects its default from the target CPU.
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

    // Install the executable without running it during the default build.
    b.step("run", "Run the consumer example against the Random123 fork").dependOn(&run.step);
}
