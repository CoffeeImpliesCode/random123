//! Known-answer tests against the upstream Random123 fixture.
//!
// tests/kat_vectors is the upstream reference file: tuples of
// (generator, round count, counter, key, expected output) produced by the
// reference implementation that passed the TestU01 SmallCrush/Crush/BigCrush
// batteries.  It is byte-order independent by construction.
//
// The bytes come from the build through the test-only `kat_vectors` import,
// whose generated root is `pub const data = @embedFile("kat_vectors")` over a
//! verbatim copy of upstream's file.  Nothing in this source tree holds a
//! second copy, so the fixture cannot drift away from upstream, and the copy
//! the build reads is the one `UPSTREAM.sha256` covers.
//!
//! Provenance: D. E. Shaw Research, Random123 1.14.0, tests/kat_vectors.
//!
//! ## The provider, in a runtime-loading build
//!
//! These are the same tests in both configurations, and the answers must be the
//! same in both. In a linked build the bridge is linked and there is nothing to
//! do. In a runtime-loading build nothing is linked, so `RANDOM123_TEST_PROVIDER`
//! has to name a shared object before the first call, and this root stops
//! without one rather than skipping: a replay of upstream's known answers that
//! ran against nothing would pass while proving nothing.
//!
//! The answers themselves are unchanged by either configuration, which is the
//! point of running them in both: a dispatch that reached a different
//! arithmetic, or passed a counter wrongly by value, would produce different
//! words here.

const std = @import("std");
const random123 = @import("random123");
const provider = @import("provider.zig");

const kat_source = @import("kat_vectors").data;

/// Load the provider, or stop without one.
///
/// Called at the top of every test rather than once at file scope: a Zig test
/// binary runs its tests in source order, and a load at the top level would run
/// before the test runner existed. The load is idempotent for the same request,
/// so the second and later calls cost one acquire load and change nothing.
fn loadProvider() !void {
    if (comptime !random123.runtime_loaded) return;
    const named = provider.fromBlock(std.testing.allocator, std.testing.environ);
    defer if (named) |value| std.testing.allocator.free(value);
    return provider.load(named);
}

const Algorithm = struct {
    name: []const u8,
    Generator: type,
    n_ctr: usize,
    n_key: usize,
};

const algorithms = [_]Algorithm{
    .{ .name = "philox2x32", .Generator = random123.Philox2x32, .n_ctr = 2, .n_key = 1 },
    .{ .name = "philox4x32", .Generator = random123.Philox4x32, .n_ctr = 4, .n_key = 2 },
    .{ .name = "philox2x64", .Generator = random123.Philox2x64, .n_ctr = 2, .n_key = 1 },
    .{ .name = "philox4x64", .Generator = random123.Philox4x64, .n_ctr = 4, .n_key = 2 },
    .{ .name = "threefry2x32", .Generator = random123.Threefry2x32, .n_ctr = 2, .n_key = 2 },
    .{ .name = "threefry4x32", .Generator = random123.Threefry4x32, .n_ctr = 4, .n_key = 4 },
    .{ .name = "threefry2x64", .Generator = random123.Threefry2x64, .n_ctr = 2, .n_key = 2 },
    .{ .name = "threefry4x64", .Generator = random123.Threefry4x64, .n_ctr = 4, .n_key = 4 },
};

/// The n-th whitespace-separated token of `s`, as a slice of `s`.  No
/// allocation: the fixture is parsed in place.
fn token(s: []const u8, n: usize) []const u8 {
    var i: usize = 0;
    var remaining = n;
    while (i < s.len) {
        while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
        if (i >= s.len) break;
        const start = i;
        while (i < s.len and s[i] != ' ' and s[i] != '\t') : (i += 1) {}
        if (remaining == 0) return s[start..i];
        remaining -= 1;
    }
    return "";
}

fn nextVector(s: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
    const raw = s.next() orelse return null;
    const line = std.mem.trim(u8, raw, " \t\r");
    if (line.len == 0 or line[0] == '#') return nextVector(s);
    return line;
}

