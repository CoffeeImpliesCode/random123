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
step instead of `run`; a native target still runs it. This is the same policy
the `test` step already follows for cross targets. Previously the sub-build
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

