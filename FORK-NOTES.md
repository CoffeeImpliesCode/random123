# FORK-NOTES

Issues genuinely encountered while designing the Zig package for Random123
`v1.14.0`. Every entry cites the source line that produced it. "Verification
status" records what has been *designed*, never a gate result: this fork's
gates were run by the integrator, not by the author of these notes.

---

## 1. Philox Nx64 does not exist on riscv64 or wasm32

**Symptom / evidence.** `include/Random123/features/compilerfeatures.h:297-299`
defines

```c
#define R123_USE_PHILOX_64BIT (R123_USE_64BIT && (R123_USE_MULHILO64_ASM || … || R123_USE_GNU_UINT128 || R123_USE_MULHILO64_C99 || …))
```

and `include/Random123/features/gccfeatures.h:156-162` enables
`R123_USE_GNU_UINT128` **only** for `__x86_64__` or `__aarch64__`, while
`gccfeatures.h:246` hard-codes `R123_USE_MULHILO64_ASM` to `0`. Every other
64x64→128 route is off by default. On riscv64-linux-gnu and wasm32-wasi the
expression therefore resolves to `0`, and `philox.h:192` wraps all four
`philoxNxW64` instantiations in `#if R123_USE_PHILOX_64BIT`, so
`philox2x64_R` and `philox4x64_R` are not declared at all.

**Cause.** *Confirmed from source*, not a hypothesis: upstream's feature
detection only learned about `__uint128_t` on the two architectures that existed
when it was written.

**Fix / constraint.** `build.zig` defines `-DR123_USE_MULHILO64_C99=1` on exactly
those architectures. That is upstream's own documented override — see the
comment block at `compilerfeatures.h:51-56`, "Library users can override any
value by defining the pp-symbol with a compiler option" — and selects
`_mulhilo_c99_tpl(64, uint64_t)` at `philox.h:210`, which builds the same
128-bit product from word-size operations only. Slower, bit-identical.
`zig/bridge/random123_bridge.c` static-asserts `R123_USE_PHILOX_64BIT` so a
target that loses the multiply fails loudly instead of silently losing two
generators.

This entry was written before entry 23: on both of the architectures it names,
upstream never gets as far as choosing a multiply. The override is still the
right one for a 64x64→128 product, and it stays, but the two contract targets
that motivated it are refused by `features/gccfeatures.h:37-45` first.

**Platform / version.** riscv64, wasm32; Random123 1.14.0; no ABI change.

**Reusable rule.** When vendoring a header-only library, walk its
`features/*features.h` files and mirror their arch switches in the build
script. A generator silently vanishing on one architecture is the failure mode
you will not notice until a user on that architecture asks.

**Verification status.** Designed. No contract target that reaches the multiply
needs the override; entry 23 records that the two this entry names never get
that far.

---

## 2. Header-only upstream emits no linkable symbol

**Symptom / evidence.** `philox.h:321` defines the entry points as
`R123_CUDA_DEVICE R123_STATIC_INLINE philoxNxW_R(...)`, and `gccfeatures.h:51-53`
sets `R123_STATIC_INLINE` to `static __inline__`. `philox.h:362-367` then makes
the default-round entry points preprocessor macros:

```c
#define philox2x32(c,k) philox2x32_R(philox2x32_rounds, c, k)
```

Static inline functions are internal to each translation unit, and macros are
not symbols at all, so an empty `librandom123` would have nothing for a Zig
`extern fn` to bind to.

**Cause.** *Confirmed from source.* This is not a defect; it is upstream's
correct design for a header-only library.

**Fix / constraint.** One added translation unit,
`zig/bridge/random123_bridge.c`, includes the upstream headers and defines
externally linked one-line forwarders. No arithmetic appears in the bridge.

**Platform / version.** All. Random123 1.14.0.

**Reusable rule.** "Link the library the vendored project needs" and "the
vendored project needs no library" are only reconcilable with a deliberate
shim file. Keep it to forwarders; the moment it contains a shift, the fork has
forked the algorithm.

**Verification status.** Designed; `zig build` and the KAT tests are the gates.

---

## 3. `array.h` drags GNU inline assembly into the translated header

**Symptom / evidence.** `array.h:34-35` unconditionally includes
`features/compilerfeatures.h` and `features/sse.h`. `features/sse.h:35` guards
its whole body on `R123_USE_SSE`, which `gccfeatures.h:140-144` sets from
`__SSE2__` — always defined on x86_64. Inside, `sse.h:64-72` declares

```c
R123_STATIC_INLINE int haveAESNI(){
    unsigned int eax, ebx, ecx, edx;
    __asm__ __volatile__ ("cpuid": "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1));
```

and `sse.h:37-43` includes `<x86intrin.h>`, with `sse.h:266-272` defining
`r123m128i` around `__m128i`. `addTranslateC` has no representation for inline
assembly.

**Cause.** *Confirmed from source.*

**Fix / constraint.** `build.zig` calls `tc.defineCMacro("R123_USE_SSE", "0")`
for the translation step only. The compiled bridge keeps the real value, keeps
`haveAESNI()`, and keeps the real AES-NI code. The `r123array1xm128i` type is
absent from the translated surface, which is exactly why AES-NI is reached
through the bridge rather than as a translated Zig type.

**Platform / version.** x86, x86_64; Zig 0.16.0 `addTranslateC`.

**Reusable rule.** Translate a *projection* of a header, not the header. Decide
which feature macros define the surface you want in the target language, set
them only on the translation step, and keep the compile step honest.

**Verification status.** Designed; `zig build` is the gate.

---

## 4. The AES-NI key type cannot cross a portable boundary

**Symptom / evidence.** `aes.h:171-173` (C branch) defines
`aesni4x32_key_t` as an alias of `aesni1xm128i_key_t`, a struct of
`__m128i k[11]`, and `aes.h:217-223` fills it through `aesni1xm128iexpand`.
`aesni4x32` is the one AES-NI generator whose *counter* is plain words
(`aes.h:211`, `r123array4x32`), but its key is 176 opaque bytes.

**Cause.** *Confirmed from source.* Upstream's AES-NI key type is deliberately
opaque — `aes.h:262-265` notes that building it costs hundreds of cycles
against tens for the bijection.

**Fix / constraint.** The bridge marshals the schedule through a
`uint32_t[44]` buffer with `memcpy`, and static-asserts
`sizeof(aesni4x32_key_t) == 11 * sizeof(__m128i) ==
R123_BRIDGE_AESNI_KEY_WORDS * sizeof(uint32_t)`. No `__m128i` crosses the
bridge and none enters the translated surface. The AES-NI 1xm128i generators
are not bridged; they remain available to C and C++ through the installed
headers.

**Platform / version.** x86 with AES-NI; Random123 1.14.0.

**Reusable rule.** Marshal an opaque C type by its size and assert the size, not
by casting. A `reinterpret` of a vector-typed struct across a Zig/C boundary is
an ABI assumption with no compiler to back it.

**Verification status.** Designed; the AES compile path is in `check`/`matrix`
for x86, and the AES/ARS known answers run where the CPU has AES-NI.

---

## 5. `R123_ASSERT` disappears under `NDEBUG`

**Symptom / evidence.** `philox.h:324` asserts `R<=16` and `threefry.h:205`
asserts `Nrounds<=32` via `R123_ASSERT`, which `gccfeatures.h:67-70` defines as
`assert(x)` — a no-op once `NDEBUG` is defined. Zig defines `NDEBUG` for
ReleaseFast and ReleaseSmall.

**Cause.** *Confirmed from source.* Upstream's guard is a debug aid, not part of
the contract; past `max_rounds` the result is undefined.

**Fix / constraint.** `zig/generator.zig` checks the bound unconditionally and
traps. Divergence, recorded as `CHANGELOG.md` entry 3. It can only fire on
input upstream leaves undefined.

**Platform / version.** All.

**Reusable rule.** When a vendored library's precondition is enforced by an
assert, decide explicitly whether the binding inherits the release-mode hole.
Inheriting it silently turns a caller error into silent garbage.

**Verification status.** Designed.

---

## 6. `installHeadersDirectory` does not configure the library's own build

**Symptom / evidence.** `lib/std/Build/Step/Compile.zig:520-552` registers
header *installations*; the doc comment on `Module.linkLibrary` states the
library's own compile line is not covered by them.

**Cause.** *Confirmed in the 0.16.0 standard library source.*

**Fix / constraint.** `build.zig` calls both `lib_mod.addIncludePath(b.path("include"))`
for the artifact and `lib.installHeadersDirectory(...)` for consumers.
`tc.createModule()` also drops include paths — `TranslateC.zig:89-100` copies
only `link_libc` and `system_libs` — so the translated module gets its own
`addIncludePath`.

**Platform / version.** Zig 0.16.0.

**Reusable rule.** Two independent mechanisms, both required: "publish headers
to dependents" and "let my own C sources find them".

**Verification status.** Designed; `zig build` is the gate.

---

## 7. Declaring a facade method is not analysing it

**Symptom / evidence.** Not a compiler failure — a design trap. Zig analyses
function bodies lazily, so a `zig build check` that merely references
`random123.Philox4x32.rounds` proves nothing about its body.

**Cause.** *Confirmed language behaviour.*

**Fix / constraint.** `zig/analyze_test.zig` *calls* every public method with
concrete types, and `zig build check` compiles that file (and the example)
without running it. `std.testing.refAllDeclsRecursive` is deliberately absent.

**Platform / version.** Zig 0.16.0.

