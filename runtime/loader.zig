// SPDX-License-Identifier: BSD-3-Clause
//
//! Generic runtime loader for one configured module.
//! It opens, resolves, validates, and publishes a complete table; failures close candidates and can be retried.
//! Same-request callers share attempts; different requests mismatch, and a successful provider stays loaded.
//! Library symbols, tables, synchronization, and validation come from the supplied configuration.
//! Provider constructors that wait on load callers can still create undetectable deadlocks.

const std = @import("std");
const builtin = @import("builtin");

/// Choose a file path or platform-loader name; requests never fall back between them.
/// Paths must be absolute; system names must be bare and contain no NUL.
pub const LoadSource = union(enum) {
    /// Absolute shared-library path.
    path: []const u8,
    /// Bare name searched by the platform loader.
    system: []const u8,
};

/// Errors returned by `load`.
pub const LoadError = error{
    /// Empty path or system-library name.
    EmptySource,
    /// Request exceeds `max_source_len`; it is refused, never truncated.
    SourceTooLong,
    /// Relative path, path-shaped system name, or embedded NUL.
    InvalidSource,
    /// Target has no dynamic loader.
    UnsupportedTarget,
    /// Platform loader refused the request or a dependency.
    OpenFailed,
    /// Opened candidate lacks a required translated symbol.
    MissingSymbol,
    /// Configuration validation rejected the resolved provider.
    ValidationFailed,
    /// A different request is loading or already loaded.
    ProviderMismatch,
    /// The current attempt owner called `load` recursively.
    ReentrantLoad,
};

/// Maximum request length in bytes.
pub const max_source_len = 32768;

/// Fixed-size request copy retained for idempotence after caller buffers expire.
/// No allocation; bytes remain valid for the process lifetime.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Store a request after its length has been validated.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Return the retained request, or null before a successful load.
    /// Returned bytes point into this record and remain valid for its lifetime.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compare request kind and bytes exactly; paths are not normalized.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// Readiness states for one configured module.
pub const Phase = enum(u8) {
    /// No provider is published; failed attempts return here for explicit retry.
    not_loaded = 0,
    /// One thread resolves a candidate; the table is not readable.
    loading = 1,
    /// The complete table is published.
    ready = 2,
};

/// Atomic table-publication flag.
/// The loader stores with release ordering; routed calls read with acquire ordering.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@intFromEnum(Phase.not_loaded)),

    /// Acquire-check whether a provider is published.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @intFromEnum(Phase.ready);
    }

    /// Read the current readiness state.
    pub fn state(self: *const Ready) Phase {
        return @enumFromInt(self.phase.load(.acquire));
    }

    /// Publish or withdraw readiness with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@intFromEnum(value), .release);
    }
};

/// Required export kind, determining the table field type.
pub const SymbolKind = enum {
    /// A function pointer with the translated header's exact type.
    function,
    /// Address of provider-owned data, never a copied value.
    data,
};

/// One required export name and its kind.
pub const Symbol = struct {
    /// Name exactly as declared by the C header.
    name: [:0]const u8,
    /// Function-pointer or data-address field kind.
    kind: SymbolKind,
};

/// Panic in every optimization mode when a routed call precedes successful load.
/// Names the library and symbol that were reached too early.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether this target has a dynamic loader.
/// WASI, Emscripten, and freestanding targets do not.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Process-global loader for one dispatch configuration; successful handles remain loaded for the process lifetime.
/// Publishes only complete tables; failures can be retried, matching callers share results, and conflicting requests fail.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The generated dispatch table type.
        pub const table_type = Config.table;

        /// In-flight attempt or waiter-drain record for this module.
        attempt: ?Attempt = null,

        /// Request copied before loading and immutable after publication.
        request: SourceRecord = .{},

        /// Open, resolve, validate, and publish the named provider.
        /// Failed attempts publish nothing and can be retried.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // Repeated loads after success take one acquire check and no lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Matching callers wait for this attempt and receive its result.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the record until all attached waiters have read the result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Drain waiters from a prior attempt before starting a retry.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run platform loading without the lock; provider constructors may block.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Broadcast the result so every attached waiter can proceed.
            Config.sync.broadcast();
            // Retain the record until every waiter leaves.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Return the successful request, or null before any provider is loaded.
        /// Returned bytes remain valid for the process lifetime.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// Reject a request that differs from the published one.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // Every call here follows an acquire readiness check.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Open, resolve, and validate without the loader lock.
        /// Close the candidate on every path that does not succeed.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    // Preserve the validator's refusal reason in diagnostics.
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // The published table points into this retained handle.
            retain = true;
        }
    };
}

/// One in-flight or undrained load attempt.
const Attempt = struct {
    /// Thread running the attempt, for reentrancy checks.
    owner: u64,
    /// Result published under the lock before waiters observe loading end.
    result: LoadError!void = error.OpenFailed,
    /// Attached waiters that have not yet read the result.
    waiters: usize = 0,
};

/// Windows UTF-16 path bound; the buffer also reserves space for the terminator.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// A target without a dynamic loader; every request returns `UnsupportedTarget`.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix `dlopen`/`dlsym`/`dlclose` backend.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // Resolve dependencies now so open failures surface at this call.
        // Keep symbols local to avoid cross-SDK lookup collisions.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

/// Direct Windows loader imports, grouped in one declaration block.
const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows `LoadLibraryExW`/`GetProcAddress`/`FreeLibrary` backend.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories for bare names; explicit paths also use their directory.
    /// Avoid current-directory search for bare names.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
