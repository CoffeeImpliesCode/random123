# NOTICE

## Upstream

Random123 is distributed by D. E. Shaw Research under the BSD 3-Clause
licence. The full licence text is reproduced, unmodified, in `LICENSE`, which
carries the notice `Copyright 2010-2012, D. E. Shaw Research.`; the individual
upstream headers carry `Copyright 2010-2011, D. E. Shaw Research.`, and the
per-file years are the ones those files state. Nothing in this fork removes,
weakens or reinterprets the terms.

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

Every file under `include/`, `tests/`, `examples/`, `docs/`, plus `LICENSE`,
`README.md` and `GNUmakefile`, is upstream source carried over byte for byte.
`UPSTREAM.sha256` proves it.

## This fork's modifications

Copyright 2025 CoffeeImpliesCode contributors. The same BSD 3-Clause terms apply
to the fork's own additions.

| File | What it is |
|---|---|
| `build.zig`, `build.zig.zon` | Zig 0.16 package: module `random123`, static artifact `random123` |
| `root.zig` | public Zig module: typed facade plus `pub const c` escape hatch |
| `zig/generator.zig` | the generic facade type shared by all eight generators |
| `zig/bridge/random123_bridge.c` | one-line forwarders into the upstream inline algorithms, plus the compile-time consistency asserts |
| `zig/bridge/random123_bridge.h` | declarations for those forwarders, and the mirrored default round counts |
| `zig/kat_test.zig` | replays upstream `tests/kat_vectors`; the bytes arrive through a build-generated module that embeds the upstream file, so no copy is committed |
| `zig/facade_test.zig` | behavioural, boundary and IEEE conversion tests |
| `zig/analyze_test.zig` | compile-only coverage of every public facade method |
| `zig/smoke.zig` | deterministic example behind `zig build smoke` |
| `consumer/` | separate package that depends on this one by path |
| `.github/workflows/verify.yml` | this fork's verification workflow |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `README.zig.md` | provenance and fork documentation |
| `.gitignore` | upstream entries kept verbatim; three Zig entries appended |

**No upstream algorithm was modified, reimplemented or re-derived.** The bridge
contains no arithmetic: each wrapper is a single call to the upstream
`static __inline__` function, using the upstream `r123arrayNxW` types. The
build script selects preprocessor values that upstream documents as
user-settable (`R123_USE_MULHILO64_C99`); it never edits a header.

The known-answer fixture is not a fork file. `zig/kat_test.zig` replays the
upstream `tests/kat_vectors` byte for byte, and the build delivers those bytes
by copying the upstream file next to a generated module root that embeds it;
the committed tree holds exactly one copy of the fixture, upstream's, and
`UPSTREAM.sha256` covers it. The AES-NI and ARS fixture lines are replayed only
when the build compiled AES-NI and the running CPU passes upstream's own CPUID
probe.

## Cryptographic suitability

Upstream states it plainly, and so does this fork: these generators are for
statistical applications and Monte Carlo simulation and are **not** suitable
for cryptography or security, even though they are constructed using
principles drawn from cryptography. AESNI uses the AES block cipher and ARS
uses the AES round function with a non-cryptographic key schedule; neither is a
CSPRNG and neither is exported as one.