**Reusable rule.** A compile-only gate must contain real call sites, not
references. Otherwise the facade ships with an unanalysed method and the gate
stays green.

**Verification status.** Designed; `zig build check` is the gate.

---

## 8. System-library mode: recorded design constraint, not an observed failure

**Symptom / evidence.** The fork contract requires that a system-library mode,
where one exists, translate the *actual* selected system headers rather than
bundled newer ones.

**Cause.** *Structural.* Random123 installs no binary: `make install` copies
`include/Random123` and the documentation. There is no installed ABI, so
`b.systemIntegrationOption` would have nothing to bind to.

**Fix / constraint.** No system mode, and no fake one. Documented in
`UPSTREAM.md`. A distro that installs Random123 installs headers; consuming
those directly is the honest equivalent and needs nothing from this package.

`WISDOM.md` W14 is therefore recorded against this fork as vacuous rather than
satisfied: with no system mode there is no installed library whose headers this
translation could describe wrongly.

**Reusable rule.** Do not add a system-library toggle for a header-only
project. It cannot select anything, and its presence implies a compatibility
guarantee that does not exist.

**Verification status.** Documented decision.

---

## 9. Packaging hygiene

**Symptom / evidence.** `zig build` writes `.zig-cache/` and `zig-out/`.

**Fix / constraint.** Both, plus `zig-cache/`, appended to `.gitignore` after
upstream's entries, which are kept verbatim. `build.zig.zon`'s `.paths` lists
directories explicitly and excludes them, so a packaged dependency never ships
build output.

**Reusable rule.** Extend a vendored ignore list; never replace it. And list
`.paths` explicitly on a forked C repo, so `zig build` artefacts cannot become
part of the published package.

**Verification status.** Designed; the parent confirms `git status` cleanliness.

---

## 10. Upstream CI targets another maintainer's dead infrastructure

**Symptom / evidence.** `.travis.yml` at the pinned tag builds
`travis-ci.org`, which is shut down.

**Fix / constraint.** Deleted (`CHANGELOG.md` entry 1); replaced by
`.github/workflows/verify.yml`, which is this fork's own workflow. No upstream
source file affected.

**Reusable rule.** Delete a dead upstream CI file rather than "fixing" it.
Keeping it invites someone to push to a stranger's pipeline.

**Verification status.** Designed.

---

## 11. `u01` is a primitive type name, so the facade namespace could not keep
    it

**Symptom / evidence.** `zig build test` failed before any facade test ran:

```
root.zig:140:11: error: name shadows primitive 'u01'
pub const u01 = struct {
```

(parent receipt `local://foundation-random123-test-debug.json`, OBSERVED by the
integrator). The name is a primitive in this compiler: the shipped `lib/std`
contains no `u01` at all, but the compiler binary carries it in its primitive
name table next to the `name shadows primitive` diagnostic (SOURCE-CONFIRMED by
inspecting the pinned compiler, not by re-running it).

**Cause.** *Confirmed, not guessed.* The fork named its conversion namespace
after upstream's C++/C spelling. Upstream spellings are a naming convention
for C, and a C identifier is not automatically a legal Zig declaration name.

**Fix / constraint.** Renamed to `random123.UnitInterval`, the words the
namespace actually means. A clean cutover: `zig/facade_test.zig`,
`zig/analyze_test.zig`, `consumer/src/main.zig` and `README.zig.md` all migrated,
no alias kept, no `@"u01"` escape hatch. `UnitInterval` is not a Zig primitive
and is not used anywhere in the shipped `lib/std`. The C bridge is untouched:
its symbols are still `r123_bridge_u01_*` under `pub const c`, so the upstream
spelling survives where it genuinely is an identifier. All twelve conversions
and all eight generators are unchanged; `CHANGELOG.md` entry 10.

**Reusable rule.** When a binding mirrors an upstream C or C++ name, check the
name against the target language's reserved words before adopting it, and keep
the upstream spelling only where the upstream identifier really survives. A
`@"name"` escape hatch silences a shadowing diagnostic without removing the
collision.

**Verification status.** Designed. Not compiled, not run by this author; the
parent's gates are the check.

---

## 12. `b.step()` returns a `*Build.Step`, not a wrapper with a `.step` field

**Symptom / evidence.** The separate `consumer/` package never configured:

```
build.zig:34:39: error: no field named 'step' in struct 'Build.Step'
    b.getInstallStep().dependOn(&step.step);
```

(parent receipt `local://foundation-random123-consumer-run.json`, OBSERVED).

**Cause.** *Confirmed in the 0.16.0 standard library source.* `lib/std/Build.zig:1355`
is `pub fn step(b: *Build, name: []const u8, description: []const u8) *Step`, so
`b.step(...)` is already the pointer, and `lib/std/Build/Step.zig:305` is
`pub fn dependOn(step: *Step, other: *Step)` — it takes `*Step` on both sides.
Only `*Step.Compile` (`b.addTest`, `b.addLibrary`, `b.addExecutable`) carries
the `.step` field, which is where the habit comes from.

**Fix / constraint.** The call is removed rather than corrected. It also asked
for the wrong thing: it made the *install* step depend on `run`, so a plain
`zig build` in `consumer/` would have executed the program. `b.installArtifact(exe)`
already installs the executable, `zig build run` still runs it, and
`zig build consumer` from the package root still shells out to `zig build run`.
`CHANGELOG.md` entry 11.

**Reusable rule.** `dependOn` takes `*Step`; only `*Step.Compile` has a `.step`
field. Read the signature before writing `&x.step`, and check what a default-step
dependency actually buys when a step has side effects.

**Verification status.** Designed. Not built or run by this author.

---

## 13. The public `generators` container is walked, not indexed

**Symptom / evidence.** Design constraint, not an observed failure. The facade
test needs a generator other than the one under test, and the obvious spelling
is `random123.generators[i]`. `generators` is declared as an inferred `.{}`
literal over eight distinct types (`root.zig:121-130`). In the shipped
`lib/std` there are 43 multi-line inferred `.{}` literals with unnamed fields
(`mem.zig:185` `primitiveIntTypes`, `crypto/blake3.zig:392`, and so on), and
every one of them is only ever walked with `for`/`inline for`: no inferred
literal anywhere in `lib/std` is indexed with `[` (SOURCE-CONFIRMED by scan).

**Cause.** *Structural.* Whether an inferred `.{}` literal is a tuple or a
struct is decided by the compiler, and this fork's gates have never reached a
line that depends on the answer. Depending on it would be depending on
something unverified.

**Fix / constraint.** `zig/facade_test.zig` picks the interloper with
`otherThan(G)`, which walks `random123.generators` with `inline for` and
returns the first entry that is not `G`. `for` over the container works whether
it is a tuple or a struct, so the test no longer depends on the question. The
public container itself is unchanged.

**Reusable rule.** A public container handed to consumers is an API contract
about iteration and length. Do not quietly make indexing part of it from one
call site that has not been compiled.

**Verification status.** Designed. Not compiled or run by this author.

---

## 14. `@panic` takes one argument, so the round-count trap was a second
     compile error

**Symptom / evidence.** `zig/generator.zig:63` read

```zig
@panic("random123: round count out of range for {s}", .{name});
```

The `@panic` builtin is declared with a parameter count of 1, and the compiler
rejects a call with any other count. SOURCE-CONFIRMED in the *pinned* compiler
that runs the gates, not in a look-alike: its own shipped source,
`lib/std/zig/BuiltinFn.zig:683-687`, gives `@panic` `.param_count = 1`, and
`lib/std/zig/AstGen.zig:9067` enforces it with
`expected {d} argument{s}, found {d}`. Two further local signals agree: every
`@panic(...)` in that `lib/` takes one argument, and `std.debug.panic` is
documented as "Equivalent to `@panic` but with a formatted message" and
formats the message itself instead of forwarding to `@panic`
(`lib/std/debug.zig:437-441`).

**Why it was not already visible.** The parent receipt
`local://foundation-random123-test-debug.json` reports exactly one error,
`root.zig:140` shadowing `u01`. That is an AST-generation error in the
`random123` module, so the import fails before any test body is analysed and
`rounds()` is never compiled. The gate was not green; it stopped early.

**Fix / constraint.** `std.debug.panic("…{s}", .{name})` — the same message
and the same `noreturn`, through the API that accepts a format string. The
round-count bound itself (entry 5) is unchanged; `CHANGELOG.md` entry 12.

**Reusable rule.** A function body is not checked until something calls it, and
an import that fails in AST generation hides every error behind it. When a
first gate stops at an early error, review the bodies the gate never reached
before calling the correction done — especially the ones that need a format
string.

**Verification status.** Designed; source-confirmed, not compiled or run by
this author.

---

## 15. `counter` and `key` are array *types*, so their shape must come from
    `@typeInfo`

**Symptom / evidence.** `zig/generator.zig` published its widths with

```zig
pub const word_bits = @bitSizeOf(@TypeOf(spec.counter[0]));
pub const counter_bits = word_bits * spec.counter.len;
pub const key_bits = word_bits * spec.key.len;
```

`spec.counter` and `spec.key` are supplied by `root.zig` as `[2]u32`, `[4]u32`,
`[1]u64` and so on — those are types, and the code indexes one and asks two for
`.len`. Neither operation is defined on a type. Reported by the integrator from
a source read; not compiler-observed, because the `u01` shadowing error is an
AST-generation failure in the same module and stops analysis before any
generator body is reached.

