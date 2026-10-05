# CHANGELOG — fork-only divergences

Upstream release history lives in the upstream repository and in
`docs/releasenotes.dox`. This file records **only** what this private fork
changed relative to Random123 `v1.14.0`
(`726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13`). Numbers are stable identifiers for
re-sync; never renumber them.

## 1. Removed upstream `.travis.yml`

Upstream CI targeted travis-ci.org, which is shut down. This fork does not run
another maintainer's CI infrastructure, so the file is deleted rather than
pointed somewhere else. No upstream source file is affected.

## 2. Appended three entries to `.gitignore`

Upstream's ignore list is preserved verbatim; `.zig-cache/`, `zig-cache/` and
`zig-out/` are appended so ordinary `zig build` runs do not contaminate the
source tree. `.gitignore` is therefore the one upstream file this fork edits,
and it is deliberately excluded from `UPSTREAM.sha256`.

## 3. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `root.zig` and `zig/`. New module
`random123`, new static artifact `random123`. No upstream header or source
file is touched.

* `zig/bridge/random123_bridge.{c,h}` compile the upstream headers into a
  library with external linkage. Upstream is header-only and emits no
  linkable symbol, so this bridge is what makes the algorithms reachable; each
  wrapper is a one-line forwarder, not a reimplementation.
* `zig/generator.zig` + `root.zig` add a typed, allocation-free Zig facade for
  Philox2x32/4x32/2x64/4x64 and Threefry2x32/4x32/2x64/4x64, plus the
  upstream `u01fixedpt` conversions. `pub const c` keeps the full translated C
  surface reachable.
* Round counts above the upstream maximum trap instead of returning garbage.
  Upstream's `R123_ASSERT` is compiled out under `NDEBUG`; the facade's check
  is unconditional. This is a deliberate divergence and it only ever fires on
  input upstream leaves undefined.

## 4. Preprocessor selection where upstream has no 64x64→128 multiply

`-DR123_USE_MULHILO64_C99=1` is defined on architectures where upstream would
otherwise have no 64x64→128 multiply and would drop `philox2x64`/`philox4x64`.
This is upstream's documented user override; results are unchanged, the
multiply is slower. See `UPSTREAM.md`.

This entry was written before the architecture guard below was understood: the
two contract targets that motivated it, riscv64 and wasm32, are refused by
upstream before any multiply is chosen (entry 23). The override stays, for any
other target a packaged dependency is built for.

## 5. Translated view pinned to the portable array types

`R123_USE_SSE` is defined to `0` for the `addTranslateC` step only.
`include/Random123/array.h` unconditionally includes `features/sse.h`, which on
x86 declares `haveAESNI()` with GNU inline assembly — something `@cImport`'s
successor cannot represent. The compiled bridge keeps the real value and the
real AES-NI code. See `UPSTREAM.md`.

## 6. AES-NI and ARS are compiled only where the target CPU has them

New `-Daesni` option, defaulting to whatever the resolved target CPU
advertises. On a baseline cross target it is off; the headers remain installed
and reachable from C and C++. The compile matrix compile-checks the AES-NI
path for x86 regardless, by adding the `aes` feature to that copy of the
target — see entry 24.

## 7. Added `consumer/`

A separate package depending on this one by path through
`b.dependency("random123", …).module("random123")`, verifying that downstream
consumers need nothing beyond the module.

## 8. Added the verification workflow

`.github/workflows/verify.yml`: native tests in Debug and ReleaseSafe, the
deterministic smoke example, the consumer package, the six-target compile
matrix, and a provenance gate (`sha256sum -c UPSTREAM.sha256` plus a diff
against the pinned upstream tag).

## 9. Added `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-NOTES.md`,
`README.zig.md`

Provenance, licence attribution, fork notes, and Zig usage. The upstream
`README.md` is untouched; `README.zig.md` is the fork's usage entry point.

## 10. The `u01` conversion namespace is `random123.UnitInterval`

`pub const u01` in `root.zig` was renamed to `pub const UnitInterval`.
`u01` is a primitive type name in Zig 0.16, so `pub const u01 = struct { … }`
does not compile (`error: name shadows primitive 'u01'`); the fork had never
been compiled far enough to see it. `@"u01"` would have suppressed the
diagnostic without fixing anything, and a deprecated alias would leave two
names for one thing, so the rename is a clean cutover: every caller —
`zig/facade_test.zig`, `zig/analyze_test.zig`, `consumer/src/main.zig` — and
`README.zig.md` now say `random123.UnitInterval`, and nothing keeps the old
name. All twelve conversions and all eight generators are unchanged.

The upstream spelling is untouched where it is a C identifier: the bridge
declarations are still `r123_bridge_u01_*`, reachable through `pub const c`.

## 11. `consumer/build.zig` no longer takes the address of a `*Build.Step`

`b.step("run", …)` already returns a `*Build.Step`, and
`Step.dependOn(step: *Step, other: *Step)` wants that pointer, so
`&step.step` did not compile (`error: no field named 'step' in struct
'Build.Step'`). The call is gone: the custom `run` step depends on the run
step directly, and the install step is no longer made to depend on `run`.
`b.installArtifact(exe)` already puts the executable in the default build, and
an ordinary `zig build` must not *run* it. `zig build run` is unchanged.

## 12. The round-count trap uses `std.debug.panic`, not a two-argument
     `@panic`

`@panic` takes a single message in Zig 0.16 — the compiler's builtin table
gives `@panic` a parameter count of 1 and rejects anything else with
`expected 1 argument, found 2` — so the formatted round-count trap in
`zig/generator.zig` now calls `std.debug.panic`. Same message, same
noreturn; the difference is that it compiles. The behaviour described in
entry 3 is unchanged.

## 13. Generator widths come from `@typeInfo`, not from indexing a type

`word_bits`, `counter_bits` and `key_bits` in `zig/generator.zig` were derived
with `spec.counter[0]` and `spec.counter.len`. `counter` and `key` are array
types, so both operations are undefined. They now read the `array` payload of
`@typeInfo`, through a helper that rejects a non-array spec with a message
naming the generator and checks that the counter and key use the same word
type. The published widths are the same numbers as before.

## 14. The documented example now quotes a known answer that is actually true

`root.zig` and `README.zig.md` both showed a `Philox4x32` example whose
commented output was upstream's answer for a *zero* key while the code passed
`{0xd82c07cd, 0x629f6fbe}`, a key that appears nowhere in the Random123 tree.
Both now use the counter and key of `tests/kat_vectors:29` with the output that
line records, and cite the line. `UPSTREAM.sha256` is also added to
`build.zig.zon` `.paths`, so a packaged tree can run the `sha256sum -c` that
`README.zig.md` tells it to run.

## 15. Two documentation claims that overreached were narrowed

`has_aesni` is documented as true "only when the selected target CPU actually
provides AES-NI", which is false when `-Daesni=true` forces the wrappers on.
It now says the flag can force them on and that anything executing those
generators must also probe `c.r123_bridge_have_aesni()` at run time, as
`zig/kat_test.zig` does. Separately, `R123_BRIDGE_ARS4x32_MAX_ROUNDS = 10` was
removed from `zig/bridge/random123_bridge.h`: it was public, had no consumer,
and no upstream macro to mirror, so it was the one entry the header's
"every constant is static-asserted" claim did not cover. The claim is now
scoped to the constants that are, and the AES key word count is called out as
asserted by size.

Note for whoever reads the tree next: an earlier build left
`zig-out/include/random123_bridge.h` on disk, and that copy still contains
`R123_BRIDGE_ARS4x32_MAX_ROUNDS`. It is gitignored build output, and only
`zig build` (not `zig build test`) rewrites it, so `rm -rf zig-out` before
treating any installed header as current.

## 16. `zig build consumer` forwards the resolved target, CPU and optimize mode

`consumer/` is a separate `zig build` invocation, so only command-line
arguments cross the boundary. `-Doptimize` is now forwarded, so
`zig build consumer -Doptimize=ReleaseSafe` really checks the consumer's known
answers in ReleaseSafe instead of silently using the consumer's own default.
The target and CPU are forwarded too, as `-Dtarget=` and `-Dcpu=`, built from
`Target.Query.zigTriple` and `Target.Query.serializeCpuAlloc` — the same two
functions `standardTargetOptions` uses to report this build's own target, so
the sub-build parses exactly what was resolved.

A non-native target now only *builds* the consumer, invoking its `install`
step instead of `run`; a native target still runs it. *(Amended later the same
day: the choice is no longer `isNative`. `addConsumerStep` asks
`hostCanExecute`, which is `std.zig.system.getExternalExecutor`, so a foreign
target this host can execute — including one an executor the build runner was
told to use can run — runs, and one it cannot installs. `test` decides nothing:
its run steps are unconditional, and the build runner executes them or fails
the step and names the target.)* Previously the sub-build
ignored the outer target entirely, so `zig build consumer -Dtarget=<foreign>`
quietly built and ran a host binary.