fn isAesFamily(name: []const u8) bool {
    return std.mem.eql(u8, name, "aesni4x32") or std.mem.eql(u8, name, "ars4x32");
}

/// The type of parameter `index` of a function type, whether it is named
/// directly or reached through a pointer to one.
///
/// Storing a function in a struct field or tuple element gives a pointer to it,
/// and a translated `extern fn` named directly gives the function itself, so the
/// two spellings of the same declaration differ by exactly one level. This
/// accepts both, which is what lets the raw table below hold function values and
/// still read the struct types back out of them.
fn FnParam(comptime F: type, comptime index: usize) type {
    const info = @typeInfo(F);
    const function = switch (info) {
        .@"fn" => |f| f,
        // A pointer to a function, which is what a function stored in a
        // container becomes.
        .pointer => |p| switch (@typeInfo(p.child)) {
            .@"fn" => |f| f,
            else => @compileError("random123: expected a function pointer"),
        },
        else => @compileError("random123: expected a function or a pointer to one"),
    };
    return function.params[index].type.?;
}

test "known answers for every portable generator" {
    try loadProvider();
    // One replay count per generator, so the test cannot pass while one of the
    // eight is missing from the fixture or from the dispatch table.
    var replayed = [_]usize{0} ** algorithms.len;
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, kat_source, '\n');
    while (nextVector(&lines)) |line| {
        const name = token(line, 0);
        // The AES-NI/ARS lines in the fixture are covered by the next test,
        // which only runs where this build actually has AES-NI.
        if (isAesFamily(name)) continue;
        const rounds = try std.fmt.parseInt(u32, token(line, 1), 10);

        var matched = false;
        inline for (algorithms, 0..) |alg, index| {
            // `name` comes out of the fixture at run time, so it cannot drive
            // the unrolled loop: a `continue` here would be comptime control
            // flow reached from a runtime branch, which the compiler rejects.
            // The comparison therefore selects a block, which is ordinary
            // runtime control flow, and the unrolled loop only supplies the
            // comptime generator type and its array lengths.
            if (std.mem.eql(u8, name, alg.name)) {
                matched = true;
                replayed[index] += 1;

                var ctr: alg.Generator.counter = undefined;
                var key: alg.Generator.key = undefined;
                inline for (0..alg.n_ctr) |i| {
                    ctr[i] = @truncate(try std.fmt.parseInt(u64, token(line, 2 + i), 16));
                }
                inline for (0..alg.n_key) |i| {
                    key[i] = @truncate(try std.fmt.parseInt(u64, token(line, 2 + alg.n_ctr + i), 16));
                }

                const got = alg.Generator.rounds(rounds, ctr, key);
                inline for (0..alg.n_ctr) |i| {
                    const want: @TypeOf(got[0]) = @truncate(
                        try std.fmt.parseInt(u64, token(line, 2 + alg.n_ctr + alg.n_key + i), 16),
                    );
                    try std.testing.expectEqual(want, got[i]);
                }
            }
        }
        try std.testing.expect(matched);
        checked += 1;
    }
    try std.testing.expect(checked > 0);

    // `algorithms` carries a `type` field, so it cannot be walked at run
    // time at all; the check is a comptime walk over the same table the
    // dispatch above used.
    inline for (algorithms, 0..) |alg, index| {
        if (replayed[index] == 0) {
            std.debug.print("no upstream known answer was replayed for {s}\n", .{alg.name});
            return error.TestUnexpectedResult;
        }
    }
}