**Cause.** *Confirmed.* A Zig array type carries no members; its length and
element type live in `@typeInfo(T).array`, whose payload is
`std.builtin.Type.Array { len: comptime_int, child: type, sentinel_ptr }`
(`lib/std/builtin.zig:636-644`, union field `array` at `builtin.zig:558`).
The idiom is used by the pinned std itself: `lib/std/os/linux.zig:2241`
(`@typeInfo(sigset_t).array.len`), `lib/std/zon/parse.zig:770`
(`const array_info = @typeInfo(T).array;`),
`lib/std/zig/c_translation/helpers.zig:299`, and for the sibling field
`lib/std/math/big/int.zig:5` (`@typeInfo(Limb).int.bits`).

**Fix / constraint.** `wordArrayType` extracts the `Array` payload once per
spec field and rejects a non-array with a message that names the generator;
`Generator` additionally checks that both arrays share one element type, which
is what makes a single `child` answer for `word_bits`. The published
`word_bits`, `counter_bits` and `key_bits` keep their previous values —
`comptime_int` — and every number `root.zig` produces is unchanged. No
signature, version, default or round count moved; `CHANGELOG.md` entry 13.

**Reusable rule.** A generic facade that takes array *types* and derives
geometry from them needs `@typeInfo`; `T.len` and `T[0]` are for values. Check
the element-type agreement while you are there — a counter of `u32` and a key
of `u64` is a spec bug that would otherwise show up as a silent width.

**Verification status.** Designed; source-confirmed against the pinned
`lib/std`, not compiled or run by this author. All eight specs in `root.zig`
were checked by hand: every counter and key array has one element type.

---

## 16. The headline example quoted a known answer for the wrong key, and the
     manifest dropped the provenance file

**Symptom / evidence.** Two independent "the first thing a reader or a
consumer touches" defects, both reported by a read-only source review.

1. `root.zig:13-16` and `README.zig.md:51-54` showed
   `Philox4x32.generate(.{0,0,0,0}, .{0xd82c07cd, 0x629f6fbe})` producing
   `.{ 0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8 }`. That quadruple is
   upstream's answer for a **zero** key: `tests/kat_vectors:27` is
   `philox4x32 10 00000000 … 00000000   6627e8d5 e169c58d bc57ac4c 9b00dbd8`.
   The key `d82c07cd 629f6fbe` occurs nowhere in the tree except in those two
   examples, so the one snippet a reader copies did not match its own comment.
2. `build.zig.zon` `.paths` listed `UPSTREAM.md` but not `UPSTREAM.sha256`,
   while `README.zig.md` tells a consumer to run `sha256sum -c
   UPSTREAM.sha256`. A packaged tree could not do what its own documentation
   says.

**Cause.** *Structural.* A worked example written from memory rather than
copied from the fixture, and a manifest maintained by listing documentation
files without asking what the documentation tells you to run.

**Fix / constraint.** Both examples now use the `pi`-vector counter and key
from `tests/kat_vectors:29` with the output that same line records, and both
say so. `UPSTREAM.sha256` is in `.paths`. The generator, the round count and
the fixture are untouched; only the prose changed. `CHANGELOG.md` entry 14.

**Reusable rule.** Take every literal in a README from a fixture the test
suite also replays, and cite the fixture line. And read each sentence of a
manifest's documentation for files it implies.

**Verification status.** Corrected; the new example is a line of the upstream
fixture that `zig/kat_test.zig` already replays. Not compiled or run here.

---

## 17. Upstream's uniform known-answer vectors do not cover the twelve
     conversions this bridge exports

**Symptom / evidence.** A review proposed embedding
`tests/ut_uniform_kat_vectors.dat` (and its header twin
`tests/ut_uniform_IEEEkatvectors.hpp`) and replaying it as an independent
oracle for the `UnitInterval` conversions. SOURCE-CONFIRMED: that is a
different API.

**Cause.** *Confirmed, and the names are deceptive.* The vectors record
`insert("u01<float>(minu32 + uint32_t(a)) a=0", 5.96046447753906250000e-10L)`
and friends — the C++ function templates `u01<Ftype>`, `uneg11<Ftype>` and
`u01fixedpt<Ftype>` declared at `include/Random123/uniform.hpp:175` and
`:239`, exercised by `tests/ut_uniform_IEEEkat.cpp:86-104`. The twelve
functions this package bridges are the C functions at
`include/Random123/u01fixedpt.h:136-192`, named
`u01fixedpt_<range>_<word>_<type>`. They are not the same function:
`u01fixedpt<Ftype>` computes `(1 | (Utype(in)>>excess)) * factor`
(`uniform.hpp:244-245`), which clears bit 0 of the shifted word, while
`u01fixedpt_open_closed_32_float` computes `(1 + (i>>8)) * 2^-24`
(`u01fixedpt.h:145-147`). For `i>>8` odd the first yields `x * 2^-24` and the
second `(1+x) * 2^-24`; at `i = 0x00000100` that is `2^-24` against `2^-23`.
Replaying those vectors would validate functions this package does not export.

There is also no in-tree oracle for the C functions themselves. `u01fixedpt.h:106`
points at "the tests in `kat_u01_main.h`", and `docs/releasenotes.dox:140`
records a `kat_u01` known-answer test, but no `kat_u01*` file ships in
Random123 1.14.0. And the vector file's own header warns that its values come
from one x86-64 reference platform with 32/64/80-bit IEEE and that other
platforms "will almost certainly fail these tests even though their results
might be perfectly valid" — a property this fork's compile matrix cannot
accept.

**Fix / constraint.** No vectors embedded. Instead the exact-grid assertions
in `zig/facade_test.zig` were widened where they were thin: the four
conversions that had only a maximum-word case (`openOpen32Double`,
`openClosed32Double`, `openOpen64Double`, `openClosed64Double`) now also pin
the zero word, and both `openOpen` 32-bit variants pin an interior grid point,
so a change to a shift, a scale or an offset breaks them. The expected values
are derived from the uniform-grid definition in `u01fixedpt.h`, not copied
from the C source, and they are exact in the target type.

**Reusable rule.** Before adopting an upstream fixture as an oracle, check that
it exercises the function you actually export. Similar names are not the same
function, and a fixture tied to one reference platform's floating-point
behaviour is a portability liability, not a guarantee.

**Verification status.** Designed; source-confirmed, not compiled or run here.

---

## 18. The translated round constants are `c_int` constants, not enum values

**Symptom / evidence.** A review flagged a compile risk it could not settle:
`root.zig` coerces `c.R123_BRIDGE_*_DEFAULT_ROUNDS` into `u32`, and
`zig/analyze_test.zig` and `zig/kat_test.zig` use
`c.R123_BRIDGE_AESNI_KEY_WORDS` directly as an array length. If `addTranslateC`
emitted a Zig `enum` for the C enum `r123_bridge_rounds`, both would need
`@intFromEnum`.

**Cause.** *Settled from the shipped translator, then confirmed against real
output.* `transEnumDecl` in
`lib/compiler/translate-c/Translator.zig:1032-1115` emits each enumerator as
its own top-level constant whose type is `transType(scope, field.qt, …)` —
the enumerator's promoted integer type — at `:1066-1079`, and emits the enum
*type* separately from `enum_ty.tag` at `:1086-1091`. The generated module in
this fork's own build cache settles which integer each one is, and it is not
the one first recorded here:

```zig
pub const R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS: c_int = 10;
pub const R123_BRIDGE_AESNI_KEY_WORDS: c_int = 44;
pub const enum_r123_bridge_rounds = c_uint;
pub const r123_bridge_rounds = enum_r123_bridge_rounds;
```

So the enumerators are **`c_int`**, and it is the enum *type* alias that is
`c_uint`. The first version of this entry had those two the other way round.
It made no difference to the code — `c_int` and `c_uint` coerce to `u32` from
a comptime-known constant, and both are valid array lengths — but the claim as
written was false.

**Fix / constraint.** None needed in the code. No `@intFromEnum` was added and
no call site changed; the prose in this entry and in `README.zig.md` was
corrected to `c_int`. Recorded so nobody re-raises it and nobody re-cites the
wrong integer.

**Reusable rule.** A translated C enum is not a Zig enum, and the enumerator's
type is not the enum's tag type either. When a binding leans on a translated
constant, read the translator *and* read one generated module before writing
down the type; the two integers are different ones.

**Verification status.** Confirmed against the generated module in this fork's
own build cache, which the integrator's `zig build` produced; no gate was run
by this author to re-derive it.

---

## 19. One `openOpen32Double` expectation was off by a factor of two

**Symptom / evidence.** `zig/facade_test.zig` asserted
`8589934591.0 / 17179869184.0` for `openOpen32Double(0xffffffff)`.
SOURCE-CONFIRMED wrong: `u01fixedpt.h:190-192` returns `(0.5+i)*R123_0x1p_32`,
and `u01fixedpt.h:120` defines `R123_0x1p_32` as `1./(1024.*1024.*1024.*4.)`,
that is `2^-32`. So

```text
(0.5 + 4294967295) * 2^-32 = 4294967295.5 / 4294967296 = 8589934591 / 2^33
```

`17179869184` is `2^34`, so the test compared the conversion against a number
half what it produces. The test would have failed at run time with
`expected 0.9999999998835847, found 0.49999999994179224` — had the earlier
compile errors not stopped `zig build test` before any test body ran.

**Cause.** *A hand-derived constant, not an upstream one.* Every other
expectation in that test was re-derived from `u01fixedpt.h` during this review
and is exact; this one had a decimal slip in the denominator.