## 17. Compile and behavioural coverage gaps closed

The eight `r123_bridge_*_keyinit` wrappers are compiled, installed and
translated but nothing called them, so their signatures were never
type-checked; `zig/analyze_test.zig` now calls all eight with keys of the
upstream widths, which puts them in the `check` gate without adding a run.
Four of the twelve `UnitInterval` conversions asserted only a maximum word;
they now also pin the zero word, and both `openOpen` 32-bit variants pin an
interior grid point, so a change to a shift, a scale or an offset in
`u01fixedpt.h` is caught rather than only a change at the top of the domain.

## 18. One `UnitInterval` expected value was off by a factor of two

`zig/facade_test.zig` compared `openOpen32Double(0xffffffff)` against
`8589934591 / 2^34`. `u01fixedpt.h:190-192` returns `(0.5 + i) * 2^-32`, which
at `i = 0xffffffff` is `8589934591 / 2^33`; the denominator was wrong by a
factor of two and the test would have failed at run time. The correct value is
in place, with its derivation written next to it. All twelve conversions were
re-derived from `u01fixedpt.h` during the same review and this was the only
incorrect one.

## 19. The known-answer dispatch selects a block instead of `continue`

`zig/kat_test.zig` picked the generator with a runtime name comparison and a
`continue` inside `inline for`, which is a compile-time jump reached from a
runtime branch:

```
error: comptime control flow inside runtime block
```

The comparison now selects a block inside the unrolled loop. Nothing else in
that test changed: the same fixture bytes, the same eight generators, the same
per-word comparison.

## 20. The known-answer tests now count generators, not fixture lines

The portable test ended with `checked > 0`, which any non-empty fixture
satisfies, so a generator dropped from the dispatch table or from the facade
would have gone unnoticed while the other seven still replayed. It now keeps one
counter per generator and fails naming whichever one contributed nothing. The
AES-NI/ARS test counts the two families separately for the same reason: four
AES-NI lines alone used to be enough to pass a test named for both.

## 21. Documentation corrections, and the copies of them

* The translated enumerators were described as `c_uint` in `FORK-NOTES.md`
  entry 18 and in `README.zig.md`. The generated module says otherwise:
  `R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS: c_int = 10` and
  `R123_BRIDGE_AESNI_KEY_WORDS: c_int = 44`, while the enum *type* alias is
  `c_uint`. Both are integers, so no code changes; the prose in both files is
  corrected and entry 18 keeps the refutation.
* `NOTICE.md`, `UPSTREAM.md` and `README.zig.md` stated "Copyright 2010–2016 D.
  E. Shaw Research". No file in the tree says that: `LICENSE` says "Copyright
  2010-2012" and the individual upstream headers say "Copyright 2010-2011".
  The three files now quote the years the files actually carry.
* `UPSTREAM.md` described the fork's work as already sitting on `main` on top of
  the tag. At the time of writing it was still in the working tree, so the
  sentence now describes the change set rather than the branch, and a `Remotes`
  row records that `origin` still points at the upstream and has to be
  repointed at the private downstream before the first push.
* `README.zig.md` called `random123.generators` "the tuple of all eight". It is
  an inferred `.{}` literal, and `FORK-NOTES.md` entry 13 records that the fork
  has deliberately never depended on whether the compiler makes that a tuple or
  a struct. The prose now says to walk it, which is what every call site does.

## 22. The keyinit compile gate now uses what each wrapper returns

`zig/analyze_test.zig` called the eight `r123_bridge_*_keyinit` wrappers and
discarded the result. Discarding a call still type-checks its parameters but
says nothing about its *return* type, so a wrapper that returned the wrong
upstream key struct would have compiled. Each wrapper's returned key is now
handed to a real generation with that generator's facade type, which checks the
return type as well and keeps the external symbol in the linked test binary.
No assertion is added: this file is a compile gate and is never run.

## 23. riscv64 and wasm32 fail in the matrix, because upstream refuses them

`zig build matrix` attempts all six contract targets, and it fails on
`riscv64-linux-gnu` and `wasm32-wasi`. The reason is upstream's:
`include/Random123/features/gccfeatures.h:37-45` ends every architecture
outside x86, powerpc, arm, aarch64 and s390x with

```c
#  error "This code has only been tested on x86, powerpc and a few arm platforms."
```

Every Random123 header reaches that guard — `array.h:34` includes
`features/compilerfeatures.h`, which picks a feature header by compiler, and
`clangfeatures.h:91` includes `gccfeatures.h` outright — so the guard fires
before a generator is declared and the C99 multiply of entry 4 never gets a
chance to matter. Observed on both targets, in the C library and in
`addTranslateC` alike:

```
Random123/features/gccfeatures.h:38:4: error: "This code has only been tested on x86, powerpc and a few arm platforms."
Random123/features/gccfeatures.h:39:10: error: 'including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_task' not found
```

It is an `#error` inside the header the compiler selection reaches, not a
value the caller supplies, so no `-D` symbol reaches it. Upstream says so
itself at `features/gccfeatures.h:41-44`: reaching it means porting the
library. The three ways to make the build green were all rejected: editing an
upstream header is forbidden, a "port" is not this fork's to ship, and
defining `__arm__` for riscv64 or `__aarch64__` for wasm32 would be a lie
about the target that upstream has no way to detect and no reason to believe.

So the two targets keep failing in the matrix rather than being dropped from
it, and the limit is recorded in `UPSTREAM.md` ("Upstream architecture guard")
and `FORK-NOTES.md` instead of being designed around. Nothing else changed: the
same upstream headers are still installed verbatim, so a consumer who does the
port is blocked by nothing here.

## 24. AES-NI is enabled with a target CPU feature, not a `-maes` cflag

`zig build matrix` also failed the AES-NI variant of both x86 targets, with
17 errors on `x86_64-linux-gnu` and `x86_64-windows-gnu`: `aesni4x32_key_t`,
`aesni4x32keyinit`, `ars4x32keyinit` and friends were all undeclared, because
`aes.h:40` and `ars.h:38` wrap their contents in `#if R123_USE_AES_NI` and that
resolved to 0. The build passed `-maes`, which is what upstream documents and
what gcc and clang honour, and it changed nothing: `__AES__` describes the
target CPU, and Zig's driver does not turn a `-maes` cflag into one. The
library would have linked with no AES-NI code in it while the installed header
still declared the wrappers.

`build.zig` now adds the `aes` feature to the target query — the same
mechanism `-Dcpu=baseline+aes` uses — whenever the AES-NI path is compiled,
and returns a target that already has the feature untouched, so a native build
on an AES-capable host is not retargeted for nothing. `random123_bridge.c`
static-asserts that `R123_USE_AES_NI` is 1 wherever `R123_BRIDGE_HAS_AESNI` is
defined, so the two gates can never disagree silently again. `-maes` stays on
the compile line: it documents the intent, and it is upstream's spelling.

## 25. Correct the integrity digest for upstream's symlink

`tests/gencl.sh` is upstream's link to `../examples/gencl.sh`. The manifest
had hashed the Git link text, but `sha256sum --check` follows the link and
hashes its target bytes. Corrected the digest without changing either upstream
file. The complete manifest and pinned-tree diff now pass.

Observed with Zig 0.16.0: eight native tests in Debug and ReleaseSafe, all
eight known-answer smoke cases, and the independent consumer pass. The six-target
matrix compiles four targets, including Windows AES-NI; RISC-V and WASM remain
blocked by upstream's architecture guard.


## 26. Zig API contract alignment — 2026-10-03

**Condition.** Built-in generators are stateless counter/key functions;
a user-supplied callback need not share their purity or concurrency contract.
Compiled AES entry points do not establish runtime CPU support.

**Fix.** State compile-time word/count/callback coercion requirements without
excluding legitimate generic callbacks, unconditional round-range errors,
AES wrapper and CPU obligations, no-entropy/non-cryptographic behavior and
supported module/raw routes. Keep native inherited tests distinct from the
fork's facade tests; correct smoke-output and grid-frequency citations.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
tests in all four modes, known-answer smoke, package consumer and module
example pass. A separate consumer accepts a generic two-word callback.
Compile-only `matrix` builds four targets; RISC-V and WASI fail the unchanged
native architecture guard. No unsupported CPU execution, system-provider or
foreign runtime result is claimed. Native and generated bytes are unchanged.

## 27. Foundation contract migration: canonical README, licence grant, Nix and
     devenv packaging — 2026-10-04

Documentation and packaging only. No upstream file changed, no algorithm
changed, and no native test was run: every result below is
`PENDING-VERIFICATION` for this tree.

