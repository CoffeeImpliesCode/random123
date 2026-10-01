//! Build for the Random123 Zig package.
//!
//! Random123 is a header-only C library, so this package does the only thing a
//! header-only library can usefully do: it compiles the genuine upstream
//! headers into a small bridge library that has external linkage, installs the
//! upstream headers next to it, and translates the public C surface for Zig.
//!
//! There is deliberately NO `b.systemIntegrationOption` here.  A header-only
//! library installs no binary, so a "system" Random123 is just a header
//! directory; there is no installed ABI to bind to and therefore nothing for a
//! system mode to select.  See UPSTREAM.md, "System-library mode".
//!
//! The behaviour tests read the upstream known-answer fixture through a
//! test-only module the build generates, not through a relative path: see
//! `addKatVectorsModule`.
//!
//! Steps: install, test, smoke, check (selected-target compile only),
//! matrix (six-target compile attempts), and consumer (separate package).
//! Upstream rejects riscv64 and wasm32; matrix reports those failures.

const std = @import("std");

pub const verify_matrix = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Bridge = struct {
    lib: *std.Build.Step.Compile,
    c_module: *std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const aesni_option = b.option(
        bool,
        "aesni",
        "Compile the AES-NI and ARS bridge wrappers (x86 only; default: follow the target CPU)",
    );

    const build_target = resolveAesniTarget(b, target, aesni_option);
    const core = addBridge(b, build_target.target, optimize, build_target.aesni);
    const mod = b.addModule("random123", .{
        .root_source_file = b.path("root.zig"),
        .target = build_target.target,
        .optimize = optimize,
    });
    mod.addImport("c", core.c_module);
    mod.linkLibrary(core.lib);

    // `zig build` installs librandom123 plus both the upstream header tree and
    // the bridge header, so C and C++ consumers get `#include <Random123/...>`
    // and `#include <random123_bridge.h>` for free once they link the artifact.
    b.installArtifact(core.lib);

    // One shared fixture module for every KAT compile path.
    const kat_vectors = addKatVectorsModule(b);

    const smoke_exe = addSmoke(b, mod, build_target.target, optimize);

    const test_step = b.step("test", "Run the Random123 behaviour tests");
    const kat = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-kat", "zig/kat_test.zig");
    const facade = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-facade", "zig/facade_test.zig");
    if (target.query.isNative()) {
        const run_kat = b.addRunArtifact(kat);
        run_kat.has_side_effects = true;
        test_step.dependOn(&run_kat.step);

        const run_facade = b.addRunArtifact(facade);
        run_facade.has_side_effects = true;
        test_step.dependOn(&run_facade.step);
    } else {
        // A cross target cannot execute.  Still compile the test bodies so a
        // compile error in them is not silently skipped.
        test_step.dependOn(&kat.step);
        test_step.dependOn(&facade.step);
    }

    const run_smoke = b.addRunArtifact(smoke_exe);
    run_smoke.has_side_effects = true;
    b.step("smoke", "Run the deterministic Random123 smoke example").dependOn(&run_smoke.step);

    // `zig build check` compiles the public facade and the example for the
    // selected target without running anything.  analyze_test.zig calls every
    // public facade method with concrete types, so compiling it forces every
    // method body to be analyzed.
    const check_step = b.step("check", "Compile the public facade and example without running them");
    addCheck(b, check_step, build_target.target, optimize, build_target.aesni, kat_vectors);
    if (isX86(target)) {
        // Compile the AES-NI/ARS path as well on x86: it must build wherever x86
        // builds, whether or not the resolved CPU has AES-NI.  The feature goes
        // on the target, so the wrappers really compile instead of silently
        // disappearing -- see withX86Aesni.
        addCheck(b, check_step, withX86Aesni(b, target), optimize, true, kat_vectors);
    }

    // The whole cross-target graph in one invocation.
    const matrix_step = b.step("matrix", "Compile-check all six required targets");
    inline for (verify_matrix) |query| {
        const resolved = b.resolveTargetQuery(query);
        const matrix_target = resolveAesniTarget(b, resolved, aesni_option);
        addCheck(b, matrix_step, matrix_target.target, optimize, matrix_target.aesni, kat_vectors);
        if (isX86(resolved)) {
            addCheck(b, matrix_step, withX86Aesni(b, resolved), optimize, true, kat_vectors);
        }
    }

    addConsumerStep(b, target, optimize);
}