**Fix / constraint.** The denominator is `8589934592.0` (`2^33`) and the
derivation is now written next to the assertion, in the same style as the ones
added for entry 17. All twelve conversions were re-checked against
`u01fixedpt.h:136-192` and the hex-float constants at `u01fixedpt.h:117-123`
during this review; this was the only wrong value. `CHANGELOG.md` entry 18.

**Reusable rule.** When a test states its expectation as `numerator /
denominator`, the denominator is the part that gets mistyped. Write the
derivation next to the value, so the next reader can re-derive it instead of
trusting it — and re-derive *all* of them when you find one wrong.

**Verification status.** Corrected by source review; not compiled or run here.

---

## 20. Withdrawn: "there is no way to format a `Target.Query`"

**Symptom / evidence.** My own first cut at what is now `CHANGELOG.md` entry 16
claimed that Zig 0.16 "has no formatter that turns a `Target.Query` back into a
`-Dtarget` triple", and made `addConsumerStep` `@panic` on a non-native target.
The parent read the pinned standard library; both halves were wrong.

**Cause.** *Two separate mistakes, both mine.*

1. I searched `lib/std/Build.zig` for `fmtTargetQuery` and
   `lib/std/Target/Query.zig` for `fmt` and `format`, found nothing, and
   generalised from that narrow search to "no such API exists". I never
   searched for the names the API actually uses. The pinned library has
   `pub fn zigTriple(self: Query, gpa: Allocator) Allocator.Error![]u8` at
   `lib/std/Target/Query.zig:421` and
   `pub fn serializeCpuAlloc(q: Query, ally: Allocator) Allocator.Error![]u8`
   at `:530` — and the build system already uses that exact pair to report a
   resolved target (`lib/std/Build.zig:439-461`) and to hand it to the compiler
   (`lib/std/Build/Module.zig:596-597`).
2. Worse, the `@panic` sat in the *body* of `addConsumerStep`, which `build()`
   calls unconditionally at `build.zig:99`. A `std.Build` step constructor runs
   at configuration time, not when the step is requested, so the refusal fired
   on every cross-target `zig build check -Dtarget=…` and on `zig build
   matrix` — the compile gate — before anything was compiled.

**Fix / constraint.** The panic is gone. `addConsumerStep` forwards `-Dtarget=`,
`-Dcpu=` and `-Doptimize=`, each as a single `-Dkey=value` argument, built from
those two functions. The earlier `run.addArgs(&.{ "-Doptimize",
@tagName(optimize) })` was a two-token form that is not the documented
`-Dkey=value` syntax and was dropped. A non-native target now invokes the
consumer's `install` step, which builds without running; a native target
invokes `run`. *(Amended later the same day: that decision is no longer
`Target.Query.isNative`. `addConsumerStep` asks `hostCanExecute`, which is
`std.zig.system.getExternalExecutor` — the predicate `std.Build.Step.Run` asks
about the binary it is about to spawn — so a foreign target this host can
execute, natively or through an external executor the build runner was told to
use, runs, and one it cannot installs.)*
`consumer/build.zig` needs no change — `b.installArtifact(exe)`
already feeds its install step, and the install-to-run edge that made a plain
`zig build` execute the program was removed earlier. The false claim is
withdrawn from `build.zig`, `README.zig.md` and `CHANGELOG.md`, not restated.

**Reusable rule.** Never put a `@panic` in the body of a `std.Build` step
constructor: `build()` calls those unconditionally, so a guard keyed on
`-Dtarget` there breaks every cross-target gate instead of only the step you
meant to restrict. Choose the *work* conditionally — run where this host can
run the target, compile only where it cannot — and leave the executor question
to the steps the build runner governs, which is what `test` does now. And when
a search finds no API, the honest conclusion is "I did not find it": grep for
the concept, not
for the name you happened to guess, before writing that it does not exist.

**Verification status.** Designed; source-confirmed against the pinned
`lib/std`, not compiled or run by this author.

---

## 21. A runtime `continue` inside an `inline for` is comptime control flow

**Symptom / evidence.** `zig build test -Doptimize=Debug` stopped at
`zig/kat_test.zig:78`:

```
error: comptime control flow inside runtime block
```

`random123-facade` passed 6/6 in the same run; the failure was the known-answer
test's generator dispatch and nothing else (parent receipt, OBSERVED by the
integrator).

**Cause.** *Confirmed, language semantics.* The fixture's generator name is a
slice read out of the embedded text at run time, so `std.mem.eql(u8, name,
alg.name)` is a runtime condition. `inline for` unrolls at compile time and its
`continue` is a compile-time jump, so reaching one from inside a runtime branch
is the error the compiler names. Nothing about the fixture or the generators is
involved: the loop only ever needs the *comptime* payload (`alg.Generator` and
`alg.n_ctr`/`alg.n_key`) to type the parse loop and the word loop, which are
both `inline for` over `0..alg.n_ctr` and stay compile-time.

**Fix / constraint.** The runtime comparison now selects a block instead of
short-circuiting the unrolled loop:

```zig
inline for (algorithms, 0..) |alg, index| {
    if (std.mem.eql(u8, name, alg.name)) {
        matched = true;
        replayed[index] += 1;
        ...
    }
}
```

Every other iteration of the unrolled loop simply does not run. The fixture, the
generators, the fixture import and the assertions are unchanged.

**Reusable rule.** `inline for` over a comptime-known table is the right tool
for *types*, not for a runtime key. When the key arrives at run time, select a
block inside the unrolled body; `continue`, `break` and `return` inside an
`inline for` body are compile-time jumps and cannot be reached from a runtime
branch.

**Platform / version.** Zig 0.16.0; any project that unrolls a comptime table
over a runtime key.

**Verification status.** Corrected in source; not compiled or run by this
author. The parent's `zig build test` is the gate.

---

## 22. A fixture replay that only counted lines could pass with a generator
      missing

**Symptom / evidence.** Design defect, not an observed failure. The portable
known-answer test asserted `matched` for each fixture line and `checked > 0` at
the end. Both hold while one of the eight generators is absent — from the
fixture, from the dispatch table, or from the facade — because the seven that
remain still produce lines. `checked` counted lines, not generators.

**Cause.** *Structural.* A count of fixture lines says the file was read; it
does not say every generator the package advertises was exercised. The same
held on the AES-NI/ARS side, where a `checked > 0` would be satisfied by four
AES-NI lines alone with no ARS line at all.

**Fix / constraint.** The portable test keeps one counter per entry in the
dispatch table and fails naming the generator whose counter is zero; the
AES-NI/ARS test counts the two families separately. Both are behavioural
assertions about coverage of an independent fixture, not constants pinned to a
value.

**Reusable rule.** When a test replays a table of known answers, count by the
key, not by the row. "I read some of the file" and "I checked every generator I
ship" are different claims and only the second one catches a dropped entry.

**Verification status.** Corrected in source; not compiled or run by this
author.

---

## 23. Upstream refuses riscv64 and wasm32 outright

**Symptom / evidence.** `zig build matrix` failed on two of the six contract
targets, in the C library and in `addTranslateC` alike (parent receipt,
OBSERVED by the integrator):

```
Random123/features/gccfeatures.h:38:4: error: "This code has only been tested on x86, powerpc and a few arm platforms."
Random123/features/gccfeatures.h:39:10: error: 'including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_task' not found
```

`include/Random123/features/gccfeatures.h:37-45` is

```c
#if !defined(__x86_64__) && !defined(__i386__) && !defined(__powerpc__) && !defined(__arm__) && !defined(__aarch64__) && !defined(__s390x__)
#  error "This code has only been tested on x86, powerpc and a few arm platforms."
```

**Cause.** *Confirmed from source.* The guard is not a value a caller
supplies, it is an `#error` inside the feature header that
`features/compilerfeatures.h:200-226` selects **by compiler**:
`compilerfeatures.h:215-218` picks `clangfeatures.h` for `__clang__`, and
`clangfeatures.h:91` includes `gccfeatures.h` outright. `array.h:34` includes
`compilerfeatures.h`, so the guard is reached from every Random123 header
before a single generator is declared. Nothing on the command line reaches it,
because the only preprocessor input the guard reads is the compiler's own
predefines. Upstream says what changing it would take
(`features/gccfeatures.h:41-44`): "Feel free to try the Random123 library on
other architectures by changing the conditions that reach this error, but you
should consider it a porting exercise and expect to encounter bugs and
deficiencies."

**Fix / constraint.** None available within the fork's rules, and that is the
finding rather than a gap. Editing `gccfeatures.h` would be editing upstream
source; a real port is upstream's call to make and to validate; and defining
`__arm__` for riscv64 or `__aarch64__` for wasm32 would silence a correct
diagnostic with a false claim about the target. So the two targets keep failing
in `zig build matrix`, which still attempts all six contract targets, and the
limit is written down in `UPSTREAM.md` ("Upstream architecture guard") and
`CHANGELOG.md` entry 23 instead of being designed around.

**Platform / version.** riscv64, wasm32; Random123 1.14.0; no ABI change, and
the installed upstream headers are unchanged.

**Reusable rule.** When a vendored header set refuses an architecture, look at
whether the refusal is a *value* or a *directive*. A value has a documented
override and the vendor's problem is a missing multiply. A directive has to be
edited, and the honest package records the limit instead of removing the target
from its own matrix. `-D`-defining a predefine to get past it is the failure
mode to avoid: it makes the build green and the library wrong.