**README relocation.** `README.md` was upstream's README, byte for byte, and is
now the fork's own document in the canonical order: current native-source
deviations (none), current native-build deviations plus dated history, the
build/run/test matrix, then consumption. Upstream's exact bytes moved to
README.upstream.md — the same 19,698 bytes, the same
`71a51dfa922bee8352ba5500ec97ab80875c712dc759528e8fc5ec5b1fd0b28f` — and
`UPSTREAM.sha256:19` now carries that path instead of `README.md`. The record
count is unchanged at 102; only a name moved. Upstream's README was not edited
and not deleted. The Zig interface documentation stays in `README.zig.md`, now
linked from both READMEs instead of being the only entry point.

**Licence.** The owner authorized a per-project licence for the fork's own
files, matching primary upstream terms. This package takes **BSD 3-Clause**
(`SPDX-License-Identifier: BSD-3-Clause`), copyright 2025-2026
CoffeeImpliesCode contributors, recorded with that authorization in
`FORK-LICENSE.md`. It covers the fork's files only and attributes nothing to
upstream. `NOTICE.md` was rewritten around a per-file inventory (§3) instead of
one package-wide statement, because the tree is not uniform:

* `LICENSE` says "Copyright 2010-2012"; the headers say 2010-2011;
  `features/clangfeatures.h` says 2010-2016;
* `include/Random123/features/pgccfeatures.h` carries a **second notice** at
  lines 33-44 — `Copyright (c) 2013, Los Alamos National Security, LLC`, under
  U.S. Government contract `DE-AC52-06NA25396`, with its own conditions
  including "modified software should be clearly marked". It is selected only
  under `__PGI` (`features/compilerfeatures.h:219-220`), so this package never
  compiles it — and installs it anyway, which is why the notice has to be
  recorded.

`UPSTREAM.md` also corrected two claims of its own: it said the manifest held
111 records when it holds 102, and its Copyright row implied one uniform notice
across the upstream tree.

**Packaging.** `package.nix` is one uncurried derivation taking injected
`lib`/`stdenv`/`zig` plus `linkage`, `optimize`, `target` and `aesni`. `src` is
this directory filtered of build and development state; nothing is fetched, no
sibling workspace is imported, no host path appears. Its one phase puts both Zig
caches under `$TMPDIR` and runs a single `zig build install -j"$NIX_BUILD_CORES"
--prefix "$out" -Doptimize=… -Dcpu=baseline -Dlinkage=…`. It installs nothing
itself: `build.zig` is the one writer of every installed path, including the
licence records and `random123.pc`.

`flake.nix` exposes `packages.<system>.static` and `.shared` from that one
derivation, `default` passing no `linkage`, so it reproduces this package's
static default. `devenv.nix` is the tools-only canonical environment with lazy
`outputs.static`, `outputs.shared` and `outputs.default` calling the same
`package.nix`; `devenv build outputs.static` is the packaging route and entering
the shell realises nothing. The SDK package is not in the shell's `packages`.

`-Dcpu=baseline` is passed on every Nix build so the artifact does not inherit
the builder's CPU features, which is why `aesni` defaults to `false`. "static"
means a static *library* artifact; no wholly-static-executable claim is made.

`flake.lock` and `devenv.lock` are the integrator's to write, and both inputs
are named by revision instead, so no digest in this tree is invented:
`github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` for
the flake, `github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737`
for the shell.

**Corrected 2026-10-04, entry 30.** This paragraph originally read "`flake.lock`
and `devenv.lock` are absent by design" and called `flake.lock` absent. That is
refuted by the tree: `flake.lock` is present and pins nixpkgs to the revision
`flake.nix:11` names. `devenv.lock` is still absent. The sentence above is the
corrected text; `README.md` §4 and `README.zig.md` were corrected with it.

## 28. Build surface for the same migration: `-Dlinkage`, installed closure,
     and the README relocation in CI — 2026-10-04

The build-graph half of the migration, landed alongside entry 27. Source only:
no build, test, cross check, formatter or installer has been run over it, so
every claim below is `SOURCE-CONFIRMED` from the files and every verification
field is `PENDING-VERIFICATION`.

* `-Dlinkage=static|dynamic`, declared as
  `b.option(std.builtin.LinkMode, "linkage", …)`. The default is `.static` with
  no flag, so `zig build` produces exactly what it produced before this entry,
  and `packages.<system>.default` in `flake.nix` reproduces that default by
  passing nothing. The selection is threaded into `addBridge`, into `addCheck`
  (so `check` and `matrix` compile the selected shape rather than always the
  static one) and into the nested `consumer/` build, so a compile gate cannot
  pass on one shape while the artifact is the other.
* `zig build install` now publishes `lib/pkgconfig/random123.pc` alongside the
  library and the header tree: `prefix=${pcfiledir}/../..`,
  `Libs: -L${libdir} -lrandom123`, `Cflags: -I${includedir}`, version read from
  `build.zig.zon`, no `Requires:`, and the same file for both linkages. The
  library needs libc and nothing else — the twelve `u01fixedpt` conversions are
  integer arithmetic with no libm, and the only libc call in the bridge is the
  `memcpy` of the AES-NI key expansion — so an absent `Requires:` is a fact
  about the code, not an omission.
* `zig build install` publishes `share/licenses/random123/` with `LICENSE`,
  `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md` and `README.upstream.md`. There
  is no `LICENSE.fork`: `FORK-LICENSE.md` section 3 carries the fork grant
  verbatim and is the fork licence file.
* **`-Druntime` was not in the tree when this entry was written. It is now.**
  *Corrected 2026-10-04, entry 30.* The runtime dispatch option is
  `-Druntime=true` (bool, default `false`), orthogonal to linkage, and it is
  declared and wired: `build.zig:171-179` declares it, `:188`, `:317`, `:331`
  and `:340` thread it, `:286-302` add the loader's own behavioural root to
  `test` under it, `runtime/graph.zig:166` supplies the dispatch module and
  `root.zig:142,160,166,192,208` publish `runtime_loaded`, `LoadSource`,
  `LoadError`, `load` and `loadedSource`. The original text of this bullet
  said the module "lands after the BLAKE3 pilot's verification"; that is
  withdrawn, and `README.md` §3 and `README.zig.md` no longer repeat it.
  The option remains orthogonal to linkage and off by default, which is
  unchanged and still true.
* No `-Dprefix`, `-Dlib-dir` or `-Dinclude-dir`. Installation goes through
  Zig's own `--prefix`, which is also what `package.nix` passes.
* `build.zig.zon` `.paths` gained `README.upstream.md`, `FORK-LICENSE.md`,
  `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` and
  `.gitignore`, so a fetched package still carries its own provenance records
  and packaging files. `devenv.lock` stays out: it is the integrator's to
  write, and `.github/` is not package content. (`flake.lock` was named here
  as absent too; see the correction in the packaging paragraph of entry 27.
  Its owner added it to `.paths` later the same day, for the same reason
  `.envrc` is there: a fetched copy carrying `flake.nix` without its lock
  re-resolves against the network on first evaluation. `devenv.lock` is the
  one lock file deliberately left out, and it is genuinely absent.)
* `.gitignore` gained `.devenv/`, `.direnv/`, `/result` and `/result-*`,
  appended below upstream's entries, which are untouched.
* `.github/workflows/verify.yml`: the required-file list gained
  `FORK-LICENSE.md`, `README.upstream.md`, `package.nix`, `flake.nix`,
  `devenv.nix` and `devenv.yaml`; the `v1.14.0` pinned-tree diff no longer
  lists `README.md`, and a new `cmp README.upstream.md <(git show
  v1.14.0:README.md)` states the relocation directly instead of relying on the
  diff alone; the native matrix gained build-shared, test-debug-shared,
  smoke-shared, check-shared and consumer-shared rows; and every cross target
  now also runs `zig build check -Dlinkage=dynamic`.
* `build.zig`, `build.zig.zon` and `consumer/build.zig` carry
  `SPDX-License-Identifier: BSD-3-Clause` and
  `Copyright 2025 CoffeeImpliesCode contributors.` — the year these files
  already had, matching the grant recorded in `NOTICE.md` §2 and
  `FORK-LICENSE.md` §3. No upstream file gained an SPDX line, and no
  package-wide `.license` field was added to `build.zig.zon`: the tree carries
  a second notice inside `include/Random123/features/pgccfeatures.h` and one
  label does not describe it.

## 29. One loader test asked for a request the loader had already refused —
     2026-10-04

The runtime-loaded route failed in all eight loaded gates, in two independent
ways, and neither one is a loader change. Every claim below is
`SOURCE-CONFIRMED` from the files and the parent receipt; every verification
field is `PENDING-VERIFICATION`.

* `runtime/load_tests.zig` expected `ProviderMismatch` from a request it built
  as `"./" ++ providerPath`. That spelling is not absolute, and `Loader.load`
  validates a request before it asks whether the request is the one already in
  use (`runtime/loader.zig:366`), so it was refused as `InvalidSource` at
  `runtime/loader.zig:194` — the run reported `expected error.ProviderMismatch,
  found error.InvalidSource`. The comparison the test exists to observe was
  never reached. The alternate request is now the provider's own path with a
  `.` component inserted after the root: still absolute, still the same file
  under POSIX pathname resolution, and a different byte sequence, which is the
  property under test. The loader's precedence is unchanged and is asserted in
  its own right by the test above it, which pins `InvalidSource` for a
  relative `.path` and for a `.system` request carrying a separator.
