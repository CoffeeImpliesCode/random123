# Random123 for Zig

A Zig 0.16 package around [Random123](https://github.com/DEShawResearch/random123)
`v1.14.0` — a library of counter-based random number generators by John Salmon
and Mark Moraes, from D. E. Shaw Research, BSD 3-Clause. See `LICENSE` for the
copyright notice upstream states.

The algorithms are upstream's, compiled from upstream's headers. This fork adds
a build script, a C bridge that gives those header-only algorithms linkable
symbols, and a typed Zig facade over them. See `UPSTREAM.md`, `NOTICE.md` and
`FORK-NOTES.md`.

> **Not suitable for cryptography or security.** Upstream says so explicitly:
> these generators are for statistical applications and Monte Carlo
> simulation, and are unsuitable for cryptography "even though they are
> constructed using principles drawn from cryptography". AESNI uses the AES
> block cipher; ARS uses the AES round function with a non-cryptographic key
> schedule. Neither is a CSPRNG and neither is exported as one.

## Status

The commands below are this fork's entry points. Their outcomes belong to a run,
not to this prose: where a gate result appears below it is named with its date
and its exit status, and the receipt itself stays in the workspace ledger
rather than here. A result no run has produced is written as
`PENDING-VERIFICATION`, never as a pass. Per-finding status, including the
withdrawn claims and the one false statement kept with its refutation, lives in
`FORK-NOTES.md`.

`README.md` is this fork's README — deviations, matrix, consumption. This file
is the Zig interface documentation and stays separate from it. Upstream's own
README is `README.upstream.md`, byte for byte.

## Consuming it

This downstream is a **private** GitHub repository
(`https://github.com/CoffeeImpliesCode/random123`), so a consumer needs an
authenticated clone first. Nothing here resolves for an anonymous fetch, and a
`.url` + `.hash` dependency needs a pushed commit to hash — the remote preflight
recorded `size = 0` and `commits_pushed = 0` for this repository, so the path
form below is the one that works today:

```sh
git clone https://github.com/CoffeeImpliesCode/random123.git random123
# or, with an SSH key:
#   git clone git@github.com:CoffeeImpliesCode/random123.git random123
```

Then depend on the clone by relative path:

```zig
// build.zig.zon
.dependencies = .{
    .random123 = .{ .path = "../random123" },
},
```

```zig
// build.zig
const random123_dep = b.dependency("random123", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("random123", random123_dep.module("random123"));
// That is all.  The module already links the compiled C artifact and carries
// the translated C declarations.
```

A runnable end-to-end example lives in `consumer/`, which depends on this
package exactly that way.

Those are the three supported routes: `module("random123")` for Zig, the
`random123` artifact plus its installed headers for C and C++, and
`random123.c` for the raw translated surface from inside Zig. There is
deliberately no system-library mode. Random123 is header-only and installs no
binary, so a "system" Random123 would only ever be a header directory: there is
no installed ABI to bind to, and nothing for such a mode to select. The build
therefore declares no `b.systemIntegrationOption`.

Downstream C and C++ consumers link the artifact instead:

```zig
// build.zig: the artifact installs librandom123 plus include/
exe.root_module.linkLibrary(random123_dep.artifact("random123"));
```

```c
#include <Random123/philox.h>       /* upstream, unmodified  */
#include <random123_bridge.h>      /* this fork's C surface  */

philox4x32_ctr_t r = philox4x32(c, k);                   /* upstream macro  */
philox4x32_ctr_t s = r123_bridge_philox4x32_R(10, c, k); /* linked symbol   */
```

`Module.linkLibrary` adds an artifact's installed headers to the linking
module's include search path, and the artifact installs the whole upstream
`include/` tree — 21 `.h` and 5 `.hpp` files — plus `random123_bridge.h` at the
include root, so both includes resolve without any extra wiring. The `.hpp`
files are C++ only; they never enter the translated surface or the C build.

And a Nix or devenv consumer takes the same artifact. `package.nix` is one
source-only derivation with no download and no sibling import; the flake and
the devenv shell both call it:

```sh
nix build .#packages.x86_64-linux.static   # the repository default linkage
nix build .#packages.x86_64-linux.shared   # the same bridge as a shared object
devenv shell                               # tools only, pinned to Zig 0.16.0
devenv shell test                          # or build / install / smoke / check / matrix / consumer / provenance
devenv build outputs.static                # lazy; the packaging route from the shell
```

Every Nix build passes `-Dcpu=baseline`, so the output does not inherit the CPU
of whichever machine built it; `aesni` therefore defaults to `false` and the
AES-NI wrappers are compiled only when a packager asks for them. `static` means a
static *library artifact*. The build graph installs the library, the 26 upstream
headers, the bridge header, `random123.pc` and the licence records under
`$out/share/licenses/random123/`; it does not install HTML docs, examples,
tests or tools. `flake.lock` is in this tree and pins nixpkgs to the revision
`flake.nix` names; `devenv.lock` is still the integrator's to write, so the
devenv input is named by revision instead. See `UPSTREAM.md`, "Packaging".

## The facade

Every built-in generator is stateless: no allocation, no global state, no
RNG object to keep, no seed and no entropy source. The result is a pure
function of the counter and key the caller supplies, so choosing the key,
advancing the counter and obtaining the key material are the caller's whole
job. Nothing here is released, because nothing is retained.

```zig
const random123 = @import("random123");

const Philox4x32 = random123.Philox4x32;

const ctr = Philox4x32.counter{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
const key = Philox4x32.key{ 0xa4093822, 0x299f31d0 };
const out = Philox4x32.generate(ctr, key);
// out == .{ 0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1 }
```

That output is upstream's own known answer for that counter and key —
`tests/kat_vectors:29` — so the example is checkable against the fixture
rather than against itself.

| | counter | key | default rounds | max rounds |
|---|---|---|---|---|
| `Philox2x32` | `[2]u32` | `[1]u32` | 10 | 16 |
| `Philox4x32` | `[4]u32` | `[2]u32` | 10 | 16 |
| `Philox2x64` | `[2]u64` | `[1]u64` | 10 | 16 |
| `Philox4x64` | `[4]u64` | `[2]u64` | 10 | 16 |
| `Threefry2x32` | `[2]u32` | `[2]u32` | 20 | 32 |
| `Threefry4x32` | `[4]u32` | `[4]u32` | 20 | 72 |
| `Threefry2x64` | `[2]u64` | `[2]u64` | 20 | 32 |
| `Threefry4x64` | `[4]u64` | `[4]u64` | 20 | 72 |

Philox keys have half as many words as the counter; Threefry keys have the same
number. `default_rounds` is upstream's own default, mirrored in
`zig/bridge/random123_bridge.h` and static-asserted against the upstream macro
in `zig/bridge/random123_bridge.c` so it cannot drift.

`max_rounds` is the largest count upstream accepts (`philox.h:324` asserts
`R<=16`, `threefry.h:205` asserts `Nrounds<=32`, `threefry.h:309` asserts
`Nrounds<=72`). That assertion is `R123_ASSERT`, which
`features/gccfeatures.h:67-70` defines as `assert(x)` and which disappears once
`NDEBUG` is defined — and Zig defines `NDEBUG` for its release optimize modes.
`rounds` therefore makes the check itself, as an ordinary comparison before the
C call, and it is **unconditional**: `R > max_rounds` traps in Debug,
ReleaseSafe, ReleaseFast and ReleaseSmall alike. The message names the count,
the bound and the generator, and goes to the process panic handler.

Per generator:

* `init(key)` — upstream's `<gen>keyinit`. For Philox and Threefry upstream
  defines it as `return uk;` (`philox.h:321`, `threefry.h:199`,
  `threefry.h:303`), so it is the identity.
* `rounds(R, ctr, key)` — explicit round count. `R == 0` is legal: upstream
  asserts only an upper bound. What it returns is family-specific, and worth
  knowing before assuming it is the identity. Philox guards every round with
  `if(R > n)` (`philox.h:325-341`), so zero rounds returns the counter
  unchanged; Threefry adds the key before that guard
  (`threefry.h:207-213`, `threefry.h:311-325`), so its zero-round result is
  the counter plus the key, word by word.
* `generate(ctr, key)` — upstream's default round count.

`random123.generators` holds all eight, for bulk iteration. Walk it with `for`
or `inline for`; indexing is deliberately not part of the contract, because
whether an inferred `.{}` literal becomes a tuple or a struct is not settled by
anything here (`FORK-NOTES.md` entry 13). A generator chosen at run time is not
reachable through it; call the type you want directly.

`random123.Generator` is published, so a consumer can build a generator this
package does not expose. It takes one compile-time `spec` carrying `name`,
`counter`, `key`, `default_rounds`, `max_rounds` and `round`. At construction,
the factory checks array shape, a common `u32` or `u64` word type and
`default_rounds <= max_rounds`. Callback compatibility is checked when a
generated method calls it: the callback accepts the count and
`.{ .v = ctr }`, `.{ .v = key }`, and returns a value whose `.v` matches
`counter`. Generic counter/key parameters are supported. Custom callback
allocation, state, purity and thread safety remain the caller's duties.
The field-by-field contract is on `Generator`; `zig/analyze_test.zig`
exercises a factory product in each compile gate.

Converting words to uniform floating point values lives in the
`random123.UnitInterval` namespace, holding upstream `u01fixedpt.h` by alias:

```zig
const x = random123.UnitInterval.closedOpen32Float(word);   // [0, 1), f32
const y = random123.UnitInterval.closedOpen64Double(word);  // [0, 1), f64
```

Each member is a plain alias of the translated C function, not a wrapper, so
upstream's arithmetic, its grid and its limits are inherited unchanged. Two
upstream properties are worth carrying into a design: each conversion maps one
already-uniform word onto a fixed grid of `2^min(M, W)` points (`M` is 24 for
`f32`, 53 for `f64`), so more resolution means slicing the word first; and the
two `closedClosed` conversions of a `u32` to `f32` and of a `u64` to `f64` ignore
the input's high bit (`u01fixedpt.h:137`, `u01fixedpt.h:156`), so their result
is not monotonic in the input. Upstream's own caveat about x87 extended
precision (`u01fixedpt.h:95-103`) is kept rather than smoothed over.

The namespace is not called `u01` because `u01` is a primitive type name in
Zig 0.16. The upstream spelling survives unchanged on the raw C escape hatch,
where the same twelve conversions are `c.r123_bridge_u01_*`.

## The raw C escape hatch

`random123.c` is a supported route, and it is the translation of **this
fork's** public header `zig/bridge/random123_bridge.h`, not of the whole
upstream tree. It carries no contract of its own beyond the declarations
themselves: it is the upstream surface under upstream's names, so a caller
reaching through it gets upstream's round-count assertion — an `assert(x)`
that vanishes under `NDEBUG` — and not the unconditional check `rounds`
performs. Use `rounds` when the bound matters.

The registered module name of this package is `random123`; `c` is an import of
that module rather than a second registered name, so a dependent reaches it as
`random123.c` and never as a top-level `@import("c")`.

The module contains:

* the upstream `r123arrayNxW` word-array structs, pulled in by
  `<Random123/array.h>` (`r123array1x32` … `r123array4x64`);
* the mirrored default round counts and the AES-NI key geometry, as plain
  integer constants — `R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS: c_int = 10`,
  `R123_BRIDGE_AESNI_KEY_WORDS: c_int = 44` in the translated module.  A
  translated C enumerator is a constant of the enumerator's promoted integer
  type, not a Zig enum, so no `@intFromEnum` is needed or wanted
  (`FORK-NOTES.md` entry 18);
* the eight `<gen>_keyinit` and eight `<gen>_R` portable wrappers;
* the twelve integer-to-floating-point conversions as `r123_bridge_u01_*`;
* `R123_BRIDGE_HAS_AESNI` and — only where this build compiled AES-NI —
  `r123_bridge_have_aesni`, `r123_bridge_aesni4x32_keyinit`,
  `r123_bridge_aesni4x32_R`, `r123_bridge_ars4x32_keyinit` and
  `r123_bridge_ars4x32_R`. `random123.has_aesni` says which.

What is deliberately **not** there: the x86 `__m128i` counter type
`r123array1xm128i`, and therefore the `aesni1xm128i` / `ars1xm128i` generators,
which upstream stores in vector registers and which the translation pins out
with `R123_USE_SSE=0`; the C++ template layer (`uniform.hpp`, `philox.hpp`, the
`r123::` CBRNG classes) on every target; `aesopenssl16x8`, which upstream
compiles only under `R123_USE_AES_OPENSSL` against OpenSSL's `AES_KEY` and
which this build never defines; and upstream's own `static __inline__` entry
points and default-round macros, which are not linkable symbols in any
translation unit and are exercised through the bridge wrappers instead.

Those paths remain reachable exactly where upstream intends: a C or C++
consumer that includes the installed `<Random123/aes.h>` and `<Random123/ars.h>`
and compiles with the AES feature the target provides gets the full AES-NI and
ARS surface, including the 1xm128i generators, with no involvement from this
fork.

```zig
const c = random123.c;                       // translated bridge surface
const block = c.r123_bridge_philox4x32_R(7, .{ .v = ctr }, .{ .v = key });
```

## The runtime-loaded configuration

`runtime_loaded` is a comptime constant, so a consumer that supports both
configurations writes two code paths and only the one it chose is analysed.

| | |
|---|---|
| `runtime_loaded` | `false` in a linked build, `true` when the build generated a dispatch. It is a build fact, like `has_aesni` |
| `LoadSource` | `.{ .path = … }` for an explicit file, `.{ .system = … }` for a name for the platform loader |
| `LoadError` | every way `load` can decline; declared here rather than only inside the loader so a caller names the failure it handles |
| `load(source)` | resolve the bridge this module dispatches to |
| `loadedSource()` | the request that succeeded, or `null` when nothing has loaded |

```zig
if (comptime random123.runtime_loaded) {
    random123.load(.{ .path = "/path/to/librandom123.so" }) catch |err| {
        std.log.err("random123: {s}", .{@errorName(err)});
        return err;
    };
}
```

The contract, as the module states it: call `load` once and then use the module
as if it were linked. Calling it again with the same request succeeds and
changes nothing; calling it with a **different** request after a success is
`ProviderMismatch`, and the provider already in use stays in use. A failed
attempt publishes nothing and is retried by calling `load` again — there is no
automatic retry and no implicit second source. There is no unload and no
reset, because the table is process-global state other code may already have
called through. `load` is safe from any thread; a thread arriving while an
attempt is in flight waits for it and gets its result, and a call from the
thread running that attempt is `ReentrantLoad` rather than a deadlock.

The two request shapes are checked against each other on purpose, and a
request that is wrong for its own field is `InvalidSource` rather than an
attempt that happened to fail: `.path` must be **absolute** and carry no NUL
byte (`runtime/loader.zig:186-194`), and `.system` must be a **bare
basename** — no separator, no drive letter (`:196-201`). Validation happens
before the loader asks whether the request is the one already in use
(`runtime/loader.zig:366`), which is why a relative `.path` is `InvalidSource`
and never `ProviderMismatch`.

In a linked build there is no provider, no table and nothing to resolve:
`load` stops the program with a message saying so rather than quietly
succeeding, and `loadedSource()` returns `null`. `runtime_loaded` is `false`
there, so a consumer that supports both tells the two apart at comptime instead
of meeting this at run time.

Under `-Druntime=true` the artifact is still built and installed — delivery and
dispatch are separate questions — because the point of the mode is that a
caller may name a provider this tree did not build. The module itself links
nothing in that configuration: linking the archive as well would let the
linker resolve the same symbols statically, and the runtime route would quietly
be a linked one.

## What is not published

`zig/kat_test.zig`, `zig/facade_test.zig`, `zig/analyze_test.zig` and
`zig/smoke.zig` ship in the manifest because the fixture they replay ships in
it too (`build.zig.zon` lists `tests/`), but none of them is a public module and
none is a supported consumer entry point. The `kat_vectors` module the build
generates for them is created with `b.createModule`, never `b.addModule`, so it
is deliberately unreachable from a dependent's build script: it exists to embed
upstream's `tests/kat_vectors` inside a module directory, and nothing in the
production graph can reach it. A consumer that wants the fixture should read
`tests/kat_vectors` out of the package; there is no second copy of those bytes
anywhere in this tree.

The AES-NI and ARS generators are published only through `c`, and only when
`has_aesni` is true. Their key is an expanded AES schedule rather than a plain
word array, which is why no `Generator` in this package wraps them.

## Commands

| Command | What it does |
|---|---|
| `zig build` | installs `librandom123` plus the upstream and bridge headers; add `-Dlinkage=dynamic` for the shared variant |
| `zig build test` | runs the known-answer and behaviour tests |
| `zig build smoke` | runs the deterministic example |
| `zig build check` | compiles the whole public facade and the example, running nothing |
| `zig build matrix` | `check` for all six required targets in one invocation; still compile-only, no target binary is executed |
| `zig build consumer` | builds and runs `consumer/`, which depends on this package by path; builds and installs instead of running when this host cannot execute the selected target |

Build options:

* `-Dtarget=…`, `-Dcpu=…`, `-Doptimize=…` — standard.
  `zig build consumer` forwards the **resolved** target, CPU and optimize mode
  to its separate invocation, each as one `-Dkey=value` argument, and *runs* the
  consumer only when `std.zig.system.getExternalExecutor` says this host can
  execute that target — natively, or through Rosetta, QEMU user mode, Wine or
  Wasmtime where the build runner was told that executor is available. For a
  target it cannot execute it asks the nested build for `install` instead, which
  is compile evidence and nothing more. `zig build test` takes no such decision:
  its run steps are unconditional and the build runner either executes them or
  fails the step and names the target. It also forwards
  `-Dlinkage` and `-Druntime` unconditionally — `false` included, so the nested
  build's own default can never be what the outer one selected — and `-Daesni`
  only when this build was given one. The target it forwards is the resolved
  one, so a `-Daesni=true` on a CPU without the feature arrives as a `-Dcpu=`
  that carries the added `+aes`, which is what makes the nested build compile
  the same wrapper set this build did. A null `-Daesni` is forwarded as **no
  argument**, not as `false` and not as this build's resolved answer: "nobody
  chose" is the dependency's own rule, and it reaches the same answer from the
  target the two forwarded arguments just handed it
  (`consumer/build.zig:35-48`).
* `-Dlinkage=static|dynamic` — which artifact is built. Default `static`, the
  package's long-standing default, unchanged. Both variants install the same 26
  upstream headers, the same bridge header and the same `random123.pc`; they
  differ only in the kind of library, and `check`/`matrix`/the nested
  `consumer/` build take the same selection. Landed in source, and
  **observed** on 2026-10-04: `zig build test smoke install` exited 0 for both
  linkages in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall, on the tree of
  that hour and again on the current graph (`21/21 steps succeeded; 10/10 tests
  passed` linked, `24/24 steps; 23/23 tests` loaded, in all eight each).
  `check` and `matrix` on `-Dlinkage=dynamic`, and the nested `consumer/` build
  on either linkage, are still `PENDING-VERIFICATION`.
* `-Druntime=true|false` — runtime dispatch, orthogonal to linkage. Default
  `false`, where every call is direct: a facade call is a call into the
  translated C declaration, which is a call into `librandom123`. `true`
  resolves the library once per process from `load(.{.path = …})` or
  `load(.{.system = …})` and routes the same native surface through a resolved
  table — no fallback, no automatic retry, and a production panic before a
  successful load in every optimize mode. **In this tree**: the option is
  declared by `b.option(bool, "runtime", …)` in `build.zig`'s `build()` and
  threaded into the facade, into `check`, into `matrix`, into the loader's own
  test and into the nested `consumer/` build; `runtime/graph.zig` is the build
  half of the route and `root.zig` publishes the API, which the next section
  documents. The published surface is `random123.runtime_loaded`, `LoadSource`,
  `LoadError`, `load` and
  `loadedSource`. The loader core is the module named `rt` in both shapes — on
  the linked facade (`addFacadeImports` in `build.zig`) and inside the generated
  dispatch and its descriptor (`runtime/graph.zig:179,205`) — so there is one
  `LoadSource` and one `LoadError` per build whichever configuration it is.
  This
  fork's own workflow runs `test`, `smoke`, `check`, `install`, `consumer` and
  every cross `check` with `-Druntime=true`.

  Status: **observed red** in all eight runtime-loaded gates between 15:09 and
  15:15 UTC on 2026-10-04 — `zig build test smoke install -Druntime=true` with
  each linkage in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall, each
  failing the same three `runtime/load_tests.zig` tests for the two reasons
  `CHANGELOG.md` entry 29 identifies and repairs. The eight linked gates over
  the same steps with `-Druntime=false` exited 0 in the same four modes,
  15:01–15:15 UTC the same day.

  **Those receipts describe the tree at that hour.** `build.zig`,
  `consumer/build.zig`, `build.zig.zon` and `verify.yml` were changed
  afterwards (`CHANGELOG.md` entry 30) and `runtime/load_tests.zig` was changed
  by the repair itself, so those sixteen runs say nothing about the graph as it
  now stands. **That graph has since been observed**: the same eight loaded
  configurations and the same eight linked ones were re-run on 2026-10-04,
  receipts `loaded-final-evidence/20261004T232823091897Z-23133/run.json` and
  `native-final-evidence/20261004T233628757747Z-69351/run.json`, every cell exit
  0, every loaded cell against this tree's own `librandom123.so`
  (`provider.kind: "own"`) with `RANDOM123_TEST_ALIEN=/lib64/libm.so.6`. What is
  still unexercised on this option is `check` and `matrix` under
  `-Druntime=true` and the nested `consumer/` build, and those stay
  `PENDING-VERIFICATION`.

  Whenever runtime dispatch is configured with `-Druntime=true`, the loader's
  own behavioural root, `runtime/load_tests.zig`, is part of `zig build test`
  on the host: `build.zig` adds it only under that option and only for a host
  target, because it opens real files and contends real threads. It needs two
  variables from the caller, and the build cannot supply either, because the
  only API for a run step's environment is `setEnvironmentVariable`, which
  takes literal strings and has no way to resolve a path
  (`Run.zig:595-598`).

  * `RANDOM123_TEST_PROVIDER` — the **absolute** path of a shared object
    exporting the `r123_bridge_*` names this build's translation declares.
  * `RANDOM123_TEST_ALIEN` — the **absolute** path of a loadable object that is
    not that bridge. It has to *open*, and it must export none of those names
    (directly or through a dependency, because the object is opened
    `RTLD_NOW | RTLD_LOCAL` and each required name is then looked up in it):
    an object that cannot open is refused as `OpenFailed` and never reaches the
    missing-symbol case. This package's own workflow resolves one on the
    machine rather than writing a path down (`.github/workflows/verify.yml`:
    `libm.so.6` from `ldconfig -p`, with a `ls` fallback).

  Neither is optional. The root stops with a message naming whichever is unset
  and skips nothing: a loader test that ran without a provider would pass while
  proving nothing.

* `-Dprefix`, `-Dlib-dir`, `-Dinclude-dir` — not provided. Installation uses
  Zig's own `--prefix`, which is what the Nix derivation passes, what
  `devenv.nix`'s `externalPrefix` resolves for the local tasks, and what this
  workflow passes: every delivery it builds, the default-step cells and the
  provider the `runtime` job loads alike, installs under `$RUNNER_TEMP` rather
  than into the checkout.
* `-Daesni=true|false` — force the AES-NI/ARS bridge on or off. Default `auto`:
  on only when the resolved target CPU advertises the `aes` feature.
  `true` on a non-x86 target is a build error, not a silent downgrade. Asking
  for it on a CPU that does not have the feature adds `aes` to the target,
  because that is what actually defines `__AES__` and therefore upstream's
  `R123_USE_AES_NI` (`features/gccfeatures.h:113-119`); the bridge then
  static-asserts the two agree. `zig build check` and `zig build matrix`
  additionally compile the AES-NI variant on every x86 target in the matrix,
  whatever the resolved CPU says, so the x86 intrinsics are type-checked even
  on a machine without the instruction.

  What the option decides is a *build* fact, visible afterwards as
  `random123.has_aesni`. It says nothing about the machine that later runs the
  binary: a build with `-Daesni=true` produces code that executes AES-NI, and
  running it on a CPU without the instruction is an illegal instruction, not a
  fallback. A program that actually calls `r123_bridge_aesni4x32_R` or
  `r123_bridge_ars4x32_R` must therefore gate on
  `c.r123_bridge_have_aesni()`, which forwards upstream's CPUID probe
  (`features/sse.h:67-72`) and is declared only alongside the wrappers
  themselves.

Cross targets are compiled by `check` and `matrix`, which execute nothing at
all. Give each cross target its own cache directory when you drive the matrix
by hand — the shared convention is `--cache-dir <cache root>/<repo>/<target>`.
`zig build consumer` starts a nested build with the same compiler that is
running this build script, and `addConsumerStep` is where that command line
lives. It passes the **resolved** `-Dtarget=`, `-Dcpu=` and `-Doptimize=`, plus
`-Dlinkage=` and `-Druntime=`, as one `-Dkey=value` argument each and `-Daesni=`
only when this build was given one. It fixes `-j8` on that nested command, the
same job count every `zig build` entry in `devenv.nix` carries: nothing can
append a `-j` to the nested build's own command line, so without one it derives
its width from the machine executing it instead of from the gate that asked for
it. `--summary all` travels with it, again as two arguments, `--summary` then
the mode: left off, the nested build reports `.failures`, which prints nothing
when nothing failed, so a passing consumer would show no steps at all in the
log that has to carry the run.

The five executor switches this build resolved (`-fwasmtime`, `-fqemu`,
`-fwine`, `-fdarling`, `-frosetta`) and `--libc-runtimes` travel with it, so the
executor that answered the `run`-or-`install` question is the one the nested
`Run` step uses. `-frosetta` gates nothing in `std.Build`; it is forwarded for
fidelity.

Both caches are forwarded, two arguments each. The local one becomes
`--cache-dir <outer cache dir>/consumer`, a subdirectory, so the nested graph
never writes the outer build's manifest directory; with the default cache
location there is no `--cache-dir` argument and the consumer uses its own
default. The global one is read as `b.graph.global_cache_root.path` — the field
is on the build's graph, so `b.global_cache_root` does not name it — and
forwarded verbatim as `--global-cache-dir <path>`, with no subdirectory, because
the global cache holds content-addressed package directories, which is what
exists to be shared, while a cache manifest belongs to one graph.

The install prefix travels when the caller named one: `--prefix` and the path
this invocation resolved, guarded on it differing from the default `zig-out`,
so a default invocation forwards no flag at all. A nested `zig build` left to
resolve its own installs into `consumer/zig-out`, a build artefact inside a
source package, and a relative prefix would resolve against the working
directory that is `consumer/` rather than against this build's root, so the
path is made absolute before it is handed on. `DESTDIR` is not forwarded: the
nested build inherits the environment this one ran with.

`zig build consumer -- --provider <path>` reaches the program. This build's
`b.args` are appended after a `--`, the nested build collects them in its own
`b.args`, and `consumer/build.zig:70` hands those to the program, which reads
`--provider` from argv (`consumer/src/main.zig:50-51`, `:57-64`). Both hops are
live, so the argument form and `RANDOM123_TEST_PROVIDER` reach the same place.

The only steps that run anything are `test`, `smoke` and `consumer`, and each
runs binaries of the selected target: `test` and `smoke` depend on their run
steps unconditionally and leave the executor question to the build runner,
which fails the step and names the target when it cannot execute one, while
`consumer` asks `hostCanExecute` first and installs instead of running. The one
exception inside `test` is the loader's own root, which runs on this machine
under no interpreter — native or Rosetta only — because it opens real files,
contends real threads and `dlopen`s a provider named by the caller.

**The nested command, as observed.** This paragraph used to document
`--cache-dir=<outer cache dir>/consumer`, one argument carrying an `=`. That is
not an alternative spelling of the option: `zig build` takes `--cache-dir` and
its path as separate arguments, and the `=`-joined token reaches the build
runner as an unrecognised `-` argument, which stops the build before the
consumer compiles — the same line `zig build -h` prints as
`--cache-dir [path]`. That repair, the cache relays, the summary, the prefix and
the argument relay have since been observed on the argument list itself, across
nine delivery cases: both linkages and both dispatch shapes, four with no
target, prefix or optional default named and four naming
`-Dtarget=x86_64-linux-gnu -Dcpu=baseline`, plus a refusal case that exited 1
and printed the message `consumer/src/main.zig` declares rather than falling
back. Every nested command carried the resolved `-Dtarget=`, `-Dcpu=`,
`-Doptimize=`, `-Dlinkage=` and `-Druntime=`, then `-j8`, `--summary all`,
`--cache-dir <outer cache dir>/consumer`, `--global-cache-dir` with the caller's
global cache and `--prefix` with the caller's prefix, and in the four loaded
cases `--provider <absolute path>` after the caller's `--`, with every provider
variable absent from the child process. `CHANGELOG.md` entries 35 and 36 record
the repairs and entry 38 the nine cases.

**One hop is still `PENDING-VERIFICATION`.** All nine were `run` hops, so what
they observe is the prefix *reaching* the nested build, not a tree that received
installed files. The check that nothing installs into `consumer/zig-out` is
`zig build consumer --prefix <dir>` against a target this host cannot execute,
which is the hop that installs.

Six-target compile matrix: `x86_64-linux-gnu`, `aarch64-linux-gnu`,
`aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi`.

`riscv64-linux-gnu` and `wasm32-wasi` are in that list and the matrix fails on
them: upstream `features/gccfeatures.h:37-45` stops the compile with `#error` on
any architecture outside x86, powerpc, arm, aarch64 and s390x, before a single
generator is declared, and nothing a user passes on the command line switches
that guard off. This fork does not edit upstream headers and does not define
`__arm__` for riscv64 to make the error go away, so both stay in the matrix as
a recorded upstream limit rather than being dropped. See `UPSTREAM.md`,
"Upstream architecture guard".

## Tests and fixtures

The known-answer test replays upstream's `tests/kat_vectors` byte for byte, and
the fixture arrives through the build: a generated root
(`pub const data = @embedFile("kat_vectors")`) sits next to a byte-for-byte
build copy of the upstream file, and the test imports that module as
`kat_vectors`. No second copy of the fixture exists in the source tree, and
none can drift from upstream. The same generated module is wired into the
native `test` step and into every `check`/`matrix` target, so one constructor
decides the bytes every KAT compile path sees. The file is one of the 102
upstream files in `UPSTREAM.sha256`, and the package ships `tests/` in its
manifest, so a packaged dependency can still build the test. The AES-NI and
ARS lines in that fixture are replayed only when the build compiled AES-NI
*and* the running CPU reports AES-NI through upstream's own CPUID probe;
`zig/kat_test.zig` does both checks.

No C++ fixture is used. `tests/ut_uniform_kat_vectors.dat` records the C++
`u01<Ftype>` / `uneg11` / `u01fixedpt` templates, which are *not* the twelve C
functions this bridge exports, and it is tied to one x86-64 IEEE reference
platform; adopting it would validate a different API and fail on other targets
(`FORK-NOTES.md` entry 17). The conversion tests instead pin exact
uniform-grid values derived from `u01fixedpt.h:136-192`.

`zig/facade_test.zig` covers what a caller relies on and cannot read off a
signature: that a generator is a pure function of counter and key even with
another generator interleaved; that a counter stream which carries into the
next word produces pairwise distinct outputs; that a single flipped counter bit
and a single flipped key bit each change the result; that the round count is a
real knob; that zero rounds is legal and returns the identity for Philox but
the counter plus the key for Threefry, which is the one place a caller is
likely to carry an assumption from one family to the other; and the uniform-grid
and high-bit behaviour of the conversions.

The round-count *refusal* has no runtime test, because it panics and there is
no `std.testing.expectPanic` at Zig 0.16 to catch it. It is covered by
compilation instead: `zig/analyze_test.zig` calls `rounds` at
`max_rounds + 1` for every published generator and for one built through
`random123.Generator`, in a file `build.zig` compiles and never runs. What that
proves is that the branch exists and type-checks; that it fires at run time in
each optimize mode is not established here.

The fixture covers round counts 7, 10, 13, 20, 32 and 72 as upstream wrote
them, so `rounds` is exercised at several counts per generator independently of
any default.

## Expected smoke output

`zig build smoke` prints the upstream known answers for an all-zero counter and
key, then a Monte Carlo pi estimate and a stream checksum. The generator lines
are fixed by `tests/kat_vectors`:

```
random123 1.14.0 (D. E. Shaw Research), Zig package
statistical and Monte Carlo use only -- NOT cryptographic
aesni bridge: not built for this target; running cpu aes-ni: unknown (wrappers not compiled)
philox2x32 rounds=10 zeros -> ff1dae59 6cd10df2
philox4x32 rounds=10 zeros -> 6627e8d5 e169c58d bc57ac4c 9b00dbd8
philox2x64 rounds=10 zeros -> ca00a0459843d731 66c24222c9a845b5
philox4x64 rounds=10 zeros -> 16554d9eca36314c db20fe9d672d0fdc d7e772cee186176b 7e68b68aec7ba23b
threefry2x32 rounds=20 zeros -> 6b200159 99ba4efe
threefry4x32 rounds=20 zeros -> 9c6ca96a e17eae66 fc10ecd4 5256a7d8
threefry2x64 rounds=20 zeros -> c2b6e3a8c2c69865 6f81ed42f350084d
threefry4x64 rounds=20 zeros -> 09218ebde6c85537 55941f5266d86105 4bd25e16282434dc ee29ec846bd2e40b
threefry2x32 stream: samples=65536 hits=… pi=….……
threefry2x32 stream checksum: ……
```

The `aesni bridge:` line reports the build; the `running cpu aes-ni:` half of
it is the separate CPUID answer, and the two can disagree — that is the whole
point of printing both. On a target where the wrappers were not compiled the
second half reads `unknown (wrappers not compiled)`, because the probe is not
declared there either. The last two lines are computed entirely in integer
arithmetic, so they are byte-identical on every conforming platform. They are
not pinned above: record the values your first run prints and compare later
runs against them. Nothing in this document is a gate result.

## Provenance

`sha256sum -c UPSTREAM.sha256` proves every carried-over upstream file is
byte-identical to tag `v1.14.0`
(`726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13`); the manifest names 102 files and
`UPSTREAM.sha256` itself travels in `build.zig.zon`'s `.paths`, so a packaged
copy can run that check. One of those 102 is upstream's README, under the name
`README.upstream.md`.

Licence: the upstream tree is BSD 3-Clause, with one file
(`include/Random123/features/pgccfeatures.h`) carrying a second notice from Los
Alamos National Security, LLC. The fork's own files are separately granted
BSD 3-Clause under the owner's authorization. `NOTICE.md` §3 is the per-file
inventory and `FORK-LICENSE.md` is the grant; neither is summarised here,
because a summary is exactly the thing that goes wrong when a tree is not
uniform.
