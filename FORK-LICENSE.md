# FORK-LICENSE — licence of this fork's own files

Status: **SOURCE-CONFIRMED** as a record of terms. Nothing here is a gate
result; no build, test, packaging or licence-compliance check has been run
against this file.

## 1. What upstream grants, and what it does not

Random123 `v1.14.0` (`726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13`) is distributed
by D. E. Shaw Research under a three-clause BSD licence. `LICENSE` carries the
full text and the notice `Copyright 2010-2012, D. E. Shaw Research.`; the
per-file notices state the years each file carries, which are not uniform (see
`NOTICE.md`).

That grant covers upstream's own files. It grants nothing over this fork's
files, and the two sets are recorded separately here and in `NOTICE.md`. No
fork-authored file is attributed to D. E. Shaw Research, John Salmon or Mark
Moraes.

## 2. The owner authorization

The owner of this repository authorized a per-project licence for the
fork-authored additions, to be chosen per project and to match the primary
upstream terms where appropriate. The authorization is recorded in the
workspace rules (`foundation-libs/AGENTS.md` §8, "Licence, provenance, privacy")
and in the migration contract
(`local://foundation-contract-implementation.md`, "Licence authorization"):

> The user chose a per-project licence for fork-authored additions, matching
> primary upstream terms where appropriate. Record that direct owner
> authorization and the actual grant in `FORK-LICENSE.md` and `NOTICE.md`.
> Preserve native licence texts, copyright notices and per-file exceptions
> byte-for-byte. Do not claim upstream authors own fork additions; do not invent
> personal copyright identities.

Records in this repository written before that authorization — including the
"no licence asserted" state of earlier waves — described the situation before
it and are superseded by this file for the fork's own code.

## 3. The grant for fork-authored files

**SPDX-License-Identifier: `BSD-3-Clause`**

The same three-clause BSD terms as Random123's own primary grant, because the
fork's own material is the build glue, the C bridge, the Zig facade and the
documentation wrapped around upstream's algorithms, and the owner's instruction
is to match the primary upstream terms where appropriate.

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

The text names no individual: this repository already records `Copyright 2025
CoffeeImpliesCode contributors.` on its 2025 files, and this grant keeps that
holder. Its third clause names D. E. Shaw Research because it is copied from the
upstream terms this grant matches; it is the no-endorsement clause, not an
attribution of the fork's files. Upstream's attribution is `NOTICE.md` §3.

Fork-authored files that are not code — `README.md`, `README.zig.md`,
`CHANGELOG.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
`FORK-NOTES.md`, `FORK-LICENSE.md`, `devenv.yaml`, `.envrc` — are covered by
the same grant. `README.upstream.md` is not in that list: it is upstream's own
file, byte for byte, under upstream's terms, and its presence here changes
nothing about it.

Other roles add this header to files they author in this repository, once, at
the top of the file, with the year the file itself carries:

```
SPDX-License-Identifier: BSD-3-Clause
Copyright 2026 CoffeeImpliesCode contributors.
```

Files this tree authored before the 2026-10-04 migration carry 2025, which is
the year `NOTICE.md` §2 already recorded for them:

* `zig/bridge/random123_bridge.h` and `zig/bridge/random123_bridge.c` carry
  `Copyright 2025 CoffeeImpliesCode contributors.` with a prose reference to
  `NOTICE.md` and no SPDX line. They are left as they are rather than churned.
* `build.zig`, `build.zig.zon` and `consumer/build.zig` carry the SPDX
  identifier with the 2025 year, for the same reason. The grant in §3 covers
  2025–2026 as a whole; the year on a file is the year of that file.

No upstream file ever receives an SPDX line: those notices are upstream's bytes
and `UPSTREAM.sha256` proves them. `build.zig.zon` deliberately carries no
package-wide `.license` field — the tree has a second notice inside
`include/Random123/features/pgccfeatures.h`, and one label does not describe
that. §5 has the details.

## 5. Upstream files this grant does not cover

Every file under `include/`, `tests/`, `examples/`, `docs/`, plus `LICENSE`,
`GNUmakefile` and upstream's `README.md` (preserved verbatim as
`README.upstream.md`) is upstream's, under upstream's terms, unchanged. The
integrity record is `UPSTREAM.sha256`.

One file in that set carries a **second** notice, and it travels with the file:

* `include/Random123/features/pgccfeatures.h:33-44` — `Copyright (c) 2013, Los
  Alamos National Security, LLC`, produced under U.S. Government contract
  `DE-AC52-06NA25396`. It sits below the D. E. Shaw Research BSD notice at
  lines 2-31, in the same comment block, and adds two conditions of its own:
  the U.S. Government reserves rights to use, reproduce and distribute the
  software, and *modified software should be clearly marked so as not to
  confuse it with the version available from LANL*.

That file is installed by this package and is selectable by
`features/compilerfeatures.h:219-220` under `__PGI`. It is not compiled by the
Zig/clang toolchain this package builds with, which is a build fact and not a
licence fact: the file ships either way, with both notices intact.

No other file in the upstream tree carries a different term. The per-file
inventory is `NOTICE.md` §3.

## 6. Where the licence material must end up

Both delivery routes install the full set, and `build.zig` is the single writer
of every path below:

| Route | Licence and notice files |
|---|---|
| `zig build install` | `share/licenses/random123/{LICENSE, NOTICE.md, FORK-LICENSE.md, UPSTREAM.md, README.upstream.md}`, plus the upstream header tree, which carries `pgccfeatures.h` and its second notice |
| Nix, via `zig build install` | the same paths, from `nix build .#packages.<system>.static` / `.shared` or `devenv build outputs.static` / `outputs.shared` |

`FORK-LICENSE.md` is the fork licence file: section 3 is the grant, verbatim.

The per-file notice requirement is not satisfied by shipping one package-wide
label. Any consumer redistributing this work must reproduce, with the upstream
bytes: the `LICENSE` notice for the upstream tree, both notices inside
`include/Random123/features/pgccfeatures.h` (which the installed header tree
carries unchanged), and the fork grant for the fork's own files.

## 7. Verification status

Nothing in this file has been observed by a build, a `sha256sum -c` run, a
`zig build install` or a `nix build`. Those are the driver's gates and are
recorded outside this repository. The statements here are `SOURCE-CONFIRMED`
reads of `LICENSE`, the upstream headers, and the workspace authorization text.