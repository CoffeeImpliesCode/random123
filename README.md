# Random123 for Zig, C and C++ — this fork

A Zig 0.16 package around [Random123](https://github.com/DEShawResearch/random123)
`v1.14.0` — a library of counter-based random number generators by John Salmon
and Mark Moraes, from D. E. Shaw Research. Upstream ships those generators as
C and C++ headers and emits **no linkable symbol at all**. This fork keeps
every one of those headers byte for byte, adds one C translation unit that turns
them into a real library with an external ABI, and wraps that in a typed Zig
module.

> **Not suitable for cryptography or security.** Upstream says so explicitly:
> these generators are for statistical applications and Monte Carlo simulation,
> and are unsuitable for cryptography "even though they are constructed using
> principles drawn from cryptography". AESNI uses the AES block cipher; ARS uses
> the AES round function with a non-cryptographic key schedule. Neither is a
> CSPRNG and neither is exported as one.

| | |
|---|---|
| Upstream | Random123 `v1.14.0`, tag `v1.14.0`, commit `726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13` |
| Upstream licence | BSD 3-Clause — `LICENSE`, and a second notice inside `include/Random123/features/pgccfeatures.h`; see `NOTICE.md` §3 |
| Fork licence | BSD 3-Clause over the fork's own files only — `FORK-LICENSE.md` |
| Integrity record | `UPSTREAM.sha256`, 102 upstream files |
| Upstream README | preserved verbatim as `README.upstream.md`; this file is the fork's |
| Zig interface documentation | [`README.zig.md`](README.zig.md) |
| Provenance | [`UPSTREAM.md`](UPSTREAM.md) · [`FORK-NOTES.md`](FORK-NOTES.md) · [`CHANGELOG.md`](CHANGELOG.md) |

This repository is **private**. That removes no upstream obligation: the
copyright notice, the conditions and the disclaimer travel with the source and
with every binary form.

---

## 1. Native-source deviations from upstream

**None.** No file under `include/`, `tests/`, `examples/` or `docs/` is edited,
reformatted, ported or replaced, and neither is `LICENSE` or `GNUmakefile`.
`UPSTREAM.sha256` covers all 102 of them and `sha256sum -c UPSTREAM.sha256` is
the check.

Three upstream files outside those trees are not carried over unmodified, and
none of them is source:

| Upstream file | What happened | Why |
|---|---|---|
| `.gitignore` | upstream's entries kept verbatim; three Zig entries appended | so an ordinary `zig build` does not contaminate the tree |
| `.travis.yml` | deleted | it built on travis-ci.org, which is shut down; running another maintainer's CI is not this fork's business |
| `README.md` | carried as `README.upstream.md`, byte for byte (same SHA-256) | this file is now the fork's README, so upstream's text had to move somewhere it stays exact and machine-checkable |

The `GNUmakefile` is kept unmodified and is **not used** by this package, so
upstream's `docs/main.md` rule — which strips HTML comments out of `README.md`
into a doxygen mainpage — now points at this file rather than at upstream's
text. Nothing here runs that rule: there is no doxygen in the build, no `make`
step, and `docs/main.md` (which upstream's `.gitignore` also lists) stays
absent. Anyone who wants upstream's generated mainpage has it in
`README.upstream.md`, which is the file upstream's own comment describes.

Every algorithm this package computes is upstream's, evaluated by upstream's own
code. The only C this fork writes is `zig/bridge/random123_bridge.c`, which
contains no arithmetic: each wrapper is a single call to the upstream
`R123_STATIC_INLINE` function, on the upstream `r123arrayNxW` types.

Two preprocessor values are selected by the build rather than by an edit, and
both are upstream's own documented user overrides:

* `-DR123_USE_MULHILO64_C99=1` on architectures where upstream would otherwise
  have no 64×64→128 multiply and would drop `philox2x64`/`philox4x64`. The
  result is identical and the multiply is slower.
* `R123_USE_SSE=0` for the **translate-C step only**, never for the compiled
  library. `features/sse.h` declares `haveAESNI()` with GNU inline assembly,
  which has no Zig representation; the compiled bridge keeps the real value and
  the real AES-NI code.

## 2. Native-build deviations from upstream

Upstream has no build system in this package: its `GNUmakefile` is retained as
source and is not used. Random123 is header-only, every algorithm is
`static __inline__`, and every default-round entry point is a preprocessor
macro, so the upstream tree produces nothing a linker could resolve. This fork
therefore owns the entire build graph (`build.zig`), and it does the four
things a header-only package can usefully do:

1. **Compile the genuine headers into a library with an external ABI.**
   `zig/bridge/random123_bridge.c` includes upstream's headers verbatim and
   defines 28 unconditionally exported functions — 8 `keyinit` forwarders,
   8 generator forwarders (`philox{2,4}x{32,64}`, `threefry{2,4}x{32,64}`), 12
   `u01fixedpt` conversions — plus 5 more under the AES-NI gate:
   `r123_bridge_have_aesni`, `aesni4x32_keyinit`, `aesni4x32_R`,
   `ars4x32_keyinit`, `ars4x32_R`. All 33 are functions: the bridge defines no
   data symbol, so nothing in this ABI has to be reached by its address. That is
   a real, useful C ABI, and it is packaged like any other library rather than
   exempted because upstream is header-only: `-Dlinkage=dynamic` builds the
   shared variant of the same bridge beside the static default, and both install
   the same 26 upstream headers plus the bridge header. §3 records the status of
   those options in this migration.
2. **Install upstream's whole public surface verbatim** — all 26 headers under
   `Random123/`, `.h` and `.hpp` alike, including the ones this package does
   not compile, such as `features/pgccfeatures.h` — plus the bridge header.
3. **Translate the public C surface for Zig** and add a typed, allocation-free
   facade over the eight portable generators and the twelve conversions.
4. **Refuse to build where upstream refuses to build**, loudly and in the open
   (see §3).

Other deviations, all recorded with their source lines in `FORK-NOTES.md`:

* **AES-NI is a target CPU feature, not a `-maes` cflag.** Upstream gates
  `aes.h` and `ars.h` on `R123_USE_AES_NI`, which `features/gccfeatures.h:113-119`
  derives from `__AES__`, and `__AES__` describes the target CPU. Zig's driver
  does not turn a `-maes` cflag into one, so the build adds the `aes` feature to
  the target query instead, and `random123_bridge.c` static-asserts that
  `R123_USE_AES_NI` really is 1 wherever the wrappers are declared. `-Daesni`
  defaults to "whatever the resolved target CPU advertises"; `-Daesni=true` on a
  non-x86 target is a build error, not a silent downgrade. The headers are
  installed on every target regardless.
* **The `1xm128i` generators are not bridged.** `aesni1xm128i` and
  `ars1xm128i` take and return `__m128i`, which cannot cross a portable
  boundary; they stay reachable from C and C++ through the installed upstream
  headers, unchanged.
* **Round counts above the upstream maximum are an unconditional error.**
  Upstream's `R123_ASSERT` is compiled out under `NDEBUG`; the Zig facade's
  check is not. It only ever fires on input upstream leaves undefined.
* **`riscv64-linux-gnu` and `wasm32-wasi` are not supported**, by upstream's
  own guard, and the matrix still attempts them.

### Dated history

[`CHANGELOG.md`](CHANGELOG.md) is the numbered, re-sync-stable record of every
divergence in this tree — never renumber an entry. Entries 1–26 are the
pre-migration work: the Zig package itself (3), the preprocessor selections (4,
5), AES-NI gating (6, 24), the consumer package (7), the verification workflow
(8), the provenance records (9), the upstream architecture guard (23), and the
API contract alignment of **2026-10-03** (26).

Entries 27 through 31, all dated **2026-10-04**, are this migration. Entry 27
is the canonical README order, the licence grant over the fork's own files and
the standalone Nix and devenv packaging. Entry 28 is the build surface the
same migration landed: `-Dlinkage`, the installed pkg-config and licence
closure, the manifest paths, and the CI changes that follow from the README
relocation; two of its claims were later refuted by the tree and are corrected
in place, with the correction dated. Entry 29 is the loader test that was
asserting a refusal the loader had already produced for a different reason.
Entry 30 is the consumer forwarding that made the consumer prove a
configuration nobody selected. Entry 31 is this documentation: the runtime
route that was documented as absent while it was in the tree, the lock file
that was documented as absent while it was on disk, and the licence inventory
that had never heard of `runtime/`.

## 3. Build / run / test matrix

Six compile-only targets, as required, and none of them is quietly dropped. The
middle column is this package's own six-row `check` / `matrix` step, which
compiles and links and runs nothing; the right column is what the independent
53-cell `cross-test` cohort observed on the same graph.

| Target | six-target `check` / `matrix` | 53-cell `cross-test` |
|---|---|---|
| `x86_64-linux-gnu` | compiles; native `test`, `smoke` and `consumer` also *run* here | **runs and passes** — `x86_64-linux`, 9 tests |
| `aarch64-linux-gnu` | compiles, never executed | **runs and passes** — `aarch64-linux`, 9 tests |
| `aarch64-macos-none` | compiles, never executed | builds, never executed — `aarch64-macos`, `build_only` |
| `x86_64-windows-gnu` | compiles, never executed | builds, never executed — `x86_64-windows`, `build_only` |
| `riscv64-linux-gnu` | **fails**, inside upstream's guard | **fails at the same guard** — `riscv64-linux`, `build=fail` |
| `wasm32-wasi` | **fails**, inside upstream's guard | **fails at the same guard** — `wasm32-wasi`, `build=fail` |

`build_only` means compiled and never executed: no emulator is assumed and no
target binary runs in `check` or `matrix`. The six-row step's own receipt
(`baseline-random123-matrix`, below) names all six triples and prints no test
count, so it is compile evidence for every row it lists.

Commands: `zig build` (install), `zig build test`, `zig build smoke`,
`zig build check` (compile-only), `zig build matrix` (all six targets in one
invocation), `zig build consumer`. `zig build` consumes no network and
`build.zig.zon` declares no dependencies.

**Why the last two fail.** `include/Random123/features/gccfeatures.h:37-45`
ends every architecture outside x86, powerpc, arm, aarch64 and s390x with an
`#error`. Every Random123 header reaches it, so it fires before a single
generator is declared, and no `-D` value switches it off — upstream says
reaching it means porting the library. This fork does not edit an upstream
header and does not define `__arm__` for riscv64 to make the error disappear.
The two targets stay in the matrix as a recorded limit instead of being dropped;
dropping them would report coverage this package does not have. Upstream's
headers are still installed verbatim, so a consumer who does the port is blocked
by nothing here. See `UPSTREAM.md`, "Upstream architecture guard".

**Evidence, stated precisely.** `CHANGELOG.md` entries 25 and 26 record the
observed results of the *previous* wave, run before this migration changed the
build graph: with Zig 0.16.0 on native Linux x86-64, the tests, the
known-answer smoke and the consumer passed, and the matrix compiled four targets
with RISC-V and WASI blocked by the guard above. Those receipts stay in this file
as history about an earlier build graph.

**What has been observed since, on the current graph.** Four driver gates, each
with its own receipt. The 53-cell cohort is the source-bound one: its receipt
records `source_stamp_before == source_stamp_after` (`2d72c0a7…`), with
`target_jobs 8`, `jobs_per_build 8` and this package's own profile deadlines.

| Gate | Result |
| --- | --- |
| native eight cells — `test smoke install`, static × dynamic crossed with Debug, ReleaseSafe, ReleaseFast, ReleaseSmall, `-Druntime=false` | observed pass, exit 0 in all eight — `Build Summary: 21/21 steps succeeded; 10/10 tests passed`, `tests_skipped 0` |
| own-loaded eight cells — the same eight configurations with `-Druntime=true`, `RANDOM123_TEST_PROVIDER` naming this tree's own `librandom123.so` (`provider.kind: "own"`) and `RANDOM123_TEST_ALIEN=/lib64/libm.so.6` | observed pass, exit 0 in all eight — `Build Summary: 24/24 steps succeeded; 23/23 tests passed` |
| 53-cell `cross-test` cohort | **observed, exit 1** — raw `pass=3 fail=24 build_only=26 partial=0`; corrected `pass 3 / build_only 26 / build_fail 15 / runtime fail 9` |
| compile-only `zig build matrix` baseline, six triples | **observed, exit 1** — `Build Summary: 45/58 steps succeeded (4 failed)`, `declared_target_count 6`, all six named, `failing_step_lines 19`, `test_pass_lines: []` |

Receipts: `native-final-evidence/20261004T233628757747Z-69351/run.json`,
`loaded-final-evidence/20261004T232823091897Z-23133/run.json`,
`20261004T221720228710Z-45046/random123-53-target-8.json`, and row
`baseline-random123-matrix` of `baselines-and-configs/20261005T014547Z-797a73f2`.
The cohort's counts are bounded to that epoch and cover nothing that landed
after it.

**The three runtime passes are three passes of nine tests, not ten.**
`random123-kat` declares `if (comptime !random123.has_aesni) return
error.SkipZigTest;` — `zig/kat_test.zig:180` and `runtime/load_tests.zig:329` are
the two sites the receipts name — and QEMU user-mode does not present AES-NI, so
every executed 53-cell reports `random123-kat 2 pass, 1 skip (3 total)` beside
`random123-facade 7 pass (7 total)`, and the harness records `tests=9`. The
host-native cells run all ten because this host has AES-NI. "3 pass" in that
table therefore means nine of ten tests, and no row of it is a full-suite result.

**The fifteen build failures are one upstream header gate.** Every one of them
stops at `include/Random123/features/gccfeatures.h:38`,
`#error "This code has only been tested on x86, powerpc and a few arm
platforms."`, followed by `:39`'s
`#include <including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_file>`
— the header's own way of stopping a compiler that ignored the `#error`. The cells
are `hexagon-linux`, `loongarch64-linux`, `mips-linux`, `mipsel-linux`,
`mips-netbsd`, `mipsel-netbsd`, `mips64-linux`, `mips64el-linux`,
`mips64-openbsd`, `mips64el-openbsd`, `riscv32-linux`, `riscv64-freebsd`,
`riscv64-linux`, `riscv64-openbsd` and `wasm32-wasi`. This is a native upstream
boundary; no `-D` reaches it and nothing in this fork edits an upstream header.
The same header ends the six-row `matrix` baseline's two failing triples,
`riscv64-linux-gnu` and `wasm32-wasi`, which is the only reason that baseline is
red.

**The nine runtime failures are in the known-answer replay and in the
32-bit-word split, and they are two shapes, not one.** Both shapes are below
Random123's own `include/Random123/philox.h`, reached through
`zig/bridge/random123_bridge.c`.

* **Five cells: the raw-C replay is wrong and the facade route is green.**
  `arm-linux`, `armeb-linux`, `thumb-linux`, `thumbeb-linux` and
  `aarch64_be-linux` each report `random123-kat 1 pass, 1 skip, 1 fail` and
  `random123-facade 7 pass (7 total)`. The failing test is
  `kat_test.test.the raw C keyinit and round wrappers replay upstream's known
  answers` at `zig/kat_test.zig:351`. `arm-linux` and `armeb-linux` read
  `expected 1601156873, found 4259204590`; `thumb-linux` and `thumbeb-linux` read
  `expected 1601156873, found 2741130706` — the same expected vector and a
  different wrong value, so the miscomputation is not endianness;
  `aarch64_be-linux` mismatches earlier in the file at
  `expected 628766323, found 928378366`.
* **Four cells: both routes are wrong, and two of them also crash.**
  `powerpc64-linux` and `powerpc64le-linux` each report `random123-kat 0 pass,
  1 skip, 2 fail`, and the two failing tests — the facade known-answer test and
  the raw-C replay — report **identical** expected/found pairs
  (`628766323`/`3441868330` and `3441868330`/`4020305955`), which is what rules
  the Zig dispatch layer out: two independent call routes agreeing puts the
  miscomputation below the bridge. Their facades also crash three tests with
  `Assertion failed: R<=16 (…/philox.h: philox4x64_R: 359)`.
  `powerpc-linux` and `s390x-linux` each report `random123-kat 0 pass, 1 skip,
  2 crash` and `random123-facade 2 pass, 5 crash`, with
  `Segmentation fault at address 0x0` at
  `zig/bridge/random123_bridge.c:89:25 in philox2x32_R` and at
  `include/Random123/philox.h:349` in `philox2x32keyinit`
  (`_philoxNxW_tpl(2, 1, 32, uint32_t)`), and, on `s390x-linux`,
  `Assertion failed: R<=16 (…/philox.h: philox2x32_R: 349)`.

The common ingredient on the 32-bit cells is `_mulhilo_c99_tpl(32, uint32_t)`,
the word-splitting C99 multiply selected at `philox.h:188` from the template at
`:139-160`. On the 32-bit cells above, `mulhilo32` goes through that path; the
three passing 53-cell cells (`x86_64-linux`, `aarch64-linux`, `x86-linux`) do not.
That is the observed shape, and this record does **not** claim a cause the logs
cannot settle: whether it is the upstream header as compiled or the emulation
layer below it is not something these receipts decide.

### Build options

| Option | Effect | Status |
|---|---|---|
| `-Dlinkage=static\|dynamic` | which artifact is built: the static archive (the default, unchanged) or the shared object of the same bridge. `check`, `matrix` and the nested `consumer/` build take the same selection | landed in source, and **observed on the current graph**: `test smoke install` at `-Druntime=false` exits 0 for both linkages in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall, and the same eight configurations at `-Druntime=true` exit 0 against an own `librandom123.so`. The six-row `matrix` baseline above ran the default static selection only; `-Dlinkage=dynamic` on `check` and `matrix` is `PENDING-VERIFICATION`, as is the nested `consumer/` build on either linkage |
| `-Druntime=true\|false` | runtime dispatch, orthogonal to linkage: `false` (the default) calls the translated C declarations directly, `true` resolves the library once per process and routes the same native surface through a resolved table — `random123.load(.{.path = …})` or `load(.{.system = …})`, no fallback, no automatic retry, a production panic before a successful load in every optimize mode. The published surface is `random123.runtime_loaded`, `LoadSource`, `LoadError`, `load` and `loadedSource`; [`README.zig.md`](README.zig.md) documents each | **in this tree, and now observed.** `build.zig`'s `build()` declares the option with `b.option(bool, "runtime", …)` and threads it into the facade, into `check`, into `matrix`, into the loader's own behavioural root and into the nested `consumer/` build; `runtime/graph.zig:143,166` supplies the dispatch module; `root.zig:142,160,166,192,208` publishes the API. The eight loaded gates were **observed red** on 2026-10-04 on the tree of that hour, for the two reasons `CHANGELOG.md` 29 names; after that repair and the later build-graph change, the same eight configurations are **observed green** — `24/24 steps succeeded; 23/23 tests passed` each, against an own `librandom123.so`. What is still `PENDING-VERIFICATION` for this option is the nested `consumer/` build and `check`/`matrix` under `-Druntime=true` |
| `-Dprefix`, `-Dlib-dir`, `-Dinclude-dir` | not provided. Installation goes through Zig's own `--prefix` | n/a |

The runtime option is neither pending nor excluded. The option, the graph
module, the dispatch and the published API are all in this tree, and this
fork's own workflow already runs `test`, `smoke`, `check`, `install`,
`consumer` and every cross `check` with `-Druntime=true`
(`.github/workflows/verify.yml`). It is now also observed: eight loaded cells,
one per optimize mode crossed with both linkages, all exit 0 with
`24/24 steps succeeded; 23/23 tests passed`, against this tree's own shared
object named by absolute path and `/lib64/libm.so.6` as the alien provider.
What remains outstanding is named per row above and below — `-Dlinkage=dynamic`
on `check` and `matrix`, the nested `consumer/` build, and every packaging route.

`-Dlinkage` and `-Druntime` have both now been exercised against the build graph
as it stands, linked and loaded, in all four optimize modes and both linkages,
over `test smoke install`. The earlier hour's sixteen runs — linked exit 0,
runtime exit 1 for the two reasons `CHANGELOG.md` entry 29 records — stay in
this file as history about that hour's tree. The packaging routes below — the
Nix derivation, the flake and the devenv shell — are integrator gates that no
run in this repository has observed.

The devenv shell's `consumer` script is the one gate in that set that has been
run *and* has failed: acceptance run `20261004T193710Z` exited 1 on
`unrecognized argument: '--cache-dir=…/consumer'`, printed by the nested
`consumer/` build because it was handed its cache directory in a spelling
`zig build` does not accept. `CHANGELOG.md` entry 34 records the cause, the
two-token repair, and the fixed `-j8` that command now carries to match the one
every script body in `devenv.nix` already writes. That command line has grown
since: entry 35 adds `--summary all`, the outer global cache and the caller's own
arguments behind a `--`, and entry 36 hands the nested build this invocation's
`--prefix`, so its install hop writes where the caller asked rather than into
`consumer/zig-out`. All of it is `SOURCE-CONFIRMED`, and the first two now have
a passing run: acceptance run `20261004T214134Z`, gate `devenv:consumer`,
exit 0 after 7.524s from a scratch project directory with both cache
directories exported, where the nested build printed
`Build Summary: 6/6 steps succeeded` and then `run exe random123-consumer
`success`. Entries 35 and 36 are observed on the argument list itself: nine
delivery cases pass across both linkages and both dispatch shapes, in each of a
default and an explicit target, with the prefix propagated to the nested build
and `--provider` reaching the program while every provider variable is absent
from the child. **`PENDING-VERIFICATION`** for one thing: every one of those
nine was a `run` hop, so nothing yet observes where an install hop writes — that
check is `zig build consumer --prefix <dir>` against a target this host cannot
execute. The Nix `packages.*` gate stays unobserved; the devenv run recorded it
under `gates_not_run` as `nix:build`.

## 4. Consumption

Four supported routes. A fifth — a system-library mode — is deliberately
absent, and the last subsection says why.

### Zig module

```zig
// build.zig.zon
.dependencies = .{
    .random123 = .{ .path = "../random123" },
},
```

```zig
// build.zig
const random123 = b.dependency("random123", .{
    .target = target,
    .optimize = optimize,
}).module("random123");
exe.root_module.addImport("random123", random123);
```

The module already links the compiled artifact and carries the translated C
declarations. `random123.c` is the raw translated surface. The typed facade is
documented in [`README.zig.md`](README.zig.md). `consumer/` is a runnable
end-to-end example of exactly this.

### C and C++

```c
#include <Random123/philox.h>       /* upstream, unmodified  */
#include <random123_bridge.h>      /* this fork's C surface  */

philox4x32_ctr_t r = philox4x32(c, k);                   /* upstream macro  */
philox4x32_ctr_t s = r123_bridge_philox4x32_R(10, c, k); /* linked symbol   */
```

Include the installed `Random123/` tree, link `random123`, and call either
spelling: upstream's inline functions and macros, or this fork's exported
forwarders. The C ABI is documented in the installed `random123_bridge.h`;
struct-by-value returns use upstream's `r123arrayNxW` layouts, which
`random123_bridge.c` static-asserts against `sizeof`.

### Nix

`package.nix` is one source-only derivation, consumed by both `flake.nix` and
`devenv.nix`:

```sh
nix build .#packages.x86_64-linux.static     # the repository default linkage
nix build .#packages.x86_64-linux.shared
nix build .#packages.x86_64-linux.default    # same as .static
```

The build graph installs the library (`librandom123.a`, or the shared object
under `packages.<system>.shared`), all 26 upstream headers, the bridge header,
`lib/pkgconfig/random123.pc`, and the licence and provenance records under
`$out/share/licenses/random123/`. It does not carry generated HTML
documentation, the upstream example programs, the upstream test programs or any
tool: the HTML needs Doxygen at build time, and the other two are the source
tree, which upstream's own `make install` copies rather than this package
building.

Every Nix build passes `-Dcpu=baseline`, so the artifact does not inherit the
CPU of whichever machine built it; the AES-NI wrappers are compiled only when a
packager asks for them (`aesni = true;`, paired with `-Daesni=true`). Nothing is
downloaded at build time — the sources are these files. `flake.lock` is in this
tree and pins nixpkgs to the same revision `flake.nix:11` names
(`c7def046b9a883d46974757852106483d741586f`, `narHash`
`sha256-6RSEDHIWQtesQKWSu5qRai8L2h4KgCgMEfJHstW99G4=`, lock format 7);
`devenv.lock` is still the integrator's to write, and `devenv.yaml` names its
input by revision instead, so no digest here is invented. Nix copies a Git work
tree as its tracked files, so the packaging and provenance files have to be
committed before a flake build can see them.

`static` means a static library artifact. No wholly-static-executable claim is
made.

One consequence worth stating, so the missing symbols are not reported as a
defect: a baseline x86_64 CPU has no `aes` feature, and `resolveAesniTarget`
defaults AES-NI to `isX86(target) and cpuHasAes(target)`. A Nix build therefore
compiles the 28 common bridge symbols only — `r123_bridge_have_aesni`,
`aesni4x32_keyinit`, `aesni4x32_R`, `ars4x32_keyinit` and `ars4x32_R` are absent
from the artifact, and the generated Windows export list names the same 28.
`aesni = true;` adds the feature back to the target and those five with it.

### Development shell

`devenv` is the canonical environment; `.envrc` and `devenv.nix` are in this
tree and `devenv.yaml` pins its nixpkgs input.

```sh
devenv shell                          # tools only; building the SDK is not a price of admission
devenv shell test                     # or build / install / smoke / check / matrix / consumer / provenance
devenv shell install                  # delivery tree beneath the caller's cache directory, never in this tree
devenv shell build                    # the same: the default step is the install step
devenv build outputs.static           # the packaging route, same package.nix as the flake
devenv build outputs.shared
```

The shell pins Zig 0.16.0 and asserts it. `outputs.*` are lazy: entering the
shell realises nothing. There is no `nix develop` devShell, so the toolchain
version is decided in one place.

Every script changes to this SDK's own directory first. That path is the
module's own `./.`, read out of the file that declares it, so it is this
checkout and never the directory the caller happened to be standing in —
`devenv` materialises each script as a generated shell program that inherits
the caller's working directory, so the path belongs in the exec body and not
in a per-entry option. `$DEVENV_ROOT` is the project directory the shell was
entered from, not this checkout. `devenv shell -- consumer` and
`devenv shell -- provenance` therefore find `consumer/build.zig` and
`UPSTREAM.sha256` whatever the caller's cwd is.

`devenv shell install` and `devenv shell build` put their delivery tree outside
the checkout — `build` counts because Zig's default step *is* the install
step. A prefix passed to `install` as the first argument wins; with none passed
both sit beneath the Zig local cache directory the caller exported —
`ZIG_LOCAL_CACHE_DIR`, then `XDG_CACHE_HOME`, then `TMPDIR` — and with none of
those exported the script says so and exits rather than write into a working
tree that may be on a volume mount. One shared helper holds that precedence,
so the two cannot drift apart. `test`, `test-release-safe`, `smoke`, `check`,
`matrix` and `provenance` take no prefix: they compile or run, and install
nothing. `consumer` takes none either, because `addConsumerStep` hands the
nested build this invocation's `--prefix` itself whenever the caller named one,
and without a named prefix the nested build resolves its own under the
`consumer/` directory. This file names no host path and invents no location.

### System-library mode: there is none, and that is a decision

A header-only library installs no binary, so a "system Random123" is just a
directory of headers. There is no installed ABI for a system mode to bind to
and nothing for it to select, so `b.systemIntegrationOption` is not declared.
The fork's compiled bridge is the one thing here that has external linkage, and
it is this package's own artifact: an installed upstream Random123 exports none
of its symbols. This is recorded by design, not by an observed failure.

## Provenance and licence in one place

* `README.upstream.md` — upstream's README, byte for byte.
* `UPSTREAM.md` — the pin, the import mechanism, the integrity record, what the
  bridge covers and why, and every platform limit.
* `UPSTREAM.sha256` — 102 digests; `sha256sum -c UPSTREAM.sha256`.
* `NOTICE.md` — the per-file licence inventory, including the second notice in
  `include/Random123/features/pgccfeatures.h`.
* `FORK-LICENSE.md` — the owner's authorization and the BSD 3-Clause grant over
  this fork's own files, and the SPDX identifier other files carry.
* `FORK-NOTES.md` — the issues actually encountered, each citing the source line
  that produced it, including the ones that were later withdrawn.
* `CHANGELOG.md` — the numbered divergence record, safe to re-sync against a new
  upstream tag.