**Verification status.** Recorded, not fixed; not compiled or run by this
author. `zig build matrix` is the gate, and it is expected to fail on these two.

---

## 24. `-maes` does not define `__AES__`

**Symptom / evidence.** `zig build matrix` failed the AES-NI variant of both
x86 contract targets, 17 errors each, all of the form "use of undeclared
identifier 'aesni4x32_key_t'" and "call to undeclared function
'ars4x32keyinit'" (parent receipt, OBSERVED by the integrator). The failing
compile line carried `-maes -DR123_BRIDGE_HAS_AESNI=1`.

**Cause.** *Confirmed from the diagnostic, then from source.* `aes.h:40` and
`ars.h:38` wrap their contents in `#if R123_USE_AES_NI`, and
`features/gccfeatures.h:113-119` defines that from `__AES__`. The 17 errors
mean `R123_USE_AES_NI` was 0, so `__AES__` was not defined — despite `-maes`
being on the command line. `__AES__` is a property of the target CPU;
Zig's driver does not turn a `-maes` cflag into one, so the cflag was
inert. The dangerous part is what the old build did with that: the header
kept declaring the AES-NI wrappers, the library compiled without them, and
nothing failed until a consumer linked.

**Fix / constraint.** `withX86Aesni` in `build.zig` adds the `aes` feature to
the target query — the mechanism `-Dcpu=baseline+aes` uses, and the one a
compiler actually reads — for every copy of a target that compiles the AES-NI
path, and returns a target that already has the feature untouched so a native
build on an AES-capable host is not retargeted for nothing. `-maes` stays on
the compile line as upstream's spelling. `random123_bridge.c` then
static-asserts `R123_USE_AES_NI` wherever `R123_BRIDGE_HAS_AESNI` is defined,
so the build's gate and upstream's gate can never disagree silently again.

**Platform / version.** x86 and x86_64; Zig 0.16.0 driver; Random123 1.14.0.

**Reusable rule.** A feature macro derived from a compiler predefine is a
statement about the target, not about the cflags, and a compiler is entitled
to ignore a cflag that contradicts its target. When a header library gates code
on such a macro, set the *target feature* and assert the macro: the assert is
what turns "this code quietly vanished" into a build error.

**Verification status.** Corrected in source; not compiled or run by this
author. The AES-NI variant of `zig build matrix` is the gate.

---

## 25. "Header-only, therefore nothing to package" is the wrong conclusion

**Symptom / evidence.** A packaging design question with no source answer:
`build.zig:135-137` builds the one artifact in this package with
`.linkage = .static`, and the migration contract asks for separate static and
shared deliverables. Upstream produces no linkable symbol at all
(`FORK-NOTES.md` entry 2), so the obvious reading is that a shared variant would
package nothing useful.

**Cause.** That reading mistakes the *absence of an upstream ABI* for the
absence of an ABI. This fork already has one: `r123_bridge_*` is a real
external C surface of 33 symbols — 28 unconditional, 5 behind the AES-NI gate —
whose signatures use upstream's `r123arrayNxW` structs by value and are
static-asserted against `sizeof` in `random123_bridge.c`. An installed shared
object exporting those is a useful, ordinary library artifact: it is what a
consumer links when it does not want to compile the bridge itself.

**Fix / constraint.** The bridge is packaged exactly like any other library:
static by default (the existing default, unchanged), `-Dlinkage=dynamic` for
the shared variant, both installing the same 26 upstream headers plus
`random123_bridge.h`. In Nix they are two packages out of one `package.nix`,
not two SDK modules, because linkage is a property of the artifact and the Zig
module is the same either way.

**Platform / version.** Any. Zig 0.16.0; Random123 1.14.0.

**Reusable rule.** When a vendored project is header-only, ask what the
*package* exports before concluding it has nothing to install. If the fork
wrote an ABI, the ABI is the artifact, and it inherits every packaging
obligation a binary has — both linkages, link metadata, and a licence closure.

**Verification status.** Corrected in source and in `package.nix`; no build or
`nix build` has observed either variant.

---

## 26. The upstream tree does not carry one notice

**Symptom / evidence.** `NOTICE.md` said Random123 is "distributed by D. E.
Shaw Research under the BSD 3-Clause licence" and reproduced `LICENSE`, which
is true and incomplete. A per-file sweep for `Copyright` found
`include/Random123/features/clangfeatures.h:2` stating "Copyright 2010-2016"
rather than 2010-2011, and
`include/Random123/features/pgccfeatures.h:33-44` carrying an entire second
notice below the first: `Copyright (c) 2013, Los Alamos National Security,
LLC`, produced under U.S. Government contract `DE-AC52-06NA25396`, reserving
Government rights to use, reproduce and distribute the software, disclaiming
warranty and liability for the Government and LANL, and adding a condition of
its own — modified software "should be clearly marked, so as not to confuse it
with the version available from LANL".

**Cause.** Not a defect and not a relicensing: it is upstream carrying a
contributed file's own provenance. `pgccfeatures.h:1` records how it got
there — "contributed via email by Gabriel Rockefeller on 8/5/2013". A sweep that
stops at `LICENSE` reads one notice for a tree of many.

**Fix / constraint.** `NOTICE.md` §3 is now the per-file inventory: which
files carry which year, which single file carries two notices and what those
notices say, and — the part that matters operationally — whether this package
compiles each one. `pgccfeatures.h` is selected only under `__PGI`
(`features/compilerfeatures.h:219-220`), so it is retained and installed but
never compiled here, which does not make its notice optional: the file ships,
so both notices must travel with it. `UPSTREAM.md`'s Copyright and Licence rows
and `FORK-LICENSE.md` §5 say the same thing, and `package.nix` installs the
whole upstream header tree unchanged.

**Platform / version.** Random123 1.14.0; no platform dependency.

**Reusable rule.** Sweep for `Copyright (c)` and `Licensed under`, not for the
project name in `LICENSE`. A single vendored file with a second notice changes
what a redistribution obligation is, and "we never compile it" is a build fact
that does not reach the obligation.

**Verification status.** `SOURCE-CONFIRMED` by reading the files. No licence
audit has been run.

---

## 27. `b.standardTargetOptions` makes a Nix build depend on the builder

**Symptom / evidence.** `build.zig:38` uses `b.standardTargetOptions(.{})`,
which with no `-Dtarget` resolves to the *native* target, and the CPU model
comes from the machine running the build. This package's own AES-NI logic
(`resolveAesniTarget`, `withX86Aesni`) keys off exactly that CPU:
`aesni = requested orelse (isX86(target) and cpuHasAes(target))`.

**Cause.** Nothing is wrong with either piece; they are simply the wrong pair
of defaults for a content-addressed build. Without a pinned CPU, one commit
produces different bytes on an AES-capable builder than on a baseline one —
and the difference is invisible in the store path until someone compares two
machines.

**Fix / constraint.** `package.nix` passes `-Dcpu=baseline` on every Nix build
and defaults `aesni = false`, which makes the two agree by construction: no
optional CPU feature, so no AES-NI wrappers, regardless of the builder.
`aesni = true` is available to a packager and is paired with `-Daesni=true`.
`dontSetZigDefaultFlags = true` is set so nixpkgs' zig setup hook does not
append its own `-Dcpu=baseline --release=safe` behind the derivation's back;
both of those flags are wanted, and they are wanted visibly.

**Platform / version.** Any nixpkgs platform; Zig 0.16.0. The same reasoning
applies to any hermetic packaging of a `standardTargetOptions` build.

**Reusable rule.** In a reproducible build, pin the CPU model, not just the
target triple. A build whose feature selection reads the builder's CPU is a
build whose output is a property of the machine, and the store will not tell
you which one it was.

**Verification status.** Corrected in source; no `nix build` has been run, so
this is a design statement about what `package.nix` asks for, not an observed
property of any output.

---

## 28. Relocating an upstream README touches files three roles own

**Symptom / evidence.** Making `README.md` the fork's canonical document means
upstream's bytes have to live somewhere exact, which means `README.md` stops
being a file this fork carries unmodified. Three records in this repository
assert that it does, in three files owned by three different roles:
`UPSTREAM.sha256:12` (provenance), `NOTICE.md` §1 (provenance) and
`.github/workflows/verify.yml:39` (build/CI), which diffs `README.md` against
the pinned upstream tag and would now fail on the fork's own prose.

**Cause.** A single rename is not a single-file change here. The digest is not
the thing at risk — upstream's bytes are unchanged and stay unchanged — but the
*path* is what three independent checks name.

**Fix / constraint.** `README.upstream.md` holds the exact bytes
(`71a51dfa922bee8352ba5500ec97ab80875c712dc759528e8fc5ec5b1fd0b28f`, verified
identical to the old `README.md` before anything moved) and `UPSTREAM.sha256`
carries that path with the same digest, at the same record count. The CI
pinned-tree diff and the required-file list belong to the build role and were
asked for explicitly rather than edited here.

**Platform / version.** No platform dependency.

**Reusable rule.** Before relocating a vendored file, grep the whole repository
for its path, not just the integrity manifest. Every check that names the path
is a place the move can break, and they are usually owned by different people.

**Verification status.** Byte comparison done by this role; `sha256sum -c
UPSTREAM.sha256` has not been re-run since the path changed, and CI has not
been run.

---

## 29. The Windows module definition may need a `LIBRARY` line, and nobody has
      linked it yet

