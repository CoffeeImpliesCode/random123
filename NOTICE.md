# NOTICE

## Upstream

Random123 v1.14.0 is distributed under BSD 3-Clause terms. `LICENSE` contains the full licence text below, unchanged. Upstream's grant covers upstream files only; fork-authored files use the separate grant in `FORK-LICENSE.md`.

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

The upstream files under `include/`, `tests/`, `examples/`, and `docs/`, plus `LICENSE` and `GNUmakefile`, are carried byte for byte. Upstream's README is retained as `README.upstream.md`. `UPSTREAM.sha256` lists 102 unchanged upstream files.

| Upstream path | Notice and scope |
|---|---|
| `LICENSE` | Copyright 2010-2012, D. E. Shaw Research; BSD 3-Clause text. |
| `include/Random123/**`, except the two paths below | Copyright 2010-2011, D. E. Shaw Research; BSD 3-Clause. |
| `include/Random123/features/clangfeatures.h` | Copyright 2010-2016, D. E. Shaw Research; BSD 3-Clause. |
| `include/Random123/features/pgccfeatures.h` | D. E. Shaw Research BSD 3-Clause notice and a second notice: Copyright (c) 2013, Los Alamos National Security, LLC, under U.S. Government contract `DE-AC52-06NA25396`. The U.S. Government reserves rights to use, reproduce and distribute the software; warranty and liability are disclaimed for the Government and LANL; modified software should be clearly marked, so as not to confuse it with the version available from LANL. |
| `tests/*`, `examples/*` | Copyright 2010-2011, D. E. Shaw Research; BSD 3-Clause. Retained upstream material, not relicensed or edited here. |
| `GNUmakefile`, `docs/*` | Upstream files carried byte for byte. |
| `README.upstream.md` | Upstream README, byte for byte; BSD 3-Clause, D. E. Shaw Research. |

`pgccfeatures.h` is installed with both notices intact. This package's Zig/Clang build does not compile it; upstream selects it only under `__PGI`. No other upstream file carries an additional notice.

## Fork-authored files

The fork's own files are covered by the BSD 3-Clause grant in `FORK-LICENSE.md`, Copyright 2025-2026 CoffeeImpliesCode contributors. No fork-authored file is attributed to D. E. Shaw Research, John Salmon or Mark Moraes. Each retained file's own notice applies; the compiled core's terms do not replace the terms on other material.

| Fork path | Licence and attribution |
|---|---|
| `build.zig`, `build.zig.zon`, `consumer/build.zig` | BSD 3-Clause; Copyright 2025 CoffeeImpliesCode contributors. |
| `root.zig`, `zig/*.zig` | BSD 3-Clause (fork). |
| `zig/bridge/random123_bridge.c`, `zig/bridge/random123_bridge.h` | BSD 3-Clause (fork); Copyright 2025 CoffeeImpliesCode contributors, with no SPDX line. |
| `runtime/*`, `zig/provider.zig` | BSD 3-Clause (fork). |
| `consumer/` | BSD 3-Clause (fork). |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | BSD 3-Clause (fork). |
| `README.md`, `README.zig.md`, `CHANGELOG.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-NOTES.md`, `FORK-LICENSE.md` | BSD 3-Clause (fork). |
| `.gitignore` | Mixed: upstream entries are retained; appended Zig entries are fork-authored. |
| `flake.lock` | Generated lock data for a BSD 3-Clause (fork) input; no copyright line of its own. |

The runtime files and `zig/provider.zig` carry `SPDX-License-Identifier: BSD-3-Clause`. `runtime/graph.zig`, `runtime/library.zig`, `runtime/load_tests.zig`, and `zig/provider.zig` also carry Copyright 2025 CoffeeImpliesCode contributors; `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.h`, and `runtime/sync.c` carry only the SPDX identifier. Per-file headers retain their recorded copyright years.

The bridge contains no upstream algorithm: each wrapper calls an upstream inline function. `zig/kat_test.zig` uses the upstream `tests/kat_vectors` bytes, embedded at build time; it is not a fork copy. No upstream algorithm or header was modified, reimplemented or re-derived.

Upstream test and example files keep their own terms; this fork does not relicense them. Random123 is for statistical applications and Monte Carlo simulation, not cryptography or security.
