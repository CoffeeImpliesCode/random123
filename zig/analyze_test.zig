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
    // The refusal path.  This file is compiled and never run (`build.zig`
    // gives `check` and `matrix` the compile step and never a run step), so
    // the call is made outright: wrapping it in `if (false)` would leave the
    // branch unanalyzed, which is the trap `FORK-NOTES.md` entry 7 records.
    _ = G.rounds(G.max_rounds + 1, ctr, key);

    // The type-level surface must resolve too.
    _ = G.name;
    _ = G.counter_bits;
    _ = G.key_bits;
    _ = G.word_bits;
}

test "every public generator method analyzes" {
    inline for (random123.generators) |G| exerciseGenerator(G);
}

test "a consumer-built generator analyzes" {
    // `random123.Generator` is published for exactly this: a generator this
    // package does not itself expose, declared with the same six `spec`
    // fields. This reaches the factory's array/word/default checks and
    // analyzes its callback through real method calls.
    //
    // The spec below is Philox4x32's, with a non-default round count, so the
    // built type is a real generator and every member below is a real call.
    const Custom = random123.Generator(.{
        .name = "custom-philox4x32",
        .counter = [4]u32,
        .key = [2]u32,
        .default_rounds = 7,
        .max_rounds = 16,
        .round = random123.c.r123_bridge_philox4x32_R,
    });

    const ctr: Custom.counter = .{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
    const key: Custom.key = .{ 0xa4093822, 0x299f31d0 };

    _ = Custom.name;
    _ = Custom.init(key);
    _ = Custom.rounds(0, ctr, key);
    _ = Custom.rounds(1, ctr, key);
    _ = Custom.rounds(Custom.max_rounds, ctr, key);
    _ = Custom.rounds(Custom.max_rounds + 1, ctr, key);

    // `generate` at the spec's own default.  Upstream's fixture carries this
    // exact counter and key at seven rounds (`tests/kat_vectors:26`), and
    // `zig/kat_test.zig` replays that line through
    // `random123.Philox4x32.rounds`, so the arithmetic a consumer reaches
    // through the factory is the one the fixture pins.
    _ = Custom.generate(ctr, key);
    _ = Custom.default_rounds;
    _ = Custom.counter_bits;
    _ = Custom.key_bits;
    _ = Custom.word_bits;
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

// The eight C `keyinit` wrappers used to have a compile-only block here, each
// call's result handed to a generation so the symbol stayed linked.  That was a
// presence and implementation check: it proved a name existed and type-checked,
// which is not a property a consumer depends on and which would not notice a
// wrapper that resolved to something else.  `zig/kat_test.zig` now drives all
// eight against upstream's own known answers instead, so the same signatures
// are checked by what they compute rather than by what they are called.

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