**Symptom / evidence.** None. This is a risk recorded before it becomes a
failure, and it is recorded here because the shared build on
`x86_64-windows-gnu` is a required gate. `addWindowsExports` in `build.zig:343`
writes the generated `.def` starting at `build.zig:348`:

```zig
out.writer.print("EXPORTS\n", .{}) catch @panic("OOM");
```

There is no `LIBRARY random123` line above it. That is the whole content of the
observation: a module definition whose first token is `EXPORTS`.

**Cause.** *Not established.* The build role reports, as a check of the
compiler's own sources rather than a run, that a bare `EXPORTS` section is valid
lld-link input, and that if the Windows link turns out to object, the fix is one
line — a `LIBRARY random123` line ahead of `EXPORTS` in `addWindowsExports`. The
reason for wanting a name is that a DLL gets its module name from that line; a
missing one means the linker picks a default, which affects what a consumer
loads by name rather than whether it links at all.

**Fix / constraint.** None pre-emptively. The build role owns `build.zig` and
owns the `.def`; it will add the line on a reported failure and not before,
because nobody has observed a Windows link and editing an unobserved problem is
how a build graph acquires cargo-cult lines. Recorded here so that when the
driver's shared-library gate reports a module-definition complaint, the cause
and the one-line fix are already written down instead of being rediscovered.

**Platform / version.** `x86_64-windows-gnu` and any COFF dynamic build with
`-Dlinkage=dynamic`; ELF and Mach-O shared builds are unaffected because
`build.zig:271` generates the `.def` only for a `.dynamic` linkage on a COFF
target.

**Reusable rule.** A generated export list is one of the few build artifacts
that no cross-compile-to-ELF check exercises. When a package's required matrix
includes a Windows shared build, name the platform-specific artifacts that have
never been linked on the platform that would produce them.

**Verification status.** Not observed by anyone. No Windows link has been run.
Reported by the build role and recorded, not confirmed.

## 30. A refusal for an earlier reason still satisfies an expectation

**Symptom / evidence.** The runtime-loaded gates reported
`expected error.ProviderMismatch, found error.InvalidSource` from
`runtime/load_tests.zig`, in the one test whose subject is byte comparison. That
test built its second request as `"./" ++ providerPath`; `Loader.load` validates
the spelling of a request before it asks whether it is the one already in use
(`runtime/loader.zig:366`), and a relative `.path` is refused at
`runtime/loader.zig:194`, so the comparison the test was written to observe was
never reached. The other two failures in the same run were crashes in
`alienPath`: the driving harness exported `RANDOM123_TEST_PROVIDER` and not
`RANDOM123_TEST_ALIEN`, and the root skips nothing when a provider cannot be
named.

**Cause.** Two mistakes of one shape. Asserting an error does not check the step
that produces it: any earlier refusal for the same input satisfies the
expectation, and the report then reads as though the intended step disagreed
with the implementation. An error assertion is evidence about the *first*
refusal the implementation can produce for that input, so the input has to be
valid in every other respect. And a provider that comes from the environment is
a contract with the caller in two halves: exporting one of the two variables is
not a smaller version of exporting both.

**Fix / constraint.** The alternate request is now the provider's own absolute
path with a `.` component inserted after the root — a no-op component in POSIX
pathname resolution, so it is the same file with different bytes, which is
exactly the property the test is about. The loader is untouched:
`InvalidSource` before the comparison is the right order, a malformed request
is not a rival provider, and its own test pins both spellings of that refusal.
`RANDOM123_TEST_ALIEN` stays mandatory and unskippable, and the root's module
comment and panic message now say that it must be an absolute path to a file
that opens and exports none of the `r123_bridge_*` names, and why a file that
cannot open would exercise `OpenFailed` instead. `README.zig.md` records both
variables for the runtime test route, with this package's own workflow recipe:
`libm.so.6` from `ldconfig -p` on the machine, not a path written down.

**Platform / version.** The runtime route on any target with a dynamic loader,
and the harness recipe is POSIX-specific because it names a host object. The
absolute-path requirement holds on Windows too, where the loader refuses a
relative `.path` through the same `validateSource`.

**Reusable rule.** When a test asserts a refusal, construct the input so every
earlier check in the implementation passes; otherwise the assertion measures
the wrong refusal and reports it as a disagreement about the right one. When a
suite's provider comes from the environment, list every variable the source
reads — not the ones the first failure named.

**Verification status.** `SOURCE-CONFIRMED` from `runtime/load_tests.zig`,
`runtime/loader.zig` and the integrator's receipt for the eight loaded gates.
`PENDING-VERIFICATION`: the repaired test has not been run, and the loaded
gates have not been re-run with `RANDOM123_TEST_ALIEN` exported.

## 31. A claim that a capability is absent outlives the tree that refutes it

**Symptom / evidence.** `README.md` §3 and `README.zig.md` said `-Druntime=true`
was "not in this tree yet" and needed "the runtime graph module, which lands
after the BLAKE3 pilot's verification", five lines above documenting the two
environment variables that option's own test requires. `CHANGELOG.md` entry 28
said the same thing as history. Nothing in the tree supported it: `build.zig`
declares the option and threads it into the facade, into `check`, into
`matrix`, into the loader's own test root and into the nested consumer build;
`runtime/graph.zig` supplies the dispatch module; `root.zig` publishes
`runtime_loaded`, `LoadSource`, `LoadError`, `load` and `loadedSource`; and
this fork's own workflow ran `test`, `smoke`, `check`, `install`, `consumer`
and every cross `check` with the flag. A second instance of the same shape sat
in the same documents: "`flake.lock` and `devenv.lock` are the integrator's to
write", read out of a tree that contains `flake.lock`.

**Cause.** A status cell is written once, when the option is being *designed*,
and then copied by whoever writes the next document. The copy inherits the
claim and nobody re-reads it, because the sentence is about an option that is
already written down somewhere else — so the one place a reader checks first,
the table, is the one place nothing is checked. The failure is directional and
that is what makes it worth a rule: the sentence survives exactly as long as the
capability stays missing, and dies the moment it arrives, which is the moment
nobody edits the prose again. A staged-delivery sentence is a temporary claim
written with permanent grammar.

**Fix / constraint.** The status cell now separates the two things it was
conflating: what is *in the tree* (`SOURCE-CONFIRMED`, cited to the lines that
declare and thread the option) and what was *observed* (a dated gate result,
red or green, named as a run). The lock-file paragraphs record what
`flake.lock` actually contains — the revision `flake.nix` already named, its
`narHash` and its lock format — and keep `devenv.lock`, which really is
absent, described as absent. `CHANGELOG.md` entry 27 and entry 28 keep the
original wording with a dated correction beside it rather than being rewritten
silently, so the record shows that the claim was made and why it was wrong.

**Platform / version.** None: this is a documentation defect about a Zig 0.16
package, and it binds wherever a status table is written before the code it
describes lands.

**Reusable rule.** A status cell records two independent facts — what the source
has, and what a run has seen — and a correction has to state which one it is
changing. "Lands later", "not yet", "pending" and "absent by design" are
claims about a tree; when the tree moves, re-read the file the sentence is
about before re-reading the sentence. If a document can be contradicted by one
`read` of a path it names, it is a claim, not a description.

**Verification status.** `SOURCE-CONFIRMED` from `build.zig`,
`runtime/graph.zig`, `root.zig`, `flake.lock` and
`.github/workflows/verify.yml`, against the eight loaded and eight linked gate
receipts of 2026-10-04 for the observations they state. Those receipts run
between 15:01 and 15:15 UTC and four build files changed after them, so they
describe a snapshot, not this tree — which is why both READMEs now say "on the
tree of that hour" beside every observed result rather than "on this tree".
The corrections were `PENDING-VERIFICATION` when this entry was written: no gate
reads prose, and the loaded replay was owed `RANDOM123_TEST_ALIEN`. **That gap
has since closed.** The eight loaded and eight linked configurations were re-run
on the current graph on 2026-10-04 — receipts
`loaded-final-evidence/20261004T232823091897Z-23133/run.json` and
`native-final-evidence/20261004T233628757747Z-69351/run.json` — with
`RANDOM123_TEST_PROVIDER` naming this tree's own `librandom123.so`
(`provider.kind: "own"`) and `RANDOM123_TEST_ALIEN=/lib64/libm.so.6`; every cell
exits 0. What is still unexercised on this graph is `check` and `matrix` under
`-Druntime=true`, `-Dlinkage=dynamic` on those two steps, and the nested
`consumer/` build.

## 32. A per-file licence inventory is per file, including the ones a new
      subsystem brings

**Symptom / evidence.** `NOTICE.md` §2 is this workspace's per-file licence
inventory. It listed the build graph, the module, the facade, the bridge, the
tests, the smoke example, the consumer and the packaging files, and it did not
mention `runtime/` at all — seven fork-authored files, including the one that
opens a provider and the one that writes the dispatch, were absent from the
only record that claims to be exhaustive. Four of those seven carry a
`Copyright` line under their SPDX identifier and three carry the identifier
alone, which the table also did not say.

**Cause.** An inventory is written once per *package*, and a subsystem that
lands later inherits the package's licence label instead of getting rows. The
label is true — the whole tree really is BSD-3-Clause — which is exactly why
the omission is silent: nothing fails, and the document that exists to catch
per-file exceptions is the one file nobody re-reads when a directory appears.