* The two missing-symbol cases need `RANDOM123_TEST_ALIEN`, and the driving
  harness exported only `RANDOM123_TEST_PROVIDER`, so both tests stopped in
  `alienPath` before the loader was asked anything. Nothing here skips when
  that variable is unset — a missing-symbol test with nothing to refuse would
  pass while proving nothing — and the build cannot resolve a path for itself,
  so the caller must export it. The requirement is now stated where it is
  read: the root's module comment says both variables are inherited rather
  than set, and its panic message says an *absolute* path, that the file has to
  open, and why a file that cannot open would exercise `OpenFailed` instead.
  `README.zig.md` records both variables for the runtime test route. The
  recipe is this package's own workflow: `libm.so.6` located with `ldconfig -p`
  on the machine rather than written into a file
  (`.github/workflows/verify.yml`), which this host's cache lists as
  `/lib64/libm.so.6`.

No loader rule moved: one process-lifetime immutable table, a failure that
publishes nothing, a retry the caller makes, no fallback, and the linked build
still direct. No upstream or native byte changed and no required symbol was
dropped. The repaired test asserts the same error it asserted before, on a
request that now reaches the comparison.

## 30. The consumer proved a configuration nobody selected — 2026-10-04

**Condition.** `zig build consumer` is a separate `zig build` invocation, so
only its command line crosses the boundary. `-Daesni` decides a *delivery*
fact — `resolveAesniTarget` feeds `addBridge`, so the wrappers compiled into
the installed artifact depend on it — and the outer build was forwarding only
`-Dtarget`, `-Dcpu`, `-Doptimize`, `-Dlinkage` and `-Druntime`.

**Symptom.** Two defects of one kind, both `SOURCE-CONFIRMED` from the build
graph. The nested build received no `-Daesni` at all, so
`zig build consumer -Daesni=true` ran a consumer compiled with
`aesni = false` — the consumer proved a configuration nobody selected. And the
target it *was* forwarded was the unresolved one, not
`build_target.target`, so the `aes` CPU feature that `withX86Aesni` adds for
the `-Daesni=true` case was missing from the forwarded `-Dcpu=` string as
well: two independent reasons the nested build could not have compiled the
wrapper set the outer one built.

**Fix.** `addConsumerStep` takes the `?bool` aesni selection and passes
`build_target.target` (`build.zig:340`, `:713-746`). `-Daesni` is forwarded
**only when the outer build was given one**, as no argument at all when it was
not: `false` would be a decision, and the outer build's resolved answer would
be a decision the dependency never made. A null is dropped by the consumer's
own `b.option` on the way in, so "nobody chose" stays the dependency's own
rule — "follow the target CPU" — and that rule then reads the same target the
two forwarded arguments just handed it (`consumer/build.zig:35-48`).
`consumer/build.zig` declares the option as nullable for the same reason; it
copies in no default, because copying one would make the two builds disagree
about the wrapper set on every host whose CPU carries AES-NI.

`.github/workflows/verify.yml` gained one cell: `consumer -Daesni=true`, in
the native job only. It is deliberately **not** in the `runtime` job: that job's
provider is built with `-Dcpu=baseline`, which carries no `aes` feature and so
exports none of the five AES-NI/ARS symbols, and a runtime consumer with those
wrappers would ask for names the named provider does not have.

`build.zig.zon` `.paths` gained two root paths that were missing:
`cross-test.profile.sh`, the 53-platform matrix profile, and `flake.lock`.
The lock is listed for the reason `.envrc` already is — a fetched copy
carrying `flake.nix` without it re-resolves against the network on first
evaluation — and `devenv.lock` is the one lock deliberately left out, because
it does not exist. `verify.yml` gained `flake.lock` to its required-fork-file
loop for the same pairing; `cross-test.profile.sh` was deliberately left out
of that list, which covers licence and provenance records plus the packaging
layer, not gate configuration. **Both additions change the package hash**: any
recorded `zig fetch` identity for this package is stale, and the final identity
is derived once after source and documentation freeze rather than per edit.

No upstream or native byte changed, no loader rule moved, and no build option
changed default. Everything here is `SOURCE-CONFIRMED` from the files;
`PENDING-VERIFICATION`, because no gate has run over it — with one exception,
the null-`-Daesni` case, which acceptance run `20261004T214134Z` exercised:
gate `devenv:consumer` passed no `-Daesni`, so no argument was forwarded, and
the nested build compiled the AES-NI wrappers from the CPU it was handed.

## 31. Three documentation claims that the source refuted, and a licence
     inventory that was missing the runtime route — 2026-10-04

Documentation only: `README.md`, `README.zig.md` and `NOTICE.md`. No build,
test, cross check, formatter or installer was run over it, so every claim
below is `SOURCE-CONFIRMED` from the files it cites and every verification
field is `PENDING-VERIFICATION`.

* **The runtime route was documented as absent, in the direction the rules
  forbid.** `README.md` §3 and `README.zig.md` said `-Druntime=true` was "not
  in this tree yet", that it needed "the runtime graph module, which lands
  after the BLAKE3 pilot's verification", and that "the only thing missing is
  the module it dispatches through". All three were false against the tree:
  `build.zig:171-179` declares the option, `:188`, `:317`, `:331` and `:340`
  thread it, `:286-302` add the loader's own behavioural root to `test` under
  it, `runtime/graph.zig:166` is the `createModule` they call, and
  `root.zig:142,160,166,192,208` publish `runtime_loaded`, `LoadSource`,
  `LoadError`, `load` and `loadedSource`. The fork's own workflow had been
  running `test`, `smoke`, `check`, `install`, `consumer` and every cross
  `check` with `-Druntime=true` against a real provider. The status cells now
  say what is in the tree and, separately, what the integrator observed: eight
  runtime-loaded gates red on 2026-10-04 for the two reasons entry 29 names,
  eight linked gates over the same steps green. Those sixteen ran between
  15:01 and 15:15 UTC, and `build.zig`, `build.zig.zon`, `consumer/build.zig`
  and `verify.yml` were all changed after them, so they are receipts about the
  tree of that hour and not a result for the tree as it stands. A capability
  declared pending that is in the tree is the specific error direction
  AGENTS §2 rule 1 forbids, and the most-consulted table in the fork README
  was the place it stood.
* **The published runtime API was undocumented.** `README.zig.md` named
  `load` only inside the `-Druntime` bullet and never documented
  `runtime_loaded`, `LoadSource`, `LoadError` or `loadedSource` at all. A new
  section, "The runtime-loaded configuration", gives each one its contract:
  the process-lifetime table, `ProviderMismatch` on a second *different*
  request, an explicit retry after a failure, `InvalidSource` for a relative
  `.path` or a `.system` carrying a separator, `ReentrantLoad`, and the
  `null` answers in a linked build. It states the validation order —
  `runtime/loader.zig:366` validates before it compares — because that order is
  what entry 29's repaired test exists to observe, and re-pinning the test to
  the earlier refusal would destroy it.
* **`flake.lock` was documented as absent and is present.** `README.md` §4,
  `README.zig.md` and entry 27 above all said `flake.lock` and `devenv.lock`
  were "the integrator's to write". `flake.lock` is in the tree and pins
  nixpkgs to the revision `flake.nix:11` already named. The documentation now
  records what the file says, including its `narHash` and lock format, because
  a revision written down and a revision a lock file carries are the same
  claim and only one of them is checkable. `devenv.lock` is still absent and is
  still the integrator's to write. `flake.lock` was not in `build.zig.zon`
  `.paths` when this entry was written; its owner added it the same day, for
  the reason entry 30 gives. That file is not this role's, so the change is
  recorded here and was not made here.
* **The licence inventory did not name the runtime route.** `NOTICE.md` §2
  listed the build graph, the facade and the bridge and stopped there. Seven
  fork files were missing from the per-file inventory this workspace requires:
  `zig/provider.zig` and the whole of `runtime/` — `loader.zig`, `library.zig`,
  `graph.zig`, `generate.zig`, `sync.h`, `sync.c`, `load_tests.zig` — plus
  `flake.lock`. They are now rows, each with what it is. The inventory also
  records which of them repeat a `Copyright` line under the SPDX identifier
  and which carry the identifier alone, because a table that reports a notice
  a file does not carry is not an inventory.

Nothing here changed a command, an option, a default or a gate result. Where
these documents previously said nothing had been exercised, they now say
what was observed on 2026-10-04 and, separately, that the six-target `matrix`
and the packaging routes remain unobserved. The historical receipts in
entries 25 and 26 are unchanged and are still history about an earlier build
graph.

