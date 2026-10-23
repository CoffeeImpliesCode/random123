// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Resolves provider paths for this package's runtime-loading examples and tests.
//! Runtime builds require `--provider <path>` or `RANDOM123_TEST_PROVIDER`; `load` is a no-op when linked.
//! Paths pass through unchanged and must satisfy the loader's absolute-path rule.

const std = @import("std");
const random123 = @import("random123");

/// Environment variable used when no command-line provider is supplied.
pub const provider_variable = "RANDOM123_TEST_PROVIDER";

/// Error returned when runtime mode has no provider request.
pub const NoProviderConfigured = error{NoProviderConfigured};

/// Union of the missing-provider error and loader errors returned by `load`.
pub const LoadFailure = NoProviderConfigured || random123.LoadError;

/// Loads the selected path or returns `NoProviderConfigured` or a loader error.
/// Linked builds return immediately; the path slice remains caller-owned.
pub fn load(value: ?[]const u8) LoadFailure!void {
    if (comptime !random123.runtime_loaded) return;
    return random123.load(.{ .path = value orelse return notConfigured("random123") });
}

/// Borrows the argument after `--provider`, or returns null when the flag or value is absent.
/// A trailing flag is absence, not an empty-path loader request.
pub fn fromArgs(argv: []const [:0]const u8) ?[]const u8 {
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (!std.mem.eql(u8, argv[index], "--provider")) continue;
        if (index + 1 >= argv.len) return null;
        return argv[index + 1];
    }
    return null;
}

/// Borrows the provider value from an environment map, or returns null if absent.
/// The slice remains valid while the map does.
pub fn fromMap(environ: *const std.process.Environ.Map) ?[]const u8 {
    return environ.get(provider_variable);
}

/// Copies the provider value from a raw environment block; absent, empty, or allocation failure returns null.
/// Caller owns the returned slice and must free it with `gpa`.
pub fn fromBlock(gpa: std.mem.Allocator, environ: std.process.Environ) ?[]u8 {
    const value = environ.getAlloc(gpa, provider_variable) catch return null;
    if (value.len == 0) {
        gpa.free(value);
        return null;
    }
    return value;
}

/// Prints provider-selection instructions and returns `NoProviderConfigured`.
pub fn notConfigured(program: []const u8) NoProviderConfigured {
    std.debug.print(
        "{s}: this is a runtime-loading build and was not told which provider to " ++
            "load. Pass --provider <path>, or export " ++
            "RANDOM123_TEST_PROVIDER, naming a shared object built from this " ++
            "package's bridge (zig/bridge/random123_bridge.c) and exporting its " ++
            "r123_bridge_* names. Nothing is loaded by default and no other file " ++
            "is tried.\n",
        .{program},
    );
    return error.NoProviderConfigured;
}
