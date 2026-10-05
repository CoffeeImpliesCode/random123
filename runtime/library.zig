// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Random123's side of the runtime loader: the names its synchronization
//! binding has, and what it requires of a provider beyond resolving its
//! symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! Random123's, and it is the file another SDK replaces.
//!
//! # What a provider is
//!
//! This package's provider is not upstream Random123. Upstream ships no library
//! at all: every algorithm is a `R123_STATIC_INLINE`, that is `static
//! __inline__`, function and every default-round entry point is a preprocessor
//! macro, so nothing in the upstream tree produces a linkable symbol
//! (`include/Random123/features/gccfeatures.h:51-53` for the inline macro,
//! `zig/bridge/random123_bridge.c` for the wrappers that give them external
//! linkage). What a provider therefore has to be is this fork's bridge library:
//! the artifact `zig/bridge/random123_bridge.c` compiles to, built from this
//! tree, exporting the `r123_bridge_*` names declared by
//! `zig/bridge/random123_bridge.h`.
//!
//! There is no other candidate. A system Random123 does not exist as a binary,
//! so `.system` can only ever name a shared object built by this package; a
//! provider that is not the bridge fails at load rather than being used partly.
//!
//! # The 28 names every build requires
//!
//! `zig/bridge/random123_bridge.h` declares twenty-eight external functions
//! outside its AES-NI block, and all twenty-eight are required:
//!
//!   * eight Philox entry points, `philox2x32`/`philox4x32`/`philox2x64`/
//!     `philox4x64` times `keyinit` and `_R`
//!     (`random123_bridge.h:84-102`);
//!   * eight Threefry entry points over the same four shapes
//!     (`random123_bridge.h:106-122`);
//!   * twelve integer-to-floating-point conversions, the four ranges times
//!     `32`/`64` input widths times `float`/`double` results
//!     (`random123_bridge.h:134-147`).
//!
//! The integer constants beside them (`R123_BRIDGE_*_ROUNDS`,
//! `R123_BRIDGE_AESNI_KEY_WORDS`, `random123_bridge.h:48-61`) are not
//! symbols: they are enumeration constants that `random123_bridge.c`
//! static-asserts against the upstream macros of the same meaning
//! (`random123_bridge.c:39-54`), so the dispatch re-exports them from the
//! translation and never looks them up.
//!
//! # The five names that depend on how this build was configured
//!
//! `r123_bridge_have_aesni`, `r123_bridge_aesni4x32_keyinit`,
//! `r123_bridge_aesni4x32_R`, `r123_bridge_ars4x32_keyinit` and
//! `r123_bridge_ars4x32_R` sit inside `#if R123_BRIDGE_HAS_AESNI`
//! (`random123_bridge.h:151-173`). Whether that is 1 is decided once, per
//! build, and the *same* decision reaches both sides:
//!
//!   * the bridge compile line gets `-DR123_BRIDGE_HAS_AESNI=1` together with
//!     the x86 `aes` CPU feature, so `R123_USE_AES_NI`
//!     (`features/gccfeatures.h:113-119`) is 1 and the definitions exist;
//!   * the translation step gets `-DR123_BRIDGE_HAS_AESNI=1`, so the
//!     declarations are in the header the dispatch is generated from.
//!
//! So this descriptor never names them and never special-cases them: a build
//! that compiled the wrappers has them in its translation, so they are in its
//! table and a provider has to export them; a build that did not has no
//! declaration for them anywhere, so there is nothing to resolve. There is no
//! fallback for an absent AES-NI path and no symbol excluded from the table to
//! make one work: a provider compiled without AES-NI offered to a consumer
//! compiled with it is refused with `MissingSymbol`, and a provider compiled
//! with AES-NI offered to a consumer compiled without it is accepted, because
//! that consumer never asks for those five.
//!
//! # The AES-NI CPU requirement, which is separate from all of that
//!
//! A provider compiled with AES-NI is a library that *contains* x86 AES
//! instructions. Loading it is safe; **calling** those four generators on a CPU
//! without AES-NI is not. Upstream ships the probe for exactly this check:
//! `haveAESNI()` reads CPUID leaf 1 bit 25 (`features/sse.h:64-72`), and
//! `r123_bridge_have_aesni` forwards it (`random123_bridge.c:268-271`).
//!
//! That probe is itself one of the five conditional symbols, so it is available
//! exactly when the wrappers are, and `random123.has_aesni` says when that is.
//! A caller that is going to run an AES-NI or ARS generator must check
//! `c.r123_bridge_have_aesni()` first; `zig/kat_test.zig` gates its AES-NI
//! fixture on that call rather than on the build decision.
//!
//! # The external ABI boundary, stated as what it is
//!
//! Every entry point is a plain C function. What crosses the boundary:
//!
//!   * **Scalars.** `unsigned int` round counts, `uint32_t` and `uint64_t`
//!     inputs and words, `float` and `double` results, and an `int` from the
//!     probe. `uint64_t` is 64-bit in every ABI this package targets
//!     (`x86_64`, `aarch64`, `riscv64`, `wasm32`), so it is one spelling
//!     everywhere; `unsigned int` is 32-bit on all of them too.
//!   * **Layout.** The `r123arrayNxW` counter and key types are bare word
//!     arrays -- `[1]u32`, `[2]u32`, `[4]u32`, `[1]u64`, `[2]u64`, `[4]u64`
//!     with no padding -- and they cross **by value**, in both directions, on
//!     every entry point. The bridge static-asserts every one of those sizes
//!     against `sizeof` (`random123_bridge.c:65-76`), so a provider that
//!     disagreed would not have compiled. That leaves the *scalar widths and
//!     the calling convention* as what has to line up, and nothing else.
//!   * **Configuration.** The round-count constants and the
//!     44-word AES-NI key schedule (`R123_BRIDGE_AESNI_KEY_WORDS`) are shared
//!     between the two sides as compile-time facts, not as arguments.
//!   * **Allocator.** There is none. No entry point takes or returns a pointer
//!     the caller has to free, and none allocates: the `uint32_t*` the AES-NI
//!     key schedule is written through is always caller storage of exactly
//!     `R123_BRIDGE_AESNI_KEY_WORDS` words
//!     (`random123_bridge.h:163,166`, `random123_bridge.c:256-259`).
//!   * **Callbacks.** There are none. No entry point takes a function pointer,
//!     so there is no convention to agree on beyond the calling convention.
//!   * **Exported data.** There is none. Every symbol this bridge defines is a
//!     function, so no table entry has to keep a provider address live and no
//!     `NAMEAddr` accessor exists for this SDK.
//!   * **Threading.** Every entry point is a pure function of its arguments
//!     (`philox2x32_R` and friends read only their parameters and the
//!     caller's key storage), so the whole surface is reentrant and needs no
//!     lock on either side.
//!
//! # What is checked at load time, and what is not
//!
//! Resolving symbols and translating a header are the boundary; they are not
//! proof of compatibility, and this file does not pretend to add any proof
//! beyond the three behaviours below. What it can honestly ask of a resolved
//! provider is that its entry points *run* and produce the results upstream's
//! own source says they produce for inputs whose correct answers are fixed
//! constants independent of this fork:
//!
//!   * `philox2x32keyinit` is `return uk;` (`include/Random123/philox.h:321`),
//!     so the wrapper must hand the key back unchanged;
//!   * Philox guards every round with `if (R > n)`
//!     (`include/Random123/philox.h:325-341`), so `R == 0` returns the counter
//!     unchanged -- this is the one that proves a counter crossed the boundary
//!     by value and came back intact, in both directions, through the table;
//!   * `u01fixedpt_closed_open_64_double` is `(i >> 11) * 2^-53`
//!     (`include/Random123/u01fixedpt.h:122,160-162`), so the word `2^63` maps
//!     to exactly `0.5`. Both operands are exactly representable, so this is an
//!     equality test and not a tolerance.
//!
//! None of these inspects a struct layout, and no load-time check can: the
//! caller is the only party that knows what it built. A caller that cares has
//! to compile the same headers, which is what this package does. What the
//! checks do rule out is a provider whose `r123_bridge_*` names resolve to
//! something that is not this bridge at all -- a stale or foreign shared object
//! with the right symbol names and different arithmetic behind them.
//!
//! Nothing here consults the AES-NI probe. `haveAESNI()` returning 0 is a
//! correct answer from a correct provider running on a CPU without the
//! instruction, so it is not evidence of a mismatch and refusing on it would
//! refuse a perfectly good library.
const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=random123_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn random123_rt_lock() void;
    extern fn random123_rt_unlock() void;
    extern fn random123_rt_wait() void;
    extern fn random123_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn random123_rt_thread_self() u64;

    pub fn lock() void {
        random123_rt_lock();
    }
    pub fn unlock() void {
        random123_rt_unlock();
    }
    pub fn wait() void {
        random123_rt_wait();
    }
    pub fn broadcast() void {
        random123_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return random123_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "random123";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this
        /// file: `symbols` is whatever `random123_bridge.h` declared for this
        /// target and this `-Daesni` decision, which is what makes the table
        /// configuration-aware without a single name here being conditional.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// Three calls, all of them on entry points that take and return only
        /// values and touch no global state: no allocation, no lock, no
        /// callback, nothing a provider could be doing on someone else's
        /// behalf. They are here because a shared object can export the right
        /// names and still be a different library, and because a provider that
        /// cannot answer them at all should be refused here rather than
        /// producing numbers in the first call the caller makes.
        pub fn validate(dst: *const table) ?[]const u8 {
            // philox.h:321 -- `philox2x32keyinit` is `return uk;`.
            const ukey: dispatch.struct_r123array1x32 = .{ .v = .{0xa4093822} };
            const keyed = dst.r123_bridge_philox2x32_keyinit(ukey);
            if (keyed.v[0] != ukey.v[0]) {
                return message(
                    "r123_bridge_philox2x32_keyinit changed the key it was given " ++
                        "({x}); upstream defines it as `return uk;` (philox.h:321), " ++
                        "so this provider is not the Random123 bridge this header " ++
                        "describes",
                    .{keyed.v[0]},
                );
            }

            // philox.h:325-341 -- every round is guarded by `if (R > n)`, so
            // zero rounds runs no round and the counter comes back unchanged.
            const ctr: dispatch.struct_r123array2x32 = .{ .v = .{ 0x243f6a88, 0x85a308d3 } };
            const zero = dst.r123_bridge_philox2x32_R(0, ctr, keyed);
            if (zero.v[0] != ctr.v[0] or zero.v[1] != ctr.v[1]) {
                return message(
                    "r123_bridge_philox2x32_R(0, ...) returned ({x} {x}) for a counter " ++
                        "it was given as ({x} {x}); upstream's zero-round guard " ++
                        "returns the counter unchanged (philox.h:325-341), so a " ++
                        "counter is not surviving the crossing by value and back",
                    .{ zero.v[0], zero.v[1], ctr.v[0], ctr.v[1] },
                );
            }

            // u01fixedpt.h:122,160-162 -- `(i >> 11) * 2^-53`, so the median
            // word is exactly 0.5. Both operands are exact, so this is an
            // equality test.
            const unit = dst.r123_bridge_u01_closed_open_64_double(@as(u64, 1) << 63);
            if (unit != 0.5) {
                return message(
                    "r123_bridge_u01_closed_open_64_double(2^63) answered {x}, not the " ++
                        "exact 0x3fe0000000000000 upstream's (i >> 11) * 2^-53 gives " ++
                        "(u01fixedpt.h:122,160-162), so this provider's conversion " ++
                        "arithmetic is not upstream's",
                    .{@as(u64, @bitCast(unit))},
                );
            }

            return null;
        }
    };
}

const std = @import("std");

/// One scratch buffer for the load-time messages that carry numbers.
///
/// The loader retains nothing but the table and the request, so a message built
/// here only has to outlive the `load` call that returns it. That call is the
/// only writer: `validate` runs inside a load attempt, and two attempts for one
/// configured module never run at once (`runtime/loader.zig`), so the buffer is
/// written once per load and read by the caller of that load. A second SDK, or
/// a second instance of this one, has its own copy of this file and therefore
/// its own buffer.
///
/// The size is a ceiling, not a figure of merit. Every format below prints
/// hexadecimal words, at most sixteen digits each, and at most four of them per
/// message, so a message cannot exceed about a hundred and forty bytes.
var message_buffer: [256]u8 = undefined;

/// Render `format` into `message_buffer`.
///
/// The fallback can only be reached if this file is edited to call it with a
/// format that does not fit, and it says what happened rather than dropping the
/// check and accepting the provider.
fn message(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "random123: a load-time check failed and its value could not be printed";
}
