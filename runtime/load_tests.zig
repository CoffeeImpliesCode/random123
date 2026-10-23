// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Exercise loader failure, retry, idempotence, mismatch, and concurrency behavior.
//! Set `RANDOM123_TEST_PROVIDER` to the bridge and `RANDOM123_TEST_ALIEN` to an absolute non-bridge path.
//! Tests run in source order because a successful load is process-global and cannot be reset.

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

/// Environment variable naming a shared object with this build's bridge exports.
const provider_variable = "RANDOM123_TEST_PROVIDER";

/// Environment variable naming a loadable object without bridge exports.
const alien_variable = "RANDOM123_TEST_ALIEN";

/// Deliberately nonexistent absolute path for `OpenFailed`.
const absent_path = "/random123-no-such-directory/librandom123.so";

/// Result stored by each loader thread.
const Outcome = random123.LoadError!void;

/// Failures in this test file's own expectations.
const Problem = error{
    /// The loader became ready without retaining a request.
    NoRetainedRequest,
    /// Distinct test requests unexpectedly compared equal.
    RequestsWereEqual,
};

/// Copy an environment variable to `buffer`, or return null if it is unavailable.
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

/// Load one path and store the result for the calling thread.
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
    var buffer: [64 * 1024]u8 = undefined;
    @memset(&buffer, 'x');
    try testing.expectError(
        error.SourceTooLong,
        random123.load(.{ .path = buffer[0..] }),
    );
    try testing.expect(random123.loadedSource() == null);
}

test "a relative path and a path-shaped system name are both refused" {
    try testing.expectError(
        error.InvalidSource,
        random123.load(.{ .path = "provider/lib/librandom123.so" }),
    );
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

    for (outcomes) |outcome| try outcome;
    try testing.expectEqualStrings(path, try retainedPath());
}

test "a different request is refused once a provider is in use" {
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
    // A dotted component names the same file but forms a different absolute request.
    // Place it after the root so the path remains absolute even when the file is in `/`.
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
    // Upstream known answers catch providers that export the names but compute different values.
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

    // Upstream maps `(i >> 11) * 2^-53`, so `2^63` is exactly 0.5 (`u01fixedpt.h:122,160-162`).
    try testing.expectEqual(
        @as(f64, 0.5),
        random123.c.r123_bridge_u01_closed_open_64_double(@as(u64, 1) << 63),
    );
}

test "an AES-NI provider on a CPU without AES-NI still serves the portable surface" {
    if (comptime !random123.has_aesni) return error.SkipZigTest;

    // An AES-NI provider still serves the 28 portable exports on CPUs without AES-NI.
    // Probe the CPU before calling the AES-NI or ARS wrappers below.
    const has_aesni_cpu = random123.c.r123_bridge_have_aesni() != 0;

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

    // AES-NI and ARS instructions trap on unsupported CPUs; gate these calls on the probe.
    if (!has_aesni_cpu) return;

    // Size the key schedule from the bridge header's exported word count.
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
