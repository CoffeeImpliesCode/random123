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
not to this prose: what the integrator observed is recorded in the workspace
ledger, not here. Per-finding status, including the withdrawn claims and the one
false statement kept with its refutation, lives in `FORK-NOTES.md`.

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

## The facade

Every generator is a stateless function: no allocation, no global state, no
RNG object to keep. The result is a pure function of the counter and key.

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
number. `default_rounds` is upstream's own default; `max_rounds` is the largest
count upstream accepts (`philox.h:324` asserts `R<=16`, `threefry.h:205` asserts
`Nrounds<=32`, `threefry.h:309` asserts `Nrounds<=72`). `rounds()` traps above
that instead of returning undefined results.

Per generator:

* `init(key)` — upstream's `<gen>keyinit`. For Philox and Threefry upstream
  defines it as `return uk;`, so it is the identity.
* `rounds(R, ctr, key)` — explicit round count.
* `generate(ctr, key)` — upstream's default round count.

`random123.generators` holds all eight, for bulk iteration. Walk it with `for`
or `inline for`; nothing in this package indexes it, because an inferred `.{}`
literal is walked rather than indexed everywhere the pinned standard library
uses one (`FORK-NOTES.md` entry 13).

Converting words to uniform floating point values lives in the
`random123.UnitInterval` namespace, forwarding upstream `u01fixedpt.h`:

```zig
const x = random123.UnitInterval.closedOpen32Float(word);   // [0, 1), f32
const y = random123.UnitInterval.closedOpen64Double(word);  // [0, 1), f64
```

The namespace is not called `u01` because `u01` is a primitive type name in
Zig 0.16. The upstream spelling survives unchanged on the raw C escape hatch,
where the same twelve conversions are `c.r123_bridge_u01_*`.

## The raw C escape hatch

The translated module `random123.c` is the canonical C surface of this
package, and it is the translation of **this fork's** public header
`zig/bridge/random123_bridge.h`, not of the whole upstream tree:

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

## Commands

| Command | What it does |
|---|---|
| `zig build` | installs `librandom123` plus the upstream and bridge headers |
| `zig build test` | runs the known-answer and behaviour tests |
| `zig build smoke` | runs the deterministic example |
| `zig build check` | compiles the whole public facade and the example, running nothing |
| `zig build matrix` | `check` for all six required targets in one invocation; still compile-only, no target binary is executed |
| `zig build consumer` | builds and runs `consumer/`, which depends on this package by path |

Build options:

* `-Dtarget=…`, `-Dcpu=…`, `-Doptimize=…` — standard.
  `zig build consumer` forwards the resolved target, CPU and optimize mode to
  its separate invocation, each as one `-Dkey=value` argument, and *runs* the
  consumer only for a native target; for any other target it builds it without
  running, the same as `zig build test` on a cross target.
* `-Daesni=true|false` — force the AES-NI/ARS bridge on or off. Default `auto`:
  on only when the resolved target CPU advertises the `aes` feature. `true` on a
  non-x86 target is a build error, not a silent downgrade. Asking for it on a
  CPU that does not have the feature adds `aes` to the target, because that is
  what actually defines `__AES__` and therefore upstream's `R123_USE_AES_NI`; the
  bridge then static-asserts the two agree.

Cross targets are compiled, never executed. Give each cross target its own
cache directory when you drive the matrix by hand — the shared convention is
`--cache-dir <cache root>/<repo>/<target>`. `zig build consumer` starts a
nested build with the same compiler that is running this build script, passes
`-Dtarget=`, `-Dcpu=` and `-Doptimize=` as one `-Dkey=value` argument each, and
adds `--cache-dir=<outer cache dir>/consumer` so the nested graph never writes
the outer build's manifest directory; with the default cache location there is
no `--cache-dir` argument and the consumer uses its own default. `check` and
`matrix` are compile-only for every target including the host: nothing is
executed by either. The only steps that run anything are the native `test`
runs, `smoke`, and `consumer` on a native target.

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

## Expected smoke output

`zig build smoke` prints the upstream known answers for an all-zero counter and
key, then a Monte Carlo pi estimate and a stream checksum. The generator lines
are fixed by `tests/kat_vectors`:

```
random123 1.14.0 (D. E. Shaw Research), Zig package
statistical and Monte Carlo use only -- NOT cryptographic
aesni bridge: not built for this target
philox2x32 rounds=10 zeros -> ff1dae59 6cd10df2
philox4x32 rounds=10 zeros -> 6627e8d5 e169c58d bc57ac4c 9b00dbd8
philox2x64 rounds=10 zeros -> ca00a0459843d731 66c24222c9a845b5
philox4x64 rounds=10 zeros -> 16554d9eca36314c db20fe9d672d0fdc d7e772cee186176b 7e68b68aec7ba23b
threefry2x32 rounds=20 zeros -> 6b200159 99ba4efe
threefry4x32 rounds=20 zeros -> 9c6ca96a e17eae66 fc10ecd4 5256a7d8
threefry2x64 rounds=20 zeros -> c2b6e3a8c2c69865 6f81ed42f350084d
threefry4x64 rounds=20 zeros -> 09218ebde6c85537 55941f5266d86105 4bd25e16282434dc ee29ec846bd2e40b
threefry2x32 stream: samples=65536 hits=… pi=….…… stream checksum: ……
```

The `aesni bridge:` line reads `compiled in` on a target whose CPU has AES-NI.
The last two lines are computed entirely in integer arithmetic, so they are
byte-identical on every conforming platform. They are not pinned above: record
the values your first run prints and compare later runs against them. Nothing in
this document is a gate result.

## Provenance

`sha256sum -c UPSTREAM.sha256` proves every carried-over upstream file is
byte-identical to tag `v1.14.0`
(`726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13`); the manifest names 102 files and
`UPSTREAM.sha256` itself travels in `build.zig.zon`'s `.paths`, so a packaged
copy can run that check.