**Fix / constraint.** Every file in `runtime/`, plus `zig/provider.zig` and
`flake.lock`, is now a row with what it is. The table records which files
repeat a `Copyright` line and which carry the SPDX identifier alone, and says
that the difference is only whether the notice is repeated — the grant is one
grant either way.

**Platform / version.** None.

**Reusable rule.** When a subsystem adds files to a tree whose licence record
is per file, the licence record is part of that subsystem's landing. A label
that happens to be correct for every file is still not an inventory, because
the record's value is entirely in the per-file exceptions.

**Verification status.** `SOURCE-CONFIRMED` from the first lines of each file
named and from `FORK-LICENSE.md` §3. `PENDING-VERIFICATION`: the licence gate
that reads this file is the driver's.

## 33. The translator is not the compiler, and a header can tell them apart

**Symptom / evidence.** The `powerpc`, `powerpc64` and `powerpc64le` cells
could not be translated at all, and every NetBSD cell failed inside
`zig translate-c` on `_Pragma` — with the C archive compiled, `zig cc`
compiling the same headers for the same targets without complaint, and the
bridge's own compile line green. That asymmetry is the whole finding: the same
bytes, read by two front ends, one of which succeeds and one of which cannot.

**Cause.** *Confirmed from source.* `zig translate-c` parses with Aro, and Aro
preprocesses as well as parses. Random123's
`include/Random123/features/compilerfeatures.h:215-218` picks a feature header
**by compiler**: `clangfeatures.h` on `__clang__`, `gccfeatures.h` on
`__GNUC__`. Aro defines `__GNUC__` and does not define `__clang__`, so every
target's translated view of Random123 was the GCC view while the compiled
bridge is the Clang view — and two families turn on that difference:

* `gccfeatures.h:47-49` is `#if defined(__powerpc__) && !defined(__clang__)`
  followed by `#include <ppu_intrinsics.h>`. The GCC-only branch is taken
  precisely *because* the front end is not Clang, and it is unconditional, so a
  target whose multiply comes from `R123_USE_MULHILO64_C99` still reaches the
  include. Reading `gccfeatures.h:249-261` explains why the guard is written
  that way at all: under `defined(__clang__)` upstream *defines*
  `__mulhdu`/`__mulhwu` inline, and only the GCC path expects them from a
  system header. A header can therefore tell the two front ends apart, and here
  it does, by branching on what the compiler calls itself.
* NetBSD routes `__END_DECLS` through `_Pragma` framing in `sys/cdefs.h`, and
  Aro destringizes each operator invocation into a `#pragma` line it then hands
  to the parser as C. Every system header this package reaches closes a
  declaration block with it: `<stdint.h>` from the bridge header,
  `<stddef.h>` from `array.h:43`, `<assert.h>` from `gccfeatures.h:68`.

Defining `__clang__` for Aro would look like the one-line fix and is not
available: `clangfeatures.h` calls `__has_feature` at `:44`, `:48`, `:65` and
`:69`, and Aro answers no `__has_feature` either. It is also the failure mode the
reusability note at the end names — a build that goes green and describes a
compiler this build did not use.

**Fix / constraint.** `translationRoute` and `preprocessedBridgeHeader` in
`build.zig`, the mechanism `erfa` and `utf8proc` already run in this workspace:
for the powerpc family and for NetBSD, the target's own C preprocessor
(`zig cc -E -dD`, the compiler that is compiling the bridge) expands the bridge
header first, for the target being built, on the same `include/` root and with
the same three macros `addBridge` puts on the translation line, and Aro parses
what came out. Every other target keeps the route it had.

Four constraints carried deliberately:
* `-dD`, because Random123's own `R123_*` defaults are object-like `#define`s
  that no declaration in the bridge header *uses*; a dump of used macros only
  would take the whole constant set with it.
* `-MD`/`-MF`, because the twenty-six upstream headers are reached only through
  `#include` and a `-I` directory contributes nothing but its own resolved path
  to a run step's manifest. Without a depfile a later `array.h` would be served
  from the run cache against a stale translation.
* The compiler's own `__int128_t`/`__uint128_t` ahead of the header, under
  `__SIZEOF_INT128__`. Clang declares those next to the `__int128` primitive
  and no libc header repeats them, so `-dD` keeps a spelling nothing in the
  expansion defines, and `generic-netbsd/arm/cdefs.h:62-63` names one:
  `__ALIGNBYTES` is `(sizeof(__int128_t) - 1)` on the `__ARM_PCS_AAPCS64`
  branch. It is a declaration of the compiler's own extension under the
  compiler's own statement that the target has it, not a patch to any upstream
  header. `erfa`, `utf8proc`, `lmdb` and `pcre2` each carry the same four lines
  for the same reason; this package's translation root is
  `zig/bridge/random123_bridge.h`, whose body this role does not own, so the
  declaration is force-included with `-include` instead.
