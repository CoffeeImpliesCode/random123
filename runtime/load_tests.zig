// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Behavioural tests for the runtime loader.
//!
//! ## What these tests are about
//!
//! The loader's contract is mostly about what happens *between* calls: a
//! failure that publishes nothing, a retry that is the caller's to make, a
//! second request for the provider already in use, a dozen threads arriving at
//! one attempt. None of that is observable from a single call, which is why this
//! is a separate test root instead of more cases in `zig/kat_test.zig`.
//!
//! ## Real providers, no mock
//!
//! Every provider here is a real file that exists on the machine, and none of
//! them imitates Random123's behaviour:
//!
//!   * `RANDOM123_TEST_PROVIDER` — a shared object exporting the `r123_bridge_*`
//!     names this build's translation declares. The answers checked below come
//!     from upstream's own fixture, so a provider that resolved but computed
//!     something else fails.
//!   * `RANDOM123_TEST_ALIEN` — the **absolute** path of a loadable object
//!     that is not this bridge. It opens, and it exports none of the bridge's
//!     names, which is exactly the situation `MissingSymbol` exists for. Both
//!     variables are inherited from the caller's environment rather than set
//!     by the build: the only API for a run step's environment is
//!     `setEnvironmentVariable`, which takes literal strings and has no way to
//!     resolve a path (`Run.zig:595-598`), so a harness that runs this root has
//!     to export both.
//!   * a path under a directory that does not exist, for `OpenFailed`. That one
//!     needs no configuration, because no machine has that directory.
//!
//! Nothing is skipped when a variable is missing. In a runtime-loading build a
//! test that cannot name a provider has nothing to say, and passing anyway
//! would mean nothing at all.
//!
//! ## Order is part of the contract
//!
//! There is one loader per process and no unload, so the first successful load
//! is a one-way door. The tests that need a module which has not loaded yet are
//! above the first successful load, and the test runner runs them in source
//! order. That is a property of the contract under test rather than a
//! convenience: any consumer with this lifecycle has the same constraint.

const std = @import("std");
const random123 = @import("random123");
const testing = std.testing;

comptime {
    if (!random123.runtime_loaded) {
        @compileError(
            "runtime/load_tests.zig is the runtime-loading test root. Build it " ++
                "with runtime loading configured; in a linked build there is no " ++
                "loader to test and `load` deliberately stops the program.",
        );
    }
}

/// A shared object exporting the `r123_bridge_*` names this build declares.
///
/// Spelled here rather than imported: a module root may not import a file
/// outside its own directory, and `zig/provider.zig` is one level up. It is the
/// same string that file names, and a mismatch fails the run with a message
/// saying the variable is unset rather than with a silent skip.
const provider_variable = "RANDOM123_TEST_PROVIDER";

/// A loadable object that is not this bridge: it opens, and exports none of them.
const alien_variable = "RANDOM123_TEST_ALIEN";

/// No machine has this directory, which is what makes it a real `OpenFailed`
/// rather than a guess about what might be missing.
const absent_path = "/random123-no-such-directory/librandom123.so";

/// What a thread stores when it comes back from a load.
const Outcome = random123.LoadError!void;

/// What can be wrong with this file's own expectations.
const Problem = error{
    /// The loader was ready but reported no request, which the contract says
    /// cannot happen.
    NoRetainedRequest,
    /// The two requests this file built to be different came out identical, so
    /// the test would not have been testing anything.
    RequestsWereEqual,
};

