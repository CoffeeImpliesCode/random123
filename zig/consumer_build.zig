// SPDX-License-Identifier: BSD-3-Clause
// Copyright 2025 CoffeeImpliesCode contributors.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    std.debug.assert(args.len >= 5);

    // Cache and library paths become concrete only in the maker.
    try init.environ_map.put("ZIG_GLOBAL_CACHE_DIR", args[1]);
    try init.environ_map.put("ZIG_LIB_DIR", args[2]);
    var child = try std.process.spawn(init.io, .{
        .argv = args[3..],
        .environ_map = init.environ_map,
    });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => {
            std.debug.print("consumer build {f}\n", .{term});
            std.process.exit(1);
        },
    }
}
