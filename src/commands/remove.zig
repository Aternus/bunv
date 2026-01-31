const std = @import("std");
const mem = std.mem;
const c = @import("../utilities/colors.zig");
const fs_utils = @import("../utilities/fs.zig");
const output = @import("../cli/output.zig");
const vm_utils = @import("../utilities/vm.zig");

pub fn run(allocator: mem.Allocator, version: []const u8) anyerror!void {
    var installed_versions = try vm_utils.getInstalledVersions(allocator);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit(allocator);
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

    const version_dir = try fs_utils.getBunVersionDir(allocator, version);
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