## 32. The translated view was the GCC view on every target, and two families
     could not be translated at all — 2026-10-04

**Condition.** `zig translate-c` reads this package's bridge header with Aro,
and Aro preprocesses as well as parses. On `powerpc`, `powerpc64` and
`powerpc64le` the translation failed outright, and on every NetBSD target it
failed on `_Pragma`; the compiled bridge, the C archive and `zig cc` were
green on those same cells, so the defect was in the translation front end and
not in the library, the headers or the toolchain.

**Cause.** `include/Random123/features/compilerfeatures.h:215-218` selects
`clangfeatures.h` on `__clang__` and `gccfeatures.h` on `__GNUC__`. Aro
defines `__GNUC__` and does not define `__clang__`, so *every* target's
translated view of Random123 was the GCC view while the compiled bridge is the
Clang view — and on two families that is a build failure:

* `include/Random123/features/gccfeatures.h:47-49` is
  `#if defined(__powerpc__) && !defined(__clang__)` followed by
  `#include <ppu_intrinsics.h>`. The GCC-only branch is taken precisely
  *because* the front end is not Clang, and it is taken unconditionally, so a
  target whose 64x64 multiply comes from elsewhere still reaches the include.
  That guard exists because `gccfeatures.h:249-261` defines
  `__mulhdu`/`__mulhwu` inline under `defined(__clang__)` and only the GCC path
  expects them from a system header. Clang preprocesses the same headers for
  the same target without trouble, which is exactly the reported asymmetry.
* NetBSD spells `__END_DECLS` as `_Pragma` framing, and Aro destringizes each
  operator invocation into a `#pragma` line it then hands to the parser as C.
  Every system header this package reaches closes a declaration block with it:
  `<stdint.h>` from the bridge header, `<stddef.h>` from `array.h:43`,
  `<assert.h>` from `gccfeatures.h:68`.

Aro could not simply be told it was Clang. `clangfeatures.h` calls
`__has_feature` at `:44`, `:48`, `:65` and `:69`, and Aro answers no
`__has_feature` either, so a `-D__clang__=1` would trade one failure for
another and, worse, would be a false claim about the front end.

**Change.** `build.zig` gains the target-Clang-preprocessing-before-Aro
routing that `erfa` and `utf8proc` already use in this workspace:
`translationRoute` picks the front end per target family and
`preprocessedBridgeHeader` runs `zig cc -E -dD` for the target being built,
on the same `include/` root and with the same three macros
(`R123_USE_SSE=0`, and `R123_USE_MULHILO64_C99=1` / `R123_BRIDGE_HAS_AESNI=1`
exactly when `addBridge` puts them on the translation line), then hands
`zig translate-c` what came out. `-MD`/`-MF` records the twenty-six upstream
headers this step actually reached as its own inputs, so a later revision of
`include/Random123/array.h` cannot be served from the run cache against a stale
translation.

`-dD` is what preserves the macro surface: Random123's own `R123_*` defaults
are object-like `#define`s that no declaration in the bridge header uses, so a
plain dump would leave `pub const c` without them.

The route also carries the compiler's own `__int128_t`/`__uint128_t` typedefs
ahead of the header, under `__SIZEOF_INT128__`. Clang declares those next to
the `__int128` primitive and no libc header repeats them, so `-dD` keeps a
spelling nothing in the expansion defines; `generic-netbsd/arm/cdefs.h:62-63`
names one (`__ALIGNBYTES` is `(sizeof(__int128_t) - 1)` on the
`__ARM_PCS_AAPCS64` branch). `erfa`, `utf8proc`, `lmdb` and `pcre2` each carry
the same four lines for the same reason. This package's translation root is
`zig/bridge/random123_bridge.h`, a file whose body this role does not own, so
the declaration is force-included with `-include` rather than written at the
top of the header.

**What did not change.** No upstream byte. No native header edit, no
predefine invented for any architecture, no option, default, step, wrapper,
constant or fixture removed, and no arch guard relaxed: `riscv64` and `wasm32`
still fail on `gccfeatures.h:37-45` exactly as entry 23 records, and the
remaining unsupported-architecture cells stay unsupported. The published
aggregate macro surface, all eight portable generators, the AES-NI/ARS family
and the upstream `tests/kat_vectors` fixture are untouched on both routes; only
the front end that reads the bridge header changes.

`SOURCE-CONFIRMED` throughout, from the files each claim cites.
`PENDING-VERIFICATION`: no gate has run over this. `zig build matrix` and the
53-cell `test` matrix over the powerpc and NetBSD families are the checks.

## 33. Every `devenv` script body ran in the caller's directory — 2026-10-04

**Condition.** The canonical environment is entered from outside the checkout:
`devenv --from path:<sdk> …` with the working directory set to a scratch
project directory, so `.devenv/`, `devenv.lock`, the autolock and the profile
cache stay off this repository and off its volume mount. That is the shape
the acceptance driver uses and it is correct; nothing here asks for it to
change.

**Symptom.** In the acceptance run `20261004T175328Z`, `devenv:consumer`
exited 1 with `error: no build.zig file found, in the current directory or
any parent directories`, and `devenv:integrity` exited 1 with `sha256sum:
UPSTREAM.sha256: No such file or directory`. Both names exist and both were
found in the observed catalogue; the bodies are what failed.

**Cause.** Every script in `devenv.nix` was a bare `zig build …` or
`sha256sum -c UPSTREAM.sha256`, which resolves against the caller's working
directory. devenv materialises tasks and scripts as generated shell programs
that inherit it, and the scratch project directory holds `.devenv/` and
`devenv.lock` and nothing else — no `build.zig`, no `consumer/`, no
`UPSTREAM.sha256`. A per-entry `cwd` option would not reach the generated
shell program, and `$DEVENV_ROOT` is that scratch project rather than this
checkout.

**Change.** `devenv.nix` binds `sdkRoot = builtins.toString ./.` — a path
literal relative to the file that names it, converted with `builtins.toString`
rather than interpolated so the result is this working tree and not a
read-only store copy of the whole SDK — and all nine script bodies begin
`cd "${sdkRoot}"`. Script names are unchanged: `build`, `install`, `test`,
`test-release-safe`, `smoke`, `check`, `matrix`, `consumer`, `provenance`.
`consumer` and `provenance` are the two the driver runs and both stay put.
`README.md` §4 states the same contract.

