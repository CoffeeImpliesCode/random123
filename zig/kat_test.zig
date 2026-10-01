//! Known-answer tests against the upstream Random123 fixture.
//!
// tests/kat_vectors is the upstream reference file: tuples of
// (generator, round count, counter, key, expected output) produced by the
// reference implementation that passed the TestU01 SmallCrush/Crush/BigCrush
// batteries.  It is byte-order independent by construction.
//
// The bytes come from the build through the test-only `kat_vectors` import,
// whose generated root is `pub const data = @embedFile("kat_vectors")` over a
// verbatim copy of upstream's file.  Nothing in this source tree holds a
// second copy, so the fixture cannot drift away from upstream, and the copy
// the build reads is the one `UPSTREAM.sha256` covers.
//
// Provenance: D. E. Shaw Research, Random123 1.14.0, tests/kat_vectors.

const std = @import("std");
const random123 = @import("random123");

const kat_source = @import("kat_vectors").data;

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

test "known answers for every portable generator" {
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
