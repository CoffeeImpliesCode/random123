// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//! Build and install a C bridge, upstream headers and the Zig facade.
//! Random123 has no upstream library ABI, so this package has no system-library mode.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// Runtime dispatch build helpers.
const graph = @import("runtime/graph.zig");

/// Fork-owned header translated into the public C import.
const bridge_header = "zig/bridge/random123_bridge.h";

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
    /// Translation step shared by both module shapes.
    translate: *std.Build.Step.TranslateC,
};

/// Licence and provenance files installed with the package.
const licence_files = [_][]const u8{
    "LICENSE",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "README.upstream.md",
};

/// Exported bridge ABI; keep this list in sync with `random123_bridge.h`.
/// PE/COFF needs an explicit export list because the shared header has no `dllexport`.
/// Missing entries omit symbols from the Windows DLL.
const bridge_abi_symbols = [_][]const u8{
    "r123_bridge_philox2x32_keyinit",
    "r123_bridge_philox2x32_R",
    "r123_bridge_philox4x32_keyinit",
    "r123_bridge_philox4x32_R",
    "r123_bridge_philox2x64_keyinit",
    "r123_bridge_philox2x64_R",
    "r123_bridge_philox4x64_keyinit",
    "r123_bridge_philox4x64_R",
    "r123_bridge_threefry2x32_keyinit",
    "r123_bridge_threefry2x32_R",
    "r123_bridge_threefry4x32_keyinit",
    "r123_bridge_threefry4x32_R",
    "r123_bridge_threefry2x64_keyinit",
    "r123_bridge_threefry2x64_R",
    "r123_bridge_threefry4x64_keyinit",
    "r123_bridge_threefry4x64_R",
    "r123_bridge_u01_closed_closed_32_float",
    "r123_bridge_u01_closed_open_32_float",
    "r123_bridge_u01_open_closed_32_float",
    "r123_bridge_u01_open_open_32_float",
    "r123_bridge_u01_closed_closed_32_double",
    "r123_bridge_u01_closed_open_32_double",
    "r123_bridge_u01_open_closed_32_double",
    "r123_bridge_u01_open_open_32_double",
    "r123_bridge_u01_closed_closed_64_double",
    "r123_bridge_u01_closed_open_64_double",
    "r123_bridge_u01_open_closed_64_double",
    "r123_bridge_u01_open_open_64_double",
};

