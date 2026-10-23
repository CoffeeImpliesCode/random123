//! Random123 1.14.0 -- a library of counter-based random number generators,
//! from D. E. Shaw Research, packaged for Zig 0.17.0.
//!
//! The algorithms are the genuine upstream C ones.  This package compiles a
//! thin bridge translation unit that gives the upstream `static __inline__`
//! implementations external linkage (see `zig/bridge/`), translates the public
//! C surface with `addTranslateC`, and wraps the result in a typed, allocation-
//! free Zig facade.
//!
//! The built-in generators are stateless functions of caller-supplied counter
//! and key. This module has no RNG object, seed, counter or entropy source.
//! Choosing the key, advancing the counter and obtaining key material are the
//! caller's duties. Built-in calls allocate and retain nothing. A custom
//! `Generator` callback carries its own state and concurrency contract.
//!
//! ```zig
//! const std = @import("std");
//! const random123 = @import("random123");
//!
//! pub fn main() void {
//!     const ctr: random123.Philox4x32.counter = .{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
//!     const key: random123.Philox4x32.key = .{ 0xa4093822, 0x299f31d0 };
//!     const out = random123.Philox4x32.generate(ctr, key);
//!     // out == .{ 0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1 }
//!     std.debug.print("{any}\n", .{out});
//! }
//! ```
//!
//! That quadruple is upstream's own known answer for exactly that counter and
//! key: `tests/kat_vectors:29`.  Counter and key are the first and second
//! groups of hex digits of pi, which is how upstream's fixture writes them.
//!
//! Supported routes: reach this module through
//! `b.dependency("random123", …).module("random123")` from a dependent's
//! build script, and `c` below for the raw translated C surface.  There is no
//! system-library mode -- upstream installs no binary -- so there is no
//! installed ABI this package could bind to instead.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default.  The bridge library is linked, `c` is the
//! translated header, and every call below is an ordinary direct call into
//! `librandom123`: no table, no readiness flag, no extra cost per call.
//!
//! *Runtime-loaded* is opt-in through `-Druntime=true`.  The bridge library is
//! not linked; `c` becomes a dispatch generated from the same translation
//! step's output, and all of this package's bridge entry points resolve through
//! the platform loader once the caller has said
//!
//! ```zig
//! try random123.load(.{ .path = "/path/to/librandom123.so" });
//! ```
//!
//! before using anything else.  A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization
//! mode.  That is a programming error rather than a recoverable condition:
//! the table does not exist yet and there is no partial state to fall back on.
//!
//! The provider is reached, never guessed.  `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! there is no unload and no reset, and the handle and this module's own copy
//! of the request live to the end of the process.
//!
//! What a provider must be -- this fork's own bridge, since upstream ships no
//! binary at all -- and what the ABI boundary is, are stated in
//! `runtime/library.zig`, next to the three upstream-defined behaviours the
//! load checks.
//!
//! ## AES-NI in a runtime-loaded build
//!
//! `has_aesni` below answers a *build* question: did this configuration
//! compile the AES-NI and ARS wrappers?  Those five entry points are declared
//! only when `R123_BRIDGE_HAS_AESNI` reached the translation step, so a
//! runtime-loaded module resolves exactly the names its own header declared --
//! twenty-eight without AES-NI, thirty-three with it -- and a provider built
//! without AES-NI is refused rather than half used.  It still does not say the
//! running CPU has the instruction; `c.r123_bridge_have_aesni()` does, and
//! that remains true in either configuration.
//!
//! NOT SUITABLE FOR CRYPTOGRAPHY OR SECURITY.  Upstream states plainly that
//! these generators are for statistical applications and Monte Carlo
//! simulation, and that they are unsuitable for cryptography "even though
//! they are constructed using principles drawn from cryptography".  Nothing in
//! this package changes that.
///
/// Factory contract, including callback and compile-time obligations, is on
/// the defining declaration in `zig/generator.zig`.
pub const Generator = @import("zig/generator.zig").Generator;

