// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//!
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
//! `WISDOM.md` W14 is therefore vacuous here, not satisfied: this fork has no
//! system mode, so it never translates a header against a library it does not
//! link.
//!
//! `-Dlinkage=static` (the default, unchanged) builds `librandom123.a`.
//! `-Dlinkage=dynamic` builds `librandom123.so`, `librandom123.dylib` or
//! `random123.dll` from the same single C source over the same headers, with
//! the same AES-NI decision.  Both variants are this package's own artifact
//! compiled in this tree; a shared build here is not a system provider and is
//! never consulted to satisfy a system link.  No SONAME version is claimed for
//! the shared variant: upstream installs no library at all, so there is no
//! upstream ABI to version a compatibility tag against.
//!
//! `zig build install` publishes the bridge artifact, the complete upstream
//! `include/Random123` header tree together with `random123_bridge.h`, a
//! `lib/pkgconfig/random123.pc` naming that artifact and header directory,
//! and the licence and provenance records under `share/licenses/random123/`.
//! Upstream's own `make install` additionally copies Doxygen html, the
//! examples and the tests; the html needs Doxygen run at build time and the
//! examples and tests are this source tree, so neither is reproduced here.
//!
//! `-Druntime=true` resolves the native entry points through the platform
//! loader instead of linking them: a bool, off by default, orthogonal to
//! `-Dlinkage`.  The seam is `runtime/graph.zig`, which the API owner owns;
//! this build supplies its `c` import and, in the linked shape, the single
//! core-module instance that carries `LoadSource` and `LoadError`.  Delivery
//! and dispatch stay separate questions: the bridge artifact is built and
//! installed either way, and `-Dlinkage` still decides which one.  See
//! `addFacadeImports`.
//!
//! The behaviour tests read the upstream known-answer fixture through a
//! test-only module the build generates, not through a relative path: see
//! `addKatVectorsModule`.
//!
//! Steps: install, test (runs, for whatever target was selected, under
//! whatever executor the build runner supplies), smoke, check (selected-target
//! compile only), matrix (six-target compile attempts), and consumer (separate
//! package, run when this host can execute the selected target).  Upstream
//! rejects riscv64 and wasm32; matrix reports those failures.
//!
//! ## Which front end reads the bridge header
//!
//! `zig translate-c` parses C with Aro, and Aro preprocesses as well as parses,
//! so `zig/bridge/random123_bridge.h` can be read either way round: Aro can do
//! both jobs, or the target's own C preprocessor can do the first and Aro the
//! second.  `translationRoute` decides per target and `preprocessedBridgeHeader`
//! is the extra front end.  Both routes read this repository's
//! `include/Random123` tree on the same include path with the same three
//! macros; only the preprocessor that has to understand the target's C library
//! and the target's own compiler predefines changes.
//!
//! Every target but two families keeps the route it already had, and both
//! families fail for one root cause seen from two sides.
//! `include/Random123/features/compilerfeatures.h:215-218` selects
//! `clangfeatures.h` on `__clang__` and `gccfeatures.h` on `__GNUC__`, and Aro
//! defines `__GNUC__` without `__clang__`.  So every translated view of
//! Random123 is the *GCC* view while the compiled bridge is the *Clang* view,
//! and on these two families that difference is a build failure rather than a
//! difference nobody notices.
//!
//!   * powerpc, powerpc64 and powerpc64le.
//!     `include/Random123/features/gccfeatures.h:47-49` is
//!     `#if defined(__powerpc__) && !defined(__clang__)` followed by
//!     `#include <ppu_intrinsics.h>`.  The GCC-only branch is taken precisely
//!     because the front end is not Clang, and it is taken unconditionally --
//!     a target whose 64x64 multiply comes from somewhere else still reaches
//!     the include.  `gccfeatures.h:249-261` is what that guard is *for*:
//!     under `defined(__clang__)` upstream defines `__mulhdu`/`__mulhwu`
//!     itself, inline, and only the GCC path expects them from a system header.
//!     Clang therefore preprocesses the very same headers for the very same
//!     target without trouble, which is why `zig cc` compiles this bridge where
//!     `zig translate-c` cannot read it.  (Aro could not be handed the Clang
//!     path instead: `clangfeatures.h` calls `__has_feature` at `:44`, `:48`,
//!     `:65` and `:69`, and Aro answers no `__has_feature`.)
//!   * NetBSD.  `__END_DECLS` is `_Pragma` framing in `sys/cdefs.h`, and Aro
//!     destringizes each operator invocation into a `#pragma` line it then hands
//!     to the parser as C.  Every system header this package reaches closes a
//!     declaration block with it: `<stdint.h>` from the bridge header,
//!     `<stddef.h>` from `array.h:43`, `<assert.h>` from `gccfeatures.h:68`.
//!
//! The extra front end runs the compiler that compiles the bridge, for the
//! target the bridge is compiled for, on the same include path and with the
//! same macros, so the declarations the translator reads are the ones the
//! archive answers to rather than a second revision of them.  `erfa` and
//! `utf8proc` already run exactly this mechanism in this workspace, for the
//! same NetBSD cause and with the same two flags.
//!
//! Three things deliberately stay out of it.  No compiler or architecture
//! identity macro is invented for Aro -- every predefine this route leans on is
//! one the target's own compiler supplies, and the arch guard at
//! `gccfeatures.h:37-45` still refuses every architecture it refuses.  No
//! upstream header changes.  And no algorithm, constant, wrapper or fixture is
//! dropped on either route: every declaration and constant this package's own
//! surface is built from is present on both, which is what the paragraph below
//! about `-dD` is for.
//!
//! `-dD` is what keeps the macro surface intact.  Random123's own `R123_*`
//! defaults are object-like `#define`s that no declaration in the translation
//! uses, so a plain dump would leave `pub const c` without them; `-dD` keeps the
//! `#define` lines beside the expanded text, so a macro a C caller reads as a
//! macro still reaches Zig as a constant.  That is additive on this route --
//! the C library's own macros come through too -- and everything this package's
//! facade is built from is on both routes.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The runtime dispatch seam, owned by the API role.  It imports only `std`
/// at the top level; the loader core, the generator and `sync.c` it names are
/// reached through `b.path` when one of its two entry points is called, so
/// importing it here costs a linked build nothing.
const graph = @import("runtime/graph.zig");

