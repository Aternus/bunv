const std = @import("std");
const mem = std.mem;
const vm = @import("../vm.zig");
const output = @import("../cli/output.zig");

pub fn run(allocator: mem.Allocator, config_dir: []const u8) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, config_dir);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit();
    }

    try output.printInstalledVersions(allocator, config_dir, installed_versions);
}
