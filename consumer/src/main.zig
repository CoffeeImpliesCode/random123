//! Consumer of the Random123 Zig package.
//!
//! This is a separate package that reaches Random123 only through
//! `b.dependency("random123", …).module("random123")`.  It exercises the typed
//! facade against the upstream known answers from tests/kat_vectors (all-zero
//! counter and key) and the raw translated C escape hatch, then prints a
//! deterministic report.
//!
//! Run with `zig build run` from the consumer/ directory.

const std = @import("std");
const random123 = @import("random123");

fn expectWords(comptime T: type, got: T, want: T) !void {
    if (!std.meta.eql(got, want)) {
        std.debug.print("known-answer mismatch\n  got:  {any}\n  want: {any}\n", .{ got, want });
        return error.KnownAnswerMismatch;
    }
}

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

/// Upstream known answers for an all-zero counter and key, at the upstream
/// default round counts.  Source: Random123 1.14.0, tests/kat_vectors.
fn verifyKnownAnswers() !void {
    const P2x32 = random123.Philox2x32;
    try expectWords(P2x32.counter, P2x32.generate(.{ 0, 0 }, .{0}), .{ 0xff1dae59, 0x6cd10df2 });

    const P4x32 = random123.Philox4x32;
    try expectWords(P4x32.counter, P4x32.generate(.{ 0, 0, 0, 0 }, .{ 0, 0 }), .{
        0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8,
    });

    const P2x64 = random123.Philox2x64;
    try expectWords(P2x64.counter, P2x64.generate(.{ 0, 0 }, .{0}), .{
        0xca00a0459843d731, 0x66c24222c9a845b5,
    });

    const P4x64 = random123.Philox4x64;
    try expectWords(P4x64.counter, P4x64.generate(.{ 0, 0, 0, 0 }, .{ 0, 0 }), .{
        0x16554d9eca36314c, 0xdb20fe9d672d0fdc, 0xd7e772cee186176b, 0x7e68b68aec7ba23b,
    });

    const T2x32 = random123.Threefry2x32;
    try expectWords(T2x32.counter, T2x32.generate(.{ 0, 0 }, .{ 0, 0 }), .{ 0x6b200159, 0x99ba4efe });

    const T4x32 = random123.Threefry4x32;
    try expectWords(T4x32.counter, T4x32.generate(.{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }), .{
        0x9c6ca96a, 0xe17eae66, 0xfc10ecd4, 0x5256a7d8,
    });

    const T2x64 = random123.Threefry2x64;
    try expectWords(T2x64.counter, T2x64.generate(.{ 0, 0 }, .{ 0, 0 }), .{
        0xc2b6e3a8c2c69865, 0x6f81ed42f350084d,
    });

    const T4x64 = random123.Threefry4x64;
    try expectWords(T4x64.counter, T4x64.generate(.{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }), .{
        0x09218ebde6c85537, 0x55941f5266d86105, 0x4bd25e16282434dc, 0xee29ec846bd2e40b,
    });
}

/// A real use: one Threefry4x32 counter stream turned into doubles with the
/// `random123.UnitInterval` conversion, reduced to a single integer summary so
/// the output is identical on every conforming platform.
fn streamSummary() u64 {
    const G = random123.Threefry4x32;
    const key = G.key{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
    var ctr = G.counter{ 0, 0, 0, 0 };

    var summary: u64 = 0;
    var n: u32 = 0;
    while (n < 1024) : (n += 1) {
        const block = G.generate(ctr, key);
        for (block) |word| summary +%= @as(u64, word);

        // The half-open double conversion of one word is exactly i * 2^-53, so
        // scaling by 2^53 recovers the integer i with no rounding at all.
        const unit = random123.UnitInterval.closedOpen64Double(@as(u64, block[0]));
        summary +%= @intFromFloat(unit * 9007199254740992.0);

        // Little-endian carry through all four counter words.
        ctr[0] +%= 1;
        if (ctr[0] == 0) {
            ctr[1] +%= 1;
            if (ctr[1] == 0) {
                ctr[2] +%= 1;
                if (ctr[2] == 0) ctr[3] +%= 1;
            }
        }
    }
    return summary;
}

pub fn main(init: std.process.Init) !void {
    try verifyKnownAnswers();

    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    try out.writeAll("random123 consumer\n");
    try out.writeAll("upstream known answers for counter=0 key=0 at default rounds:\n");
    inline for (random123.generators) |G| {
        const ctr: G.counter = std.mem.zeroes(G.counter);
        const key: G.key = G.init(std.mem.zeroes(G.key));
        try out.print("  {s:>13} -> ", .{G.name});
        try printWords(out, G.generate(ctr, key));
        try out.writeAll("\n");
    }

    try out.print("threefry4x32 1024-counter stream summary: {x:0>16}\n", .{streamSummary()});
    // Raw C oracle, stated rather than compared against the facade: 2^63 is the
    // median of the u64 domain, and `u01fixedpt_closed_open_64_double` is
    // `(i >> 11) * 2^-53` (u01fixedpt.h:160-162, :122), so the median word maps
    // to `2^52 * 2^-53` = exactly 0.5.  Both operands are exactly representable,
    // so `!=` here is an equality test, not a tolerance.
    const raw_interval = random123.c.r123_bridge_u01_closed_open_64_double(0x8000000000000000);
    if (raw_interval != 0.5) return error.RawOracleMismatch;
    try out.print("raw C u01: closedOpen64Double(0x8000000000000000) = {d}\n", .{raw_interval});

    try out.flush();
}