/// The one header `zig translate-c` is pointed at, whichever front end reads
/// it.  It is this fork's own file -- a fork addition holding no upstream code
/// -- so naming it here keeps `addBridge`'s two routes and
/// `preprocessedBridgeHeader`'s input line reading the same path.
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
    /// The translation step, not a module: which module the facade ends up
    /// importing is `addFacadeImports`' decision, and both shapes consume this
    /// one step rather than a module built from it.
    translate: *std.Build.Step.TranslateC,
};

/// The licence and provenance material an installed binary form has to carry.
/// Upstream's BSD-3-Clause text travels with the headers as their own
/// per-file notices; these are the records that describe the fork itself.
const licence_files = [_][]const u8{
    "LICENSE",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "README.upstream.md",
};

/// The complete externally linked ABI of the fork bridge: every function
/// `zig/bridge/random123_bridge.c` defines, one per declaration in
/// `zig/bridge/random123_bridge.h`, with no target or configuration left out.
///
/// This list exists for one purpose -- writing the Windows export list in
/// `addWindowsExports`.  A COFF/PE DLL exports nothing unless something tells
/// it to, and the bridge declarations deliberately carry no
/// `__declspec(dllexport)`, because that is what keeps one header correct for
/// the static archive, for the DLL and for a consumer that includes it
/// directly.  On ELF and Mach-O a shared object already exports these names
/// under the C default visibility rule, so the list restricts nothing there.
///
/// Keep it in step with the bridge header: a name added there and not here
/// builds and passes every Linux gate and is simply missing from the Windows
/// export table.
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

