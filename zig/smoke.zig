//! Deterministic Random123 smoke example.
//!
//! Everything printed here is a pure function of the upstream algorithms, so
//! two runs on any conforming platform produce byte-identical output:
//!
//!   * the upstream known answers for an all-zero counter and key,
//!   * a Monte Carlo pi estimate from a Threefry2x32 counter stream, computed
//!     entirely in integer arithmetic so no floating-point contraction or
//!     rounding difference can perturb it,
//!   * an integer checksum over the same stream.
//!
//! Run with `zig build smoke`.

const std = @import("std");
const random123 = @import("random123");

/// Samples used for the Monte Carlo estimate.
const sample_count: u32 = 1 << 16;

/// Side length of the square the samples are drawn in, and radius of the
/// quarter disk.  Both are exact powers of two, so the integer test
/// `x*x + y*y <= r*r` is exact.
const grid: u32 = 1 << 16;

fn printWords(out: *std.Io.Writer, words: anytype) !void {
    for (words, 0..) |word, i| {
        if (i != 0) try out.writeAll(" ");
        if (@bitSizeOf(@TypeOf(word)) == 32) {
            try out.print("{x:0>8}", .{word});
        } else {
            try out.print("{x:0>16}", .{word});
        }
    }
}

fn zeroVector(out: *std.Io.Writer, comptime G: type) !void {
    const ctr: G.counter = std.mem.zeroes(G.counter);
    const key: G.key = std.mem.zeroes(G.key);
    try out.print("{s} rounds={d} zeros -> ", .{ G.name, G.default_rounds });
    try printWords(out, G.generate(ctr, key));
    try out.writeAll("\n");
}

/// One Threefry2x32 counter stream, walked from counter 0.  Returns the
/// quarter-disk hit count and accumulates a checksum over every generated word.
fn stream(hits: *u64, checksum: *u64) void {
    const key = random123.Threefry2x32.key{ 0x243f6a88, 0x85a308d3 };
    var ctr = random123.Threefry2x32.counter{ 0, 0 };

    var n: u32 = 0;
    while (n < sample_count) : (n += 1) {
        const block = random123.Threefry2x32.generate(ctr, key);
        for (block) |word| checksum.* +%= @as(u64, word);

        const x: u64 = block[0] & (grid - 1);
        const y: u64 = block[1] & (grid - 1);
        if (x * x + y * y <= @as(u64, grid) * grid) hits.* += 1;

        // Little-endian carry into the high counter word.
        ctr[0] +%= 1;
        if (ctr[0] == 0) ctr[1] +%= 1;
    }
}

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    try out.writeAll("random123 1.14.0 (D. E. Shaw Research), Zig package\n");
    try out.writeAll("statistical and Monte Carlo use only -- NOT cryptographic\n");
    try out.print("aesni bridge: {s}\n", .{
        if (random123.has_aesni) "compiled in" else "not built for this target",
    });

    inline for (random123.generators) |G| try zeroVector(out, G);

    var hits: u64 = 0;
    var checksum: u64 = 0;
    stream(&hits, &checksum);

    // pi ~= 4 * hits / sample_count, printed in millionths with integer maths.
    const millionths: u64 = (4 * hits * 1_000_000) / sample_count;
    try out.print(
        "threefry2x32 stream: samples={d} hits={d} pi={d}.{d:0>6}\n",
        .{ sample_count, hits, millionths / 1_000_000, millionths % 1_000_000 },
    );
    try out.print("threefry2x32 stream checksum: {x:0>16}\n", .{checksum});

    try out.flush();
}
