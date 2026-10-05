//! Behavioural tests for the Random123 Zig facade.
//!
//! The known-answer fixtures live in zig/kat_test.zig.  These tests cover the
//! properties a consumer actually relies on: that the generator is a pure
//! function of counter and key, that a counter stream does not collide, that
//! boundary counters and keys are handled, and that the round count is a real
//! behavioural knob.  They also pin the integer-to-floating-point conversions
//! to exact IEEE 754 values derived from the definition of a uniform grid, not
//! from the C source.
//!
//! ## The provider, in a runtime-loading build
//!
//! These are the same tests in both configurations and they must reach the same
//! behaviour. In a runtime-loading build nothing is linked, so
//! `RANDOM123_TEST_PROVIDER` has to name a shared object before the first call
//! and this root stops without one rather than skipping. A purity property that
//! was checked against nothing, or a grid that was checked against the wrong
//! conversion, is not a weaker result; it is no result at all.

const std = @import("std");
const random123 = @import("random123");
const provider = @import("provider.zig");

/// Load the provider, or stop without one.
///
/// Called at the top of each test rather than once at file scope, because a Zig
/// test binary runs its tests from a runner and a load at the top level would
/// happen before that runner exists. The load is idempotent for the same
/// request, so the second and later calls change nothing.
fn loadProvider() !void {
    if (comptime !random123.runtime_loaded) return;
    const named = provider.fromBlock(std.testing.allocator, std.testing.environ);
    defer if (named) |value| std.testing.allocator.free(value);
    return provider.load(named);
}

/// A deterministic, non-degenerate key for any generator shape.
fn sampleKey(comptime T: type) T {
    var k = std.mem.zeroes(T);
    for (&k, 0..) |*word, i| {
        word.* = @truncate(0x9e3779b97f4a7c15 +% (@as(u64, i) *% 0x00000100000001b3));
    }
    return k;
}

/// A deterministic, non-degenerate counter for any generator shape.
fn sampleCounter(comptime T: type) T {
    var ctr = std.mem.zeroes(T);
    for (&ctr, 0..) |*word, i| {
        word.* = @truncate(0x243f6a8885a308d3 +% (@as(u64, i) *% 0x00000100000001b3));
    }
    return ctr;
}

/// Little-endian counter increment with carry, matching the counter ordering
/// upstream uses when walking a CBRNG stream.
fn incr(comptime T: type, ctr: *T) void {
    for (ctr) |*word| {
        word.* +%= 1;
        if (word.* != 0) break;
    }
}

fn flipped(comptime T: type, v: T) T {
    var out = v;
    out[0] ^= @as(@TypeOf(out[0]), 1);
    return out;
}

/// The first generator in `random123.generators` that is not `G`.  The
/// purity test needs a *different* generator to interleave, and this finds one
/// by walking the public container instead of indexing it.
fn otherThan(comptime G: type) type {
    inline for (random123.generators) |Candidate| {
        if (Candidate != G) return Candidate;
    }
    unreachable;
}

test "a generator is a pure function of counter and key" {
    try loadProvider();
    inline for (random123.generators) |G| {
        const ctr = sampleCounter(G.counter);
        const key = sampleKey(G.key);
        const first = G.generate(ctr, key);

        // Interleave unrelated work, including a different generator, then
        // repeat the original call.  Any hidden state would show up here.
        const other = otherThan(G);
        _ = other.generate(sampleCounter(other.counter), sampleKey(other.key));
        _ = G.generate(sampleCounter(G.counter), key);
        _ = random123.UnitInterval.closedOpen32Float(@truncate(@as(u64, ctr[0])));

        try std.testing.expectEqual(first, G.generate(ctr, key));
        try std.testing.expectEqual(first, G.rounds(G.default_rounds, ctr, key));
    }
}

