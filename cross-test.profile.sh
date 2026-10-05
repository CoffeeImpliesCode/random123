# cross-test profile for Random123.
#
# A settings-only profile. `cross-test` discovers this file at the project root,
# so an unqualified `cross-test` run in this repository reads it and a
# `--no-profile` run ignores it. Every name below is also a `cross-test`
# command-line flag or an environment variable, and the command line wins.
#
# What it deliberately does NOT contain, and why:
#
#   * No `CROSS_MATRIX` and no `TARGETS`. The published 53-platform Zig 0.16.0
#     Tier 1/2 table stays whole. Two of those cells — `riscv64-linux-gnu` and
#     `wasm32-wasi` — are refused by an upstream architecture guard
#     (`include/Random123/features/gccfeatures.h`), so a cell that does not
#     build is a fact about the algorithm this package compiles, not about this
#     package's configuration. Narrowing the matrix here would hide it rather
#     than explain it.
#   * No `cross_build_command`, `cross_artifact`, `cross_run_command` or
#     `cross_count_tests`. This profile selects no runner and names no artifact,
#     so `cross-test` keeps its own native/QEMU/Wine/Wasmtime detection, and a
#     target with no detected runner fails the `test` step with the target and
#     the switch that would answer it — reported as unavailable, never as a
#     compile that quietly passed.
#   * No `-Doptimize` and no `-Dtarget`. The gate is this package's own `test`
#     step in its own default Debug mode: the harness owns the target, and an
#     added optimisation mode would be a second, differently-shaped gate wearing
#     this matrix's exit code. The two `-D` flags below are named for a
#     different reason and are explained where they are set.
#   * No host path of any kind. Scratch and cache placement is `cross-test`'s
#     own host policy, which it resolves before it reads any name in this file,
#     and this package resolves nothing from a path it hard-codes. Both
#     behavioural roots embed the upstream `tests/kat_vectors` fixture with
#     `@embedFile` and touch no filesystem, so they need no scratch directory
#     of their own on any target.
#   * No resource limits beyond the two deadlines below. `--jobs` stays
#     whatever the caller asked for; this package does not know the machine it
#     will be measured on.
#
# The step this matrix runs, stated rather than assumed: `test` is the step
# `addTest` + `addRunArtifact` makes real for whatever `-Dtarget` names, so an
# explicit host triple runs on the host, a foreign target runs under a detected
# executor, and a foreign target with no executor is reported as build-only
# coverage and never counted as a pass. `build.zig` gives both test binaries a
# Run step unconditionally, which is what leaves that choice open; `check` and
# `matrix` stay compile-only for every target, including the host.
CROSS_BUILD_STEP=test

# One target at a time inside one `zig build`. A target graph compiles the one
# C bridge translation unit over the upstream headers, runs translate-c on the
# bridge header, and builds the facade, the smoke example and both test
# binaries; four in-build jobs keep a loaded host from idling while memory
# pressure from a whole matrix does not oversubscribe it. `--build-jobs` and
# `--build-timeout` still override this.
CROSS_BUILD_JOBS=4

# Deadline for one `zig build test -Dtarget=…`, covering both the compile and
# the run of that target's two test binaries.
CROSS_BUILD_TIMEOUT=1800

# Per-test-binary deadline, passed on as `zig build --test-timeout`. Eight
# known-answer tests replay the upstream `tests/kat_vectors` fixture through
# every Philox, Threefry and AES-NI/ARS shape, and the facade root checks
# generator purity, counter-stream uniqueness, boundary counters and keys, the
# round-count knob and the integer-to-floating-point grid conversions. None of
# that is a large corpus: the fixture is a few thousand tuples and the property
# roots are single-threaded arithmetic, so 600 seconds leaves a slow
# interpreter cell room without inviting a change to what is being measured. If
# a cell does hit a deadline, that is a fact to record and diagnose: do not
# sample the fixture, do not skip algorithms, and do not remap Debug to an
# optimized mode to make it pass.
CROSS_TIMEOUT=600

# The configuration, named rather than left to the defaults.
#
# `build.zig` has two delivery options and both defaults are the ordinary
# linked, static build. Neither default is relied on here, because a cell that
# silently changed kind would still exit zero.
#
#   * `-Dlinkage=static`. The two linkages are not interchangeable over this
#     matrix, and one of them has no answer on a cell at all: WASI has no
#     shared object for a C library to be built into, so `-Dlinkage=dynamic`
#     cannot be the answer for `wasm32-wasi`.
#   * `-Druntime=false`. The linked dispatch, not the generated one. This is the
#     one that would be most tempting to omit, because a linked cell still
#     compiles and still runs the behavioural tests; what it would not be is a
#     runtime cell. The loader's Unix backend calls `dlopen`, which WASI does
#     not have either, and a runtime root additionally needs a real provider
#     named by `RANDOM123_TEST_PROVIDER`, so `-Druntime=true` has cells it
#     cannot answer as well.
#
# So the published 53-platform matrix is the static LINKED closure, which every
# cell can satisfy. The other configurations are verified separately and on
# their own terms: the shared artifact with `zig build -Dlinkage=dynamic` plus
# the installed C consumer, and the runtime route with
# `zig build test -Druntime=true` on the host, which needs a real provider and
# is therefore not something a compile-and-run matrix cell can stand for.
# Narrowing the matrix is not what this does — all 53 cells stay, and none of
# them is a cell pretending to be a configuration it is not.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)