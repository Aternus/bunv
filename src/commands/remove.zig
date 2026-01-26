const std = @import("std");
const mem = std.mem;
const fs_utils = @import("../utilities/fs.zig");
const vm = @import("../vm.zig");
const output = @import("../cli/output.zig");

pub fn run(allocator: mem.Allocator, bunv_install_dir: []const u8, version: []const u8) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, bunv_install_dir);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit();
    }

    var version_exists = false;
    for (installed_versions.items) |installed_version| {
        if (mem.eql(u8, installed_version, version)) {
            version_exists = true;
            break;
        }
    }

    if (!version_exists) {
        output.fatalFmt("Bun v{s} is not installed", .{version});
    }

    const version_dir = try fs_utils.getBunVersionDir(allocator, bunv_install_dir, version);
    defer allocator.free(version_dir);

    output.printRemovingVersion(version);

    fs_utils.deleteTreeAbsolute(version_dir) catch |err| {
        output.fatalFmt("Failed to remove Bun v{s}: {s}", .{ version, @errorName(err) });
    };

    output.printRemovedVersion(version);
}
