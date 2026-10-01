//! Random123 1.14.0 -- a library of counter-based random number generators,
//! from D. E. Shaw Research, packaged for Zig 0.16.
//!
//! The algorithms are the genuine upstream C ones.  This package compiles a
//! thin bridge translation unit that gives the upstream `static __inline__`
//! implementations external linkage (see `zig/bridge/`), translates the public
//! C surface with `addTranslateC`, and wraps the result in a typed, allocation-
//! free Zig facade.
//!
//! ```zig
//! const random123 = @import("random123");
//!
//! const ctr = random123.Philox4x32.counter{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
//! const key = random123.Philox4x32.key{ 0xa4093822, 0x299f31d0 };
//! const out = random123.Philox4x32.generate(ctr, key);
//! // out == .{ 0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1 }
//! ```
//!
//! That quadruple is upstream's own known answer for exactly that counter and
//! key: `tests/kat_vectors:29`.  Counter and key are the first and second
//! groups of hex digits of pi, which is how upstream's fixture writes them.
//!
//! NOT SUITABLE FOR CRYPTOGRAPHY OR SECURITY.  Upstream states plainly that
//! these generators are for statistical applications and Monte Carlo
//! simulation, and that they are unsuitable for cryptography "even though
//! they are constructed using principles drawn from cryptography".  Nothing in
//! this package changes that.

pub const Generator = @import("zig/generator.zig").Generator;

/// The complete translated portable C API: the upstream `r123arrayNxW` counter
/// and key types, the upstream default round counts, the `r123_bridge_*`
/// wrappers, the `u01fixedpt` integer-to-floating-point conversions, and -- when
/// this build compiled AES-NI -- the AES-NI and ARS wrappers.  This is the
/// escape hatch for anything the typed facade does not cover.
pub const c = @import("c");

/// True when this build compiled the AES-NI and ARS bridge wrappers: either
/// the resolved target CPU advertises the `aes` feature, or `-Daesni=true`
/// forced them on.  Forcing the flag cannot give a CPU the instruction, so
/// anything that actually executes those generators must additionally check
/// `c.r123_bridge_have_aesni()` at run time, as `zig/kat_test.zig` does.  The
/// x86-only generators stay reachable through `c` when this is true; the
/// portable generators above are unaffected either way.
pub const has_aesni: bool = @hasDecl(c, "r123_bridge_aesni4x32_R");

/// `r123::Philox2x32`: 2 words in, 2 words out, 1-word key, 10 rounds.
pub const Philox2x32 = Generator(.{
    .name = "philox2x32",
    .counter = [2]u32,
    .key = [1]u32,
    .default_rounds = c.R123_BRIDGE_PHILOX2x32_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox2x32_R,
});

/// `r123::Philox4x32`: 4 words in, 4 words out, 2-word key, 10 rounds.
pub const Philox4x32 = Generator(.{
    .name = "philox4x32",
    .counter = [4]u32,
    .key = [2]u32,
    .default_rounds = c.R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox4x32_R,
});

/// `r123::Philox2x64`: 2 words in, 2 words out, 1-word key, 10 rounds.
pub const Philox2x64 = Generator(.{
    .name = "philox2x64",
    .counter = [2]u64,
    .key = [1]u64,
    .default_rounds = c.R123_BRIDGE_PHILOX2x64_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox2x64_R,
});

/// `r123::Philox4x64`: 4 words in, 4 words out, 2-word key, 10 rounds.
pub const Philox4x64 = Generator(.{
    .name = "philox4x64",
    .counter = [4]u64,
    .key = [2]u64,
    .default_rounds = c.R123_BRIDGE_PHILOX4x64_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox4x64_R,
});

/// `r123::Threefry2x32`: 2 words in, 2 words out, 2-word key, 20 rounds.
pub const Threefry2x32 = Generator(.{
    .name = "threefry2x32",
    .counter = [2]u32,
    .key = [2]u32,
    .default_rounds = c.R123_BRIDGE_THREEFRY2x32_DEFAULT_ROUNDS,
    .max_rounds = 32,
    .round = c.r123_bridge_threefry2x32_R,
});

/// `r123::Threefry4x32`: 4 words in, 4 words out, 4-word key, 20 rounds.
pub const Threefry4x32 = Generator(.{
    .name = "threefry4x32",
    .counter = [4]u32,
    .key = [4]u32,
    .default_rounds = c.R123_BRIDGE_THREEFRY4x32_DEFAULT_ROUNDS,
    .max_rounds = 72,
    .round = c.r123_bridge_threefry4x32_R,
});

/// `r123::Threefry2x64`: 2 words in, 2 words out, 2-word key, 20 rounds.
pub const Threefry2x64 = Generator(.{
    .name = "threefry2x64",
    .counter = [2]u64,
    .key = [2]u64,
    .default_rounds = c.R123_BRIDGE_THREEFRY2x64_DEFAULT_ROUNDS,
    .max_rounds = 32,
    .round = c.r123_bridge_threefry2x64_R,
});

/// `r123::Threefry4x64`: 4 words in, 4 words out, 4-word key, 20 rounds.
pub const Threefry4x64 = Generator(.{
    .name = "threefry4x64",
    .counter = [4]u64,
    .key = [4]u64,
    .default_rounds = c.R123_BRIDGE_THREEFRY4x64_DEFAULT_ROUNDS,
    .max_rounds = 72,
    .round = c.r123_bridge_threefry4x64_R,
});

/// Every portable generator this package exposes, for bulk iteration.
pub const generators = .{
    Philox2x32,
    Philox4x32,
    Philox2x64,
    Philox4x64,
    Threefry2x32,
    Threefry4x32,
    Threefry2x64,
    Threefry4x64,
};

/// Converting random words to uniformly distributed floating point values,
/// forwarding the upstream `u01fixedpt.h` conversions.
///
/// The namespace is `UnitInterval`, not upstream's `u01`: `u01` is a primitive
/// type name in Zig 0.16, so it cannot be used as a declaration name.  The
/// upstream spelling is unchanged on the raw C escape hatch, where the same
/// twelve conversions are `c.r123_bridge_u01_*`.
///
/// Every member is `<range><Word><Type>`.  The four ranges mean, in the
/// upstream sense:
///   `closedClosed` -- result in [0, 1]
///   `closedOpen`   -- result in [0, 1)
///   `openClosed`   -- result in (0, 1]
///   `openOpen`     -- result in (0, 1)
pub const UnitInterval = struct {
    pub const closedClosed32Float = c.r123_bridge_u01_closed_closed_32_float;
    pub const closedOpen32Float = c.r123_bridge_u01_closed_open_32_float;
    pub const openClosed32Float = c.r123_bridge_u01_open_closed_32_float;
    pub const openOpen32Float = c.r123_bridge_u01_open_open_32_float;

    pub const closedClosed32Double = c.r123_bridge_u01_closed_closed_32_double;
    pub const closedOpen32Double = c.r123_bridge_u01_closed_open_32_double;
    pub const openClosed32Double = c.r123_bridge_u01_open_closed_32_double;
    pub const openOpen32Double = c.r123_bridge_u01_open_open_32_double;

    pub const closedClosed64Double = c.r123_bridge_u01_closed_closed_64_double;
    pub const closedOpen64Double = c.r123_bridge_u01_closed_open_64_double;
    pub const openClosed64Double = c.r123_bridge_u01_open_closed_64_double;
    pub const openOpen64Double = c.r123_bridge_u01_open_open_64_double;
};
