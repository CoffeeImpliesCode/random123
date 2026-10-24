# Random123

Random123 v1.14.0 is a header-only, counter-based random-number library for C and C++; this Zig 0.17.0 package adds a C ABI bridge and typed facade.
Use it for statistical and Monte Carlo work, not cryptography or security.

## Source deviations

| File | Change |
|---|---|
| `include/`, `tests/`, `examples/`, `docs/`, `LICENSE`, `GNUmakefile` | Upstream files remain unchanged; `UPSTREAM.sha256` lists 102 carried files. |
| `README.md`, `README.upstream.md` | Fork documentation replaces upstream's README path; its text remains unchanged as `README.upstream.md`. |
| `.gitignore` | Keeps upstream entries and adds Zig cache/output paths. |
| `zig/bridge/random123_bridge.h` | Declares the fork's C ABI for the header-only API. |
| `zig/bridge/random123_bridge.c` | Adds forwarding wrappers to upstream functions. |
| `root.zig`, `zig/generator.zig` | Add the typed Zig facade and compile-time generator factory. |

## Build deviations

Upstream's functions are static inline or macros, so its headers provide no linkable symbols. The build compiles the bridge against those unchanged headers and produces the `random123` library.

The build defines `R123_USE_SSE=0` for translation only, to avoid GNU inline assembly in the Zig translation. The compiled bridge keeps the target's upstream SIMD and AES-NI code. It sets `R123_USE_MULHILO64_C99=1` where needed for the 64×64-to-128 multiply.

The optional runtime graph generates dispatch from the selected translation and resolves its symbols from an explicit provider. That module does not link the bridge artifact. The artifact remains available for C/C++ consumers and as a runtime provider.

`build.zig.zon` declares no external dependencies.

## Support matrix

| Target | Upstream architecture guard |
|---|---|
| `x86_64-linux-gnu` | accepts |
| `aarch64-linux-gnu` | accepts |
| `aarch64-macos-none` | accepts |
| `x86_64-windows-gnu` | accepts |
| `riscv64-linux-gnu` | rejects before generator declarations |
| `wasm32-wasi` | rejects before generator declarations |

The last two targets reach upstream's `features/gccfeatures.h` architecture error. Runtime loading also requires the platform loader; it is unavailable on WASI, Emscripten and freestanding targets.

`zig build matrix` uses each target CPU's AES-NI default and also checks enabled AES-NI on x86. It omits WASI for dynamic linkage or runtime loading, which require a platform dynamic loader.

## Consumption

Fetch the package from GitHub:

```sh
zig fetch --save git+https://github.com/CoffeeImpliesCode/random123#v1.14.0
```

Import the Zig module from `build.zig`:

```zig
const dep = b.dependency("random123", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("random123", dep.module("random123"));
```

| Name | Use |
|---|---|
| `module("random123")` | Typed Zig facade; `random123.c` exposes the translated bridge declarations. |
| `artifact("random123")` | Static archive by default or shared library; C/C++ consumers link it. |

The artifact installs all 26 upstream headers, `random123_bridge.h`, and `random123.pc`. C/C++ consumers include `<Random123/...>` or `<random123_bridge.h>` and link the `random123` artifact.

| Option | Default | Effect |
|---|---|---|
| `-Dtarget`, `-Dcpu`, `-Doptimize` | Zig defaults | Select target, CPU and optimization mode. |
| `-Dlinkage=static\|dynamic` | `static` | Select the library artifact. |
| `-Druntime=true\|false` | `false` | Use explicit runtime dispatch instead of direct linked calls; independent of artifact linkage. |
| `-Daesni=true\|false` | Follow target CPU | Compile or omit AES-NI and ARS wrappers for the selected target and consumer; `true` is an error when that target is non-x86. |
| `--prefix PATH` | `zig-out` | Choose the install prefix. |

See `LICENSE`, `NOTICE.md` and `FORK-LICENSE.md` for licensing terms.