**The delivery prefix.** `install` defaulted `--prefix` to `$PWD/zig-out`,
which with the new `cd` would be this repository's own `zig-out/`. `build` had
the same hole by a shorter name: Zig's default step *is* the install step —
`build.zig:266` calls `b.installArtifact` on the bridge, so the headers,
`random123.pc` and the licence records all land there — and a bare `zig build`
writes `zig-out/` into the checkout. Both bodies now resolve `--prefix` through
one shared shell function, `externalPrefix`, so there is a single copy of the
precedence: a prefix the caller passed (`install` only — that argument is this
SDK's `install` API), else `$ZIG_LOCAL_CACHE_DIR/random123-install`, else
`$XDG_CACHE_HOME/random123/install`, else `$TMPDIR/random123-install`, and with
none of the three exported the script prints what it needs and exits non-zero
rather than choose a location. `install` still forwards the remaining caller
arguments.

The workflow reached the same hole by a third route, and it is closed there too.
`.github/workflows/verify.yml` ran the `native` job's build step with no
`--prefix`, so the three matrix cells whose `flags` name no step — `build`,
`build-shared` and `install-runtime`, since Zig's default step is the install
step — wrote `zig-out/` into the checkout; and its `runtime` job passed
`--prefix "$PWD/provider"`, which is that same tree under another name. Both
now install under `$RUNNER_TEMP`, the runner's own directory outside
`$GITHUB_WORKSPACE`, and the three `RANDOM123_TEST_PROVIDER` exports name that
same absolute path through `${{ runner.temp }}`. The cells that do name a step
take no prefix, for the reason in the next paragraph. No job, step, target or
option other than the added `--prefix` changed.

The other seven bodies carry no `--prefix`. They depend on compile and run steps
only — `addConsumerStep`'s `consumer` step and `consumer/build.zig:77` each take
just `&run.step` — so a prefix there would change nothing this graph delivers,
and their intermediates go to the cache that `ZIG_LOCAL_CACHE_DIR` already places
outside the checkout. Every body now writes a literal `-j8` and names an explicit
`--cache-dir "${cacheDir}"` rather than leaving either to the environment.
Nothing reads `NIX_BUILD_CORES`, which is whatever derivation happens to be in
front of a given caller, so the same command would otherwise take a different
job count in different callers. The named directory is
`$ZIG_LOCAL_CACHE_DIR/random123`, spelled once in `devenv.nix`; the preamble
fills that variable from the caller's own value, else from `XDG_CACHE_HOME`,
else from `TMPDIR`, and refuses rather than choose one. Naming it on the
command line is what puts every entry on this workspace's per-repository cache
convention, which a bare environment-derived path does not give. `--summary all`
is unchanged.

*(Amended after entry 34: this paragraph previously said `-j` still honours
`NIX_BUILD_CORES` and that the bodies carried no `--cache-dir`. Both were true
of `devenv.nix` when entry 33 was written and are false of it now. The
`build.zig:1014` reference became `build.zig:1037` because entry 34's edit
lengthened that function; `consumer/build.zig:77` is unchanged.)*

**What did not change.** No upstream byte. No `build.zig`, generator, KAT
fixture, API surface or architecture guard was touched; `devenv.yaml` and
`package.nix` are unchanged. `riscv64` and `wasm32` are still refused by
upstream in `matrix`, for the reason entry 23 records.

`OBSERVED`, by both checks named here. Acceptance run `20261004T214134Z`:
gate `devenv:integrity` exit 0 after 0.46s and gate `devenv:consumer` exit 0
after 7.524s, each entered as `devenv shell --from path:<sdk> …` from a scratch
project directory, so both bodies found the files they name relative to this
checkout — `UPSTREAM.sha256`, and `consumer/build.zig`. Receipts in
`…/nix-acceptance-evidence/20261004T214134Z/`. Bounded: those are the two
bodies that were run, not all nine.

## 34. The nested consumer build asked for its cache directory in a spelling
     `zig build` does not accept — 2026-10-04

**Condition.** `b.cache_root.path` was non-null, so the nested command carried a
cache argument at all. Two routes reach that state — a local cache directory
exported in the environment (`devenv` inherits the shell's, and
`host-scratch.sh` exports `ZIG_LOCAL_CACHE_DIR`), or `--cache-dir` named on the
command line — and either one is enough. In the observed run only the first was
in play; `devenv.nix` now passes the flag explicitly, so the branch is taken
everywhere and the spelling below would have failed on every invocation rather
than only where a variable happened to be set. With no cache directory of any
kind the command never reaches this code at all.

**Symptom.** In acceptance run `20261004T193710Z`, `devenv:consumer` exited 1
after 42.7s:

```
unrecognized argument: '--cache-dir=/home/tmp2/gertullj/cache/zig-local/consumer'
  access the help menu with 'zig build -h'
failed command: cd …/random123/consumer && zig build run -Dtarget=native
  -Dcpu=native -Doptimize=Debug -Dlinkage=static -Druntime=false
  --cache-dir=/home/tmp2/gertullj/cache/zig-local/consumer
```

The nested build died while parsing its own command line, so nothing in
`consumer/` was compiled and the outer build reported one failed step. The
outer gate itself was fine: it reached the nested command and handed it
everything else it asks for.

**Cause.** `build.zig`, in the step that starts the nested build, appended
`b.fmt("--cache-dir={s}/consumer", …)` — one argument carrying an `=`. `zig
build` does not accept that form. It documents `--cache-dir [path]` as two
arguments, and an `=`-joined token is not a recognised alternative: it reaches
the build runner as an ordinary `-`-prefixed argument, and the runner's list
is `-D`, `-Z`, `--verbose`, `-p`, `-l`, the enumerated long options, `-j…`,
`-f…`, `--`, and nothing else — everything else is fatal. This is specific to
`zig build`: the compiler's own test runner *does* take `--cache-dir=[path]`
in one token, which is why the shape looked plausible.

**Change.** `build.zig` only, one argument pair inside the nested command:
`--cache-dir` and then `{s}/consumer`. The subdirectory rule itself is
unchanged — a null `path` still means the nested build uses its own default —
and so is the reason for it: two build graphs must not write one cache
manifest. No `--global-cache-dir` was emitted anywhere in this build, so there
was no second spelling to migrate.

*(Amended after entry 35: this paragraph previously said "No
`--global-cache-dir` is emitted anywhere in this build … the nested build
continues to resolve the global cache the way every other build on the machine
does", in the present tense. That was accurate of `build.zig` as this entry left
it, and stopped being accurate when entry 35 forwarded that path to the nested
build. The `=`-joined spelling was indeed the only instance of that mistake
here; what entry 35 adds is a flag that was absent rather than misspelled.)*

**The nested job count.** The same command now carries a fixed `-j8`. It did
not before, and nothing could supply one: a `Run` step's command line is
built here, and the caller's `-j` reaches the outer graph, not this argument
list. Left alone, the nested build takes its width from the machine executing
it (`cpu_count - 1`), so the consumer this gate proves compiles at a different
width from the build that asked for it, and at a different width again on
another host. Eight is the count `devenv.nix` fixes in all eight of its
`zig build` script bodies for the same reason, so the nested build now matches
the entry that invoked it.

**What did not change.** Every requested option is forwarded exactly as it
was: the resolved `-Dtarget=`, `-Dcpu=`, `-Doptimize=`, `-Dlinkage=` and
`-Druntime=`, plus `-Daesni=` only when this build was given one; the
`run`-versus-`install` choice `hostCanExecute` makes; the executor switches
and `--libc-runtimes`; and `run.has_side_effects`. No option was added, none
was defaulted, no path is hardcoded and no target is overridden. No upstream
byte, no generated header, no API surface, no test and no fixture was touched.
`devenv.nix` is unchanged by this entry.

`OBSERVED` for the check this entry named. Acceptance run `20261004T214134Z`,
gate `devenv:consumer`, exit 0 after 7.524s, from a scratch project directory
with both cache directories exported, so the guarded branch above was taken.
The nested build ran to completion — `Build Summary: 6/6 steps succeeded`, then
`run exe random123-consumer success` — where the same command had died on the
`=`-joined token in run `20261004T193710Z`. Receipts:
`…/nix-acceptance-evidence/20261004T214134Z/random123-index.json` and
`random123-devenv-consumer.log` in the same directory. Bounded: that is this
one cell, on the host target; no other configuration was run.

## 35. The nested consumer build lost the global cache, the caller's own
     arguments and the summary — 2026-10-04

**Condition.** `zig build consumer` is a second `zig build` process, so its
configuration crosses the boundary as an argument list and nothing else. Entry
34 gave that list a correct `--cache-dir` and a fixed `-j8`; three things that
`AGENTS.md:157-158` puts on every CLI entry were still absent from it.

**Cause.** *Three independent omissions in the same argument list, all in the
step that starts the nested build (`build.zig`, `addConsumerStep`).*

1. **The global cache was never forwarded.** Every sibling read here is
   `b.cache_root.path`; the global cache is the same kind of read one field
   away, `b.graph.global_cache_root.path`, and nobody made it. The build runner
   resolves that path once and hands it to the build script
   (`lib/compiler/build_runner.zig:53-54`, `:73-76`, `:89`;
   `lib/std/Build.zig:122`, where the field is declared inside `pub const
   Graph` at `:112` rather than on `Build` itself — so the read is
   `b.graph.global_cache_root.path`, not `b.global_cache_root`), so a global
   cache chosen for the outer build was simply not on the nested command line,
   and the nested build resolved a global cache of its own instead — outside
   the approved `/home/tmp2/gertullj/cache/foundation-libs` root whenever the
   outer one was pointed there. `devenv.nix`'s `preamble` and `package.nix`'s
   `installPhase` each name a global cache directory for the builds they drive,
   so this is a path this SDK's own packaging selects, not a hypothetical.
2. **The caller's trailing arguments were dropped.** `zig build consumer --
   --provider <path>` collects them in `b.args`, and the helper never emitted a
   `--`, so they stopped at the outer build. The nested package was already
   prepared to carry them — `consumer/build.zig:70` hands its own `b.args` to
   the program — and the program is the check:
   `consumer/src/main.zig:50-51`, `:57-64` read `--provider` from argv. The
   channel was therefore live end to end except for the one hop this SDK owns,
   so `RANDOM123_TEST_PROVIDER` kept working while the documented argument form
   could not.
3. **`--summary all` was absent.** Left off, the nested build reports
   `.failures` (`lib/compiler/build_runner.zig:523`), which prints nothing when
   nothing failed — so a *passing* consumer produced no step output at all, and
   the run this step exists to perform was invisible in the log that has to
   carry it.

**Change.** `build.zig` only, three additions to the nested command's argument
list, in that order and each at its natural place:

* `--summary` then `all`, two arguments after the `-j8`, in `addConsumerStep`.
  Two tokens because the runner documents `--summary [mode]`
  (`lib/compiler/build_runner.zig:1639`) and reads the mode as the *next*
  argument (`:262-265`), with `all` one of five enumerated spellings (`:1738`) —
  the same two-token discipline entry 34 established for `--cache-dir`.
* `--global-cache-dir` then `b.graph.global_cache_root.path`, in the same
  helper, two tokens for the identical reason
  (`lib/compiler/build_runner.zig:1675`). The path is forwarded **verbatim**,
  with no `/consumer` subdirectory, and that asymmetry with the local cache is
  deliberate rather than an omission: the local cache holds this graph's
  manifest directory and is locked for the life of the process holding it, so
  two graphs are given two of them, whereas the global cache holds
  content-addressed package directories keyed by hash, which is what exists to
  be shared. The compiler forwards it verbatim from a build script on exactly
  this reasoning (`lib/std/Build/Step/Compile.zig:1477-1480`, and again
  `lib/std/Build/Step/TranslateC.zig:179-180`). The guard is kept because
  `Cache.Directory.path` is `?[]const u8`
  (`lib/std/Build/Cache/Directory.zig:13`), not because the runner can leave it
  null.
* `--` then `b.args`, in the same helper and last, because `--` ends the
  nested build's option parsing and so has to follow every option above it.

**What did not change.** Every previously forwarded item is byte-for-byte as it
was: the resolved `-Dtarget=`, `-Dcpu=`, `-Doptimize=`, `-Dlinkage=` and
`-Druntime=`; `-Daesni=` still passed only when this build was given one, and
still never defaulted in either direction; the `run`-versus-`install` choice
`hostCanExecute` makes of the resolved target; the five executor switches and
`--libc-runtimes`; the fixed `-j8`; the `--cache-dir` pair and its `/consumer`
subdirectory rule; and `run.has_side_effects`. No option was added, none was
defaulted, no path is hardcoded, no target is overridden and no helper was
introduced. `consumer/build.zig` needed no change and did not get one. No
upstream byte, no generated header, no algorithm, no API surface, no test and
no fixture was touched. `devenv.nix`, `package.nix` and the CI workflow are
unchanged by this entry.

**A claim in the source that this entry makes true.** A comment in
`preprocessedBridgeHeader`, on the step name that carries the triple, says
"because `matrix` builds several of these at once and `--summary all` has to
tell them apart, exactly as `addConsumerStep`'s nested build and utf8proc's
preprocessor do". The nested build did not carry `--summary all` when that
sentence was written; it does now. The comment needed no edit, and was left
alone.

`OBSERVED` for all three items, in two runs. This run carries the first two:
both `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LOCAL_CACHE_DIR` were exported to it, so
both relay branches in `addConsumerStep` were taken, and the nested build
printed `Build Summary: 6/6 steps succeeded` — the output `--summary all` asks
for and the `.failures` default does not produce on a passing build. The third,
the `--` and `b.args` hop, is covered by the nine delivery cases entry 38
records, where `--provider <path>` passed after the caller's `--` and the
program loaded from it with every provider variable absent from the child. No
build, compiler, formatter or linter was invoked to produce this entry.

## 36. The nested consumer build installed into `consumer/zig-out` — 2026-10-04

**Condition.** `zig build consumer` is a second `zig build` process, so its
configuration — including where it installs — crosses the boundary as an
argument list and nothing else. Entry 34 corrected the two-token
`--cache-dir`, entry 35 added the global cache, `--summary all` and the
caller's trailing arguments. None of those is a destination.

**Cause.** `addConsumerStep` in `build.zig` read `b.install_prefix` for every
delivery decision this build makes for itself and did not hand it on, so a
nested `zig build` left to resolve its own prefix installed into
`consumer/zig-out` — a build artefact inside a source package, written by the
one hop (`install`, taken when `hostCanExecute` says this host cannot execute
the selected target) whose whole purpose is to deliver somewhere. The outer
graph's delivery tree is under `--prefix`; the nested graph's was not.

**Change.** `build.zig` only, inside `addConsumerStep`: `--prefix` and the
resolved path, guarded on `b.install_prefix` differing from
`b.build_root.join(b.allocator, &.{"zig-out"})`. The guard is what keeps a
default invocation byte-identical — a flag that forwards the default says
nothing and pins a spelling this package does not otherwise have. A relative
prefix is joined against `b.graph.cache.cwd` before it is handed on, because
the step's working directory is `consumer/`, not this build's root, so the same
relative path would otherwise resolve somewhere else. `DESTDIR` is not
forwarded: the nested build inherits the environment this one ran with. The
shape is byte-identical to `tzdata/build.zig`'s own relay, which is the
convention this matches.

**Why no flag through `b.args`.** `--prefix` is this build's own option and
stays on the nested command, where every other build option already is.
`b.args` carries what the caller typed *after* `--`, and those are program
arguments: they travel the two hops entry 35 records, into the consumer
executable's argv.

**What did not change.** The `run`-versus-`install` choice, the five executor
switches and `--libc-runtimes`, the fixed `-j8`, `--summary all`, the
`--cache-dir` pair and its `/consumer` subdirectory rule, the
`--global-cache-dir` pair forwarded verbatim, the trailing `--` with `b.args`,
and `run.has_side_effects`. No `b.args` flag was added, nothing was defaulted,
no path is hardcoded, no target is overridden and no helper was introduced.
`consumer/build.zig`, `devenv.nix`, `package.nix` and the CI workflow are
unchanged by this entry. No upstream byte, no generated header, no algorithm, no
API surface, no test and no fixture was touched.

`OBSERVED` for the relay, `PENDING-VERIFICATION` for the install hop. Acceptance
run `20261004T214134Z` does not reach it — that command names no prefix, so the
guard is not taken. The nine delivery cases entry 38 records do: every one named
a prefix, and the nested command carried `--prefix` with the caller's own path,
recorded as propagated and as not resolving into this SDK's tree. That is the
flag reaching the nested build, which is what this entry changed. What no case
exercised is the hop that installs, because every case asked the consumer
package for `run`. The remaining check is `zig build consumer --prefix <dir>`
over this checkout with a target this host cannot execute. No build, compiler,
formatter or linter was invoked to produce this entry.

## 37. `devenv.nix` could not be evaluated at all — 2026-10-04

**Condition.** Every gate in this SDK's canonical environment enters through
`devenv`, which evaluates `devenv.nix` before any task or script exists.

**Symptom.** Acceptance run `20261004T212645Z`: `devenv:info` exited 1 after
0.717s on

```
at /vol/fob-vol7/mi19/gertullj/foundation-libs/random123/devenv.nix:72:19:
   71|   # value `preamble` fills when it is missing.
   72|   cacheDir = "''${ZIG_LOCAL_CACHE_DIR}/random123";
  error: undefined variable 'ZIG_LOCAL_CACHE_DIR'
```

(parent receipt, OBSERVED by the integrator:
`…/nix-acceptance-evidence/20261004T212645Z/random123-devenv-info.log`, with the
matching `random123-index.json`). Every other devenv gate failed for this one
reason rather than independently: `devenv:tasks-list`,
`devenv:canonical-integrity-mapping` (which recorded
`tasks_observed []`), `devenv:shell-zig-version`, `devenv:shell-zig-env`,
`devenv:consumer` and `devenv:integrity`.

**Cause.** That line was the file's only *regular* double-quoted Nix string
holding a shell expansion. `''${` is the escape sequence for the start of a
shell expansion inside an indented string (`''…''`); in a double-quoted string
it escapes nothing, so Nix read the rest as `${ZIG_LOCAL_CACHE_DIR}` — a Nix
interpolation of a variable the file never binds — and stopped. The same
spelling is correct in `externalPrefix`, `preamble` and `install`, which are
indented strings, and it is correct there now.

**Change.** `devenv.nix` only, one line: `cacheDir` is now
`"$ZIG_LOCAL_CACHE_DIR/random123"`, with no braces, so Nix copies the text out
unchanged and the shell expands it from the caller's environment, which
`preamble` has already filled. Five comment lines above it record the rule. This
is the spelling `blake3`, `box2d`, `box3d` and `erfa` already use, so no second
convention was introduced.

**What did not change.** The nine script names; `preamble`, `externalPrefix` and
`sdkRoot`; the `-j8 --cache-dir "${cacheDir}" --summary all` triple, in that
order, in all eight builds; every guard and the caller-environment-only
precedence, including the refusal with a message and a non-zero exit when
`XDG_CACHE_HOME` and `TMPDIR` are both unset; `zig = pkgs.zig_0_16` and the
`zig.version == "0.16.0"` assertion. No build option, no installed path, no
upstream byte and no test changed.

`OBSERVED` for the repair. Acceptance run `20261004T214134Z`, scope `devenv`,
status `pass`, with `gates_failed []`, `gates_unsupported []` and `problems []`
over eight gates: `devenv:info` exit 0 after 2.586s, listing all nine scripts
and all five tasks; `devenv:tasks-list` exit 0;
`devenv:canonical-integrity-mapping` pass, mapping `provenance`;
`devenv:shell-zig-version` exit 0; `devenv:shell-zig-env` exit 0;
`devenv:consumer` exit 0; `devenv:integrity` exit 0; and `repo:untouched` pass,
364 entries with an identical tree digest before and after
(`…/nix-acceptance-evidence/20261004T214134Z/random123-index.json`, this SDK's
index in the combined `index-box3d-random123-pcre2.json` run). No Nix, devenv
or build command was invoked to produce this entry.

Bounded: that run is devenv-scoped, and `gates_not_run` names `nix:build`, so
nothing here observes the Nix `packages.*` derivation — that stays
unobserved. The earlier receipts quoted above describe the file before this
repair and are kept as the failure they record. One comment in `devenv.nix`
still cites the pre-repair `build.zig:1014` for the `consumer` step; this
entry and the four documents beside it cite the symbol `addConsumerStep`
instead, and that comment belongs to the packaging file's owner.

## 38. Nine delivery cases across both linkages and both dispatch shapes —
     2026-10-04

**Condition.** `zig build consumer` hands its whole configuration to a second
`zig build` as an argument list, so that list is the contract between this
package and the consumer package. Entries 34, 35 and 36 each named the check
that would fail if the repair on it were wrong.

**What was run.** One SDK, nine cases, reported by the integrator as an actual
run of this checkout, each with its own receipt and output log in one evidence
directory (`…/nested-delivery-proof/evidence/20261004T220323250122Z-515d06adcbbf/index.json`).
All nine rows read `PASS` with `failed_checks []` and every nested-command check
`ok`: eight semantic cases exiting 0, and one refusal case exiting 1.

* Both linkages and both dispatch shapes, each in a default case that named no
  target, no prefix and no optional SDK default, and an explicit case that named
  `-Dtarget=x86_64-linux-gnu -Dcpu=baseline`: linked/static, linked/dynamic,
  loaded/static, loaded/dynamic.
* The default cases forwarded `-Dtarget=native -Dcpu=native`, which is this
  build's own resolved answer, and the explicit cases forwarded the caller's
  selection. No optional default was invented by the driver, and it records
  that this SDK declares none.
* The refusal case is `-Druntime=true` with no provider: the program exited 1
  and printed the refusal `consumer/src/main.zig` declares rather than falling
  back to anything.

**What the argument list carried.** In every case: the resolved `-Dtarget=`,
`-Dcpu=`, `-Doptimize=`, `-Dlinkage=` and `-Druntime=`; `-j8`; `--summary all`;
`--cache-dir <outer cache dir>/consumer`; `--global-cache-dir` with the caller's
named global cache; and `--prefix` with the caller's prefix, recorded as
propagated and as not resolving into this SDK's tree. That is entries 34, 35 and
36 observed on the list itself rather than inferred from the source.

**The argument hop, without an environment behind it.** The four loaded cases
passed `--provider <absolute path>` after the caller's `--`. Every provider
variable was excluded from every child process — `RANDOM123_TEST_PROVIDER` is
named in that list — so the argument reached the program with no environment
handoff available to explain it. The two documented ways in are therefore not
the same observation: this one exercises the argument form alone.

**Bounded.** All nine are `run` hops, so the prefix is observed *reaching* the
nested build, not a tree that received installed files; the install hop stays
`PENDING-VERIFICATION` as entry 36 states. Nothing here exercises the Nix
derivation. The index carrying these rows also carries a top-level
`status_note` saying its driver "has never been executed"; the parent reports
these random123 rows as actual and this entry records them on that basis rather
than resolving the discrepancy. No build, compiler, formatter or linter was
invoked to produce this entry.

## 39. The current matrix is observed, and its twenty-four red cells are two boundaries — 2026-10-05

**Scope.** Documentation only. No build file, no source file, no upstream header,
no upstream byte and no licence record changed, and no gate was run for this
entry; the numbers are read out of four existing driver receipts.

**Observed.**

- Native eight cells, `zig build test smoke install -Doptimize=<mode>
  -Dlinkage=<l> -Druntime=false`, static × dynamic crossed with Debug,
  ReleaseSafe, ReleaseFast and ReleaseSmall: exit 0 in all eight,
  `Build Summary: 21/21 steps succeeded; 10/10 tests passed`, `tests_skipped 0`.
- Own-loaded eight cells, the same eight configurations with `-Druntime=true`,
  `RANDOM123_TEST_PROVIDER` naming this tree's own `librandom123.so`
  (`provider.kind: "own"`) and `RANDOM123_TEST_ALIEN=/lib64/libm.so.6`: exit 0 in
  all eight, `Build Summary: 24/24 steps succeeded; 23/23 tests passed`. The eight
  loaded gates that were red earlier on 2026-10-04 (entry 29) are green after that
  repair and the later graph change.
- The 53-cell cohort, receipt `20261004T221720228710Z-45046/random123-53-target-8.json`,
  `source_stamp_before == source_stamp_after` (`2d72c0a7…`), `target_jobs 8`,
  `jobs_per_build 8`: **exit 1**. Raw `pass=3 fail=24 build_only=26 partial=0`;
  corrected `pass 3 / build_only 26 / build_fail 15 / runtime fail 9`.
- The compile-only `zig build matrix` baseline, row `baseline-random123-matrix`:
  **exit 1**, `Build Summary: 45/58 steps succeeded (4 failed)`,
  `declared_target_count 6`, all six triples named, `failing_step_lines 19`,
  `test_pass_lines: []`.

**The three passes are three passes of nine tests.** `random123-kat` declares
`if (comptime !random123.has_aesni) return error.SkipZigTest;` at
`zig/kat_test.zig:180` and `runtime/load_tests.zig:329`, and QEMU user-mode does
not present AES-NI, so every executed 53-cell reports
`random123-kat 2 pass, 1 skip (3 total)` beside `random123-facade 7 pass (7
total)` and the harness records `tests=9`. The host-native cells run all ten.
No row of the 53-cell table is a full-suite result.

**The fifteen build failures are one upstream header gate**, at
`include/Random123/features/gccfeatures.h:38` —
`#error "This code has only been tested on x86, powerpc and a few arm
platforms."` — followed by `:39`'s
`#include <including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_file>`.
The cells are `hexagon-linux`, `loongarch64-linux`, `mips-linux`, `mipsel-linux`,
`mips-netbsd`, `mipsel-netbsd`, `mips64-linux`, `mips64el-linux`,
`mips64-openbsd`, `mips64el-openbsd`, `riscv32-linux`, `riscv64-freebsd`,
`riscv64-linux`, `riscv64-openbsd` and `wasm32-wasi`. The same header is the
only reason the six-row `matrix` baseline is red, on `riscv64-linux-gnu` and
`wasm32-wasi`. Nothing in this fork edits an upstream header to remove it.

**The nine runtime failures are in the known-answer replay and the 32-bit word
split, in two shapes.**

- Five cells — `arm-linux`, `armeb-linux`, `thumb-linux`, `thumbeb-linux`,
  `aarch64_be-linux` — report `random123-kat 1 pass, 1 skip, 1 fail` and
  `random123-facade 7 pass (7 total)`. The failing test is
  `kat_test.test.the raw C keyinit and round wrappers replay upstream's known
  answers` at `zig/kat_test.zig:351`: `expected 1601156873, found 4259204590` on
  both 32-bit ARM cells, `expected 1601156873, found 2741130706` on both thumb
  cells, and `expected 628766323, found 928378366` on `aarch64_be-linux`. Same
  expected vector, two different wrong values, so the miscomputation is not
  endianness.
- Four cells — `powerpc64-linux`, `powerpc64le-linux`, `powerpc-linux`,
  `s390x-linux` — fail on both routes. On the two 64-bit PowerPC cells
  `random123-kat 0 pass, 1 skip, 2 fail` reports **identical** expected/found
  pairs from the facade known-answer test and the raw-C replay
  (`628766323`/`3441868330`, `3441868330`/`4020305955`), which rules the Zig
  dispatch layer out, and `random123-facade 2 pass, 2 fail, 3 crash` also trips
  `Assertion failed: R<=16 (…/philox.h: philox4x64_R: 359)`. On the 32-bit
  PowerPC and s390x cells both suites crash: `Segmentation fault at address 0x0`
  at `zig/bridge/random123_bridge.c:89:25 in philox2x32_R` and at
  `include/Random123/philox.h:349` in `philox2x32keyinit`
  (`_philoxNxW_tpl(2, 1, 32, uint32_t)`), with
  `Assertion failed: R<=16 (…/philox.h: philox2x32_R: 349)` on s390x.

**Bounded.** The cohort's counts describe the source it stamped and nothing
later. Twenty-six `build_only` cells compiled and ran nothing and are not
passes. The six-row `matrix` baseline is compile-only by construction and by the
receipt's `runtime_pass_claimed: false`. Whether the runtime failures originate
in `philox.h` as compiled or in the emulation layer beneath it is **not**
settled by these receipts and is not claimed. `-Dlinkage=dynamic` on `check` and
`matrix`, `check`/`matrix` under `-Druntime=true`, the nested `consumer/` build,
the Nix derivation and the devenv packaging routes remain
`PENDING-VERIFICATION`.