* The route's surface is *additive*, and that is stated rather than left to be
  discovered. A `-dD` dump covers every header on the path, so on this route
  `pub const c` also carries the C library's own macro constants and
  declarations where the `aro` route carries only the ones something in the
  translation referred to. Every name this package's own surface is built from
  — the `r123arrayNxW` structs, the 33 `r123_bridge_*` declarations, the
  `R123_BRIDGE_*` enumerators — is on both routes. The one place the extra
  surface is visible is the runtime dispatch: `runtime/graph.zig:97-100`
  classifies a translated `extern` as C-library noise by name, and
  `__assert` (NetBSD's spelling) is already on that list, so the assertion
  failure function the powerpc and NetBSD cells reach through
  `gccfeatures.h:67-70` stays direct. That file is not this role's, and
  `-Druntime=true` is not one of the published matrix configurations
  (`cross-test.profile.sh:98` runs every cell with `-Druntime=false`), so
  nothing here depends on the difference.

Nothing upstream changed, no predefine was invented for any architecture, no
option, step, wrapper, constant, generator or fixture was removed, and the arch
guard at `gccfeatures.h:37-45` still refuses every architecture it refuses
(entry 23). `riscv64` and `wasm32` are still red for that reason and only that
reason.

**Platform / version.** `powerpc`, `powerpc64`, `powerpc64le` and every NetBSD
target; Zig 0.16.0 `zig translate-c`/Aro; Random123 1.14.0. No ABI change and
no change to the installed header set.

**Reusable rule.** When a vendored header selects behaviour by `__GNUC__` and
`__clang__`, the front end that *translates* it and the compiler that *compiles*
it are two different programs with two different ideas of what the compiler is,
and the header can tell them apart. Reach for the compiler's own preprocessor,
not for a `-D` that tells the translator what it is not. The same shape is
behind the NetBSD `_Pragma` failure and behind every `__ALIGNBYTES` /
`__int128_t` failure in this workspace: the expansion a real compiler writes is
already the answer, and the only thing missing was a step to produce it with the
same compiler, the same target and the same macros as the compile.

**Verification status.** `SOURCE-CONFIRMED` from
`include/Random123/features/compilerfeatures.h`, `gccfeatures.h`,
`clangfeatures.h`, `array.h` and `zig/bridge/random123_bridge.h`, and from the
`erfa`/`utf8proc` routes this reuses. **The named checks have now run, on
2026-10-04/05, and they are what `README.md` §3 and `CHANGELOG.md` 39 record.**
The six-row `zig build matrix` baseline exits 1 —
`Build Summary: 45/58 steps succeeded (4 failed)`, `declared_target_count 6`,
`test_pass_lines: []` — and its two failing triples, `riscv64-linux-gnu` and
`wasm32-wasi`, fail inside upstream's `gccfeatures.h` gate, not in the
translation route this entry is about.
The 53-cell cohort (`20261004T221720228710Z-45046/random123-53-target-8.json`,
exit 1) settles the NetBSD half of this entry's platform list directly. **Seven
NetBSD cells build** — `aarch64-netbsd`, `aarch64_be-netbsd`, `arm-netbsd`,
`armeb-netbsd`, `powerpc-netbsd`, `x86-netbsd` and `x86_64-netbsd` — each
`build=pass run=unavailable`, so the translation route is compile-visible and
unbroken on all seven and none of them is a runtime claim. **Two NetBSD cells do
not reach it**: `mips-netbsd` and `mipsel-netbsd` stop in the preprocessing step,
at `gccfeatures.h:39`'s
`#include <including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_file>`,
which is upstream's own header and not this entry's fix — the two 64-bit MIPS
OpenBSD cells, `mips64-openbsd` and `mips64el-openbsd`, stop at the same line. On
the powerpc family the route is exercised at run time: `powerpc-linux`,
`powerpc64-linux` and `powerpc64le-linux` all build and all execute, and the two
64-bit cells fail inside `philox.h` on wrong known answers rather than on any
translation error, which places that failure below the translator.

## 34. A script that changes nothing about the caller's directory still depends
      on it

**Symptom / evidence.** In acceptance run `20261004T175328Z`, `devenv:consumer`
printed `error: no build.zig file found, in the current directory or any parent
directories` and `devenv:integrity` printed `sha256sum: UPSTREAM.sha256: No
such file or directory`. Both entries were present in the observed catalogue,
so this is not the missing-entry shape; the bodies ran and were standing in the
wrong tree. `nix build path:…#static path:…#shared` passed for this SDK in the
same run, so nothing here is a build-graph problem.

**Cause.** Confirmed from the driver and from the shell wrapper it produced. The
canonical environment is entered as `devenv --from path:<sdk> …` with the
working directory set to a scratch project directory, so the autolock, the
profile cache and `.devenv/` stay off the repository. devenv materialises both
tasks and scripts as generated shell programs under `/nix/store` that inherit
the caller's cwd — the receipts show the `/nix/store/…-sdk-consumer` prefix on
the failing line. A body that is only `zig build consumer` therefore resolves
against a directory holding `.devenv/` and `devenv.lock` and nothing else. A
per-entry `cwd` option cannot fix this, because it would not reach the
generated shell program; and `$DEVENV_ROOT` is that scratch project, so a body
that `cd`s to it lands in the same empty place.

**Fix / constraint.** `devenv.nix` binds `sdkRoot = builtins.toString ./.`. The
`./.` path literal is relative to the file that names it, so it is this
checkout whatever the caller's cwd is; `builtins.toString` converts the path
without interpolating it into a string literal, which keeps the result this
working tree rather than a copy of the whole SDK in the read-only store. All
nine bodies begin `cd "${sdkRoot}"`. No host path appears in the file, and
there is no per-caller configuration to get wrong.

Two consequences carried deliberately. Script names are unchanged, including
the two the acceptance driver runs: a dotted script name is legal and
renaming `consumer` or `provenance` would break a mapping that already works.
And a body that changes into the checkout inherits a second mistake from it.
`install` defaulted `--prefix` to `$PWD/zig-out`, and `build` — a bare
`zig build` — has the same defect by a shorter name, because Zig's default step
*is* the install step (`build.zig:266` calls `b.installArtifact` on the
bridge). Both now resolve `--prefix` through one shared shell function,
`externalPrefix`: a prefix the caller passed (`install` only; that argument is
this SDK's `install` API and stays there), else `$ZIG_LOCAL_CACHE_DIR`, else
`$XDG_CACHE_HOME`, else `$TMPDIR`, and with none of the three exported the
script says what it needs and exits non-zero rather than invent a location. One
copy of the precedence, because two copies would drift and only one of them
would be tested.

The other seven bodies carry no prefix, and that is read out of the graph rather
than assumed: `addConsumerStep`'s `consumer` step and `consumer/build.zig:77`
each take just `&run.step`, so nothing they run depends on this package's own
install step. A `--prefix` there would change nothing this graph delivers, and
their intermediates go to the cache `ZIG_LOCAL_CACHE_DIR` already places
outside the checkout.

The workflow reached the same hole by a third route and is now closed there too.
`.github/workflows/verify.yml` ran the `native` job's build step with no
`--prefix`, so the three matrix cells whose `flags` name no step wrote
`zig-out/` into the checkout, and its `runtime` job passed `--prefix
"$PWD/provider"`, which is that tree under another name. Both now install under
`$RUNNER_TEMP`, the runner's own directory outside `$GITHUB_WORKSPACE`. The
cells that name a step take no prefix, for the reason in the paragraph above.

**Platform / version.** Every `devenv` version in this workspace, any caller
whose cwd is not this checkout; devenv 2.4.1 and the pinned devenv-nixpkgs
`c2f38fe7f9e04d9aadd354d380f2bd40531d9737`. No Zig, no ABI, no installed
header and no build-graph change; `devenv.yaml` and `package.nix` are
untouched.

**Reusable rule.** A task or script body that names a file relative to the
package — `build.zig`, `UPSTREAM.sha256`, `consumer/` — is written against an
assumption the runner does not guarantee. devenv hands the generated shell
program the caller's working directory, not the package root, and
`--from path:<sdk>` deliberately lets that differ from the checkout. Locate the
root from the module that owns the entry (`./.`), and never from `$DEVENV_ROOT`,
which names the scratch project. Where the body also writes, send the output
beneath a cache directory the caller exported rather than into the tree it just
changed into.

**Verification status.** `OBSERVED` on the two failures above, from acceptance
run `20261004T175328Z`. `SOURCE-CONFIRMED` for the fix: the `./.` literal, the
`builtins.toString` conversion and all nine `cd` lines are read out of
`devenv.nix` as it now stands, and the `.devenv/`-only contents of a scratch
project directory are read out of the driver's own record. `OBSERVED` for the
repair by the two bodies that were run: acceptance run `20261004T214134Z`, gate
`devenv:integrity` exit 0 after 0.46s and gate `devenv:consumer` exit 0 after
7.524s, each entered as `devenv shell --from path:<sdk> …` from a scratch
project directory and each finding the file it names there. Bounded: two
bodies, not all nine.

## 35. A flag the build runner never accepted, reachable only through an
      exported environment variable

**Symptom / evidence.** Acceptance run `20261004T193710Z`, `devenv:consumer`,
exit 1 after 42.7s:

```
unrecognized argument: '--cache-dir=/home/tmp2/gertullj/cache/zig-local/consumer'
  access the help menu with 'zig build -h'
failed command: cd …/foundation-libs/random123/consumer && …/zig build run
  -Dtarget=native -Dcpu=native -Doptimize=Debug -Dlinkage=static
  -Druntime=false --cache-dir=/home/tmp2/gertullj/cache/zig-local/consumer
```

The inner `zig build` rejected its own argument list, so `consumer/` was never
compiled and the outer graph reported `0/2 steps succeeded (1 failed)`. The
same `build.zig` passes in a shell that exports no cache directory, because the
branch that emits the flag is guarded on a non-null cache path.

**Cause.** Two independent facts, both read out of the pinned compiler rather
than recalled. First, the argument: `zig build` documents `--cache-dir [path]`
(`build_runner.zig:1674`) and its option loop recognises `-D…`, `-Z…`, a fixed
list of long options, `-j…`, `-f…` and `--`; any other `-`-prefixed token is
`fatal("unrecognized argument")` (`:160`, `:431-433`). `--cache-dir=` is not
among them. `zig test` *does* take `--cache-dir=` as one token
(`test_runner.zig:58-59`), which is exactly the trap — the two subcommands
disagree about the same option. Second, the reachability: the emitting branch
is `if (b.cache_root.path)`, and `host-scratch.sh` exports
`ZIG_LOCAL_CACHE_DIR`, which devenv passes into the task's environment. So the
bug is invisible in every shell that does not export one, and the acceptance
driver — which sources the same script the gates are told to use — always does.

**Fix / constraint.** Two arguments, `--cache-dir` then the path. The
subdirectory stays: two build graphs must not write one cache manifest, and a
null path still means the nested build keeps its own default. Nothing else in
the command changed, and this build emitted no `--global-cache-dir` at all, so
there was no second instance of the same mistake to find. *(Amended after
`CHANGELOG.md` entry 35: `addConsumerStep` does emit `--global-cache-dir` now,
read from `b.graph.global_cache_root.path` and forwarded verbatim. That flag
was absent rather than misspelled, so the `=`-joined spelling above was still
the only instance of this mistake in this build.)*

The same command now carries a fixed `-j8`. Not a repair of the failure — a
separate hole in the same argument list, found while reading it. Nothing can
put a job count on a `Run` step's command: the outer `-j` reaches the outer
graph, and this list is written here. Without one, the nested build sizes
itself from the machine (`cpu_count - 1`), so the consumer is compiled at a
width that varies with the host rather than with the gate. `devenv.nix` fixes
`-j8` in all eight of its `zig build` bodies for the same reason, and the
config worker's statement of that bound is what the nested build now matches.

**Platform / version.** Zig 0.16.0 build runner, any host, whenever a local
cache directory is exported — or set on the command line, which reaches the
same `b.cache_root.path`. Unaffected: a shell exporting nothing (the branch is
not taken), and every other SDK's flags. `box2d` and `box3d` carry the same
two-token shape in their own nested commands and are the convention this
matches. No ABI, header, fixture or test change; `devenv.nix`, `package.nix`
and `consumer/` are untouched by this entry.

**Reusable rule.** A `Run` step that starts another build writes that build's
command line by hand, so every option on it is a claim about the outer
compiler's grammar that nothing checks. Spell an option the way
`zig build -h` prints it, one option and one value as separate arguments, and
do not generalise from a sibling subcommand: `--cache-dir=` and
`--cache-dir ` are both correct, for different programs. Then ask what reaches
the branch — a flag on the outer command line is always typed, an environment
variable is only exported in some shells, and the second is how a broken
argument survives a year of green runs. A fixed job count belongs in the same
list, because the width of a nested build is otherwise a property of the host
rather than of the gate.

**Verification status.** `OBSERVED` for the failure, from acceptance run
`20261004T193710Z` and its log `random123-devenv-consumer.log`; the exact
command line above is that log's, not a reconstruction. `SOURCE-CONFIRMED` for
the cause and the repair: the argument list, the fatal and the
`cpu_count - 1` default are read out of the pinned `lib/compiler` and
`lib/std/Io/Threaded.zig` shipped with the compiler the gate ran, and the
`--cache-dir` pair is read out of `addConsumerStep` as it now stands, beside
the `--summary all`, `--global-cache-dir` and trailing `b.args` additions that
`CHANGELOG.md` entry 35 records.
`OBSERVED` for the repair: acceptance run `20261004T214134Z`, gate
`devenv:consumer`, exit 0 after 7.524s, entered from a scratch project
directory with `ZIG_LOCAL_CACHE_DIR` exported. The nested build ran to
completion and printed `Build Summary: 6/6 steps succeeded`, which is the cell
that failed before the repair. Bounded: one cell, host target, and no trailing
arguments — the `b.args` hop is untouched by that gate and is covered instead
by the nine delivery cases `CHANGELOG.md` entry 38 records, where
`--provider <path>` reached the program with every provider variable excluded
from the child.
