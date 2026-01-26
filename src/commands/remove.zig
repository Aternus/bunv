const std = @import("std");
const mem = std.mem;
const fs_utils = @import("../utilities/fs.zig");
const vm = @import("../utilities/vm.zig");
const output = @import("../cli/output.zig");
const c = @import("../utilities/colors.zig");

pub fn run(allocator: mem.Allocator, install_dir: []const u8, version: []const u8) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, install_dir);
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

    const version_dir = try fs_utils.getBunVersionDir(allocator, install_dir, version);
    defer allocator.free(version_dir);

    printRemovingVersion(version);

    fs_utils.deleteTreeAbsolute(version_dir) catch |err| {
        output.fatalFmt("Failed to remove Bun v{s}: {s}", .{ version, @errorName(err) });
    };

    printRemovedVersion(version);
}

fn printRemovingVersion(version: []const u8) void {
    std.debug.print("Removing Bun v{s}...\n", .{version});
}

fn printRemovedVersion(version: []const u8) void {
    std.debug.print("{s}✓{s} Successfully removed Bun v{s}\n", .{ c.green, c.reset, version });
}
