//! Behavioural tests for the Random123 facade and unit-interval conversions.
//! Runtime-loading tests require the explicitly named provider.

const std = @import("std");
const random123 = @import("random123");
const provider = @import("provider.zig");

/// Loads the provider before a test.
/// Called per test because file-scope loads precede the runner; repeats are idempotent.
fn loadProvider() !void {
    if (comptime !random123.runtime_loaded) return;
    const named = provider.fromBlock(std.testing.allocator, std.testing.environ);
    defer if (named) |value| std.testing.allocator.free(value);
    return provider.load(named);
}

fn sampleKey(comptime T: type) T {
    var k = std.mem.zeroes(T);
    for (&k, 0..) |*word, i| {
        word.* = @truncate(0x9e3779b97f4a7c15 +% (@as(u64, i) *% 0x00000100000001b3));
    }
    return k;
}

fn sampleCounter(comptime T: type) T {
    var ctr = std.mem.zeroes(T);
    for (&ctr, 0..) |*word, i| {
        word.* = @truncate(0x243f6a8885a308d3 +% (@as(u64, i) *% 0x00000100000001b3));
    }
    return ctr;
}

/// Increments a little-endian counter with carry.
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

/// Returns another generator type for interleaving tests.
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

        // Interleave a different generator before repeating G to expose hidden state.
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
        // Start near word 0's maximum to force one carry into word 1.
        ctr[0] = std.math.maxInt(@TypeOf(ctr[0])) - (n / 2);

        var results: [n]G.counter = undefined;
        for (&results) |*slot| {
            slot.* = G.generate(ctr, key);
            incr(G.counter, &ctr);
        }

        try std.testing.expectEqual(@as(@TypeOf(ctr[0]), @truncate(n / 2 - 1)), ctr[0]);
        try std.testing.expectEqual(@as(@TypeOf(ctr[1]), 1), ctr[1]);

        for (results, 0..) |a, i| {
            for (results[i + 1 ..], i + 1..) |b, j| {
                // Compare arrays element-wise; Zig does not provide array `==`.
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

        // Flip one counter bit and one key bit independently; each must affect the result.
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
    // At R=0, Philox returns the counter; Threefry adds the key before its loop.
    // Check both because the families have different upstream semantics.
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
    // Upstream ignores the high bit in these two closed-closed conversions.
    try std.testing.expectEqual(
        random123.UnitInterval.closedClosed32Float(0x12345678),
        random123.UnitInterval.closedClosed32Float(0x92345678),
    );
    try std.testing.expectEqual(
        random123.UnitInterval.closedClosed64Double(0x123456789abcdef0),
        random123.UnitInterval.closedClosed64Double(0x923456789abcdef0),
    );
    // The other conversions use the high bit; check one per input width.
    const a32 = random123.UnitInterval.closedOpen32Float(0x12345678);
    try std.testing.expect(a32 != random123.UnitInterval.closedOpen32Float(0x92345678));
    const a64 = random123.UnitInterval.closedOpen64Double(0x123456789abcdef0);
    try std.testing.expect(a64 != random123.UnitInterval.closedOpen64Double(0x923456789abcdef0));
}

// Exact rational grids and powers of two provide exact expected floats.
// This checks each conversion against its mathematical interval grid, not itself.

test "unit-interval conversions hit exact uniform-grid values" {
    try loadProvider();
    // closed_open_32_float uses the top 24 bits for a 2^-24 grid on [0, 1).
    try std.testing.expectEqual(@as(f32, 0.0), random123.UnitInterval.closedOpen32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 0x1p-8), random123.UnitInterval.closedOpen32Float(0x01000000));
    try std.testing.expectEqual(
        @as(f32, 16777215.0) / @as(f32, 16777216.0),
        random123.UnitInterval.closedOpen32Float(0xffffffff),
    );

    // open_open_32_float shifts the same grid by half a step.
    try std.testing.expectEqual(@as(f32, 0x1p-24), random123.UnitInterval.openOpen32Float(0x00000000));
    try std.testing.expectEqual(
        // An interior odd multiple distinguishes the half-step offset from endpoint-only checks.
        @as(f32, 131073.0) / @as(f32, 16777216.0),
        random123.UnitInterval.openOpen32Float(0x02000000),
    );
    try std.testing.expectEqual(
        @as(f32, 16777215.0) / @as(f32, 16777216.0),
        random123.UnitInterval.openOpen32Float(0xffffffff),
    );

    // closed_closed_32_float rounds to 25 significant bits on [0, 1].
    try std.testing.expectEqual(@as(f32, 0.0), random123.UnitInterval.closedClosed32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 1.0), random123.UnitInterval.closedClosed32Float(0xffffffff));

    // open_closed_32_float shifts the half-open grid up by one step.
    try std.testing.expectEqual(@as(f32, 0x1p-24), random123.UnitInterval.openClosed32Float(0x00000000));
    try std.testing.expectEqual(@as(f32, 1.0), random123.UnitInterval.openClosed32Float(0xffffffff));

    // closed_open_32_double uses a 2^-32 grid on [0, 1).
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedOpen32Double(0x00000000));
    try std.testing.expectEqual(
        @as(f64, 4294967295.0) / @as(f64, 4294967296.0),
        random123.UnitInterval.closedOpen32Double(0xffffffff),
    );

    // open_open_32_double shifts the same grid by half a step.
    try std.testing.expectEqual(@as(f64, 0x1p-33), random123.UnitInterval.openOpen32Double(0x00000000));
    try std.testing.expectEqual(
        // An odd multiple of 2^-33 distinguishes the half-step offset.
        @as(f64, 16777217.0) / @as(f64, 8589934592.0),
        random123.UnitInterval.openOpen32Double(0x00800000),
    );
    try std.testing.expectEqual(
        // At max input, the half-step grid ends at 8589934591 / 2^33.
        @as(f64, 8589934591.0) / @as(f64, 8589934592.0),
        random123.UnitInterval.openOpen32Double(0xffffffff),
    );

    // Rounding reaches 1 only for odd 32-bit words.
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedClosed32Double(0x00000000));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.closedClosed32Double(0xffffffff));
    try std.testing.expectEqual(
        @as(f64, 4294967294.0) / @as(f64, 4294967296.0),
        random123.UnitInterval.closedClosed32Double(0xfffffffe),
    );

    // open_closed_32_double shifts the half-open grid up by one step.
    try std.testing.expectEqual(@as(f64, 0x1p-32), random123.UnitInterval.openClosed32Double(0x00000000));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.openClosed32Double(0xffffffff));

    // closed_open_64_double uses a 2^-53 grid on [0, 1).
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedOpen64Double(0));
    try std.testing.expectEqual(
        @as(f64, 9007199254740991.0) / @as(f64, 9007199254740992.0),
        random123.UnitInterval.closedOpen64Double(std.math.maxInt(u64)),
    );

    // open_open_64_double shifts the same grid by half a step.
    try std.testing.expectEqual(@as(f64, 0x1p-53), random123.UnitInterval.openOpen64Double(0));
    try std.testing.expectEqual(
        @as(f64, 9007199254740991.0) / @as(f64, 9007199254740992.0),
        random123.UnitInterval.openOpen64Double(std.math.maxInt(u64)),
    );

    // closed_closed_64_double rounds to 54 significant bits on [0, 1].
    try std.testing.expectEqual(@as(f64, 0.0), random123.UnitInterval.closedClosed64Double(0));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.closedClosed64Double(std.math.maxInt(u64)));

    // open_closed_64_double shifts the half-open grid up by one step.
    try std.testing.expectEqual(@as(f64, 0x1p-53), random123.UnitInterval.openClosed64Double(0));
    try std.testing.expectEqual(@as(f64, 1.0), random123.UnitInterval.openClosed64Double(std.math.maxInt(u64)));
}