/// The translated public C surface of this package: the upstream
/// `r123arrayNxW` counter and key structs, the mirrored default round counts
/// and AES-NI key geometry as integer constants, the `r123_bridge_*_R` and
/// `r123_bridge_*_keyinit` wrappers, the twelve `r123_bridge_u01_*`
/// integer-to-floating-point conversions, and -- only when this build compiled
/// AES-NI, see `has_aesni` -- `r123_bridge_have_aesni`,
/// `r123_bridge_aesni4x32_keyinit`, `r123_bridge_aesni4x32_R`,
/// `r123_bridge_ars4x32_keyinit` and `r123_bridge_ars4x32_R`.
///
/// This is a translation of this fork's `zig/bridge/random123_bridge.h`, not of
/// the whole upstream tree, and it reaches the same compiled bridge the typed
/// facade does: reaching `c` is a supported route for a counter or key in the
/// upstream struct form, and for the AES-NI and ARS generators the typed
/// facade does not wrap.  It is the same declarations with no added promise --
/// it carries upstream's own contracts, including upstream's round-count
/// assertion, which is a no-op under `NDEBUG` and is therefore *not* the
/// unconditional check `rounds` performs.  What is deliberately absent is
/// listed in `README.zig.md`, "The raw C escape hatch".
///
/// In a runtime-loading build this module is a generated dispatch rather than
/// the translation step's own output.  It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `c.struct_r123array4x32` is the same nominal type either way
/// and nothing here needs a cast.  What differs is how a name reaches the
/// bridge: a direct call in the linked configuration, a call through a table
/// that `load` fills in the runtime-loaded one.  `runtime_loaded` below says
/// which configuration this build is, at comptime.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration.  In a runtime-loading build
/// the dispatch carries its own copy of the same declarations and this module
/// is never referenced, so it is never resolved and never compiled.  Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");
const std = @import("std");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the bridge library is linked and `c` is
/// the translated header itself.  True when the build generated a dispatch
/// that resolves the same symbols through the platform loader, in which case
/// `load` is the call that makes the bridge usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader.  There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
///
/// The two are checked against each other on purpose, and a request that is the
/// wrong shape for its own field is `InvalidSource` rather than an attempt that
/// happened to fail: `.path` must be **absolute** and carry no NUL byte
/// (`runtime/loader.zig:186-194`), and `.system` must be a **bare basename** --
/// no separator, no drive letter (`:196-201`).  A relative `.path` would mean
/// whatever the process's working directory happens to be, and a path handed to
/// the platform loader as a name is a different kind of request wearing the same
/// spelling.  Both are reasons a caller gets a clear refusal instead of a
/// library nobody chose.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside
/// the loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the bridge this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked.  Calling it again with the same
/// request succeeds and changes nothing; calling it with a different request
/// after a success is `ProviderMismatch`, and the provider already in use stays
/// in use.  A failed attempt publishes nothing and can be retried explicitly,
/// by calling this again: there is no automatic retry and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process.  There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread.  A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was.  A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding.  `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "random123: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process.  Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Whether this build *compiled* the AES-NI and ARS bridge wrappers.  It is a
/// compile-time constant and answers a build question, not a hardware
/// question: it is true when the resolved target CPU advertises the x86 `aes`
/// feature, or when `-Daesni=true` asked for the wrappers on an x86 target --
/// in which case the build adds `aes` to the target, because upstream's
/// `R123_USE_AES_NI` comes from `__AES__`
/// (`features/gccfeatures.h:113-119`) and a `-maes` cflag alone does not set
/// it.  `-Daesni=true` on a non-x86 target is a build-time error, not a
/// silent downgrade.
///
/// It therefore does **not** say the executing CPU has AES-NI.  A binary
/// built with `-Daesni=true` and moved to a CPU without the instruction will
/// execute those wrappers illegally.  Before running any AES-NI or ARS
/// generator, call `c.r123_bridge_have_aesni()`, which forwards upstream's own
/// CPUID probe (`features/sse.h:67-72`) and is nonzero only when this CPU
/// advertises AES-NI; `zig/kat_test.zig` gates the fixture on exactly that
/// pair.  This declaration has no effect when `has_aesni` is false: the
/// wrappers, and the probe itself, are then absent from `c`, and the eight
/// portable generators above are unaffected either way.
pub const has_aesni: bool = @hasDecl(c, "r123_bridge_aesni4x32_R");

/// `r123::Philox2x32`: `[2]u32` counter, `[1]u32` key, 10 rounds by default,
/// 16 at most.  See `Generator` for the shape of the type and `rounds` for
/// what a round count outside `0...max_rounds` does.
pub const Philox2x32 = Generator(.{
    .name = "philox2x32",
    .counter = [2]u32,
    .key = [1]u32,
    .default_rounds = c.R123_BRIDGE_PHILOX2x32_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox2x32_R,
});

/// `r123::Philox4x32`: `[4]u32` counter, `[2]u32` key, 10 rounds by default,
/// 16 at most.  See `Generator` for the shape of the type and `rounds` for
/// what a round count outside `0...max_rounds` does.
pub const Philox4x32 = Generator(.{
    .name = "philox4x32",
    .counter = [4]u32,
    .key = [2]u32,
    .default_rounds = c.R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox4x32_R,
});