/// Copy an environment variable into `buffer`, or return null when it is unset.
fn envCopy(buffer: []u8, key: []const u8) ?[]const u8 {
    const value = std.testing.environ.getAlloc(std.testing.allocator, key) catch return null;
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

fn providerPath(buffer: []u8) []const u8 {
    return envCopy(buffer, provider_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ provider_variable ++
            " is not set. These tests load a real provider by path; without one " ++
            "there is nothing to test and passing would mean nothing.",
    );
}

fn alienPath(buffer: []u8) []const u8 {
    return envCopy(buffer, alien_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ alien_variable ++
            " is not set. Point it at the ABSOLUTE path of a loadable object " ++
            "that is not this bridge; the partial-symbol case needs a file " ++
            "that opens and exports none of the r123_bridge_* names. A path is " ++
            "required because the loader refuses a relative .path as " ++
            "InvalidSource before it opens anything, and a file that cannot " ++
            "open would be refused as OpenFailed, which is a different case " ++
            "and one the absent-directory test already covers. The " ++
            "caller exports it, because a build step's environment map takes " ++
            "literal strings and has no way to resolve a path at build time; " ++
            "nothing is skipped here when it is missing.",
    );
}

/// One thread's whole job: load one path and store what came back.
fn contendOn(path: []const u8, outcome: *Outcome) void {
    outcome.* = random123.load(.{ .path = path });
}

fn retainedPath() Problem![]const u8 {
    const retained = random123.loadedSource() orelse return error.NoRetainedRequest;
    return retained.path;
}

test "an empty request is refused before the platform is called" {
    try testing.expectError(error.EmptySource, random123.load(.{ .path = "" }));
    try testing.expectError(error.EmptySource, random123.load(.{ .system = "" }));
    try testing.expect(random123.loadedSource() == null);
}

test "a request longer than the loader will remember is refused" {
    // The loader keeps its own copy of the request and refuses one that does
    // not fit, because a truncated path is a different path.
    var buffer: [64 * 1024]u8 = undefined;
    @memset(&buffer, 'x');
    try testing.expectError(
        error.SourceTooLong,
        random123.load(.{ .path = buffer[0..] }),
    );
    try testing.expect(random123.loadedSource() == null);
}

test "a relative path and a path-shaped system name are both refused" {
    // The loader requires `.path` to be absolute and `.system` to be a bare
    // basename (`runtime/loader.zig:186-201`). Both of these are checked before
    // the platform is called, so they are refusals rather than attempts that
    // happened to fail, and neither reaches `dlopen`.
    //
    // The relative one is the case worth pinning: a caller who exports
    // `RANDOM123_TEST_PROVIDER=./librandom123.so` would otherwise be silently
    // loading whatever that means relative to wherever the process happens to
    // be, and the answer would depend on the working directory rather than on
    // what was asked for.
    try testing.expectError(
        error.InvalidSource,
        random123.load(.{ .path = "provider/lib/librandom123.so" }),
    );
    // A `.system` request carrying a separator is a path wearing a name, which
    // is the other kind of request the two spellings exist to keep apart.
    try testing.expectError(
        error.InvalidSource,
        random123.load(.{ .system = "provider/lib/librandom123.so" }),
    );
    try testing.expect(random123.loadedSource() == null);
}

test "a file that is not there is refused, and nothing is published" {
    try testing.expectError(error.OpenFailed, random123.load(.{ .path = absent_path }));
    try testing.expect(random123.loadedSource() == null);
}

test "a provider that exports none of the bridge's names is refused" {
    var alien: [4096]u8 = undefined;
    const path = alienPath(&alien);
    try testing.expectError(error.MissingSymbol, random123.load(.{ .path = path }));
    // The candidate opened. Nothing about it reached the table, so there is
    // still no provider and no request.
    try testing.expect(random123.loadedSource() == null);
}

test "threads contending on one failing attempt all get that attempt's result" {
    const ThreadCount = 8;
    var alien: [4096]u8 = undefined;
    const path = alienPath(&alien);

    var outcomes: [ThreadCount]Outcome = undefined;
    var threads: [ThreadCount]std.Thread = undefined;
    for (&threads, &outcomes) |*thread, *outcome| {
        thread.* = try std.Thread.spawn(.{}, contendOn, .{ path, outcome });
    }
    for (threads) |thread| thread.join();

    // Every one of them waited for the single attempt and received its error.
    // None of them started a competing attempt and none of them saw a different
    // outcome: that is what receiving that attempt's result means.
    for (outcomes) |outcome| {
        try testing.expectError(error.MissingSymbol, outcome);
    }
    try testing.expect(random123.loadedSource() == null);
}

test "an explicit retry after a failure succeeds and is retained" {
    var bridge: [4096]u8 = undefined;
    const path = providerPath(&bridge);
    try random123.load(.{ .path = path });
    try testing.expectEqualStrings(path, try retainedPath());
}

test "the same request twice succeeds and changes nothing" {
    var bridge: [4096]u8 = undefined;
    const path = providerPath(&bridge);
    try random123.load(.{ .path = path });
    try random123.load(.{ .path = path });
    try testing.expectEqualStrings(path, try retainedPath());
}

test "threads contending after a load all succeed" {
    const ThreadCount = 8;
    var bridge: [4096]u8 = undefined;
    const path = providerPath(&bridge);

    var outcomes: [ThreadCount]Outcome = undefined;
    var threads: [ThreadCount]std.Thread = undefined;
    for (&threads, &outcomes) |*thread, *outcome| {
        thread.* = try std.Thread.spawn(.{}, contendOn, .{ path, outcome });
    }
    for (threads) |thread| thread.join();

    // The loader is published here, so these take the lock-free path. They
    // still have to agree with each other and with the table.
    for (outcomes) |outcome| try outcome;
    try testing.expectEqualStrings(path, try retainedPath());
}

test "a different request is refused once a provider is in use" {
    // Both spellings are refused, and neither reaches the platform: the
    // provider in use stays in use.
    try testing.expectError(
        error.ProviderMismatch,
        random123.load(.{ .system = "librandom123-not-installed.so" }),
    );
    try testing.expectError(
        error.ProviderMismatch,
        random123.load(.{ .path = "/somewhere/else/librandom123.so" }),
    );
    const before = try retainedPath();
    try testing.expect(before.len != 0);
}

test "a request that is not the same byte sequence is a different request" {
    var bridge: [4096]u8 = undefined;
    const path = providerPath(&bridge);
    // The same file, named with an extra `.` component. There is no
    // normalization anywhere in the loader, so this is a different request and
    // is refused.
    //
    // The alternate has to be a request the loader would otherwise accept, and
    // that is what this test used to get wrong: it spelled the request as
    // `"./" ++ path`, which is not absolute, so `validateSource` refused it as
    // `InvalidSource` (`runtime/loader.zig:194`) before the comparison in
    // `accept` ever ran — `load` calls `validateSource` before it asks whether
    // the request is the one already in use (`runtime/loader.zig:366`). The
    // expectation then read that earlier refusal as an answer about the byte
    // comparison, and the run reported `expected error.ProviderMismatch, found
    // error.InvalidSource`.
    //
    // A `.` component is a no-op in POSIX pathname resolution, so this names
    // the same file the loaded provider lives in and only the bytes differ.
    // It is inserted after the root rather than before it because the loader
    // requires an absolute path, and this spelling stays one for every
    // provider path, including a provider that sits directly in `/`. `path` is
    // absolute here by fact rather than by assumption: the test above it loaded
    // this provider successfully, and the loader refuses a relative `.path`.
    var decorated: [4200]u8 = undefined;
    const longer = try std.fmt.bufPrint(
        &decorated,
        "{s}/.{s}",
        .{ path[0..1], path[1..] },
    );
    if (std.mem.eql(u8, longer, path)) return error.RequestsWereEqual;
    try testing.expectError(error.ProviderMismatch, random123.load(.{ .path = longer }));
}

test "the loaded bridge answers upstream's own known answers" {
    // The whole point of loading a real provider: these words are what upstream
    // published for these exact inputs, so they are an oracle this fork does
    // not get to choose. A provider that resolved but computed something else
    // produces different words here.
    //
    // The source is `tests/kat_vectors`, replayed through the typed facade so
    // this file stays about the loader rather than about parsing.
    const P2x32 = random123.Philox2x32;
    try testing.expectEqual(
        P2x32.counter{ 0xff1dae59, 0x6cd10df2 },
        P2x32.generate(.{ 0, 0 }, .{0}),
    );

    const P4x32 = random123.Philox4x32;
    try testing.expectEqual(
        P4x32.counter{ 0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8 },
        P4x32.generate(.{ 0, 0, 0, 0 }, .{ 0, 0 }),
    );

    const T4x64 = random123.Threefry4x64;
    try testing.expectEqual(
        T4x64.counter{ 0x09218ebde6c85537, 0x55941f5266d86105, 0x4bd25e16282434dc, 0xee29ec846bd2e40b },
        T4x64.generate(.{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }),
    );

    // And one raw conversion, straight through `c`, at the exact grid point
    // upstream's definition gives for the median u64: `(i >> 11) * 2^-53`, so
    // `2^63` is exactly 0.5 (`u01fixedpt.h:122,160-162`). Both operands are
    // exactly representable, so `!=` here is an equality test.
    try testing.expectEqual(
        @as(f64, 0.5),
        random123.c.r123_bridge_u01_closed_open_64_double(@as(u64, 1) << 63),
    );
}

test "an AES-NI provider on a CPU without AES-NI still serves the portable surface" {
    // Not analysed at all when this build declared no AES-NI entry points, so a
    // build without them needs no provider for this test and does not demand one.
    if (comptime !random123.has_aesni) return error.SkipZigTest;

    // The five AES-NI names resolved as part of the load that already happened,
    // or the table would not be ready and this line would not run. What is not
    // automatic is that the *rest* still works: a provider compiled with AES-NI
    // contains x86 AES instructions, and a caller who never calls those four
    // generators must still get correct answers from the twenty-eight portable
    // ones on a CPU that has no AES-NI. That is the case a `-Daesni=true` build
    // on a baseline x86 CPU is actually in, and it is why `validate` does not
    // consult the probe: refusing the provider there would refuse a library
    // that is entirely usable across most of its surface.
    const has_aesni_cpu = random123.c.r123_bridge_have_aesni() != 0;

    // Upstream's own answers for an all-zero counter and key, reached through
    // the loaded provider. Asked unconditionally, on both branches, because
    // that is the property: the portable surface does not depend on whether
    // this CPU could have run the AES-NI one.
    const T4x32 = random123.Threefry4x32;
    try testing.expectEqual(
        T4x32.counter{ 0x9c6ca96a, 0xe17eae66, 0xfc10ecd4, 0x5256a7d8 },
        T4x32.generate(.{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }),
    );
    const P2x32 = random123.Philox2x32;
    try testing.expectEqual(
        P2x32.counter{ 0xff1dae59, 0x6cd10df2 },
        P2x32.generate(.{ 0, 0 }, .{0}),
    );

    // Nothing below this line runs on a CPU without AES-NI, and that is a hard
    // boundary rather than a caution: upstream's key expansion is
    // `_mm_aeskeygenassist_si128` (`aes.h:71,75,79,83,87,91,95,99,103`) and the
    // round function is `_mm_aesenc_si128` (`aes.h:186-195`), so calling them
    // here would be an illegal instruction rather than a wrong answer. ARS uses
    // the carry-less multiply in the same instruction set.
    if (!has_aesni_cpu) return;

    // `R123_BRIDGE_AESNI_KEY_WORDS` is the header's own statement of the
    // schedule size, and this array is sized from it, so a provider that
    // expanded to a different length would be written past rather than
    // silently tolerated. `zig/kat_test.zig` replays upstream's AES-NI and ARS
    // fixture lines under this same probe gate.
    var schedule: [random123.c.R123_BRIDGE_AESNI_KEY_WORDS]u32 = undefined;
    random123.c.r123_bridge_aesni4x32_keyinit(&schedule, .{ .v = .{ 0, 0, 0, 0 } });
    const ars_key = random123.c.r123_bridge_ars4x32_keyinit(.{ .v = .{ 0, 0, 0, 0 } });
    _ = random123.c.r123_bridge_aesni4x32_R(
        random123.c.R123_BRIDGE_AESNI4x32_ROUNDS,
        .{ .v = .{ 0, 0, 0, 0 } },
        &schedule,
    );
    _ = random123.c.r123_bridge_ars4x32_R(
        random123.c.R123_BRIDGE_ARS4x32_DEFAULT_ROUNDS,
        .{ .v = .{ 0, 0, 0, 0 } },
        ars_key,
    );
}
