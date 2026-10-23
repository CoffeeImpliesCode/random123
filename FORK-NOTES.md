# Fork notes

## Source deviations

| File | Change and reason |
|---|---|
| `zig/bridge/random123_bridge.h` | Declares the fork's C ABI because upstream exposes its functions as inline definitions and macros. |
| `zig/bridge/random123_bridge.c` | Adds exported forwarders and marshals the AES-NI key schedule so Zig and C consumers can link the upstream algorithms. |
| `root.zig` | Publishes typed generators, interval conversions, and optional runtime dispatch under Zig-safe names. |
| `zig/generator.zig` | Builds stateless generator types and rejects invalid word arrays or round bounds at compile time; out-of-range rounds trap in every build mode. |
| `zig/provider.zig` | Reads an explicit provider path for examples and tests; runtime mode never guesses a library. |
| `runtime/generate.zig` | Parses target-specific translated declarations and emits dispatch plus routed native declarations; unsupported declarations stop generation. |
| `runtime/graph.zig` | Builds linked or runtime module graphs from the selected translation and keeps translated C-library externs direct. |
| `runtime/library.zig` | Defines the provider ABI and validates key, counter, and conversion behavior before publishing the dispatch table. |
| `runtime/loader.zig` | Loads an explicit path or platform name, resolves and validates symbols, and coordinates retries and concurrent callers. |
| `runtime/sync.h` | Declares namespaced lock, wait, broadcast, and thread-identity functions for the loader. |
| `runtime/sync.c` | Implements loader synchronization with Windows, POSIX, or single-threaded WASI/Emscripten primitives. |
| `zig/analyze_test.zig` | Calls each public method and a custom generator so Zig's lazy analysis checks their bodies. |
| `zig/facade_test.zig` | Exercises generator and interval-conversion behavior, including counter and key boundaries. |
| `zig/kat_test.zig` | Replays upstream known-answer vectors through the typed facade and raw C bridge. |
| `runtime/load_tests.zig` | Exercises loader refusals, retry, idempotence, provider mismatch, and concurrent calls with named libraries. |
| `zig/smoke.zig` | Demonstrates known outputs and a deterministic Threefry Monte Carlo stream without entropy or cryptographic use. |

## Build-graph deviations

- Compile the bridge against upstream headers to provide the package's linkable artifact; upstream installs headers only and has no binary ABI.
- Translate the fork bridge header, with `R123_USE_SSE=0` only for translation; the compiled bridge keeps upstream SIMD and AES-NI code.
- Use the target C preprocessor with `-E -dD` before Aro for PowerPC and NetBSD; other targets use direct `translate-c`.
- Runtime mode generates dispatch from the selected translation, loads an explicit bridge provider, and omits the bridge link; linked mode calls the same ABI directly.
- Static linkage is the default; dynamic linkage builds the same bridge ABI as a shared library. AES-NI/ARS wrappers follow the target feature selection.
- There is no system-library build mode or fetched dependency.

## Platform boundaries

- Upstream's architecture guard rejects `riscv64-linux-gnu` and `wasm32-wasi`; the fork does not bypass it.
- Runtime loading requires a platform dynamic loader and is unavailable on WASI, Emscripten, and freestanding targets.
- AES-NI/ARS wrappers are x86-only; runtime CPU support is queried separately from whether the wrappers were compiled.