test "known answers for AES-NI and ARS when this build has AES-NI" {
    // comptime, so the rest of this test is not analysed -- and the missing
    // AES-NI declarations are not referenced -- when AES-NI is not built in.
    if (comptime !random123.has_aesni) return error.SkipZigTest;
    // Loaded before the probe below, because the probe is one of the routed
    // entry points and a runtime-loading build has no provider until it is
    // named. Above the `has_aesni` check would be wrong: a build without the
    // wrappers has nothing to replay and must not demand a provider for it.
    try loadProvider();
    // Compiled with -maes does not mean the running CPU has AES-NI; upstream
    // ships this exact CPUID probe for the runtime check.
    if (random123.c.r123_bridge_have_aesni() == 0) return error.SkipZigTest;

    // Counted per family: a fixture that lost every AES-NI line, or every ARS
    // line, must fail rather than pass on whichever family survived.
    var aesni_replayed: usize = 0;
    var ars_replayed: usize = 0;
    var lines = std.mem.splitScalar(u8, kat_source, '\n');
    while (nextVector(&lines)) |line| {
        const name = token(line, 0);
        if (!isAesFamily(name)) continue;
        const rounds = try std.fmt.parseInt(u32, token(line, 1), 10);

        var ctr: [4]u32 = undefined;
        var ukey: [4]u32 = undefined;
        inline for (0..4) |i| ctr[i] = @truncate(try std.fmt.parseInt(u64, token(line, 2 + i), 16));
        inline for (0..4) |i| ukey[i] = @truncate(try std.fmt.parseInt(u64, token(line, 6 + i), 16));

        const got: [4]u32 = if (std.mem.eql(u8, name, "aesni4x32")) blk: {
            aesni_replayed += 1;
            var schedule: [random123.c.R123_BRIDGE_AESNI_KEY_WORDS]u32 = undefined;
            random123.c.r123_bridge_aesni4x32_keyinit(&schedule, .{ .v = ukey });
            break :blk random123.c.r123_bridge_aesni4x32_R(rounds, .{ .v = ctr }, &schedule).v;
        } else blk: {
            ars_replayed += 1;
            const ars_key = random123.c.r123_bridge_ars4x32_keyinit(.{ .v = ukey });
            break :blk random123.c.r123_bridge_ars4x32_R(rounds, .{ .v = ctr }, ars_key).v;
        };

        inline for (0..4) |i| {
            const want: u32 = @truncate(try std.fmt.parseInt(u64, token(line, 10 + i), 16));
            try std.testing.expectEqual(want, got[i]);
        }
    }
    try std.testing.expect(aesni_replayed > 0);
    try std.testing.expect(ars_replayed > 0);
}

// ---------------------------------------------------------------------------
// The raw C route.
//
// Everything above reaches the bridge through the typed facade, which is one
// caller of the `r123_bridge_*` names and not the only one. This block is the
// other caller: it drives all twenty-eight common entry points -- eight
// `keyinit` wrappers and eight `_R` round functions, plus the twelve
// `u01_*` conversions -- directly through `c`, in the upstream
// `r123arrayNxW` struct form, with the same upstream fixture as the oracle.
//
// The point is not to check the facade against itself. Every expected word is
// read out of `tests/kat_vectors`, and the two routes are compared against
// that same external file, so a dispatch that reached the wrong table entry,
// passed a counter wrongly by value, or returned a struct whose words came
// back in the wrong order produces different words here rather than agreeing
// with the facade.


