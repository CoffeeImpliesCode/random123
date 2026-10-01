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
invokes `run`. `consumer/build.zig` needs no change — `b.installArtifact(exe)`
already feeds its install step, and the install-to-run edge that made a plain
`zig build` execute the program was removed earlier. The false claim is
withdrawn from `build.zig`, `README.zig.md` and `CHANGELOG.md`, not restated.

**Reusable rule.** Never put a `@panic` in the body of a `std.Build` step
constructor: `build()` calls those unconditionally, so a guard keyed on
`-Dtarget` there breaks every cross-target gate instead of only the step you
meant to restrict. Choose the *work* conditionally — run for native, compile
otherwise — the way the `test` step already does. And when a search finds no
API, the honest conclusion is "I did not find it": grep for the concept, not
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
