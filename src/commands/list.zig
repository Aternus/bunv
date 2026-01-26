const std = @import("std");
const mem = std.mem;
const vm = @import("../vm.zig");
const output = @import("../cli/output.zig");

pub fn run(allocator: mem.Allocator, bunv_install_dir: []const u8) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, bunv_install_dir);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit();
    }

    try output.printInstalledVersions(allocator, bunv_install_dir, installed_versions);
}