/// Compiles the upstream headers into `librandom123` and translates the public
/// C surface for Zig.
fn addBridge(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    aesni: bool,
) Bridge {
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // installHeadersDirectory below publishes the headers to consumers; the
    // library's OWN compile line still needs them on the include path.
    lib_mod.addIncludePath(b.path("include"));

    const lib = b.addLibrary(.{
        .name = "random123",
        .linkage = .static,
        .root_module = lib_mod,
    });

    var flags: [4][]const u8 = undefined;
    var flag_count: usize = 0;
    flags[flag_count] = "-std=c11";
    flag_count += 1;
    if (needsC99Mulhilo(target)) {
        flags[flag_count] = "-DR123_USE_MULHILO64_C99=1";
        flag_count += 1;
    }
    if (aesni) {
        // `-maes` is what upstream documents, and it is kept so the compile
        // line says what it means, but it is not what turns AES-NI on here:
        // the target carries the feature (withX86Aesni) and the bridge
        // static-asserts that the two agree.  See FORK-NOTES.md.
        flags[flag_count] = "-maes";
        flag_count += 1;
        flags[flag_count] = "-DR123_BRIDGE_HAS_AESNI=1";
        flag_count += 1;
    }

    lib_mod.addCSourceFiles(.{
        .root = b.path("zig/bridge"),
        .files = &.{"random123_bridge.c"},
        .flags = flags[0..flag_count],
    });

    // The artifact carries upstream's whole public header set, so both the
    // installed tree and `getEmittedIncludeTree()` -- what `linkLibrary` puts
    // on a consumer's include search path -- need the same filter.  Upstream's
    // `install-include` copies `include/Random123` wholesale, and five of those
    // files are `.hpp`: a `.h`-only filter would silently drop every C++ header
    // (`uniform.hpp`, `MicroURNG.hpp`, `conventional/Engine.hpp`, ...).
    lib.installHeadersDirectory(b.path("include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    lib.installHeader(b.path("zig/bridge/random123_bridge.h"), "random123_bridge.h");

    const tc = b.addTranslateC(.{
        .root_source_file = b.path("zig/bridge/random123_bridge.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tc.addIncludePath(b.path("include"));
    // <Random123/array.h> unconditionally includes features/sse.h, which on x86
    // declares haveAESNI() with GNU inline assembly and pulls in <x86intrin.h>.
    // Inline assembly has no Zig representation, so the TRANSLATED view is
    // pinned to the portable r123arrayNxW types.  The compiled bridge keeps the
    // real value and the real AES-NI code; no upstream file is modified.
    tc.defineCMacro("R123_USE_SSE", "0");
    if (needsC99Mulhilo(target)) tc.defineCMacro("R123_USE_MULHILO64_C99", "1");
    if (aesni) tc.defineCMacro("R123_BRIDGE_HAS_AESNI", "1");

    const c_module = tc.createModule();
    // createModule() copies only link_libc and system_libs, so the include path
    // has to be re-added for the translated module itself.
    c_module.addIncludePath(b.path("include"));

    return .{ .lib = lib, .c_module = c_module };
}

/// The generated root of the test-only `kat_vectors` module.
const kat_vectors_module_source =
    \\//! The upstream Random123 known-answer fixture, embedded verbatim.
    \\//!
    \\//! Provenance: D. E. Shaw Research, Random123 1.14.0, tests/kat_vectors.
    \\//! The build copies that file next to this generated root byte for byte
    \\//! and never writes a copy into the source tree.
    \\pub const data = @embedFile("kat_vectors");
    \\
;

/// Builds the test-only `kat_vectors` module: one generated root that embeds a
/// verbatim sibling copy of the upstream `tests/kat_vectors` fixture.
///
/// `zig/kat_test.zig` cannot embed `../tests/kat_vectors` directly, because a
/// module root may not read outside its own directory; the compiler stopped
/// there.  Writing a one-declaration root into a generated directory and
/// copying the upstream fixture next to it puts the embed back inside the
/// module directory, and the fixture stays byte-identical to upstream.
///
/// No dependency edge is created either way: the copy comes from this
/// package's own `tests/kat_vectors`, and only test roots import the result,
/// so nothing in the production graph can reach it.
fn addKatVectorsModule(b: *std.Build) *std.Build.Module {
    const files = b.addWriteFiles();
    const root = files.add("kat_vectors.zig", kat_vectors_module_source);
    _ = files.addCopyFile(b.path("tests/kat_vectors"), "kat_vectors");
    return b.createModule(.{ .root_source_file = root });
}

fn addTestArtifact(
    b: *std.Build,
    mod: *std.Build.Module,
    kat_vectors: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime source: []const u8,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("random123", mod);
    // The shared upstream known-answer fixture.  Every KAT compile path -- the
    // native `test` step and every `check`/`matrix` target -- comes through
    // this one constructor, so they all see the same import and the same
    // fixture bytes.  Modules that do not reference it ignore the entry.
    test_mod.addImport("kat_vectors", kat_vectors);
    return b.addTest(.{ .name = name, .root_module = test_mod });
}

fn addSmoke(
    b: *std.Build,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("zig/smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("random123", mod);
    return b.addExecutable(.{ .name = "random123-smoke", .root_module = exe_mod });
}

/// Compile-only coverage: every public facade method is called with concrete
/// types from zig/analyze_test.zig, and the example is compiled.  Nothing runs.
fn addCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    aesni: bool,
    kat_vectors: *std.Build.Module,
) void {
    const core = addBridge(b, target, optimize, aesni);
    const mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("c", core.c_module);
    mod.linkLibrary(core.lib);

    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-analyze", "zig/analyze_test.zig").step);
    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-kat", "zig/kat_test.zig").step);
    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-facade", "zig/facade_test.zig").step);
    parent.dependOn(&addSmoke(b, mod, target, optimize).step);
}

/// `zig build consumer` builds the standalone consumer/ package, which depends
/// on this package by path through `b.dependency`, and runs it when the target
/// is the host.
///
/// `consumer/` is a separate `zig build` invocation, so the options that must
/// reach it travel as `-Dkey=value` arguments, one argument each, which is the
/// form the build runner parses.  The target and CPU strings come from
/// `Target.Query.zigTriple` and `Target.Query.serializeCpuAlloc`, which are
/// exactly the two functions `standardTargetOptions` itself uses to report
/// this build's resolved target (`Build.zig:1521-1524`); the compiler argument
/// builder uses the same pair (`Build/Module.zig:596-597`).  So the sub-build
/// parses precisely what this build resolved, for every target in the matrix.
///
/// A non-native target only *builds* the consumer.  That is the same policy
/// the `test` step above follows for cross targets: a foreign binary cannot be
/// executed here.  `consumer/` needs no change for this — its `install` step
/// already builds the executable, and its `run` step is what runs it.
fn addConsumerStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const query = target.query;
    // `addArg` copies each argument, so these temporaries can go right after.
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build uses the same toolchain instead of whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (query.isNative()) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory, and a cache manifest is
    // locked for the duration of the process that holds it
    // (`Build/Cache.zig` Manifest).  A null `path` means "the current
    // directory", and the working directory above is already the consumer
    // package, so the default is right there.
    if (b.cache_root.path) |cache| {
        run.addArg(b.fmt("--cache-dir={s}/consumer", .{cache}));
    }
    run.has_side_effects = true;
    b.step("consumer", "Build the consumer/ package, and run it for a native target").dependOn(&run.step);
}

/// A target to build for, together with whether the AES-NI bridge wrappers
/// belong to it.  The two travel together because the wrappers need a target
/// CPU feature, and a target without one must not be handed to the bridge.
const BuildTarget = struct {
    target: std.Build.ResolvedTarget,
    aesni: bool,
};

/// AES-NI defaults to whatever the resolved target CPU actually provides, so a
/// baseline cross target never gets x86 intrinsics forced onto it.  Asking for
/// it is only meaningful on x86, and on a CPU without the feature it means
/// adding the feature to the target.
fn resolveAesniTarget(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    requested: ?bool,
) BuildTarget {
    const aesni = requested orelse (isX86(target) and cpuHasAes(target));
    if (!aesni) return .{ .target = target, .aesni = false };
    if (!isX86(target)) {
        @panic("-Daesni=true requires an x86 or x86_64 target: the upstream AES-NI and ARS headers are x86 intrinsics");
    }
    return .{ .target = withX86Aesni(b, target), .aesni = true };
}

/// Returns `target` with the x86 `aes` feature on it, or `target` unchanged
/// when its CPU already has it.
///
/// Upstream gates `aes.h` and `ars.h` on `R123_USE_AES_NI`, which
/// `features/gccfeatures.h:113-119` derives from `__AES__`, and `__AES__` is a
/// property of the target CPU, not of a cflag: Zig's driver leaves a `-maes`
/// cflag out of the feature set, so `R123_USE_AES_NI` stays 0 and every
/// AES-NI wrapper in `random123_bridge.c` compiles to nothing while the
/// installed header still declares it.  Adding the feature to the target
/// query is what a compiler honours, and it is the same mechanism `-Dcpu=`
/// uses.  A target that already has the feature is returned untouched, so a
/// native build on an AES-capable host is never retargeted for nothing.
fn withX86Aesni(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.ResolvedTarget {
    if (cpuHasAes(target)) return target;
    var query = target.query;
    query.cpu_features_add.addFeature(@intCast(@intFromEnum(std.Target.x86.Feature.aes)));
    return b.resolveTargetQuery(query);
}

fn isX86(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .x86, .x86_64 => true,
        else => false,
    };
}

fn cpuHasAes(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .x86, .x86_64 => std.Target.x86.featureSetHas(target.result.cpu.features, .aes),
        else => false,
    };
}

/// features/gccfeatures.h turns R123_USE_GNU_UINT128 on only for __x86_64__ and
/// __aarch64__.  Without a 64x64->128 multiply, upstream drops Philox2x64 and
/// Philox4x64 entirely (R123_USE_PHILOX_64BIT resolves to 0).  Everywhere else
/// this selects the upstream-documented strict-C99 multiply, which computes
/// the identical product using word-size operations only.  No contract target
/// this package compiles needs it -- the two that would have are refused
/// earlier, by the architecture guard in gccfeatures.h.  See UPSTREAM.md.
fn needsC99Mulhilo(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .x86_64, .aarch64 => false,
        else => true,
    };
}
