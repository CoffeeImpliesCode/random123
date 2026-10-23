# Changelog

Changes relative to Random123 v1.14.0.

- `zig build consumer` forwards resolved build options, optional AES-NI, cache and prefix paths, and caller arguments to its nested build.
- `devenv` scripts run from the package root and keep caches and install outputs outside the source tree.
- `translate-c` uses target Clang preprocessing for PowerPC and NetBSD targets.
- Added runtime loading under `-Druntime=true`, exposing `runtime_loaded`, `LoadSource`, `LoadError`, `load`, and `loadedSource`; no fallback is used, and failed loads may be retried.
- Added `-Dlinkage=static|dynamic` (static by default) and installs `random123.pc` with the library and header tree.
- Added Nix static/shared packages and a tools-only development shell pinned to Zig 0.16.0.
- AES-NI/ARS wrappers follow the resolved target's `aes` feature unless `-Daesni` overrides it; callers must probe `random123.c.r123_bridge_have_aesni()` before execution.
- The translated C view uses portable array types (`R123_USE_SSE=0`); the C bridge includes upstream headers unchanged.
- The build selects upstream's C99 64-bit multiply fallback where its default path lacks 64×64-to-128 multiplication.
- Generic generator widths now come from `@typeInfo`; mismatched counter and key word types fail at compile time.
- Out-of-range generator rounds now trap unconditionally rather than depending on upstream assertions.
- Renamed the fixed-point namespace from `u01` to `UnitInterval` for Zig 0.16.
- Added the Zig 0.16 `random123` module and static artifact, with a bridge for eight portable generators, eight key-init calls and twelve fixed-point conversions.
