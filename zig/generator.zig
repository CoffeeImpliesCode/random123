//! Typed counter-based RNG facade over the upstream Random123 C API.
//!
//! This file is the implementation behind `random123.Generator`, which is the
//! published factory; every public generator in `root.zig` is one of its
//! products, and a consumer may build its own with the same six `spec` fields.
//!
//! A generated namespace has no instances or stored RNG state. Its callback
//! determines allocation, purity and thread safety. Built-in Philox and
//! Threefry callbacks are stateless, so equal arguments give equal outputs
//! regardless of interleaved calls.
//!
//! Built-in `rounds` calls enter `r123_bridge_*_R`, which calls upstream's
//! `static __inline__` implementation. Custom callbacks need not use a C
//! bridge. This factory reimplements no upstream algorithm.
//!
//! NOT SUITABLE FOR CRYPTOGRAPHY.  Upstream is explicit that these generators
//! are statistical, not cryptographic, even where they borrow cryptographic
//! primitives.  Do not use them for keys, nonces, or any other secret.

const std = @import("std");

/// The array type of a `spec` word array (`counter`, `key`), so a spec that
/// passes a scalar, a pointer or a slice fails here with the generator's name
/// rather than at an opaque mismatch where the bridge is called.  Both are
/// array *types*, so their shape has to come from `@typeInfo`.
fn specArrayType(
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

/// The word type of a `spec` array.  Upstream instantiates only unsigned
/// 32- and 64-bit words -- `philox.h:344-354` defines
/// `_philox2xWbumpkey_tpl`/`_philox4xWbumpkey_tpl` for `W = 32` and `W = 64`,
/// `threefry.h:736-740` defines `_threefry2x_tpl`/`_threefry4x_tpl` for the
/// same two widths, and nothing else -- so a signed or differently sized
/// element type names a generator the bridge cannot carry, and would fail
/// later as an opaque store into `r123arrayNxW.v`.
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

/// Builds one typed CBRNG type from a compile-time `spec` value.
///
/// Array shape, word type and default-round bounds are checked when
/// `Generator(spec)` is evaluated. Callback compatibility is checked when a
/// generated method that calls it is analyzed. `spec` carries:
///
///   - `name`          the upstream C identifier, e.g. `"philox4x32"`.  Used
///                     verbatim in the round-count diagnostic.
///   - `counter`       the counter word *array type*, e.g. `[4]u32`.  Its
///                     length is the counter width, and its element type must
///                     be 32- or 64-bit unsigned: upstream instantiates no
///                     other word width.
///   - `key`           the key word array type, e.g. `[2]u32`.  Its element
///                     type must equal `counter`'s.  Upstream gives a Philox
///                     key half as many words as its counter (`philox.h:319`)
///                     and a Threefry key the same number (`threefry.h:197`),
///                     but that ratio is not this function's rule -- it is
///                     whatever `round` is declared to accept.
///   - `default_rounds` upstream default round count, used by `generate`.  It
///                     may not exceed `max_rounds`; a spec that breaks that is
///                     rejected here, because `generate` would then always
///                     refuse.
///   - `max_rounds`    largest round count `round` accepts.  `rounds` refuses
///                     a larger `R` in every optimize mode.  It must be the
///                     bound the `round` function actually implements; this
///                     factory cannot read it out of C, and upstream states it
///                     only as an assertion (`philox.h:324`,
///                     `threefry.h:205`, `threefry.h:309`).
///   - `round`         a callable accepting the round count and the two
///                     values `.{ .v = ctr }`, `.{ .v = key }`, and returning
///                     a value whose `.v` can be returned as `counter`.
///                     Native bridges take `c_uint` and `r123arrayNxW`
///                     structs. Custom callbacks may use generic counter/key
///                     parameters or additional defaulted struct fields.
///                     The count parameter must support `@intCast(R)` for
///                     every `R <= max_rounds`.
///
/// The result is a namespace type, not an instance. The facade allocates and
/// retains nothing. Built-in callbacks are stateless and may run concurrently.
/// A custom callback's allocation, state and thread-safety obligations remain
/// the caller's. This factory cannot prove its purity or native round bound.
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
        /// Upstream C identifier, e.g. `"philox4x32"`.  Present for diagnostics
        /// and for a consumer labelling its own results; the algorithms do not
        /// read it.
        pub const name: []const u8 = spec.name;
        /// Counter words, passed by value. Native `r123arrayNxW` uses a `v`
        /// array; no conversion beyond argument/result passing occurs here.
        pub const counter = spec.counter;
        /// The key, as plain words, with the same passing rules as `counter`.
        /// Philox keys have half as many words as the counter; Threefry keys
        /// have the same number.
        pub const key = spec.key;
        /// Upstream default round count (`PHILOxNxW_DEFAULT_ROUNDS`,
        /// `THREEFRYNxW_DEFAULT_ROUNDS`).  `generate` uses it, and the factory
        /// rejects a spec whose default exceeds `max_rounds`.
        pub const default_rounds: u32 = spec.default_rounds;
        /// Largest round count `round` accepts.  Upstream asserts `R <= 16` for
        /// Philox (`philox.h:324`), `Nrounds <= 32` for Threefry2xW
        /// (`threefry.h:205`) and `Nrounds <= 72` for Threefry4xW
        /// (`threefry.h:309`), through `R123_ASSERT`, which
        /// `features/gccfeatures.h:67-70` defines as `assert(x)` -- a no-op
        /// once `NDEBUG` is defined, and Zig defines it for its release
        /// optimize modes (`FORK-NOTES.md` entry 5).  `rounds` therefore
        /// checks this bound itself and traps in *every* optimize mode.
        pub const max_rounds: u32 = spec.max_rounds;
        /// Bits per counter/key word: 32 or 64.  Both arrays were checked to
        /// have the same element type, so one child answers for both.
        pub const word_bits = @bitSizeOf(counter_array.child);
        /// Total counter width in bits.
        pub const counter_bits = word_bits * counter_array.len;
        /// Total key width in bits.
        pub const key_bits = word_bits * key_array.len;

        /// Returns `k` unchanged: upstream defines `<gen>keyinit` as
        /// `return uk;` for every generator in this package (`philox.h:321`,
        /// `threefry.h:199`, `threefry.h:303`).  It is published because the
        /// name is part of upstream's own surface; it takes and returns the
        /// key by value, allocates nothing and keeps nothing.
        pub inline fn init(k: key) key {
            return k;
        }

        /// The generator over `ctr` and `k` with exactly `R` rounds.
        ///
        /// `R == 0` is legal: upstream asserts only an upper bound, and
        /// `philox.h:325-341` guards every round with `if(R > n)`, so the
        /// result is `ctr` unchanged.  Threefry adds the key before that guard
        /// (`threefry.h:207-213`, `threefry.h:311-325`), so its zero-round
        /// result is `ctr +% k` word by word.
        ///
        /// `R > max_rounds` traps before the C call, in every optimize mode.
        /// The check is a plain comparison, not `std.debug.assert`: it is not
        /// compiled out under ReleaseFast or ReleaseSmall, where upstream's
        /// own `R123_ASSERT` is.  The message goes to the process panic
        /// handler, which the root module of the final program selects.
        ///
        /// Built-in callbacks depend only on `R`, `ctr` and `k`, allocate
        /// nothing and may run concurrently. Custom callbacks carry their
        /// own state, allocation and concurrency contract.
        pub inline fn rounds(R: u32, ctr: counter, k: key) counter {
            if (R > max_rounds) {
                // `@panic` takes a plain message and no arguments in Zig 0.16,
                // so the formatted message goes through `std.debug.panic`.
                std.debug.panic(
                    "random123: round count {d} exceeds max_rounds {d} for {s}",
                    .{ R, max_rounds, name },
                );
            }
            const out = spec.round(@intCast(R), .{ .v = ctr }, .{ .v = k });
            return out.v;
        }

        /// The generator over `ctr` and `k` at `default_rounds`, i.e.
        /// `rounds(default_rounds, ctr, k)`. The factory rejects a default
        /// above `max_rounds`; the callback and every other obligation of
        /// `rounds` still apply.
        pub inline fn generate(ctr: counter, k: key) counter {
            return rounds(default_rounds, ctr, k);
        }
    };
}