/// `r123::Philox2x64`: `[2]u64` counter, `[1]u64` key, 10 rounds by default,
/// 16 at most.  See `Generator` for the shape of the type and `rounds` for
/// what a round count outside `0...max_rounds` does.
pub const Philox2x64 = Generator(.{
    .name = "philox2x64",
    .counter = [2]u64,
    .key = [1]u64,
    .default_rounds = c.R123_BRIDGE_PHILOX2x64_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox2x64_R,
});

/// `r123::Philox4x64`: `[4]u64` counter, `[2]u64` key, 10 rounds by default,
/// 16 at most.  See `Generator` for the shape of the type and `rounds` for
/// what a round count outside `0...max_rounds` does.
pub const Philox4x64 = Generator(.{
    .name = "philox4x64",
    .counter = [4]u64,
    .key = [2]u64,
    .default_rounds = c.R123_BRIDGE_PHILOX4x64_DEFAULT_ROUNDS,
    .max_rounds = 16,
    .round = c.r123_bridge_philox4x64_R,
});

/// `r123::Threefry2x32`: `[2]u32` counter, `[2]u32` key, 20 rounds by
/// default, 32 at most.  See `Generator` for the shape of the type and
/// `rounds` for what a round count outside `0...max_rounds` does.
pub const Threefry2x32 = Generator(.{
    .name = "threefry2x32",
    .counter = [2]u32,
    .key = [2]u32,
    .default_rounds = c.R123_BRIDGE_THREEFRY2x32_DEFAULT_ROUNDS,
    .max_rounds = 32,
    .round = c.r123_bridge_threefry2x32_R,
});

/// `r123::Threefry4x32`: `[4]u32` counter, `[4]u32` key, 20 rounds by
/// default, 72 at most.  See `Generator` for the shape of the type and
/// `rounds` for what a round count outside `0...max_rounds` does.
pub const Threefry4x32 = Generator(.{
    .name = "threefry4x32",
    .counter = [4]u32,
    .key = [4]u32,
    .default_rounds = c.R123_BRIDGE_THREEFRY4x32_DEFAULT_ROUNDS,
    .max_rounds = 72,
    .round = c.r123_bridge_threefry4x32_R,
});

/// `r123::Threefry2x64`: `[2]u64` counter, `[2]u64` key, 20 rounds by
/// default, 32 at most.  See `Generator` for the shape of the type and
/// `rounds` for what a round count outside `0...max_rounds` does.
pub const Threefry2x64 = Generator(.{
    .name = "threefry2x64",
    .counter = [2]u64,
    .key = [2]u64,
    .default_rounds = c.R123_BRIDGE_THREEFRY2x64_DEFAULT_ROUNDS,
    .max_rounds = 32,
    .round = c.r123_bridge_threefry2x64_R,
});

/// `r123::Threefry4x64`: `[4]u64` counter, `[4]u64` key, 20 rounds by
/// default, 72 at most.  See `Generator` for the shape of the type and
/// `rounds` for what a round count outside `0...max_rounds` does.
pub const Threefry4x64 = Generator(.{
    .name = "threefry4x64",
    .counter = [4]u64,
    .key = [4]u64,
    .default_rounds = c.R123_BRIDGE_THREEFRY4x64_DEFAULT_ROUNDS,
    .max_rounds = 72,
    .round = c.r123_bridge_threefry4x64_R,
});

/// The eight portable generators above, collected for bulk iteration.
///
/// This is an inferred `.{}` literal over eight distinct types, so whether the
/// compiler makes it a tuple or a struct is not settled by anything in this
/// package, and `FORK-NOTES.md` entry 13 records that reading deliberately.
/// Iteration with `for` or `inline for` works either way and is the supported
/// way in; indexing is not part of this contract.  Nothing in this package
/// indexes it.  The AES-NI and ARS generators are not here even when
/// `has_aesni` is true: they are reached through `c`, because their key is an
/// expanded AES schedule rather than a plain word array.
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

