# Zig facade API

## Built-in generators

Each type is a stateless namespace over caller-supplied counter and key arrays. Built-in calls allocate no memory and retain no state.

| Type | Counter | Key | Default rounds | Maximum |
|---|---|---|---:|---:|
| `Philox2x32` | `[2]u32` | `[1]u32` | 10 | 16 |
| `Philox4x32` | `[4]u32` | `[2]u32` | 10 | 16 |
| `Philox2x64` | `[2]u64` | `[1]u64` | 10 | 16 |
| `Philox4x64` | `[4]u64` | `[2]u64` | 10 | 16 |
| `Threefry2x32` | `[2]u32` | `[2]u32` | 20 | 32 |
| `Threefry4x32` | `[4]u32` | `[4]u32` | 20 | 72 |
| `Threefry2x64` | `[2]u64` | `[2]u64` | 20 | 32 |
| `Threefry4x64` | `[4]u64` | `[4]u64` | 20 | 72 |

```zig
const r = @import("random123");
const ctr: r.Philox4x32.counter = .{ 0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344 };
const key: r.Philox4x32.key = .{ 0xa4093822, 0x299f31d0 };
const out = r.Philox4x32.generate(ctr, key);
```

Each generator exposes `name`, `counter`, `key`, `default_rounds`, `max_rounds`, `word_bits`, `counter_bits` and `key_bits`.

- `init(key)` returns the key unchanged.
- `rounds(R, counter, key)` runs exactly `R` rounds. `R > max_rounds` panics before the native call in every optimization mode.
- `generate(counter, key)` uses `default_rounds`.

`R == 0` is valid. Philox returns the counter unchanged; Threefry returns the counter plus the key, word by word. `generators` groups the eight built-ins for iteration with `for` or `inline for`; indexing is not part of its contract.

## Custom generator factory

`Generator(spec)` returns a namespace type. `spec` supplies `name`, `counter`, `key`, `default_rounds`, `max_rounds` and `round`.

`counter` and `key` must be array types with matching unsigned `u32` or `u64` elements. The factory checks the array shapes and `default_rounds <= max_rounds` at compile time. The callback receives the round count, `.{ .v = counter }` and `.{ .v = key }`, and returns a value whose `.v` is the counter type. Callback compatibility is checked when a generated method is analyzed.

The factory cannot verify that a custom callback enforces its declared round bound, is pure, or is thread-safe. Those obligations belong to the caller.

## Unit-interval conversions

`UnitInterval` aliases the twelve translated bridge functions. The range prefix names the included endpoints.

| Methods | Input | Result |
|---|---|---|
| `closedClosed32Float`, `closedOpen32Float`, `openClosed32Float`, `openOpen32Float` | `u32` | `f32` |
| `closedClosed32Double`, `closedOpen32Double`, `openClosed32Double`, `openOpen32Double` | `u32` | `f64` |
| `closedClosed64Double`, `closedOpen64Double`, `openClosed64Double`, `openOpen64Double` | `u64` | `f64` |

Each conversion maps one integer to a fixed grid; it does not draw a random value or create a seed. `closedClosed32Float` and `closedClosed64Double` ignore the input's high bit, so their results are not monotonic. Upstream also documents an x87 precision caveat that can affect exact endpoints on x86.

## Raw C surface

`c` is the translation of this fork's `zig/bridge/random123_bridge.h`, not the full upstream C++ API. It exposes bridge functions, translated `r123arrayNxW` types and constants. Raw round calls retain upstream's assertion behavior; use facade `rounds` for the unconditional bound check.

`has_aesni` is a compile-time flag for the AES-NI and ARS wrappers, not a hardware probe. When those wrappers are present, `c.r123_bridge_have_aesni()` checks the running CPU before use.

## Runtime-loading API

`runtime_loaded` is a compile-time constant. In a runtime-loaded build, load a provider before calling the facade:

```zig
if (comptime r.runtime_loaded) {
    try r.load(.{ .path = "/path/to/librandom123.so" });
}
```

`LoadSource` accepts an absolute `.path` or a bare `.system` name. It rejects NUL bytes and path components in system names; requests do not fall back to another form. `load` retains the provider handle and a copy of the request for the process lifetime; there is no unload or reset.

The same request is idempotent. Concurrent calls for it share the attempt's result. A different request after success or during another attempt returns `ProviderMismatch`; failed attempts may be retried explicitly. Calls before successful loading panic in every optimization mode. `loadedSource()` returns the retained request or `null` before success. In a linked build, `runtime_loaded` is false, `loadedSource()` returns `null`, and calling `load` panics.

`LoadError` variants are `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch` and `ReentrantLoad`. `load` is thread-safe; a recursive call from the thread running an attempt returns `ReentrantLoad`.