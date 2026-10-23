//! Compile-time analysis of the public facade and consumer-built generators.

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
    // Keep the over-bound call unconditional so compile-only analysis reaches the refusal path.
    _ = G.rounds(G.max_rounds + 1, ctr, key);

    // Resolve the generated type's public constants too.
    _ = G.name;
    _ = G.counter_bits;
    _ = G.key_bits;
    _ = G.word_bits;
}

test "every public generator method analyzes" {
    inline for (random123.generators) |G| exerciseGenerator(G);
}

test "a consumer-built generator analyzes" {
    // Instantiate a custom Philox4x32 generator to exercise the public factory.
    // Its non-default round count and calls analyze the callback and generated API.
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

test "the AES-NI bridge analyzes on a target that provides AES-NI" {
    // Compile only when wrappers exist so unavailable declarations are not analyzed.
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
