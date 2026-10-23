//! Replays D. E. Shaw Research's `tests/kat_vectors` fixture through typed and raw C APIs.
//! The build embeds the fixture bytes; runtime-loading tests require a named provider.
//! AES-NI/ARS cases require compiled wrappers and a CPU that supports AES-NI.

const std = @import("std");
const random123 = @import("random123");
const provider = @import("provider.zig");

const kat_source = @import("kat_vectors").data;

/// Loads the configured provider; runtime tests fail rather than skip without one.
/// Call per test because the runner starts after file scope; same-provider loads are idempotent.
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

/// Returns the nth whitespace token as a slice without allocating.
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

/// Reads a function parameter type from a function or function pointer.
/// Container fields are pointers; direct `extern fn` declarations are function types.
fn FnParam(comptime F: type, comptime index: usize) type {
    const info = @typeInfo(F);
    const function = switch (info) {
        .@"fn" => |f| f,
        // A function stored in a container is represented by a pointer.
        .pointer => |p| switch (@typeInfo(p.child)) {
            .@"fn" => |f| f,
            else => @compileError("random123: expected a function pointer"),
        },
        else => @compileError("random123: expected a function or a pointer to one"),
    };
    return function.param_types[index].?;
}

test "known answers for every portable generator" {
    try loadProvider();
    // Require at least one fixture row per generator.
    var replayed: [algorithms.len]usize = @splat(0);
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, kat_source, '\n');
    while (nextVector(&lines)) |line| {
        const name = token(line, 0);
        // AES-NI/ARS fixture rows are checked only when this build includes the wrappers.
        if (isAesFamily(name)) continue;
        const rounds = try std.fmt.parseInt(u32, token(line, 1), 10);

        var matched = false;
        inline for (algorithms, 0..) |alg, index| {
            // Fixture names are runtime data, so select a block inside the comptime-unrolled loop.
            // The loop supplies each generator type and array shape.
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

    // Check every generator at comptime; the table carries their types.
    inline for (algorithms, 0..) |alg, index| {
        if (replayed[index] == 0) {
            std.debug.print("no upstream known answer was replayed for {s}\n", .{alg.name});
            return error.TestUnexpectedResult;
        }
    }
}

test "known answers for AES-NI and ARS when this build has AES-NI" {
    // Compile-time return avoids references to AES-NI wrappers absent from this build.
    if (comptime !random123.has_aesni) return error.SkipZigTest;
    // Load only after confirming wrappers exist; otherwise runtime builds would demand an unused provider.
    try loadProvider();
    // Compile-time AES-NI support does not prove the runtime CPU supports it.
    if (random123.c.r123_bridge_have_aesni() == 0) return error.SkipZigTest;

    // Require fixture rows for both AES-NI and ARS.
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

// Raw C tests call bridge wrappers directly, independently of the typed facade.
// The upstream fixture checks the C route without using the facade as its own oracle.

test "the raw C keyinit and round wrappers replay upstream's known answers" {
    try loadProvider();

    // Keep wrapper pairs in a tuple because each translated array has a distinct type.
    // Explicit entries make missing or unrouted wrappers compile-time failures.
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

    var replayed: [raws.len]usize = @splat(0);
    var lines = std.mem.splitScalar(u8, kat_source, '\n');
    while (nextVector(&lines)) |line| {
        const name = token(line, 0);
        if (isAesFamily(name)) continue;
        const rounds = try std.fmt.parseInt(u32, token(line, 1), 10);

        var matched = false;
        inline for (raws, 0..) |alg, index| {
            // Fixture names are runtime data; select a block inside the comptime-unrolled loop.
            // The loop supplies each raw function type and array shape.
            if (std.mem.eql(u8, name, alg.name)) {
                matched = true;
                replayed[index] += 1;

                // Read counter/key types from translated function parameters, unwrapping tuple-field pointers.
                // This keeps the replay tied to the declarations.
                const Ctr = FnParam(@TypeOf(alg.round), 1);
                const Key = FnParam(@TypeOf(alg.keyinit), 0);

                // Derive word counts from translated structs; the bridge asserts their sizes.
                // A table mismatch then fails while parsing fixture words.
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

                // Exercise the C keyinit wrapper before the round function.
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
