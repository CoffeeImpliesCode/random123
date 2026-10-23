// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Build the runtime modules and one target-specific dispatch.
//! The dispatch replaces the linked bridge and imports translated declarations.
//! Load this fork's bridge shared library; upstream Random123 is header-only.
//! Do not link the bridge into a module that imports this dispatch.
const std = @import("std");

/// Prefix shared by the C synchronization binding and descriptor symbol names.
/// Change it in both files for an independent SDK instance.
const sync_prefix = "random123_rt";

/// C-library externs emitted by translation, kept direct instead of routed.
/// This list covers assertion and MinGW helpers reachable from the bridge header; over-listing is inert, under-listing breaks loading.
const libc_noise =
    \\__assert_fail,__assert_perror_fail,__assert,_assert,__assert2,__assert_rtn,_wassert,
    \\__mingw_get_crt_info,__prefetch
;

/// No provider exports are optional: AES-NI/ARS declarations exist only when the bridge and translation share a feature decision.
/// If compiled, all five must resolve; direct references cannot be optional in an unlinked runtime module.
const provider_optional = "";

/// No bridge symbols are excluded; only `libc_noise` stays direct.
const provider_excluded = "";

/// Create the linked facade's loader core for shared `LoadSource` and `LoadError` types.
/// Runtime facades must instead import the dispatch's single core instance.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // Unix dynamic loading uses libc; linked builds do not instantiate this module.
        .link_libc = true,
    });
}

/// Create the target-specific runtime `c` module from this build's translation.
/// Its table includes AES-NI/ARS entries exactly when this build declares them.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // Re-export native declarations so the dispatch and facade share nominal types.
    // Patch `__root` to route nested aliases, forming the dispatch/native mutual import.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Generate dispatch from this target's translated-header output.
/// Feature options affect both inputs, so each configuration gets its own dispatch.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("random123-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("random123");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
