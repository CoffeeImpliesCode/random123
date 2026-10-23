# UPSTREAM

## Identity

| Field | Value |
|---|---|
| Project | Random123 — a Library of Counter-Based Random Number Generators |
| Authors | John Salmon, Mark Moraes |
| Canonical URL | <https://github.com/DEShawResearch/random123> |
| Homepage | <http://deshawresearch.com/resources_random123.html> |
| Version | `v1.14.0` |
| Commit | `726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13` (`Release 1.14.0`) |
| Licence | BSD 3-Clause; `include/Random123/features/pgccfeatures.h` also carries a LANL notice. See `NOTICE.md`. |
| Copyright | D. E. Shaw Research; per-file years are in the source notices. |
| Source | Cloned from `https://github.com/DEShawResearch/random123.git` and checked out at the pinned tag. |

```sh
git clone https://github.com/DEShawResearch/random123.git random123
cd random123
git checkout -B main v1.14.0  # 726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13
```

The fork preserves upstream Git history. Fork changes are recorded in `CHANGELOG.md`.

## Upstream files

`UPSTREAM.sha256` lists 102 upstream files carried unchanged: `include/`, `tests/`, `examples/`, `docs/`, `LICENSE`, `README.upstream.md`, and `GNUmakefile`. For the upstream symlink `tests/gencl.sh`, the manifest records the target bytes followed by `sha256sum`.

| Path | Status |
|---|---|
| `.gitignore` | Upstream entries remain; `.zig-cache/`, `zig-cache/`, and `zig-out/` were appended. Excluded from `UPSTREAM.sha256`. |
| `README.md` | Fork-authored README. Upstream's README is retained byte for byte as `README.upstream.md`, SHA-256 `71a51dfa922bee8352ba5500ec97ab80875c712dc759528e8fc5ec5b1fd0b28f`. |

No upstream source, header, test, example or documentation file was removed. `README.upstream.md` remains under upstream's terms; `NOTICE.md` records per-path notices and exceptions.

`include/Random123/features/pgccfeatures.h`, `msvcfeatures.h`, and `nvccfeatures.h` remain installed unchanged. Upstream selects them only under `__PGI`, `_MSC_FULL_VER`, and `__CUDACC__`, respectively; `pgccfeatures.h` carries the additional LANL notice recorded in `NOTICE.md`.

`tests/kat_vectors` is the upstream known-answer fixture, unchanged and covered by the manifest. The build embeds those same bytes; the fork does not carry a second copy.

No upstream algorithm or header was modified, reimplemented or re-derived. `zig/bridge/random123_bridge.c` contains fork-authored forwarders to upstream inline functions.
