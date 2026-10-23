# FORK-LICENSE

## Upstream scope

Random123 `v1.14.0` (`726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13`) is distributed by D. E. Shaw Research under a three-clause BSD licence. `LICENSE` carries the full text and `Copyright 2010-2012, D. E. Shaw Research.` Per-file copyright years differ; see `NOTICE.md`.

Upstream's grant covers upstream files, not fork-authored files. No fork-authored file is attributed to D. E. Shaw Research, John Salmon or Mark Moraes.

## Fork grant

**SPDX-License-Identifier: `BSD-3-Clause`**

This grant covers fork-authored code, build glue, the C bridge, Zig facade, package documentation and configuration.

```
Copyright 2025-2026 CoffeeImpliesCode contributors.
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

The grant also covers fork-authored `README.md`, `README.zig.md`, `CHANGELOG.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `devenv.yaml` and `.envrc`. `README.upstream.md` is excluded: it is upstream's README, preserved byte-for-byte under upstream terms.

`zig/bridge/random123_bridge.h` and `zig/bridge/random123_bridge.c` carry `Copyright 2025 CoffeeImpliesCode contributors.` and no SPDX line. `build.zig`, `build.zig.zon` and `consumer/build.zig` carry the BSD-3-Clause SPDX identifier with the 2025 year. The grant covers both year ranges.

## Upstream files not covered by the fork grant

All files under `include/`, `tests/`, `examples/` and `docs/`, plus `LICENSE`, `GNUmakefile` and upstream's `README.md` (stored as `README.upstream.md`), are upstream files under upstream terms, unchanged. `UPSTREAM.sha256` records their bytes. Upstream files retain their original notices; none receives a fork SPDX line.

`include/Random123/features/pgccfeatures.h` also carries `Copyright (c) 2013, Los Alamos National Security, LLC`, produced under U.S. Government contract `DE-AC52-06NA25396`. Its notice reserves government rights to use, reproduce and distribute the software, and says *modified software should be clearly marked so as not to confuse it with the version available from LANL*. Both notices share one comment block in this unchanged header, which ships whether or not the selected compiler uses it.

No other upstream file carries a different term. `NOTICE.md` contains the per-file inventory.

## Installed legal files

`zig build install` installs `share/licenses/random123/{LICENSE, NOTICE.md, FORK-LICENSE.md, UPSTREAM.md, README.upstream.md}` and the upstream header tree, including `pgccfeatures.h`. Nix outputs use the same install step.

Redistributors must retain the upstream `LICENSE`, both notices in `pgccfeatures.h`, and the fork grant for fork-authored files. One package-wide label does not replace these per-file terms.
