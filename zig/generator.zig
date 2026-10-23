//! Typed facade over Random123; it reuses upstream algorithms and stores no generator state.
//! Built-ins are stateless; custom callbacks own their state, allocation, and thread-safety.
//! Statistical, not cryptographic; never use it for secrets.

const std = @import("std");

/// Returns the array type of a spec field or reports a compile-time error.
fn specArrayType(
    comptime generator: []const u8,
    comptime field_name: []const u8,
    comptime T: type,
) std.lang.Type.Array {
    return switch (@typeInfo(T)) {
        .array => |array| array,
        else => @compileError("random123: " ++ generator ++ ": " ++ field_name ++
            " must be an array of words, e.g. [4]u32"),
    };
}

/// Rejects word types other than unsigned 32- and 64-bit integers at compile time.
fn checkWordType(
    comptime generator: []const u8,
    comptime field_name: []const u8,
    comptime T: type,
) void {
    const info = @typeInfo(T);
    if (info != .int) {
        @compileError("random123: " ++ generator ++ ": " ++ field_name ++
            " must be an array of u32 or u64 words, e.g. [4]u32");
    }
    if (info.int.signedness != .unsigned or (info.int.bits != 32 and info.int.bits != 64)) {
        @compileError("random123: " ++ generator ++ ": " ++ field_name ++
            " words must be u32 or u64, e.g. [4]u32");
    }
}

/// Builds a typed generator from a comptime spec: name, counter/key array types, round bounds, and callback.
/// The facade stores nothing; invalid shapes, bounds, or callback types fail at compile time. Custom callbacks own allocation, state, and thread-safety.
pub fn Generator(comptime spec: anytype) type {
    const counter_array = specArrayType(spec.name, "spec.counter", spec.counter);
    const key_array = specArrayType(spec.name, "spec.key", spec.key);
    checkWordType(spec.name, "counter", counter_array.child);
    checkWordType(spec.name, "key", key_array.child);
    if (counter_array.child != key_array.child) {
        @compileError("random123: " ++ spec.name ++ ": counter and key must use the same word type");
    }
    if (spec.default_rounds > spec.max_rounds) {
        @compileError("random123: " ++ spec.name ++ ": default_rounds exceeds max_rounds, so `generate` would always refuse");
    }

    return struct {
        /// Upstream C identifier, also used in diagnostics.
        pub const name: []const u8 = spec.name;
        /// Counter word array type accepted by `rounds` and `generate` by value.
        pub const counter = spec.counter;
        /// Key word array type; its word type must match the counter's.
        pub const key = spec.key;
        /// Default round count used by `generate`; it must not exceed `max_rounds`.
        pub const default_rounds: u32 = spec.default_rounds;
        /// Largest round count accepted by `rounds`; larger values trap in every optimization mode.
        /// The spec must match the callback's actual bound.
        pub const max_rounds: u32 = spec.max_rounds;
        /// Bits per counter/key word (32 or 64).
        pub const word_bits = @bitSizeOf(counter_array.child);
        /// Total counter width in bits.
        pub const counter_bits = word_bits * counter_array.len;
        /// Total key width in bits.
        pub const key_bits = word_bits * key_array.len;

        /// Returns the key unchanged; allocates and retains nothing.
        pub inline fn init(k: key) key {
            return k;
        }

        /// Runs the callback for `R` rounds; at zero, Philox returns the counter and Threefry adds the key.
        /// `R > max_rounds` traps in every optimization mode; custom callbacks own state, allocation, and thread-safety.
        pub inline fn rounds(R: u32, ctr: counter, k: key) counter {
            if (R > max_rounds) {
                // Use std.debug.panic to format the diagnostic; @panic accepts no arguments.
                std.debug.panic(
                    "random123: round count {d} exceeds max_rounds {d} for {s}",
                    .{ R, max_rounds, name },
                );
            }
            const out = spec.round(@intCast(R), .{ .v = ctr }, .{ .v = k });
            return out.v;
        }

        /// Runs at `default_rounds`; inherits the bound and callback requirements of `rounds`.
        pub inline fn generate(ctr: counter, k: key) counter {
            return rounds(default_rounds, ctr, k);
        }
    };
}