/// The five extra wrappers that exist only when the build compiles the AES-NI
/// and ARS paths, that is when `R123_BRIDGE_HAS_AESNI` is 1.  The export list
/// is generated per build, so it names only what this build actually
/// compiled; a `.def` entry for an absent symbol is a link error, not a
/// harmless extra line.
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
    // Static stays the default: this package has always installed an archive,
    // and `packages.default` in the Nix flake has to reproduce it with no
    // flag.  The shared variant is an additional delivery of the same bridge,
    // not a replacement.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Build the bridge as a static archive (default) or as a shared library",
    ) orelse .static;
    // Off by default, and orthogonal to `-Dlinkage`: that option says which
    // artifact this build delivers and installs, this one says which one the
    // module dispatches through.  A linked build is unchanged in every respect
    // when this is false, so `packages.default` and the Nix derivation need no
    // mention of it.
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

    // `zig build` installs librandom123 plus both the upstream header tree and
    // the bridge header, so C and C++ consumers get `#include <Random123/...>`
    // and `#include <random123_bridge.h>` for free once they link the artifact.
    // This is unconditional on purpose: under `-Druntime=true` the module links
    // nothing, but the artifact is still the thing a caller may name as a
    // provider, and delivery is a separate question from dispatch.
    b.installArtifact(core.lib);

    // Link metadata for a C consumer that was handed this prefix rather than a
    // dependency manager.  It describes the artifact this build produced and
    // the header directory it was installed beside.
    installPkgConfig(b);

    // What a binary distribution has to carry: upstream's licence text, the
    // fork's own grant and inventory, the pin record and the exact upstream
    // README bytes this tree is diffed against.
    for (licence_files) |file| {
        b.installFile(file, b.pathJoin(&.{ "share", "licenses", "random123", file }));
    }

    // One shared fixture module for every KAT compile path.
    const kat_vectors = addKatVectorsModule(b);

    const smoke_exe = addSmoke(b, mod, build_target.target, optimize);

    // `zig build test` runs the tests, for whatever target was selected.
    //
    // Both run steps are unconditional.  The guard they replaced asked
    // `target.query.isNative()`, and in Zig 0.16 that is false for *every*
    // query that names a target at all: `Target.Query.isNative()`
    // (`lib/std/Target/Query.zig:396-398`) is
    // `isNativeTriple() and ofmt == null`, and `isNativeTriple()` (`:392-394`)
    // demands `cpu_arch`, `os_tag` and `abi` all be null.  So
    // `zig build test -Dtarget=x86_64-linux` on an x86_64 Linux host took the
    // compile-only branch: both binaries were built, neither was run, and the
    // harness -- which always passes `-Dtarget` -- read that build as
    // `no_test_results` and marked every one of its 53 cells failed.  Observed
    // in the 2026-10-04 run, whose `x86_64-linux` log carries a green build
    // summary with only compile dependencies and no `run test` line at all.
    //
    // What then happens to the run is the build runner's business, and each
    // outcome is reportable as what it is.  A host target executes.  A foreign
    // target executes under whatever external executor the runner supplies --
    // the host itself, Rosetta, QEMU user mode, Wine or Wasmtime.  A foreign
    // target with no executor available fails this step and names the target
    // and the switch that would answer it (`lib/std/Build/Step/Run.zig:2760-
    // 2772`, reached from `failForeign`), which is build-only coverage
    // reported as unavailable rather than a compile that silently passes.
    // `addRunArtifact` says so itself (`lib/std/Build.zig:937-939`): "It
    // doesn't have to be native.  We catch that if you actually try to run
    // it."  Deciding that policy here would replace the runner's answer with a
    // guess about a target this script has not resolved.
    //
    // `has_side_effects` on both, because a `.zig_test` binary carries no side
    // effects (`lib/std/Build/Step/Run.zig:707-713`): a run whose compile step
    // was cached would otherwise be served from the run cache and report a pass
    // without executing a single test.
    const test_step = b.step("test", "Run the Random123 behaviour tests for the selected target");
    const kat = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-kat", "zig/kat_test.zig");
    const facade = addTestArtifact(b, mod, kat_vectors, build_target.target, optimize, "random123-facade", "zig/facade_test.zig");

    const run_kat = b.addRunArtifact(kat);
    run_kat.has_side_effects = true;
    test_step.dependOn(&run_kat.step);

    const run_facade = b.addRunArtifact(facade);
    run_facade.has_side_effects = true;
    test_step.dependOn(&run_facade.step);

    // The loader's own behavioural root.  Two guards, both load-bearing:
    //
    // `runtime_loaded`, because that file's first statement is a
    // `@compileError` unless `random123.runtime_loaded` is true.  Constructing
    // it unconditionally would fail the *default* build instead of adding
    // coverage to it, and `addCheck`/`matrix` compile the linked shape by
    // default, so neither of them constructs it either.
    //
    // Runs on this host, because it opens real files, contends real threads
    // and `dlopen`s a provider named by `RANDOM123_TEST_PROVIDER`.  The
    // predicate used to be `target.query.isNative()`, which is false for
    // `-Dtarget=x86_64-linux` on an x86_64 Linux host -- so naming this host's
    // own triple is what silently dropped these tests, for the same reason it
    // dropped the KAT and facade runs above.  `runsOnHost` asks
    // `std.zig.system.getExternalExecutor` instead, which is the question the
    // run itself is governed by, and answers yes for a host target reached
    // through any spelling of it.
    //
    // It stops at the host on purpose.  An interpreter is not this machine: a
    // foreign target under QEMU user mode, Wine or Wasmtime would answer
    // against a provider path a caller names for *that* ABI, and none of this
    // build's own output is one.  Forcing these roots into a compile-and-run
    // cell would report a result for a provider this build never produced.
    //
    // No `kat_vectors` import: that root carries fixed known answers inline so
    // it is about the loader and not about parsing, and it asks for nothing
    // else.
    if (runtime_loaded and runsOnHost(b, build_target.target)) {
        const load_tests_mod = b.createModule(.{
            .root_source_file = b.path("runtime/load_tests.zig"),
            .target = build_target.target,
            .optimize = optimize,
            // The loader reaches the platform's own dynamic linker through
            // libc.  The facade module carries that requirement through its
            // `c` import; this binary has to satisfy it the same way the
            // BLAKE3 pilot's equivalent root does.
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

    // `zig build check` compiles the public facade and the example for the
    // selected target without running anything.  analyze_test.zig calls every
    // public facade method with concrete types, so compiling it forces every
    // method body to be analyzed.
    const check_step = b.step("check", "Compile the public facade and example without running them");
    addCheck(b, check_step, build_target.target, optimize, build_target.aesni, linkage, runtime_loaded, kat_vectors);
    if (isX86(target)) {
        // Compile the AES-NI/ARS path as well on x86: it must build wherever x86
        // builds, whether or not the resolved CPU has AES-NI.  The feature goes
        // on the target, so the wrappers really compile instead of silently
        // disappearing -- see withX86Aesni.
        addCheck(b, check_step, withX86Aesni(b, target), optimize, true, linkage, runtime_loaded, kat_vectors);
    }

    // The whole cross-target graph in one invocation.
    const matrix_step = b.step("matrix", "Compile-check all six required targets");
    inline for (verify_matrix) |query| {
        const resolved = b.resolveTargetQuery(query);
        const matrix_target = resolveAesniTarget(b, resolved, aesni_option);
        addCheck(b, matrix_step, matrix_target.target, optimize, matrix_target.aesni, linkage, runtime_loaded, kat_vectors);
        if (isX86(resolved)) {
            addCheck(b, matrix_step, withX86Aesni(b, resolved), optimize, true, linkage, runtime_loaded, kat_vectors);
        }
    }

    // The *resolved* target, and the option as given rather than the resolved
    // answer: this step needs the CPU this build compiled for, and only the
    // caller's own selection.  See the note there on why that one stays null.
    addConsumerStep(b, build_target.target, aesni_option, optimize, linkage, runtime_loaded);
}

/// The front end that reads `zig/bridge/random123_bridge.h` for one target.
const TranslationRoute = enum {
    /// Aro preprocesses and parses the bridge header for itself.
    aro,
    /// The target's own C preprocessor expands it first, and Aro parses what
    /// that produced.
    preprocessed,
};

/// Chooses the front end that reads `zig/bridge/random123_bridge.h`.
///
/// Both arms are conditions on a family rather than on a list of triples, for
/// the same reason `erfa` and `utf8proc` decide theirs that way: every member of
/// a family reaches the same header through the same cause, so a triple list
/// would silently stop covering the family the moment a matrix grew an OS or a
/// CPU this file had never heard of.  See "Which front end reads the bridge
/// header" at the top of this file for the full cause.
fn translationRoute(target: std.Build.ResolvedTarget) TranslationRoute {
    // `powerpc`, `powerpc64` and `powerpc64le` are three `std.Target.Cpu.Arch`
    // members, and `gccfeatures.h:47` keys on the one `__powerpc__` predefine all
    // three share, so they are named separately for the same reason utf8proc
    // names `.mips64` and `.mips64el` separately.
    if (target.result.cpu.arch == .powerpc or
        target.result.cpu.arch == .powerpc64 or
        target.result.cpu.arch == .powerpc64le) return .preprocessed;
    return switch (target.result.os.tag) {
        .netbsd => .preprocessed,
        // Every other C library in this matrix closes a declaration block with
        // plain tokens that Aro parses, and none of them reads a compiler
        // predefine the way `gccfeatures.h:47` does.
        else => .aro,
    };
}

/// The generated prologue the preprocessed route prepends to the expansion.
///
/// `__int128_t` and `__uint128_t` belong to the compiler rather than to a
/// header: Clang declares them next to the `__int128` primitive it provides
/// (`clang/lib/Sema/Sema.cpp:402-415`) and no libc header repeats them, so
/// `-dD` keeps a spelling that nothing in the expansion defines.  NetBSD names
/// one -- `generic-netbsd/arm/cdefs.h:62-63` spells `__ALIGNBYTES` as
/// `(sizeof(__int128_t) - 1)` on the `__ARM_PCS_AAPCS64` branch, which is one of
/// the compiler's own predefines for AArch64 -- and the translated Zig then
/// names an identifier nothing in the file declares.
///
/// These are the compiler's own typedefs, restated under the compiler's own
/// capability macro, which it defines exactly when the target has that type: a
/// target without `__int128` declares neither.  It is a declaration of the
/// compiler's own extension, not a patch to any upstream header and not a
/// redefinition of a name a header owns.  `erfa`, `utf8proc`, `lmdb` and
/// `pcre2` each carry the same four lines for the same reason; the difference
/// is only that this package reads its translation root from
/// `zig/bridge/random123_bridge.h`, which is not a file this fork's build owns
/// the body of, so the declaration is force-included ahead of it instead of
/// written at the top of it.
const translate_prologue =
    \\#if defined(__SIZEOF_INT128__)
    \\typedef __int128 __int128_t;
    \\typedef unsigned __int128 __uint128_t;
    \\#endif
;

/// `zig/bridge/random123_bridge.h`, preprocessed for the target being built.
///
/// The extra front end `translationRoute` selects for the powerpc and NetBSD
/// families.  What this writes is the bridge header with every `#include`
/// resolved, every conditional settled and every macro definition kept, for the
/// target the bridge library is being compiled for.  Nothing is stubbed,
/// narrowed, renamed or substituted, and no architecture or compiler identity
/// macro is invented: the preprocessor here is the compiler that compiles
/// `random123_bridge.c`, so `__clang__`, `__powerpc__`, `_Pragma` and the C
/// library's own `__END_DECLS` are all resolved the way the target really has
/// them.
///
/// ## Why this preprocessor may run at all
///
/// It is the compiler running this build script -- `b.graph.zig_exe` -- so the
/// target and the include path are the ones `random123_bridge.c` is compiled
/// with, and the macros are the ones `addBridge` puts on this package's two C
/// lines: `R123_USE_MULHILO64_C99` and `R123_BRIDGE_HAS_AESNI` on the compile
/// line and on the translation line alike, `R123_USE_SSE` on the translation
/// line alone, which is exactly the split the `.aro` route already has.
///
/// ## Why `-dD`
///
/// Without it the expansion carries no macro definitions and `pub const c`
/// loses them.  Random123's own feature defaults (`R123_USE_GNU_UINT128`,
/// `R123_USE_MULHILO64_C99`, `R123_64BIT`, `R123_ULONG_LONG` and the rest of
/// the `R123_*` set) are object-like `#define`s that no declaration in the
/// bridge header *uses*, so a dump of used macros only would take the whole
/// constant set with it.  `-dD` keeps the `#define` lines beside the expanded
/// text, so a macro a C caller reads as a macro still reaches Zig as a
/// constant.  It is additive rather than lossy: the C library's own macros
/// come through on this route as well, and `zig/root.zig` names only this
/// package's own symbols out of `c`.
///
/// ## Why `-MD`
///
/// `zig/bridge/random123_bridge.h` reaches the twenty-six upstream headers only
/// through `#include`, and a `-I` directory argument contributes nothing but
/// its own resolved path to a run step's manifest (`Run.zig:827-831` hashes
/// `resolved_arg`, not the directory's contents).  So without a depfile this
/// step's declared inputs would be the bridge header and two path strings: a
/// later revision of `include/Random123/array.h` would be served from the run
/// cache and the translation would go on describing the previous one.  `-MD`
/// with `-MF`, through `addPrefixedDepFileOutputArg`, hands the discovered
/// headers to the build system as this step's own inputs.
///
/// ## What is deliberately not on this line
///
/// No `-std=`, no `-x c`, and no identity predefine.  The bridge header is a
/// `.h` file, which is C to both front ends, and pinning a dialect here would be
/// a third opinion the C compile line does not have.  The three macros below are
/// this fork's own configuration -- `R123_USE_SSE` is the translated view's
/// pin, and the other two are build decisions that already reach the C compile
/// line -- and not one of them is a statement about which compiler or CPU this
/// build is using.
fn preprocessedBridgeHeader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    aesni: bool,
) std.Build.LazyPath {
    // `b.graph.zig_exe` is the compiler running this build script, so the
    // preprocessor is the same pinned one the bridge is compiled by.
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD" });
    const triple = target.result.zigTriple(b.allocator) catch @panic("random123: unspellable target");
    // The step name carries the triple because `matrix` builds several of these
    // at once and `--summary all` has to tell them apart, exactly as
    // `addConsumerStep`'s nested build and utf8proc's preprocessor do.
    run.setName(b.fmt("preprocess random123 bridge header {s}", .{triple}));
    if (!target.query.isNative()) {
        run.addArg("-target");
        run.addArg(triple);
    }
    // The same include root the C compile line gives the bridge, so
    // `<Random123/array.h>` resolves to this repository's tree.
    run.addPrefixedDirectoryArg("-I", b.path("include"));
    // The compiler's own 128-bit typedefs, ahead of the header rather than
    // inside it.  See `translate_prologue`.
    run.addPrefixedFileArg("-include", b.addWriteFiles().add("random123-translate-prologue.h", translate_prologue));
    // The same three macros the translation line carries in `addBridge`, in the
    // same spelling, so the two cannot resolve different names.  Where both
    // lines define one, they define the identical object-like macro, which C
    // allows to be repeated without a diagnostic.
    run.addArg("-DR123_USE_SSE=0");
    if (needsC99Mulhilo(target)) run.addArg("-DR123_USE_MULHILO64_C99=1");
    if (aesni) run.addArg("-DR123_BRIDGE_HAS_AESNI=1");
    run.addArg("-o");
    // The generated file is this step's output, so the step is cached and the
    // `TranslateC` below depends on it rather than on a path in the source tree.
    const preprocessed = run.addOutputFileArg("random123-translate.c");
    run.addArg("-MD");
    // Discarded on purpose: the dep file itself is nothing downstream wants --
    // what matters is that the run step now records it, so `Run` reads it back
    // and the headers it names become this step's own inputs.
    _ = run.addPrefixedDepFileOutputArg("-MF", "random123-translate.d");
    run.addFileArg(b.path(bridge_header));
    return preprocessed;
}

/// Compiles the upstream headers into `librandom123` and translates the public
/// C surface for Zig.
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
        // A shared object has to be position independent or the loader cannot
        // place it away from its link address.  The static default is left at
        // the compiler's own choice, which is what this package always built.
        .pic = switch (linkage) {
            .static => null,
            .dynamic => true,
        },
    });
    // installHeadersDirectory below publishes the headers to consumers; the
    // library's OWN compile line still needs them on the include path.
    lib_mod.addIncludePath(b.path("include"));

    const lib = b.addLibrary(.{
        .name = "random123",
        .linkage = linkage,
        .root_module = lib_mod,
        // A COFF/PE DLL exports nothing unless something says otherwise, and
        // the bridge declarations carry no `__declspec(dllexport)` on purpose:
        // that is what lets one header serve the archive, the DLL and a
        // consumer that includes it directly.  The shared variant therefore
        // carries a generated module definition instead of a header edit.
        // `Step.Compile` reads this only for a library, a `.dynamic` linkage
        // and a COFF target, so the file is generated only for those and never
        // for an ELF or Mach-O build, which exports the same names already.
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
    lib.installHeader(b.path(bridge_header), "random123_bridge.h");

    // Which front end reads the bridge header is `translationRoute`'s call.  The
    // two routes differ in exactly one respect: the `.aro` one hands the
    // translator this fork's `zig/bridge/random123_bridge.h` to preprocess for
    // itself, and the `.preprocessed` one hands it what `zig cc -E -dD` already
    // wrote for the same target, on the same include path and with the same
    // three macros.  Either way the file translated is this package's bridge
    // header over this repository's upstream `include/Random123` tree, so the
    // declarations and constants below are the same set either way.
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
    // <Random123/array.h> unconditionally includes features/sse.h, which on x86
    // declares haveAESNI() with GNU inline assembly and pulls in <x86intrin.h>.
    // Inline assembly has no Zig representation, so the TRANSLATED view is
    // pinned to the portable r123arrayNxW types.  The compiled bridge keeps the
    // real value and the real AES-NI code; no upstream file is modified.
    tc.defineCMacro("R123_USE_SSE", "0");
    if (needsC99Mulhilo(target)) tc.defineCMacro("R123_USE_MULHILO64_C99", "1");
    if (aesni) tc.defineCMacro("R123_BRIDGE_HAS_AESNI", "1");

    return .{ .lib = lib, .translate = tc };
}

/// Gives the facade its `c` import, and the `rt` import it needs in the linked
/// shape, in exactly the form the selected dispatch mode calls for.
///
/// `-Druntime=true`: the facade's `c` import is the generated dispatch, which
/// re-exports the translated type and constant namespace and carries the table
/// behind `load`.  Nothing is linked, because a loaded provider has to arrive
/// through the platform loader; linking the archive as well would let the
/// linker resolve the same symbols statically and the runtime route would
/// quietly be a linked one.  The artifact is still built and installed by the
/// caller -- delivery and dispatch are separate questions -- because the point
/// of the mode is that a caller may name a provider this tree did not build.
/// The facade reaches `rt` only through its own `if (runtime_loaded)` branches,
/// so no `rt` import is created here and that module is never resolved.
///
/// otherwise: the translated header is imported, never registered as a named
/// module, so `dep.module("c")` cannot hand a dependent the declarations
/// without the library that satisfies them -- `random123.c` on the facade is
/// the supported way in and carries the facade's own linkage.  `rt` is the one
/// core-module instance in this build.  A second instance would be a
/// *different* `LoadSource`, and `load` would be handed the facade's type where
/// the dispatch expects its own; exactly one `createCoreModule` call happens
/// per shape, and in the runtime shape it happens inside `createModule`.
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
    // createModule() copies only link_libc and system_libs, so the include
    // path has to be re-added for the translated module itself.
    c_module.addIncludePath(b.path("include"));
    mod.addImport("c", c_module);
    mod.addImport("rt", graph.createCoreModule(b, target, optimize));
    mod.linkLibrary(core.lib);
}