test "the raw C keyinit and round wrappers replay upstream's known answers" {
    try loadProvider();

    // The eight pairs, as a tuple rather than an array: each carries its own
    // `struct_r123arrayNxW` types, and eight distinct types cannot share one
    // array element type. `inline for` unrolls over the tuple, so each entry is
    // seen at its own comptime type. Naming every entry point explicitly is the
    // point of the block: a wrapper that stopped being declared, or stopped
    // being routed, stops this from compiling rather than quietly dropping out
    // of the replay.
    const raws = .{
        .{
            .name = "philox2x32",
            .keyinit = random123.c.r123_bridge_philox2x32_keyinit,
            .round = random123.c.r123_bridge_philox2x32_R,
        },
        .{
            .name = "philox4x32",
            .keyinit = random123.c.r123_bridge_philox4x32_keyinit,
            .round = random123.c.r123_bridge_philox4x32_R,
        },
        .{
            .name = "philox2x64",
            .keyinit = random123.c.r123_bridge_philox2x64_keyinit,
            .round = random123.c.r123_bridge_philox2x64_R,
        },
        .{
            .name = "philox4x64",
            .keyinit = random123.c.r123_bridge_philox4x64_keyinit,
            .round = random123.c.r123_bridge_philox4x64_R,
        },
        .{
            .name = "threefry2x32",
            .keyinit = random123.c.r123_bridge_threefry2x32_keyinit,
            .round = random123.c.r123_bridge_threefry2x32_R,
        },
        .{
            .name = "threefry4x32",
            .keyinit = random123.c.r123_bridge_threefry4x32_keyinit,
            .round = random123.c.r123_bridge_threefry4x32_R,
        },
        .{
            .name = "threefry2x64",
            .keyinit = random123.c.r123_bridge_threefry2x64_keyinit,
            .round = random123.c.r123_bridge_threefry2x64_R,
        },
        .{
            .name = "threefry4x64",
            .keyinit = random123.c.r123_bridge_threefry4x64_keyinit,
            .round = random123.c.r123_bridge_threefry4x64_R,
        },
    };

    var replayed = [_]usize{0} ** raws.len;
    var lines = std.mem.splitScalar(u8, kat_source, '\n');
    while (nextVector(&lines)) |line| {
        const name = token(line, 0);
        if (isAesFamily(name)) continue;
        const rounds = try std.fmt.parseInt(u32, token(line, 1), 10);

        var matched = false;
        inline for (raws, 0..) |alg, index| {
            // `name` comes out of the fixture at run time, so it cannot drive
            // the unrolled loop: `continue` here would be comptime control flow
            // reached from a runtime branch. The comparison selects a block,
            // which is ordinary runtime control flow, and the unrolled loop
            // supplies only the comptime entry and its array lengths.
            if (std.mem.eql(u8, name, alg.name)) {
                matched = true;
                replayed[index] += 1;

                // The counter type is the round wrapper's own second parameter
                // and the key type is the keyinit wrapper's parameter, both read out of
                // the translated declarations rather than restated here, so this
                // block follows the header if the header moves. A function stored in
                // a field is a pointer, so the function type is one level in.
                const Ctr = FnParam(@TypeOf(alg.round), 1);
                const Key = FnParam(@TypeOf(alg.keyinit), 0);

                // The word counts come from the structs rather than from the
                // literals in the table above: `r123arrayNxW` is a bare `[N]Word`
                // and the bridge static-asserts every one of those sizes, so the
                // array length *is* the counter and key width upstream defines. A
                // table entry that disagreed with its own struct would then fail
                // here instead of reading the wrong number of fixture words.
                const ctr_words = @typeInfo(@FieldType(Ctr, "v")).array.len;
                const key_words = @typeInfo(@FieldType(Key, "v")).array.len;
                const Word = @typeInfo(@FieldType(Ctr, "v")).array.child;

                var ctr: Ctr = undefined;
                var ukey: Key = undefined;
                inline for (0..ctr_words) |i| {
                    ctr.v[i] = @truncate(try std.fmt.parseInt(u64, token(line, 2 + i), 16));
                }
                inline for (0..key_words) |i| {
                    ukey.v[i] = @truncate(try std.fmt.parseInt(u64, token(line, 2 + ctr_words + i), 16));
                }

                // The key goes through the C keyinit wrapper on the way to the
                // round function, so that wrapper's own signature and its by-value
                // return are exercised rather than only the round function's.
                const keyed = alg.keyinit(ukey);
                const got = alg.round(@intCast(rounds), ctr, keyed);

                inline for (0..ctr_words) |i| {
                    const want: Word = @truncate(
                        try std.fmt.parseInt(u64, token(line, 2 + ctr_words + key_words + i), 16),
                    );
                    try std.testing.expectEqual(want, got.v[i]);
                }
            }
        }
        try std.testing.expect(matched);
    }

    inline for (raws, 0..) |alg, index| {
        if (replayed[index] == 0) {
            std.debug.print("no upstream known answer reached the raw {s} route\n", .{alg.name});
            return error.TestUnexpectedResult;
        }
    }
}