test "a counter stream with a carry produces pairwise distinct outputs" {
    try loadProvider();
    const n = 128;
    inline for (random123.generators) |G| {
        const key = sampleKey(G.key);
        var ctr: G.counter = std.mem.zeroes(G.counter);
        // Start close enough to the top of word 0 that the stream must carry
        // into word 1 half way through.
        ctr[0] = std.math.maxInt(@TypeOf(ctr[0])) - (n / 2);

        var results: [n]G.counter = undefined;
        for (&results) |*slot| {
            slot.* = G.generate(ctr, key);
            incr(G.counter, &ctr);
        }

        // Exactly one carry happened, and it landed in word 1.
        try std.testing.expectEqual(@as(@TypeOf(ctr[0]), @truncate(n / 2 - 1)), ctr[0]);
        try std.testing.expectEqual(@as(@TypeOf(ctr[1]), 1), ctr[1]);

        for (results, 0..) |a, i| {
            for (results[i + 1 ..], i + 1..) |b, j| {
                // `==` is not an operation Zig 0.16 offers on an array, so
                // the word-wise comparison this test means goes through
                // `std.meta.eql`, which compares containers element by element
                // (lib/std/meta.zig:650-655).
                if (std.meta.eql(a, b)) {
                    std.debug.print("{s}: counters {d} and {d} collided\n", .{ G.name, i, j });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
}

test "boundary counters and keys stay distinct" {
    try loadProvider();
    inline for (random123.generators) |G| {
        const key = sampleKey(G.key);
        const base = sampleCounter(G.counter);

        const zeros_ctr: G.counter = std.mem.zeroes(G.counter);
        var ones_ctr: G.counter = std.mem.zeroes(G.counter);
        for (&ones_ctr) |*word| word.* = std.math.maxInt(@TypeOf(word.*));

        const zeros_out = G.generate(zeros_ctr, key);
        const ones_out = G.generate(ones_ctr, key);
        try std.testing.expect(!std.meta.eql(zeros_out, ones_out));

        // A single counter bit and a single key bit must each change the result.
        const base_out = G.generate(base, key);
        const ctr_flipped = G.generate(flipped(G.counter, base), key);
        const key_flipped = G.generate(base, flipped(G.key, key));
        try std.testing.expect(!std.meta.eql(ctr_flipped, base_out));
        try std.testing.expect(!std.meta.eql(key_flipped, base_out));
    }
}

test "round count is a behavioural knob" {
    try loadProvider();
    inline for (random123.generators) |G| {
        const ctr = sampleCounter(G.counter);
        const key = sampleKey(G.key);

        const one = G.rounds(1, ctr, key);
        const two = G.rounds(2, ctr, key);
        const most = G.rounds(G.max_rounds, ctr, key);
        try std.testing.expect(!std.meta.eql(one, two));
        try std.testing.expect(!std.meta.eql(two, most));
    }
}

test "zero rounds is legal, and each family does its own documented thing" {
    try loadProvider();
    // Upstream asserts only an upper bound, so R = 0 reaches the algorithm.
    // Philox guards every round with `if(R > n)`
    // (philox.h:325-341), so nothing runs and the counter comes back
    // unchanged.  Threefry adds the key before that guard
    // (threefry.h:207-213, threefry.h:311-325), so its zero-round result is
    // the counter plus the key word by word.  Both are checked here because
    // "zero rounds returns the input" is the assumption a caller is most
    // likely to carry over from one family to the other, and it is wrong for
    // four of the eight generators.
    inline for (.{ random123.Philox2x32, random123.Philox4x32, random123.Philox2x64, random123.Philox4x64 }) |G| {
        const ctr = sampleCounter(G.counter);
        try std.testing.expectEqual(ctr, G.rounds(0, ctr, sampleKey(G.key)));
    }
    inline for (.{ random123.Threefry2x32, random123.Threefry4x32, random123.Threefry2x64, random123.Threefry4x64 }) |G| {
        const ctr = sampleCounter(G.counter);
        const key = sampleKey(G.key);
        var want = ctr;
        for (&want, key) |*word, k| word.* +%= k;
        try std.testing.expectEqual(want, G.rounds(0, ctr, key));
    }
}

test "a closed-closed conversion ignores the input's high bit, as upstream says" {
    try loadProvider();
    // `u01fixedpt.h:137` and `u01fixedpt.h:156` note the ignored high bit for
    // exactly these two, so their result is not monotonic in the input -- a
    // fact a caller sorting or bucketing by converted value would otherwise
    // learn the hard way.
    try std.testing.expectEqual(
        random123.UnitInterval.closedClosed32Float(0x12345678),
        random123.UnitInterval.closedClosed32Float(0x92345678),
    );
    try std.testing.expectEqual(
        random123.UnitInterval.closedClosed64Double(0x123456789abcdef0),
        random123.UnitInterval.closedClosed64Double(0x923456789abcdef0),
    );
    // The other ten conversions do read the high bit, so flipping it moves the
    // result.  One per input width is checked here, so the pair above is a
    // real asymmetry and not an artefact of the comparison.
    const a32 = random123.UnitInterval.closedOpen32Float(0x12345678);
    try std.testing.expect(a32 != random123.UnitInterval.closedOpen32Float(0x92345678));
    const a64 = random123.UnitInterval.closedOpen64Double(0x123456789abcdef0);
    try std.testing.expect(a64 != random123.UnitInterval.closedOpen64Double(0x923456789abcdef0));
}

// ---------------------------------------------------------------------------
// The `random123.UnitInterval` conversions, aliased from upstream u01fixedpt.h.
//
// Expected values are stated as exact ratios or powers of two, i.e. as the
// definition of the uniform grid each conversion claims to produce.  Every one
// of them is exactly representable in its target type, so the comparison is
// exact and cannot be satisfied by any mis-scaled implementation.

test "unit-interval conversions hit exact uniform-grid values" {
    try loadProvider();
    // closed_open_32_float: the top 24 bits index 2^-24-spaced points on [0, 1).
    try std.testing.expectEqual(@as(f32, 0.0), random123.UnitInterval.closedOpen32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 0x1p-8), random123.UnitInterval.closedOpen32Float(0x01000000));
    try std.testing.expectEqual(
        @as(f32, 16777215.0) / @as(f32, 16777216.0),
        random123.UnitInterval.closedOpen32Float(0xffffffff),
    );

    // open_open_32_float: the same grid, shifted up by half a step.
    try std.testing.expectEqual(@as(f32, 0x1p-24), random123.UnitInterval.openOpen32Float(0x00000000));
    try std.testing.expectEqual(
        // (0.5 + (i>>9)) * 2^-23 at i = 0x02000000: an odd multiple of 2^-24,
        // which pins the half-step offset rather than only the endpoints.
        @as(f32, 131073.0) / @as(f32, 16777216.0),
        random123.UnitInterval.openOpen32Float(0x02000000),
    );
    try std.testing.expectEqual(
        @as(f32, 16777215.0) / @as(f32, 16777216.0),
        random123.UnitInterval.openOpen32Float(0xffffffff),
    );

    // closed_closed_32_float: rounds the word to 25 significant bits on [0, 1].
    try std.testing.expectEqual(@as(f32, 0.0), random123.UnitInterval.closedClosed32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 1.0), random123.UnitInterval.closedClosed32Float(0xffffffff));

    // open_closed_32_float: the half-open grid shifted up by one whole step.
    try std.testing.expectEqual(@as(f32, 0x1p-24), random123.UnitInterval.openClosed32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 1.0), random123.UnitInterval.openClosed32Float(0xffffffff));

    // closed_open_32_double: 2^-32-spaced points on [0, 1).
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedOpen32Double(0x00000000));
    try std.testing.expectEqual(
        @as(f64, 4294967295.0) / @as(f64, 4294967296.0),
        random123.UnitInterval.closedOpen32Double(0xffffffff),
    );

    // open_open_32_double: the same grid, shifted up by half a step.
    try std.testing.expectEqual(@as(f64, 0x1p-33), random123.UnitInterval.openOpen32Double(0x00000000));
    try std.testing.expectEqual(
        // (0.5 + i) * 2^-32 at i = 0x00800000: an odd multiple of 2^-33.
        @as(f64, 16777217.0) / @as(f64, 8589934592.0),
        random123.UnitInterval.openOpen32Double(0x00800000),
    );
    try std.testing.expectEqual(
        // (0.5 + 0xffffffff) * 2^-32 = 4294967295.5 / 2^32
        //                             = 8589934591 / 2^33.
        @as(f64, 8589934591.0) / @as(f64, 8589934592.0),
        random123.UnitInterval.openOpen32Double(0xffffffff),
    );

    // closed_closed_32_double: the even/odd trapezoid rounding reaches 1 only
    // for an odd word.
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedClosed32Double(0x00000000));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.closedClosed32Double(0xffffffff));
    try std.testing.expectEqual(
        @as(f64, 4294967294.0) / @as(f64, 4294967296.0),
        random123.UnitInterval.closedClosed32Double(0xfffffffe),
    );

    // open_closed_32_double: the half-open grid shifted up by one whole step.
    try std.testing.expectEqual(@as(f64, 0x1p-32), random123.UnitInterval.openClosed32Double(0x00000000));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.openClosed32Double(0xffffffff));

    // closed_open_64_double: 2^-53-spaced points on [0, 1).
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedOpen64Double(0));
    try std.testing.expectEqual(
        @as(f64, 9007199254740991.0) / @as(f64, 9007199254740992.0),
        random123.UnitInterval.closedOpen64Double(std.math.maxInt(u64)),
    );

    // open_open_64_double: the same grid, shifted up by half a step.
    try std.testing.expectEqual(@as(f64, 0x1p-53), random123.UnitInterval.openOpen64Double(0));
    try std.testing.expectEqual(
        @as(f64, 9007199254740991.0) / @as(f64, 9007199254740992.0),
        random123.UnitInterval.openOpen64Double(std.math.maxInt(u64)),
    );

    // closed_closed_64_double: rounds the word to 54 significant bits on [0, 1].
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedClosed64Double(0));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.closedClosed64Double(std.math.maxInt(u64)));

    // open_closed_64_double: the half-open grid shifted up by one whole step.
    try std.testing.expectEqual(@as(f64, 0x1p-53), random123.UnitInterval.openClosed64Double(0));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.openClosed64Double(std.math.maxInt(u64)));
}