/// Writes the Windows module definition file that gives the shared bridge a
/// real export table.
///
/// One `.def` per build, named for the artifact, listing exactly the wrappers
/// this build compiled: the common bridge ABI, plus the AES-NI and ARS entries
/// only when `R123_BRIDGE_HAS_AESNI` is 1.  Listing a symbol the artifact does
/// not define would turn the missing AES-NI path on a baseline x86 CPU into a
/// link failure, so the two lists are never merged into one constant.
fn addWindowsExports(b: *std.Build, aesni: bool) std.Build.LazyPath {
    // `Step.WriteFile.add` copies the bytes into the build allocator, so this
    // scratch buffer can stay owned by the same allocator for the rest of the
    // run; there is nothing here worth releasing early.
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

/// Writes and installs `lib/pkgconfig/random123.pc`.
///
/// `prefix` is derived from `${pcfiledir}`, which pkg-config defines as the
/// directory holding the `.pc` file, so the record keeps working when the
/// whole prefix is moved and no configured-in path is baked into it.  The
/// installed layout puts the artifact in `lib/` and the headers in `include/`,
/// so `../..` from `lib/pkgconfig` is the prefix.
///
/// `Libs: -lrandom123` names whichever artifact this build installed, the
/// archive or the shared object, which is why the file does not vary with
/// `-Dlinkage`.  There is no `Requires:` line: the bridge calls only the
/// upstream inline algorithms and the C library it is already linked against,
/// and Random123 has no build-time or link-time dependency to declare.
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
///
/// `linkage` and `runtime_loaded` are the caller's selections, not fixed
/// ones, so `check` and `matrix` compile the same artifact shape and the same
/// dispatch shape that `install` produces.  A build option that only affected
/// `install` would leave the only place that actually compiles C unexercised
/// for the shared variant, and would leave the runtime branch uncompiled
/// everywhere.
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
/// `-Dlinkage` travels the same way and for the same reason.  The consumer
/// reaches this package only as a path dependency, so without the forwarded
/// option it would silently rebuild the static bridge and link that, and
/// `zig build consumer -Dlinkage=dynamic` would then prove nothing about the
/// shared artifact this build just installed.
///
/// `-Druntime` travels with them.  The same reasoning applies for the same
/// reason: a runtime-loaded consumer must reach the *dispatching* module, and
/// one that silently got the linked one back would prove nothing about the
/// configuration the outer build just selected.  The flag is always passed,
/// `false` included, so the sub-build's own default can never be what a
/// consumer build ended up exercising.
///
/// `-Daesni` travels with them, and it is the one flag this step passes only
/// when it was given one.  The target above is the *resolved* one, which is
/// what makes that asymmetry sound rather than lossy: `withX86Aesni` puts the
/// `aes` feature on the query, and `Target.Query.serializeCpu` renders
/// `cpu_features_add` after the CPU name
/// (`lib/std/Target/Query.zig:509-527`), so the sub-build parses the same
/// feature set this build compiled with.  An unset flag then needs no
/// forwarding at all: the dependency's own rule (`requested orelse isX86(target)
/// and cpuHasAes(target)`) reads that CPU and reaches the same answer without
/// being told.  A set flag is the one selection no CPU can imply, and it is
/// exactly what used to be dropped: `zig build consumer -Daesni=true` reached
/// the sub-build as `-Dtarget=… -Dcpu=baseline`, which compiled, linked and
/// ran the aesni=false consumer -- a configuration the caller did not ask for
/// and not the artifact this build had just installed.  Substituting the
/// resolved `bool` instead of the option would be worse in the one case that
/// matters most, `-Daesni=false` on a host whose CPU does have AES-NI: the
/// sub-build's CPU alone would answer yes, and the two graphs would disagree
/// about the very wrapper set the caller explicitly turned off.
///
/// Run, or only install
/// --------------------
/// The question is whether *this host* can execute the selected target.  It is
/// asked of the resolved target by `std.zig.system.getExternalExecutor`
/// (`lib/std/zig/system.zig:42`), the same function `std.Build.Step.Run` calls
/// when a spawned binary turns out to be foreign
/// (`lib/std/Build/Step/Run.zig:1268`).  That replaces a predicate which could
/// not answer it: `Target.Query.isNative()`
/// (`lib/std/Target/Query.zig:396-398`) is
/// `isNativeTriple() and ofmt == null`, and `isNativeTriple()` (`:392-394`)
/// demands `cpu_arch`, `os_tag` and `abi` all be null, so `-Dtarget=x86_64-linux`
/// was never native on an x86_64 Linux host.  This step took the `install`
/// branch there, which is the one thing it exists to prevent: a consumer build
/// that installs and runs nothing reports a green consumer for a program that
/// was never executed.
///
/// An external executor counts as available only when the build runner was
/// told it may use one: `-fwasmtime`, `-fqemu`, `-fwine` and `-fdarling` are the
/// build runner's own switches for that (`lib/compiler/build_runner.zig:388-
/// 407`, exposed as `b.enable_wasmtime` and friends, `lib/std/Build.zig:71-79`),
/// and each names a separate program whose presence on `PATH` this script
/// cannot know.  `-frosetta` names none and `std.Build` reads `enable_rosetta`
/// nowhere, so it is forwarded for fidelity and never gates the decision.
/// Forwarding the switches makes the decision and the nested run agree on one
/// executor: a QEMU'd target here runs the consumer under the same QEMU that
/// runs the tests above, and without the switch this step would install a
/// consumer that the nested `Run` step then refuses.  A target that still has
/// no executor builds and installs, which is compile evidence and nothing
/// more.
///
/// Everything else this build resolved travels with it too: the job width and
/// summary, both cache directories, and the install prefix when the caller
/// named one.  Each is forwarded for the same reason as the options above --
/// a nested build left to resolve its own would prove a configuration nobody
/// asked for.
fn addConsumerStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    aesni: ?bool,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
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
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // `-Daesni`, unlike the two above, travels only when this build was given
    // one.  A null is forwarded as no argument at all -- not as `false`, and
    // not as this build's resolved answer -- because "nobody chose" is the
    // dependency's own rule, and it reaches the same answer from the CPU the
    // two `-D` arguments above just handed it.
    if (aesni) |selected| {
        run.addArg(b.fmt("-Daesni={s}", .{if (selected) "true" else "false"}));
    }
    // The executor switches this build resolved, so the nested build runs
    // under the same one `hostCanExecute` decided with: an explicitly enabled
    // QEMU executes a foreign consumer here, exactly as it executes the test
    // binaries above, and without the switch the nested `Run` step would
    // refuse the same binary this step promised to run.  `--libc-runtimes` is
    // that QEMU integration's dynamic-linker support
    // (`lib/compiler/build_runner.zig:325`), and `hostCanExecute` asks the
    // question including the refusal `Run` makes once the predicate has
    // already said yes, so the two have to carry the same directory.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // The nested build carries this workspace's job count in its own command
    // line, for the reason every `zig build` entry in `devenv.nix` writes one:
    // nothing can append a `-j` to a `Run` step's command, so a nested build
    // left to derive its own width takes `cpu_count - 1`
    // (`std/Io/Threaded.zig:1639`) instead, and the consumer this step proves
    // then compiles at a different width from the build that asked for it --
    // and at a different width again on whichever machine runs the gate.
    run.addArg("-j8");
    // `--summary all`, two arguments for the same reason `--cache-dir` below is
    // two: the build runner documents it as `--summary [mode]`
    // (`lib/compiler/build_runner.zig:1639`) and reads the mode as the next
    // argument (`:262-265`), with `all` one of five enumerated spellings
    // (`:1738`).  Left off, the nested build reports `.failures`
    // (`lib/compiler/build_runner.zig:523`), which prints nothing when nothing
    // failed -- so on a passing consumer the gate's own output would show no
    // steps at all, and the run this step exists to perform would be invisible
    // in the log that has to carry it.
    run.addArgs(&.{ "--summary", "all" });
    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory, and a cache manifest is
    // locked for the duration of the process that holds it
    // (`Build/Cache.zig` Manifest).  A null `path` means "the current
    // directory", and the working directory above is already the consumer
    // package, so the default is right there.
    //
    // Two arguments, not one `--cache-dir=...`.  `--cache-dir [path]` is the
    // spelling the build system documents
    // (`lib/compiler/build_runner.zig:1674`), and the `=`-joined spelling is
    // not an alternative form of it: it arrives at the build runner as an
    // unrecognised `-` argument, which is fatal
    // (`lib/compiler/build_runner.zig:160`, `:431-433` -- `-D`, `-Z` and the
    // enumerated long options are the whole list).  Observed: with
    // `ZIG_LOCAL_CACHE_DIR` exported, `zig build consumer` reached exactly this
    // branch and the nested build died before compiling anything, on
    // `unrecognized argument: '--cache-dir=.../consumer'`
    // (random123-devenv-consumer.log, 2026-10-04T19:43:42Z).  With no cache
    // directory given the branch is not taken, which is why the same command
    // succeeds in a shell that exports none.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache travels by its own path, with no `/consumer`
    // subdirectory, and that asymmetry with the local cache above is the whole
    // point rather than an oversight.  The local cache holds this graph's
    // manifest directory and is locked for the life of the process holding it,
    // so two graphs are given two of them; the global cache holds
    // content-addressed package directories keyed by hash, which is what is
    // meant to be shared between builds, and the compiler forwards it verbatim
    // from a build script rather than deriving one
    // (`lib/std/Build/Step/Compile.zig:1477-1480`, and again
    // `lib/std/Build/Step/TranslateC.zig:179-180`).  Two arguments, and the
    // same spelling as the local pair
    // (`lib/compiler/build_runner.zig:1675`).  The build runner populates
    // this path unconditionally (`:53-54`, `:73-76`, `:89`), so a
    // `--global-cache-dir` the caller named here is the directory the nested
    // build then uses, instead of the nested build resolving one of its own
    // outside this workspace's approved root.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The install prefix this invocation resolved, handed on when the caller
    // named one.  A nested `zig build` left to resolve its own installs into
    // `consumer/zig-out` -- a build artefact inside a source package -- rather
    // than into the directory the caller asked for.  A relative `--prefix`
    // would resolve against the working directory set above, `consumer/`, and
    // not against this build's root, so it is made absolute before it is
    // handed on.  `DESTDIR` needs no forwarding, because the nested build
    // inherits the environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`.  `zig build consumer --
    // --provider <path>` collects them in `b.args`, the nested build's `run`
    // step hands its own `b.args` to the program (`consumer/build.zig:70`), and
    // that program is the consumer check: it reads `--provider` from argv
    // (`consumer/src/main.zig:50-51`, `:57-64`).  Every argument above is this
    // package's own bookkeeping with the nested build; an argument the caller
    // typed is forwarded verbatim or not at all, and this `--` has to follow
    // all of them because it ends the nested build's option parsing.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    b.step("consumer", "Build the consumer/ package, and run it when this host can execute the selected target").dependOn(&run.step);
}

