//! Compile-only analysis of the whole public facade.
//!
//! `zig build check` compiles this file and never runs it.  Every public facade
//! method is called here with concrete types, so the compiler has to analyze
//! every method body -- referencing the declarations would not be enough.
//!
//! `zig build test` does not run this file; it exists for the compile gate.

const std = @import("std");
const random123 = @import("random123");

fn exerciseGenerator(comptime G: type) void {
    const ctr: G.counter = std.mem.zeroes(G.counter);
    const key: G.key = G.init(std.mem.zeroes(G.key));

    _ = G.init(key);
    _ = G.generate(ctr, key);
    _ = G.rounds(G.default_rounds, ctr, key);
    _ = G.rounds(0, ctr, key);
    _ = G.rounds(1, ctr, key);
    _ = G.rounds(G.max_rounds, ctr, key);

    // The type-level surface must resolve too.
    _ = G.name;
    _ = G.counter_bits;
    _ = G.key_bits;
    _ = G.word_bits;
}

test "every public generator method analyzes" {
    inline for (random123.generators) |G| exerciseGenerator(G);
}

test "every public unit-interval conversion analyzes" {
    _ = random123.UnitInterval.closedClosed32Float(0);
    _ = random123.UnitInterval.closedOpen32Float(0);
    _ = random123.UnitInterval.openClosed32Float(0);
    _ = random123.UnitInterval.openOpen32Float(0);
    _ = random123.UnitInterval.closedClosed32Double(0);
    _ = random123.UnitInterval.closedOpen32Double(0);
    _ = random123.UnitInterval.openClosed32Double(0);
    _ = random123.UnitInterval.openOpen32Double(0);
    _ = random123.UnitInterval.closedClosed64Double(0);
    _ = random123.UnitInterval.closedOpen64Double(0);
    _ = random123.UnitInterval.openClosed64Double(0);
    _ = random123.UnitInterval.openOpen64Double(0);
}

test "every public C keyinit wrapper analyzes" {
    // These eight wrappers are compiled into the artifact, installed in the
    // public header and translated into `c`, but nothing else in this package
    // calls them: the facade's `init` is its own identity, not a call through
    // the bridge.  Without this block their signatures would never be
    // checked, and a bridge drift would surface in a downstream C consumer
    // instead of in `zig build check`.
    //
    // Argument widths are upstream's key widths: a Philox key has half as many
    // words as its counter (philox.h:317-323), a Threefry key the same number
    // (threefry.h:199, threefry.h:303).
    //
    // Each wrapper's *result* is handed to a real generation rather than
    // discarded.  That checks the returned key type as well as the parameter,
    // and it keeps the external symbol alive in the linked test binary, so the
    // wrapper is link-checked and not merely referenced.
    const P2x32 = random123.Philox2x32;
    const p2x32_key = random123.c.r123_bridge_philox2x32_keyinit(.{ .v = .{1} }).v;
    _ = P2x32.generate(std.mem.zeroes(P2x32.counter), p2x32_key);

    const P4x32 = random123.Philox4x32;
    const p4x32_key = random123.c.r123_bridge_philox4x32_keyinit(.{ .v = .{ 1, 2 } }).v;
    _ = P4x32.generate(std.mem.zeroes(P4x32.counter), p4x32_key);

    const P2x64 = random123.Philox2x64;
    const p2x64_key = random123.c.r123_bridge_philox2x64_keyinit(.{ .v = .{1} }).v;
    _ = P2x64.generate(std.mem.zeroes(P2x64.counter), p2x64_key);

    const P4x64 = random123.Philox4x64;
    const p4x64_key = random123.c.r123_bridge_philox4x64_keyinit(.{ .v = .{ 1, 2 } }).v;
    _ = P4x64.generate(std.mem.zeroes(P4x64.counter), p4x64_key);

    const T2x32 = random123.Threefry2x32;
    const t2x32_key = random123.c.r123_bridge_threefry2x32_keyinit(.{ .v = .{ 1, 2 } }).v;
    _ = T2x32.generate(std.mem.zeroes(T2x32.counter), t2x32_key);

    const T4x32 = random123.Threefry4x32;
    const t4x32_key = random123.c.r123_bridge_threefry4x32_keyinit(.{ .v = .{ 1, 2, 3, 4 } }).v;
    _ = T4x32.generate(std.mem.zeroes(T4x32.counter), t4x32_key);

    const T2x64 = random123.Threefry2x64;
    const t2x64_key = random123.c.r123_bridge_threefry2x64_keyinit(.{ .v = .{ 1, 2 } }).v;
    _ = T2x64.generate(std.mem.zeroes(T2x64.counter), t2x64_key);

    const T4x64 = random123.Threefry4x64;
    const t4x64_key = random123.c.r123_bridge_threefry4x64_keyinit(.{ .v = .{ 1, 2, 3, 4 } }).v;
    _ = T4x64.generate(std.mem.zeroes(T4x64.counter), t4x64_key);
}

test "the AES-NI bridge analyzes on a target that provides AES-NI" {
    // Not an assertion about presence: when this build has no AES-NI the block
    // is never analyzed at all.  When it does, every AES-NI/ARS entry point has
    // to type-check against the bridge signatures.
    if (comptime random123.has_aesni) {
        var schedule: [random123.c.R123_BRIDGE_AESNI_KEY_WORDS]u32 = undefined;
        random123.c.r123_bridge_aesni4x32_keyinit(&schedule, .{ .v = .{ 0, 0, 0, 0 } });
        _ = random123.c.r123_bridge_aesni4x32_R(
            random123.c.R123_BRIDGE_AESNI4x32_ROUNDS,
            .{ .v = .{ 0, 0, 0, 0 } },
            &schedule,
        );
        const ars_key = random123.c.r123_bridge_ars4x32_keyinit(.{ .v = .{ 0, 0, 0, 0 } });
        _ = random123.c.r123_bridge_ars4x32_R(
            random123.c.R123_BRIDGE_ARS4x32_DEFAULT_ROUNDS,
            .{ .v = .{ 0, 0, 0, 0 } },
            ars_key,
        );
        _ = random123.c.r123_bridge_have_aesni();
    }
}
