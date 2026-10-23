// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
//
//! Random123 runtime descriptor: synchronization, required exports, and validation.
//! Providers are fork-built bridge libraries; upstream Random123 is header-only.
//! The bridge requires 28 base exports and five more when built with AES-NI/ARS.
//! Check `has_aesni` before calling AES-NI/ARS wrappers; loading alone is safe.
//! The ABI passes scalars and fixed word arrays by value; no allocations or callbacks cross it.
//! Validation checks key identity, zero-round counter identity, and exact 0.5 conversion before publication.
const rt = @import("rt");

/// Namespaced synchronization functions compiled from `runtime/sync.c`.
/// The prefix must match `runtime/graph.zig`; each configured module has independent state.
pub const Sync = struct {
    extern fn random123_rt_lock() void;
    extern fn random123_rt_unlock() void;
    extern fn random123_rt_wait() void;
    extern fn random123_rt_broadcast() void;
    // C `unsigned long long` is `u64` on every target this SDK supports.
    extern fn random123_rt_thread_self() u64;

    pub fn lock() void {
        random123_rt_lock();
    }
    pub fn unlock() void {
        random123_rt_unlock();
    }
    pub fn wait() void {
        random123_rt_wait();
    }
    pub fn broadcast() void {
        random123_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return random123_rt_thread_self();
    }
};

/// Configure the loader from the dispatch type without importing it here.
/// The generated dispatch owns the table and symbol lists for this target.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name shown in the pre-load panic.
        pub const library_name = "random123";

        /// Target-specific dispatch table and required symbols from the translation.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Verify upstream-derived key, zero-round counter, and conversion fixtures.
        /// Reject mismatched providers before publishing the table.
        pub fn validate(dst: *const table) ?[]const u8 {
            // Upstream philox.h:321 returns the key unchanged.
            const ukey: dispatch.struct_r123array1x32 = .{ .v = .{0xa4093822} };
            const keyed = dst.r123_bridge_philox2x32_keyinit(ukey);
            if (keyed.v[0] != ukey.v[0]) {
                return message(
                    "r123_bridge_philox2x32_keyinit changed the key it was given " ++
                        "({x}); upstream defines it as `return uk;` (philox.h:321), " ++
                        "so this provider is not the Random123 bridge this header " ++
                        "describes",
                    .{keyed.v[0]},
                );
            }

            // philox.h:325-341 skips all rounds when R=0, preserving the counter.
            const ctr: dispatch.struct_r123array2x32 = .{ .v = .{ 0x243f6a88, 0x85a308d3 } };
            const zero = dst.r123_bridge_philox2x32_R(0, ctr, keyed);
            if (zero.v[0] != ctr.v[0] or zero.v[1] != ctr.v[1]) {
                return message(
                    "r123_bridge_philox2x32_R(0, ...) returned ({x} {x}) for a counter " ++
                        "it was given as ({x} {x}); upstream's zero-round guard " ++
                        "returns the counter unchanged (philox.h:325-341), so a " ++
                        "counter is not surviving the crossing by value and back",
                    .{ zero.v[0], zero.v[1], ctr.v[0], ctr.v[1] },
                );
            }

            // u01fixedpt.h:122,160-162 maps 2^63 exactly to 0.5.
            const unit = dst.r123_bridge_u01_closed_open_64_double(@as(u64, 1) << 63);
            if (unit != 0.5) {
                return message(
                    "r123_bridge_u01_closed_open_64_double(2^63) answered {x}, not the " ++
                        "exact 0x3fe0000000000000 upstream's (i >> 11) * 2^-53 gives " ++
                        "(u01fixedpt.h:122,160-162), so this provider's conversion " ++
                        "arithmetic is not upstream's",
                    .{@as(u64, @bitCast(unit))},
                );
            }

            return null;
        }
    };
}

const std = @import("std");

/// Scratch storage for diagnostics returned by the current load call.
/// Attempts are serialized per configured module; every formatted value fits.
var message_buffer: [256]u8 = undefined;

/// Format a validation diagnostic; report overflow rather than accepting the provider.
fn message(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "random123: a load-time check failed and its value could not be printed";
}
