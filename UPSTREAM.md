# UPSTREAM

## Canonical source

| Field | Value |
|---|---|
| Project | Random123 — a Library of Counter-Based Random Number Generators |
| Authors | John Salmon, Mark Moraes |
| Copyright | D. E. Shaw Research — `LICENSE` says "Copyright 2010-2012", the individual upstream headers say "Copyright 2010-2011" |
| Canonical URL | <https://github.com/DEShawResearch/random123> |
| Homepage | <http://deshawresearch.com/resources_random123.html> |
| Licence | BSD-3-Clause (see `LICENSE`, reproduced unmodified) |
| Tag pinned | `v1.14.0` |
| Commit pinned | `726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13` ("Release 1.14.0") |
| Cloned from | `https://github.com/DEShawResearch/random123.git` |
| Upstream branch state at pin | `origin/main` is 5 commits ahead of the tag (`9545ff6`, "added Ampere CC 80 and 86 to the core counting logic") |
| Remotes | `origin` → `https://github.com/DEShawResearch/random123.git`, fetch and push alike, exactly as cloned. The downstream is a separate private repository and is not configured as a remote yet; repoint `origin` at the downstream and add the upstream as `upstream` before the first push. |

This repository is a clone of that upstream. Git history is preserved in full,
and this fork's own work is the set of changes on top of the pinned tag that
`CHANGELOG.md` records.

## Import mechanism

```
git clone https://github.com/DEShawResearch/random123.git random123
cd random123
git checkout -B main v1.14.0     # 726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13
```

To re-sync later, drop the fork-only files, `git fetch origin`, `git checkout
<newtag>`, then re-apply `CHANGELOG.md`'s numbered divergences. `UPSTREAM.sha256`
will fail loudly if any upstream file drifted in the meantime.

## Integrity

`UPSTREAM.sha256` records the SHA-256 of every upstream file this fork carries
over unmodified (111 records: `include/`, `tests/`, `examples/`, `docs/`,
`LICENSE`, `README.md`, `GNUmakefile`). Check it with:

```
sha256sum -c UPSTREAM.sha256
```

`tests/gencl.sh` is upstream's symlink to `../examples/gencl.sh`. The manifest
records the file bytes `sha256sum` follows, not the Git symlink blob. CI's
pinned-tree diff also checks the link itself.

Two upstream files are deliberately **not** in that manifest:

* `.gitignore` — this fork appends Zig build artefacts to it. The upstream
  entries are preserved verbatim above them.
* `.travis.yml` — upstream CI pointed at travis-ci.org, which is shut down.
  Running another maintainer's CI is not this fork's business; see
  `CHANGELOG.md` entry 1.

`tests/kat_vectors` is the only known-answer fixture this fork replays, and it
is the upstream file itself, byte for byte: the build copies it next to a
generated module root that embeds it, so the Zig test imports the identical
bytes the manifest covers instead of a copy committed into the tree. `tests/`
stays in `build.zig.zon`'s `.paths` for exactly that reason.

## How the fork builds upstream

Random123 is header-only. Every algorithm is a `R123_STATIC_INLINE`
(`static __inline__`) function, and every default-round entry point is a
preprocessor macro, so the upstream tree produces **no linkable symbol at all**.
This fork therefore adds one C translation unit, `zig/bridge/random123_bridge.c`,
which `#include`s the upstream headers verbatim and defines plain, externally
linked one-line forwarders (`r123_bridge_*`). No upstream file is modified, and
no algorithm is reimplemented — see `NOTICE.md`.

The bridge covers the eight portable generators (Philox2x32/4x32/2x64/4x64 and
Threefry2x32/4x32/2x64/4x64), their eight `keyinit` forwarders, the twelve
`u01fixedpt` conversions, and — only when AES-NI is compiled in — `aesni4x32`
and `ars4x32`. It does **not** bridge the x86 `1xm128i` generators, whose
counters are `__m128i` values that cannot cross a portable boundary, nor
`aesopenssl16x8`, which upstream compiles only under `R123_USE_AES_OPENSSL`.
Those remain available to C and C++ consumers through the installed upstream
headers, unchanged.

## System-library mode

There is none, deliberately. A header-only library installs no binary, so a
"system Random123" is just a directory of headers; there is no installed ABI
for `b.systemIntegrationOption` to bind to, and nothing for it to select. This
is a packaging decision recorded by the foundation fork contract, not an
observed build failure. Consumers who want the plain upstream headers without
this package can use the tree as-is, exactly as upstream intends.

## Platform notes

### AES-NI and ARS

`include/Random123/aes.h` and `include/Random123/ars.h` compile to nothing
unless `R123_USE_AES_NI` is true, which `features/gccfeatures.h:113-119` derives
from `__AES__`. `__AES__` describes the **target CPU**, and Zig's driver does
not build it from a `-maes` cflag, so this fork puts the `aes` feature on the
target query instead — the same mechanism `-Dcpu=` uses — and
`zig/bridge/random123_bridge.c` static-asserts that `R123_USE_AES_NI` really is
1 wherever the AES-NI wrappers are declared. A silent mismatch is now a compile
error rather than a library that links and contains no AES-NI at all.

