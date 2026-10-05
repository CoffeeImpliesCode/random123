// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Naming the provider for a runtime-loading build of this package.
//!
//! This package's own smoke example and its behaviour tests are the programs
//! that have to name a provider, because they run in both configurations. In a
//! linked build they reach the bridge through the link and there is nothing to
//! name, so every loading function here is a no-op there and the caller writes
//! one branch rather than two programs.
//!
//! In a runtime-loading build nothing is linked, so a provider has to be named
//! explicitly before the first call. Two spellings are accepted, in this order:
//!
//!   * `--provider <path>` on the command line, which is what an interactive
//!     run uses and what a build's run step passes;
//!   * `RANDOM123_TEST_PROVIDER` in the environment, which is what a Zig test
//!     binary gets, because a test binary takes no arguments of its own.
//!
//! Neither has a default and neither falls back to the other. A build that was
//! told nothing is told so and stops, because reaching for a library in a
//! directory this package invented is exactly the "quietly load something else"
//! outcome the loader contract forbids.
//!
//! ## `.path` must be absolute, and that is the loader's rule, not this file's
//!
//! Both spellings above reach `load(.{ .path = ... })`, and the loader requires
//! that path to be absolute: a relative one is `InvalidSource`
//! (`runtime/loader.zig:186-194`), because a relative path means whatever the
//! process's current working directory happens to be, and a provider is
//! something a caller reaches for deliberately. The same check rejects a NUL
//! byte anywhere in the request. `.system` is the mirror image: a bare basename
//! with no separator and no drive letter (`loader.zig:196-201`), because that is
//! what the platform loader searches for, and a path handed to it as a name
//! would be a different kind of request wearing the same spelling.
//!
//! So an absolute provider path is a requirement on whoever exports the
//! variable, not a normalization this package performs.
//!
//! What a provider *is* is this fork's own bridge library, built as a shared
//! object from `zig/bridge/random123_bridge.c`. Upstream Random123 installs no
//! binary at all -- every algorithm is `static __inline__` -- so there is no
//! system Random123 for a name to be discovered from, and a `.system` request
//! can only ever name a shared object built by this package. The ABI boundary
//! and what the load checks are in `runtime/library.zig`.

const std = @import("std");
const random123 = @import("random123");

/// The environment variable that names a provider for a program that takes no
/// command line of its own.
pub const provider_variable = "RANDOM123_TEST_PROVIDER";

/// This build is runtime-loaded and was not told which provider to load.
///
/// Separate from `random123.LoadError` on purpose: every member of that set is
/// something the loader checked about a request it *was* given, and this is the
/// absence of a request.
pub const NoProviderConfigured = error{NoProviderConfigured};

/// Everything `load` can decline, in this package's own programs.
///
/// The union rather than either set alone, because both are reachable: the
/// loader's own errors come from the request this forwards, and
/// `NoProviderConfigured` comes from there being no request to forward.
pub const LoadFailure = NoProviderConfigured || random123.LoadError;

/// Load the provider named by `value`, or stop if there is none.
///
/// `value` is what the caller resolved: the argument after `--provider`, the
/// environment variable, or null. In a linked build the body is skipped, so a
/// caller's branch costs nothing and this cannot fail there.
pub fn load(value: ?[]const u8) LoadFailure!void {
    if (comptime !random123.runtime_loaded) return;
    return random123.load(.{ .path = value orelse return notConfigured("random123") });
}

/// The path that follows `--provider` in `argv`, or null when it names none.
///
/// A flag with nothing after it counts as "not named" rather than as an empty
/// path: `EmptySource` is the loader's answer to a request that reached it, and
/// reaching it through a bare flag would replace a message about the command
/// line with one about the loader.
pub fn fromArgs(argv: []const [:0]const u8) ?[]const u8 {
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (!std.mem.eql(u8, argv[index], "--provider")) continue;
        if (index + 1 >= argv.len) return null;
        return argv[index + 1];
    }
    return null;
}

/// `RANDOM123_TEST_PROVIDER` from an `Init`'s environment map, or null.
///
/// `Init` builds the map from the process environment before `main` runs, so
/// this borrows the value and the slice is valid for as long as that map is.
pub fn fromMap(environ: *const std.process.Environ.Map) ?[]const u8 {
    return environ.get(provider_variable);
}

/// `RANDOM123_TEST_PROVIDER` from a raw environment block, or null.
///
/// A Zig test binary has no `Init` and no environment map, but
/// `std.testing.environ` is the block itself. This allocates a copy through
/// `gpa` because a raw block's bytes belong to the operating system and cannot
/// be borrowed past the process's own copy of them; the caller frees the result.
///
/// A set-but-empty variable answers null, because an empty path is what the
/// loader's own `EmptySource` check is for and this is not where that answer
/// belongs.
pub fn fromBlock(gpa: std.mem.Allocator, environ: std.process.Environ) ?[]u8 {
    const value = environ.getAlloc(gpa, provider_variable) catch return null;
    if (value.len == 0) {
        gpa.free(value);
        return null;
    }
    return value;
}

/// Say that this build needs a provider and was not given one.
///
/// An error name on its own would send the next person into the loader instead
/// of to the command line, so the two ways of naming a provider are printed
/// along with what this build has to export.
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