/// True when this host can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`) is the
/// predicate `std.Build.Step.Run` asks about the artifact it is about to spawn
/// (`lib/std/Build/Step/Run.zig:1268`).  That replaces a predicate which could
/// not answer it: `Target.Query.isNative()`
/// (`lib/std/Target/Query.zig:396-398`) is
/// `isNativeTriple() and ofmt == null`, and `isNativeTriple()` (`:392-394`)
/// demands `cpu_arch`, `os_tag` and `abi` all be null, so `-Dtarget=x86_64-linux`
/// was never native on an x86_64 Linux host -- this step installed the nested
/// build instead of running it, which is the one thing it exists to prevent.
///
/// Both options `Run` fills in from that artifact are filled in here from the
/// same facts.  `consumer/` builds its executable with `b.addExecutable` and no
/// linkage, so `Run`'s `need_cross_libc` (`lib/std/Build/Step/Run.zig:1264-1266`)
/// is that binary's `is_linking_libc` -- true, because the `random123` module
/// it imports reaches this package's bridge, whose module sets `link_libc` --
/// tested against the target itself; its musl half additionally asks for
/// `exe.linkage == .dynamic`, and that field is null here, so the half never
/// contributes.  QEMU reaches a foreign dynamic linker only with
/// `--libc-runtimes`, which is `qemu_fixes_dl`.
///
/// `Run` allows every executor in the predicate and then gates the answer on
/// this build's own switches (`:1277`, `:1291`, `:1317`, `:1325`); carrying
/// those switches in `allow_*` asks the identical question and answers it
/// without a second switch.  What an `allow_*` option cannot carry is a
/// refusal `Run` makes *after* the predicate has already said yes: its QEMU arm
/// returns `failForeign` for a `need_cross_libc` target that was given no
/// `--libc-runtimes` (`:1294-1311`).  That second gate is the `.qemu` arm below,
/// and it is why the answer there is not simply `true`.  A target with no
/// executor at all builds and installs, which is compile evidence and nothing
/// more; that is also the case in which the nested `run` step would fail, and
/// this step declines to ask it a question it cannot answer.
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
        // Reachable only for an executor the switches above enabled.
        .wine, .wasmtime, .darling => true,
        // `.qemu` is not a yes on its own: the second gate above.  A GNU libc
        // target with no runtimes directory is a step `Run` fails after this
        // function said yes to it, so this step installs it instead.  Every
        // other QEMU case -- a foreign architecture whose libc needs no cross
        // runtime, a musl consumer among them -- still runs.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        // Same OS and CPU with no dynamic linker to load, or an architecture
        // and system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// True when `target` runs on this machine itself, with no interpreter.
///
/// `hostCanExecute` answers "can this host run it at all"; this answers "is
/// this host the machine".  Only `.native` and Rosetta qualify: Rosetta is the
/// operating system running the binary rather than a program this build has to
/// find, and both give `runtime/load_tests.zig` the real files, the real
/// threads and the real platform loader it needs in order to say anything at
/// all.  QEMU user mode, Wine and Wasmtime are interpreters: a provider named
/// for one ABI is not a provider for another.
///
/// Every `allow_*` here is false because this function asks about the machine,
/// not about availability -- which is exactly why `enable_rosetta` is absent:
/// `-frosetta` resolves, but nothing in `std.Build` reads it, because on an
/// Apple Silicon host it is the operating system that runs the binary.
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