/// The twelve integer-to-floating-point conversions of upstream
/// `include/Random123/u01fixedpt.h`, bound one-to-one to the translated
/// `c.r123_bridge_u01_*` functions.
///
/// Each member is a plain alias of that function, not a wrapper: it inherits
/// upstream's arithmetic, its range and its grid unchanged, and nothing here
/// converts, clamps or re-rounds a value.  Only the spelling differs: the
/// namespace is `UnitInterval` rather than upstream's `u01`, because `u01` is
/// a primitive type name in Zig and cannot be used as a declaration name.
/// The upstream names survive on the raw escape hatch.
///
/// Every member is `<range><Word><Type>`, where the two range words say which
/// endpoints the result may take, `32`/`64` is the width of the integer input,
/// and `Float`/`Double` is the result type.  Upstream states the value set for
/// each range at `u01fixedpt.h:78-93`, and the caveats below are upstream's
/// own, kept because this namespace does not remove them:
///
///   - Every input is equally likely, and each result is one point of a fixed
///     grid.  A caller needing finer resolution than the grid below must slice
///     the input itself.
///   - In the `closedClosed` cases the two extreme values are returned with
///     half the frequency of every other value (`u01fixedpt.h:92-94`).
///   - On x86, and especially on 32-bit machines, x87 80-bit intermediate
///     precision can give "bonus" precision, so a closed interval may not be
///     really closed (`u01fixedpt.h:95-103`).  Upstream keeps that caveat, and
///     so does this contract: no member promises an exact endpoint on every
///     target.
///   - No member creates a seed.  Each maps one integer to one float; a
///     caller wanting a uniform variate draws the integer from a generator such
///     as `Philox4x32` above and converts it here.
pub const UnitInterval = struct {
    /// Result in `[0, 1]`, one of `1 + 2^24` points `2^-24` apart.  Upstream
    /// ignores the input's high bit, so the result is **not** monotonic in `i`:
    /// `i` and `i ^ 0x80000000` map to the same value (`u01fixedpt.h:136-139`).
    pub const closedClosed32Float = c.r123_bridge_u01_closed_closed_32_float;
    /// Result in `[0, 1)`, one of `2^24` points `2^-24` apart: the top 24 bits
    /// of `i` index the grid (`u01fixedpt.h:141-143`).
    pub const closedOpen32Float = c.r123_bridge_u01_closed_open_32_float;
    /// Result in `(0, 1]`, one of `2^24` points `2^-24` apart: the same grid
    /// as `closedOpen32Float`, shifted up one whole step (`u01fixedpt.h:145-147`).
    pub const openClosed32Float = c.r123_bridge_u01_open_closed_32_float;
    /// Result in `(0, 1)`, one of `2^23` points `2^-23` apart: odd multiples
    /// of `2^-24`, i.e. `closedOpen32Float`'s grid at half the density
    /// (`u01fixedpt.h:149-151`).
    pub const openOpen32Float = c.r123_bridge_u01_open_open_32_float;

    /// Result in `[0, 1]`, one of `1 + 2^31` points `2^-31` apart.  Widening to
    /// `f64` before the rounding add is what preserves that grid; the extreme
    /// values carry half weight (`u01fixedpt.h:174-181`).
    pub const closedClosed32Double = c.r123_bridge_u01_closed_closed_32_double;
    /// Result in `[0, 1)`, one of `2^32` points `2^-32` apart
    /// (`u01fixedpt.h:182-184`).
    pub const closedOpen32Double = c.r123_bridge_u01_closed_open_32_double;
    /// Result in `(0, 1]`, one of `2^32` points `2^-32` apart, shifted up one
    /// whole step (`u01fixedpt.h:186-188`).
    pub const openClosed32Double = c.r123_bridge_u01_open_closed_32_double;
    /// Result in `(0, 1)`, one of `2^32` points `2^-32` apart, each shifted up
    /// half a step (`u01fixedpt.h:190-192`).
    pub const openOpen32Double = c.r123_bridge_u01_open_open_32_double;

    /// Result in `[0, 1]`, one of `1 + 2^53` points `2^-53` apart.  Upstream
    /// ignores the input's high bit, so the result is **not** monotonic in `i`:
    /// `i` and `i ^ 0x8000000000000000` map to the same value
    /// (`u01fixedpt.h:155-158`).
    pub const closedClosed64Double = c.r123_bridge_u01_closed_closed_64_double;
    /// Result in `[0, 1)`, one of `2^53` points `2^-53` apart: the top 53 bits
    /// of `i` index the grid (`u01fixedpt.h:160-162`).
    pub const closedOpen64Double = c.r123_bridge_u01_closed_open_64_double;
    /// Result in `(0, 1]`, one of `2^53` points `2^-53` apart, shifted up one
    /// whole step (`u01fixedpt.h:164-166`).
    pub const openClosed64Double = c.r123_bridge_u01_open_closed_64_double;
    /// Result in `(0, 1)`, one of `2^52` points `2^-52` apart, each shifted up
    /// half a step (`u01fixedpt.h:168-170`).
    pub const openOpen64Double = c.r123_bridge_u01_open_open_64_double;
};
