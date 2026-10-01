//! Typed counter-based RNG facade over the upstream Random123 C API.
//!
//! A `Generator` is a stateless function object: it owns no memory, performs
//! no allocation, keeps no global state, and its result depends only on the
//! counter and key it is handed.  `Philox` and `Threefry` from Random123 1.14.0
//! are counter-based RNGs in exactly that sense.
//!
//! The work itself happens in compiled C: every `rounds` call forwards to the
//! `r123_bridge_*_R` wrapper, which is a one-line call into the upstream
//! `static __inline__` implementation.  Nothing here reimplements an upstream
//! algorithm, and nothing here changes an upstream result.
//!
//! NOT SUITABLE FOR CRYPTOGRAPHY.  Upstream is explicit that these generators
//! are statistical, not cryptographic, even where they borrow cryptographic
//! primitives.  Do not use them for keys, nonces, or any other secret.

const std = @import("std");

/// The element type and element count of a word array type, with a compile
/// error that names the generator when `T` is not an array.  `counter` and
/// `key` are array *types*, so their shape has to come from `@typeInfo`; every
/// width the facade publishes is derived from that metadata, and a wrong spec
/// must fail here rather than at an opaque union-field mismatch later.
fn wordArrayType(
    comptime generator: []const u8,
    comptime field_name: []const u8,
    comptime T: type,
) std.builtin.Type.Array {
    return switch (@typeInfo(T)) {
        .array => |array| array,
        else => @compileError("random123: " ++ generator ++ ": " ++ field_name ++
            " must be an array of words, e.g. [4]u32"),
    };
}

/// Builds one typed CBRNG type.
///
/// `spec` must carry:
///   - `name`          the upstream C identifier, e.g. `"philox4x32"`
///   - `counter`       the counter word array, e.g. `[4]u32`
///   - `key`           the key word array, e.g. `[2]u32`
///   - `default_rounds` upstream default round count
///   - `max_rounds`    largest round count upstream accepts
///   - `round`         the `r123_bridge_*_R` function to call
///
/// `counter` and `key` are array types and must both be arrays of the same
/// word type, 32 or 64 bits wide.
pub fn Generator(comptime spec: anytype) type {
    const counter_array = wordArrayType(spec.name, "counter", spec.counter);
    const key_array = wordArrayType(spec.name, "key", spec.key);
    if (counter_array.child != key_array.child) {
        @compileError("random123: " ++ spec.name ++ ": counter and key must use the same word type");
    }

    return struct {
        /// Upstream C identifier, e.g. `"philox4x32"`.
        pub const name: []const u8 = spec.name;
        /// The counter, as plain words.  The upstream type is the `r123arrayNxW`
        /// struct whose sole member is `v[N]`; the facade hands that member
        /// straight to the bridge, so no conversion and no copy beyond the
        /// by-value argument passing happens here.
        pub const counter = spec.counter;
        /// The key, as plain words.  Philox keys have half as many words as the
        /// counter; Threefry keys have the same number.
        pub const key = spec.key;
        /// Upstream default round count (`PHILOxNxW_DEFAULT_ROUNDS`,
        /// `THREEFRYNxW_DEFAULT_ROUNDS`).  `generate` uses this.
        pub const default_rounds: u32 = spec.default_rounds;
        /// Largest round count upstream accepts.  Upstream asserts `R <= 16` for
        /// Philox, `Nrounds <= 32` for Threefry2xW and `Nrounds <= 72` for
        /// Threefry4xW; past that the result is undefined, so the facade traps
        /// instead of returning garbage.
        pub const max_rounds: u32 = spec.max_rounds;
        /// Bits per counter/key word: 32 or 64.  Both arrays were checked to
        /// have the same element type, so one child answers for both.
        pub const word_bits = @bitSizeOf(counter_array.child);
        /// Total counter width in bits.
        pub const counter_bits = word_bits * counter_array.len;
        /// Total key width in bits.
        pub const key_bits = word_bits * key_array.len;

        /// Upstream `<generator>keyinit`.  For Philox and Threefry upstream
        /// defines that function as `return uk;`, so the user key and the key
        /// type are the same thing and this is the identity.
        pub inline fn init(k: key) key {
            return k;
        }

        /// The generator with an explicit round count.
        pub inline fn rounds(R: u32, ctr: counter, k: key) counter {
            if (R > max_rounds) {
                // `@panic` takes a plain message and no arguments in Zig 0.16,
                // so the formatted message goes through `std.debug.panic`.
                std.debug.panic("random123: round count out of range for {s}", .{name});
            }
            const out = spec.round(@intCast(R), .{ .v = ctr }, .{ .v = k });
            return out.v;
        }

        /// The generator with upstream's default round count.
        pub inline fn generate(ctr: counter, k: key) counter {
            return rounds(default_rounds, ctr, k);
        }
    };
}