/// AES-NI/ARS exports are emitted only when compiled; absent `.def` names fail linking.
const aesni_bridge_abi_symbols = [_][]const u8{
    "r123_bridge_have_aesni",
    "r123_bridge_aesni4x32_keyinit",
    "r123_bridge_aesni4x32_R",
    "r123_bridge_ars4x32_keyinit",
    "r123_bridge_ars4x32_R",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const aesni_option = b.option(
        bool,
        "aesni",
        "Compile the AES-NI and ARS bridge wrappers (x86 only; default: follow the target CPU)",
    );
    // Keep static as the default artifact form.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Build the bridge as a static archive (default) or as a shared library",
    ) orelse .static;
    // Runtime dispatch is independent of artifact linkage.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time through the platform loader instead of linking them. " ++
            "The facade keeps the same translated header and the same public types; each selected native " ++
            "function becomes a dispatch through one process-lifetime table that an explicit load(source) " ++
            "fills, and the module links no archive. Independent of -Dlinkage, which still decides which " ++
            "artifact this build delivers and installs. Default off.",
    ) orelse false;

    const build_target = resolveAesniTarget(b, target, aesni_option);
    const core = addBridge(b, build_target.target, optimize, build_target.aesni, linkage);
    const mod = b.addModule("random123", .{
        .root_source_file = b.path("root.zig"),
        .target = build_target.target,
        .optimize = optimize,
    });
    addFacadeImports(b, mod, core, build_target.target, optimize, runtime_loaded);

    // Delivery is independent of dispatch; install the bridge in both modes.
    b.installArtifact(core.lib);

    installPkgConfig(b);

    for (licence_files) |file| {
        b.installFile(file, b.pathJoin(&.{ "share", "licenses", "random123", file }));
    }

    const kat_vectors = addKatVectorsModule(b);

    const smoke_exe = addSmoke(b, mod, build_target.target, optimize);

    // Test runners must execute even when their binaries are cached.
    const test_step = b.step("test", "Run the Random123 behaviour tests for the selected target");
    const kat = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-kat", "zig/kat_test.zig");
    const facade = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-facade", "zig/facade_test.zig");

    const run_kat = b.addRunArtifact(kat);
    run_kat.has_side_effects = true;
    test_step.dependOn(&run_kat.step);

    const run_facade = b.addRunArtifact(facade);
    run_facade.has_side_effects = true;
    test_step.dependOn(&run_facade.step);

    // Loader tests require runtime mode and a real host provider.
    // Do not run them under an emulator that may use a provider for another ABI.
    if (runtime_loaded and runsOnHost(b, build_target.target)) {
        const load_tests_mod = b.createModule(.{
            .root_source_file = b.path("runtime/load_tests.zig"),
            .target = build_target.target,
            .optimize = optimize,
            // The loader uses libc's dynamic-linker API.
            .link_libc = true,
        });
        load_tests_mod.addImport("random123", mod);
        const load_tests = b.addTest(.{
            .name = "random123-runtime-loads",
            .root_module = load_tests_mod,
        });
        const run_load_tests = b.addRunArtifact(load_tests);
        run_load_tests.has_side_effects = true;
        test_step.dependOn(&run_load_tests.step);
    }

    const run_smoke = b.addRunArtifact(smoke_exe);
    run_smoke.has_side_effects = true;
    if (b.args) |args| run_smoke.addArgs(args);
    b.step("smoke", "Run the deterministic Random123 smoke example").dependOn(&run_smoke.step);

    const check_step = b.step("check", "Compile the public facade and example without running them");
    addCheck(b, check_step, build_target.target, optimize, build_target.aesni, linkage, runtime_loaded, kat_vectors);
    if (isX86(target)) {
        // Compile AES-NI/ARS wrappers on x86 even when the selected CPU is baseline.
        addCheck(b, check_step, withX86Aesni(b, target), optimize, true, linkage, runtime_loaded, kat_vectors);
    }

    const matrix_step = b.step("matrix", "Compile-check all six required targets");
    inline for (verify_matrix) |query| {
        const resolved = b.resolveTargetQuery(query);
        const matrix_target = resolveAesniTarget(b, resolved, aesni_option);
        addCheck(b, matrix_step, matrix_target.target, optimize, matrix_target.aesni, linkage, runtime_loaded, kat_vectors);
        if (isX86(resolved)) {
            addCheck(b, matrix_step, withX86Aesni(b, resolved), optimize, true, linkage, runtime_loaded, kat_vectors);
        }
    }

    // Forward the resolved target and the caller's AES-NI selection to the consumer.
    addConsumerStep(b, build_target.target, aesni_option, optimize, linkage, runtime_loaded);
}

/// Front end used to translate the bridge header.
const TranslationRoute = enum {
    /// Aro preprocesses and parses the header.
    aro,
    /// Target C preprocessing runs before Aro parsing.
    preprocessed,
};

/// Use target preprocessing for PowerPC and NetBSD.
/// Aro sees the upstream GCC-only PowerPC include and NetBSD `_Pragma` framing.
fn translationRoute(target: std.Build.ResolvedTarget) TranslationRoute {
    // These PowerPC targets all define the upstream `__powerpc__` macro.
    if (target.result.cpu.arch == .powerpc or
        target.result.cpu.arch == .powerpc64 or
        target.result.cpu.arch == .powerpc64le) return .preprocessed;
    return switch (target.result.os.tag) {
        .netbsd => .preprocessed,
        else => .aro,
    };
}

/// NetBSD/AArch64 libc uses compiler-provided `__int128_t` in `__ALIGNBYTES`.
/// The preprocessed headers omit intrinsic typedefs, so restore them when supported.
const translate_prologue =
    \\#if defined(__SIZEOF_INT128__)
    \\typedef __int128 __int128_t;
    \\typedef unsigned __int128 __uint128_t;
    \\#endif
;