* the headers are installed verbatim and stay available to every target;
* the bridge compiles its AES-NI and ARS wrappers — `aesni4x32` and `ars4x32`,
  the two generators whose counters and keys are plain `r123array4x32` words —
  only when the **resolved target CPU** advertises the `aes` feature
  (`-Daesni=auto`, the default), or when the packager asks for it explicitly
  with `-Daesni=true`;
* `-Daesni=true` on a non-x86 target is a hard build error, not a silent
  downgrade;
* `zig build check` and `zig build matrix` additionally compile the AES-NI path
  for every x86 target in the matrix, adding the feature to that copy of the
  target, so it is never left untested;
* the typed Zig facade covers the eight portable generators only. AES-NI and ARS
  are reached through the raw C escape hatch (`random123.c`) where they are
  present, guarded by `random123.has_aesni`.

The `1xm128i` generators (`aesni1xm128i`, `ars1xm128i`) are not bridged at all:
their counters are `__m128i` values that the translated surface pins out with
`R123_USE_SSE=0`, and marshalling a vector register through a plain-word ABI
would be an assumption with no compiler behind it (`FORK-NOTES.md` entries 3
and 4). A C or C++ consumer that compiles against the installed
`<Random123/aes.h>` and `<Random123/ars.h>` with the AES feature enabled gets
them, and the rest of upstream's AES surface, unchanged.

`random123.c.r123_bridge_have_aesni()` is upstream's own `haveAESNI()` CPUID
probe: compiling the AES-NI code does not mean the *running* CPU has AES-NI.

### Philox Nx64 where upstream has no 64x64→128 multiply

`features/gccfeatures.h` enables `R123_USE_GNU_UINT128` only for `__x86_64__`
and `__aarch64__`, and `R123_USE_MULHILO64_ASM` is hard-coded to `0`. On any
other architecture that leaves upstream with no 64x64→128 multiply, so
`R123_USE_PHILOX_64BIT` resolves to `0` and `philox2x64` / `philox4x64` are
simply not declared. This fork defines `-DR123_USE_MULHILO64_C99=1` on exactly
those architectures. That is upstream's own documented user override ("Library
users can override any value by defining the pp-symbol with a compiler
option"); the C99 path uses word-size operations only, computes the identical
128-bit product, and is slower. The static assert in
`zig/bridge/random123_bridge.c` fails the build if a target ever ends up
without a working multiply.

The two contract targets that would have needed this override, riscv64 and
wasm32, are refused by upstream before a multiply is ever chosen — see below.
The override stays for any other target a packaged dependency is built for.

### Upstream architecture guard

`include/Random123/features/gccfeatures.h:37-45` is a hard stop for every
architecture upstream has not tested:

```c
#if !defined(__x86_64__) && !defined(__i386__) && !defined(__powerpc__) && !defined(__arm__) && !defined(__aarch64__) && !defined(__s390x__)
#  error "This code has only been tested on x86, powerpc and a few arm platforms."
```

Every Random123 header reaches it. `array.h:34` includes
`features/compilerfeatures.h`, which selects a feature header by compiler
(`clangfeatures.h` for clang, `gccfeatures.h` for gcc), and the selected header
carries the guard; `clangfeatures.h:91` includes `gccfeatures.h` outright. Zig's
clang takes that path, so the guard fires before a single generator is
declared. This, and not a missing multiply, is what a
`-target wasm32-wasi` or `-target riscv64-linux-gnu` build fails on:

```
Random123/features/gccfeatures.h:38:4: error: "This code has only been tested on x86, powerpc and a few arm platforms."
Random123/features/gccfeatures.h:39:10: error: 'including_a_nonexistent_file_will_stop_some_compilers_from_continuing_with_a_hopeless_task' not found
```

No user-facing preprocessor symbol switches it off: the guard is an `#error`
inside the header the compiler selection reaches, not a value the caller
supplies. The upstream comment above it is explicit about what changing that
would mean (`features/gccfeatures.h:41-44`): "Feel free to try the Random123
library on other architectures by changing the conditions that reach this
error, but you should consider it a porting exercise and expect to encounter
bugs and deficiencies."

Changing those conditions means editing an upstream header. This fork does not
edit upstream source, and it will not reach the guard the dishonest way either:
defining `__arm__` for riscv64 would make the compile pass without making
Random123 correct there. So **riscv64-linux-gnu and wasm32-wasi are not
supported targets of this package**, and no `-D` flag, facade subset or
generated table is offered in their place. The upstream headers are still
installed verbatim, so a consumer who does the port is blocked by nothing here.

`zig build matrix` still attempts all six contract targets rather than quietly
dropping two of them, so it fails: the four supported targets compile, and
riscv64-linux-gnu and wasm32-wasi fail inside `gccfeatures.h`. That failure is
the honest result of an upstream limit, not a fork defect to be papered over,
and it is recorded here rather than removed from the matrix.

## Verification targets

`zig build matrix` attempts all six contract targets: x86_64-linux-gnu,
aarch64-linux-gnu, aarch64-macos-none, x86_64-windows-gnu, riscv64-linux-gnu
and wasm32-wasi. Cross targets are compiled, never executed; no emulator is
assumed, and no target binary is run anywhere in `check` or `matrix`.

The first four compile. `riscv64-linux-gnu` and `wasm32-wasi` fail, in
`include/Random123/features/gccfeatures.h:37-45` — see "Upstream architecture
guard" above. They stay in the matrix on purpose: dropping them would report a
coverage the package does not have.
