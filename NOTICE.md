# NOTICE

## 1. Upstream

Random123 is distributed by D. E. Shaw Research under the BSD 3-Clause
licence. The full licence text is reproduced, unmodified, in `LICENSE`, which
carries the notice `Copyright 2010-2012, D. E. Shaw Research.`; the individual
upstream headers carry `Copyright 2010-2011, D. E. Shaw Research.`, with one
exception named in §3, and the per-file years are the ones those files state.
Nothing in this fork removes, weakens or reinterprets the terms.

```
Copyright 2010-2012, D. E. Shaw Research.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of D. E. Shaw Research nor the names of its contributors may
  be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

This repository is **private**. That changes nothing about the obligations
above: the copyright notice, the conditions and the disclaimer travel with the
source and with any binary form.

Every file under `include/`, `tests/`, `examples/`, `docs/`, plus `LICENSE`
and `GNUmakefile`, is upstream source carried over byte for byte. Upstream's
`README.md` is carried over byte for byte as `README.upstream.md`.
`UPSTREAM.sha256` proves all 102 of them.

## 2. This fork's own files

The owner of this repository authorized a licence for the fork-authored
additions, chosen per project and matching the primary upstream terms where
appropriate. The authorization is recorded in `foundation-libs/AGENTS.md` §8 and
in the SDK migration contract; the resulting grant and its SPDX identifier are
in `FORK-LICENSE.md`. In summary:

* **BSD 3-Clause, `SPDX-License-Identifier: BSD-3-Clause`**, over the fork's own
  files, copyright `2025-2026 CoffeeImpliesCode contributors.`
* Upstream's grant covers upstream's files only. No fork-authored file is
  attributed to D. E. Shaw Research, John Salmon or Mark Moraes, and no personal
  copyright identity is invented here.
* Material a package carries is licensed by its own file, not automatically by
  the licence of the compiled core.
* A per-file SPDX header states the year range that file itself carries:
  `build.zig`, `build.zig.zon` and `consumer/build.zig` say
  `Copyright 2025 CoffeeImpliesCode contributors.`, which is the year this tree
  already recorded for them; a file first written in the 2026-10-04 migration
  says 2026. The grant is one grant; only the year on a file differs.

Earlier records in this repository describing the fork's own files as carrying
"no licence asserted" described the state before that authorization. They are
superseded by this section and by `FORK-LICENSE.md`.

| File | What it is | Licence |
|---|---|---|
| `build.zig`, `build.zig.zon` | Zig 0.16 package: module `random123`, artifact `random123` | BSD-3-Clause (fork) |
| `root.zig` | public Zig module: typed facade plus `pub const c` escape hatch | BSD-3-Clause (fork) |
| `zig/generator.zig` | the generic facade type shared by all eight generators | BSD-3-Clause (fork) |
| `zig/provider.zig` | names the provider for a runtime-loading build of this package, for the two programs that have to name one; every loading function in it is a no-op in a linked build | BSD-3-Clause (fork) |
| `runtime/loader.zig` | the reusable loader core: the platform's own `dlopen`/`dlsym` behind one process-lifetime immutable table, and the definitions of `LoadSource` and `LoadError` | BSD-3-Clause (fork) |
| `runtime/library.zig` | this SDK's descriptor of its own side of the loader: the names a provider has to export beyond `r123_bridge_*`, and the namespaced synchronization binding. It is the file another SDK replaces | BSD-3-Clause (fork) |
| `runtime/graph.zig` | the build half of the runtime route: the loader core module, the descriptor module and the generated dispatch module | BSD-3-Clause (fork) |
| `runtime/generate.zig` | the build-time generator that writes the dispatch module from this build's own `translate-c` output, so the dispatch table carries exactly the declarations this build selected | BSD-3-Clause (fork) |
| `runtime/sync.h`, `runtime/sync.c` | the process-global mutex, wake-up and thread identity the loader uses, with `RT_SYNC_PREFIX` keeping each SDK's synchronization symbols distinct | BSD-3-Clause (fork) |
| `runtime/load_tests.zig` | the loader's behavioural tests; `build.zig` adds this root to `zig build test` only under `-Druntime=true` and only for a host target | BSD-3-Clause (fork) |
| `zig/bridge/random123_bridge.c`, `zig/bridge/random123_bridge.h` | the C ABI: one-line forwarders into the upstream inline algorithms, plus the compile-time consistency asserts | BSD-3-Clause (fork); contains no upstream algorithm |
| `zig/kat_test.zig` | replays upstream `tests/kat_vectors`; the bytes arrive through a build-generated module that embeds the upstream file, so no copy is committed | BSD-3-Clause (fork) |
| `zig/facade_test.zig` | behavioural, boundary and IEEE conversion tests | BSD-3-Clause (fork) |
| `zig/analyze_test.zig` | compile-only coverage of every public facade method | BSD-3-Clause (fork) |
| `zig/smoke.zig` | deterministic example behind `zig build smoke` | BSD-3-Clause (fork) |
| `consumer/` | separate package that depends on this one by path | BSD-3-Clause (fork) |
| `.github/workflows/verify.yml` | this fork's verification workflow | BSD-3-Clause (fork) |
| `package.nix` | one source-only Nix derivation; static and shared packages both come from it | BSD-3-Clause (fork) |
| `flake.nix` | the two packages and the pinned nixpkgs input | BSD-3-Clause (fork) |
| `devenv.nix`, `devenv.yaml`, `.envrc` | the canonical development environment | BSD-3-Clause (fork) |
| `README.md` | this file's sibling: the fork's README | BSD-3-Clause (fork) |
| `README.upstream.md` | upstream's README, byte for byte | **BSD 3-Clause, D. E. Shaw Research** — it is upstream's file |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `README.zig.md` | provenance and fork documentation | BSD-3-Clause (fork) |
| `.gitignore` | upstream entries kept verbatim; three Zig entries appended | mixed file: upstream's entries are D. E. Shaw Research's tree conventions, the appended entries are the fork's |
| `flake.lock` | Nix's resolved input for `flake.nix`, generated by Nix from the revision `flake.nix` names; not authored here and carrying no copyright line of its own | generated lock data for a BSD-3-Clause (fork) input |

Within the runtime route, every file carries `SPDX-License-Identifier:
BSD-3-Clause` on its first line, and that identifier names the one grant in
`FORK-LICENSE.md`. Four of them repeat a `Copyright 2025 CoffeeImpliesCode
contributors.` line underneath it — `runtime/graph.zig`,
`runtime/library.zig`, `runtime/load_tests.zig` and `zig/provider.zig` — while
`runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.h` and
`runtime/sync.c` carry the identifier alone. The grant is the same one either
way; the difference is only whether the file repeats the notice, and it is
written down here because an inventory that reports a copyright line where a
file carries only an identifier is not an inventory.

**No upstream algorithm was modified, reimplemented or re-derived.** The bridge
contains no arithmetic: each wrapper is a single call to the upstream
`static __inline__` function, using the upstream `r123arrayNxW` types. The build
script selects preprocessor values that upstream documents as user-settable
(`R123_USE_MULHILO64_C99`, and `R123_USE_SSE` for the translate-C step only); it
never edits a header.

The known-answer fixture is not a fork file. `zig/kat_test.zig` replays the
upstream `tests/kat_vectors` byte for byte, and the build delivers those bytes
by copying the upstream file next to a generated module root that embeds it;
the committed tree holds exactly one copy of the fixture, upstream's, and
`UPSTREAM.sha256` covers it. The AES-NI and ARS fixture lines are replayed only
when the build compiled AES-NI and the running CPU passes upstream's own CPUID
probe.

## 3. Per-file exceptions in the upstream tree

The compiled core and the retained material do not all carry the same notice.
This section is the inventory; a package-wide label does not replace it.

| Path | Notice | Compiled by this package? |
|---|---|---|
| `LICENSE` | `Copyright 2010-2012, D. E. Shaw Research.` + BSD 3-Clause text, the whole file being a doxygen `@page LICENSE` | not source |
| every header under `include/Random123/` except the two below | `Copyright 2010-2011, D. E. Shaw Research.` + BSD 3-Clause text | yes, those the generator headers select |
| `include/Random123/features/clangfeatures.h` | `Copyright 2010-2016, D. E. Shaw Research.` + BSD 3-Clause text — the only header with a later year | yes |
| **`include/Random123/features/pgccfeatures.h`** | **Two notices in one comment block:** the D. E. Shaw Research BSD text at lines 2-31, **and** `Copyright (c) 2013, Los Alamos National Security, LLC` at lines 33-44, produced under U.S. Government contract `DE-AC52-06NA25396`, which reserves U.S. Government rights to use, reproduce and distribute the software, disclaims warranty and liability for the Government and LANL, and adds a condition of its own: modified software "should be clearly marked, so as not to confuse it with the version available from LANL" | no — `features/compilerfeatures.h:219-220` selects it only under `__PGI`. It is installed and shipped either way |
| `tests/*`, `examples/*` | `Copyright 2010-2011, D. E. Shaw Research.` + BSD 3-Clause text | no; the C++/CUDA/OpenCL suites are retained upstream material |
| `examples/*.{cu,ocl,metal}`, `tests/*.cu` | same BSD 3-Clause text, GPU platform sources | no; retained uncompiled, no GPU is required to build this package |
| `GNUmakefile`, `docs/*` | upstream files, carried byte for byte | `GNUmakefile` is not used by this package's build; `docs/Doxyfile` builds upstream's HTML documentation |

No file in the upstream tree carries a different licence from the rest: the
`pgccfeatures.h` addition is an additional notice under the same three-clause
terms, plus the LANL conditions, not a different licence. It is recorded as an
exception because it is one, and because the file that carries it is installed
by this package and must not be distributed without both notices.

Upstream's own test and example material keeps its own terms whatever this fork
does with it; none of it is relicensed here, and none of it was edited.

## 4. Cryptographic suitability

Upstream states it plainly, and so does this fork: these generators are for
statistical applications and Monte Carlo simulation and are **not** suitable
for cryptography or security, even though they are constructed using principles
drawn from cryptography. AESNI uses the AES block cipher and ARS uses the AES
round function with a non-cryptographic key schedule; neither is a CSPRNG and
neither is exported as one.

## 5. Status of this record

Every statement above is read out of a file in this repository. Nothing here has
been confirmed by a build, an install, a `sha256sum -c` run or a `nix build`;
those are the integrator's gates and are recorded outside this repository.