/// Preprocess PowerPC/NetBSD bridge headers with the target compiler before `translate-c`.
/// `-dD` preserves Random123 macros; `-MD` tracks included headers as build inputs.
/// The route uses the same target and include root as C compilation.
fn preprocessedBridgeHeader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    aesni: bool,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD" });
    const triple = target.result.zigTriple(b.allocator) catch @panic("random123: unspellable target");
    run.setName(b.fmt("preprocess random123 bridge header {s}", .{triple}));
    if (!target.query.isNative()) {
        run.addArg("-target");
        run.addArg(triple);
    }
    run.addPrefixedDirectoryArg("-I", b.path("include"));
    run.addPrefixedFileArg("-include", b.addWriteFiles().add("random123-translate-prologue.h", translate_prologue));
    run.addArg("-DR123_USE_SSE=0");
    if (needsC99Mulhilo(target)) run.addArg("-DR123_USE_MULHILO64_C99=1");
    if (aesni) run.addArg("-DR123_BRIDGE_HAS_AESNI=1");
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("random123-translate.c");
    run.addArg("-MD");
    _ = run.addPrefixedDepFileOutputArg("-MF", "random123-translate.d");
    run.addFileArg(b.path(bridge_header));
    return preprocessed;
}

/// Compile the bridge and translate its public C declarations.
fn addBridge(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    aesni: bool,
    linkage: std.builtin.LinkMode,
) Bridge {
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = switch (linkage) {
            .static => null,
            .dynamic => true,
        },
    });
    lib_mod.addIncludePath(b.path("include"));

    const lib = b.addLibrary(.{
        .name = "random123",
        .linkage = linkage,
        .root_module = lib_mod,
        // PE/COFF shared libraries need an export table; keep `dllexport` out of the shared header.
        // Generate the `.def` only for dynamic COFF targets.
        .win32_module_definition = if (linkage == .dynamic and target.result.ofmt == .coff)
            addWindowsExports(b, aesni)
        else
            null,
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
        // `-maes` is descriptive; the target feature enables AES-NI and matches the bridge macro.
        // The bridge asserts that `R123_BRIDGE_HAS_AESNI` agrees with the target.
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

    // Include upstream's public C and C++ headers in the artifact.
    lib.installHeadersDirectory(b.path("include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    lib.installHeader(b.path(bridge_header), "random123_bridge.h");

    const tc = b.addTranslateC(.{
        .root_source_file = switch (translationRoute(target)) {
            .aro => b.path(bridge_header),
            .preprocessed => preprocessedBridgeHeader(b, target, aesni),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tc.addIncludePath(b.path("include"));
    // Disable x86 inline-assembly helpers only in the translated view; Zig cannot represent them.
    // The compiled bridge retains the upstream implementation.
    tc.defineCMacro("R123_USE_SSE", "0");
    if (needsC99Mulhilo(target)) tc.defineCMacro("R123_USE_MULHILO64_C99", "1");
    if (aesni) tc.defineCMacro("R123_BRIDGE_HAS_AESNI", "1");

    return .{ .lib = lib, .translate = tc };
}

/// Register translated or generated `c` declarations and the matching loader core.
/// Linked mode links one bridge; runtime dispatch does not link an archive.
fn addFacadeImports(
    b: *std.Build,
    mod: *std.Build.Module,
    core: Bridge,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    runtime_loaded: bool,
) void {
    if (runtime_loaded) {
        mod.addImport("c", graph.createModule(b, core.translate, target, optimize));
        return;
    }
    const c_module = core.translate.createModule();
    // `createModule` does not copy include paths.
    c_module.addIncludePath(b.path("include"));
    mod.addImport("c", c_module);
    mod.addImport("rt", graph.createCoreModule(b, target, optimize));
    mod.linkLibrary(core.lib);
}

/// Generate the Windows export table with only the bridge wrappers compiled here.
fn addWindowsExports(b: *std.Build, aesni: bool) std.Build.LazyPath {
    var out: std.Io.Writer.Allocating = .init(b.allocator);
    out.writer.print("EXPORTS\n", .{}) catch @panic("OOM");
    for (bridge_abi_symbols) |symbol| {
        out.writer.print("{s}\n", .{symbol}) catch @panic("OOM");
    }
    if (aesni) {
        for (aesni_bridge_abi_symbols) |symbol| {
            out.writer.print("{s}\n", .{symbol}) catch @panic("OOM");
        }
    }
    return b.addWriteFiles().add("random123.def", out.written());
}

/// Write a relocatable pkg-config record using `${pcfiledir}` for its prefix.
/// The bridge has no external link dependency, so the record omits `Requires`.
fn installPkgConfig(b: *std.Build) void {
    const pc = b.addWriteFiles().add("random123.pc", b.fmt(
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: random123
        \\Description: Philox, Threefry, ARS, AES-NI and u01fixedpt counter-based random number generators, plus this fork's C bridge over the upstream header-only library
        \\URL: https://github.com/DEShawResearch/random123
        \\Version: {s}
        \\Libs: -L${{libdir}} -lrandom123
        \\Cflags: -I${{includedir}}
        \\
    , .{manifest.version}));
    b.getInstallStep().dependOn(&b.addInstallFile(pc, "lib/pkgconfig/random123.pc").step);
}

/// Generated root for the test-only embedded fixture.
const kat_vectors_module_source =
    \\//! The upstream Random123 known-answer fixture, embedded verbatim.
    \\//!
    \\//! Provenance: D. E. Shaw Research, Random123 1.14.0, tests/kat_vectors.
    \\//! The build copies that file next to this generated root byte for byte
    \\//! and never writes a copy into the source tree.
    \\pub const data = @embedFile("kat_vectors");
    \\
;

/// Copy the fixture beside a generated root because a module cannot embed outside its directory.
/// Only test roots import the generated module.
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

/// Add compile-only facade, test and example coverage for the selected configuration.
fn addCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    aesni: bool,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    kat_vectors: *std.Build.Module,
) void {
    const core = addBridge(b, target, optimize, aesni, linkage);
    const mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addFacadeImports(b, mod, core, target, optimize, runtime_loaded);

    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-analyze", "zig/analyze_test.zig").step);
    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-kat", "zig/kat_test.zig").step);
    parent.dependOn(&addTestArtifact(b, mod, kat_vectors, target, optimize, "random123-facade", "zig/facade_test.zig").step);
    parent.dependOn(&addSmoke(b, mod, target, optimize).step);
}

/// Build/run the consumer with the outer target, linkage and runtime mode.
/// Preserve explicit AES-NI selection, executor flags, cache roots and install prefix.
fn addConsumerStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    aesni: ?bool,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const query = target.query;
    // `run.addArg` copies these temporary strings.
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Run the nested build with the same Zig executable.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // Forward AES-NI only when explicitly selected; otherwise infer it from the target.
    if (aesni) |selected| {
        run.addArg(b.fmt("-Daesni={s}", .{if (selected) "true" else "false"}));
    }
    // Forward enabled executor flags so the nested run matches the outer decision.
    // QEMU also needs the same libc runtime directory for GNU targets.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // Keep nested build parallelism consistent with the package tasks.
    run.addArg("-j8");
    // Show all nested build steps so a passing consumer run is visible.
    run.addArgs(&.{ "--summary", "all" });
    // Give the nested graph its own local manifest directory under the same cache root.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // Share the caller's global package cache with the nested build.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // Forward a non-default prefix as an absolute path; the nested cwd is `consumer/`.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // Put caller arguments after `--` so the nested build forwards them to its program.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    b.step("consumer", "Build the consumer/ package, and run it when this host can execute the selected target").dependOn(&run.step);
}

/// Whether the target can run here with the executor flags and libc runtime settings resolved by this build.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(
        b.graph.io,
        &b.graph.host.result,
        candidate,
        options,
    )) {
        .native, .rosetta => true,
        .wine, .wasmtime, .darling => true,
        // GNU targets under QEMU need a libc runtimes directory for the run step.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        // No compatible dynamic linker or enabled executor is available.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// True only for native or Rosetta execution, not an emulator.
/// Runtime-loader tests need this host's files, threads and dynamic loader.
fn runsOnHost(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = false,
        .allow_qemu = false,
        .allow_wasmtime = false,
        .allow_wine = false,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(
        b.graph.io,
        &b.graph.host.result,
        &target.result,
        options,
    )) {
        .native, .rosetta => true,
        else => false,
    };
}

/// Resolved target and whether its bridge includes AES-NI/ARS wrappers.
const BuildTarget = struct {
    target: std.Build.ResolvedTarget,
    aesni: bool,
};

/// Default AES-NI from the target CPU; explicit requests add the feature on x86 only.
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

/// Add the x86 `aes` target feature so upstream's `__AES__` guard enables wrappers.
/// Targets that already have the feature are unchanged.
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

/// Use the C99 multiply where upstream's compiler guards do not enable `__uint128_t`.
/// The native 64×64-to-128 path is selected only for x86_64 and aarch64.
fn needsC99Mulhilo(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .x86_64, .aarch64 => false,
        else => true,
    };
}
