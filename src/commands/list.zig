const std = @import("std");
const mem = std.mem;
const c = @import("../utilities/colors.zig");
const fs_utils = @import("../utilities/fs.zig");
const vm_utils = @import("../utilities/vm.zig");

pub fn run(allocator: mem.Allocator) anyerror!void {
    var installed_versions = try vm_utils.getInstalledVersions(allocator);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit(allocator);
    }

    try printInstalledVersions(allocator, installed_versions);
}

fn printInstalledVersions(allocator: mem.Allocator, versions: std.ArrayList([]const u8)) anyerror!void {
    std.debug.print("{s}Installed versions:{s}\n", .{ c.bold, c.reset });
    if (versions.items.len == 0) {
        std.debug.print("  {s}No versions installed{s}\n", .{ c.yellow, c.reset });
        return;
    }
    for (versions.items) |version| {
        const version_dir = try fs_utils.getBunVersionDir(allocator, version);
        defer allocator.free(version_dir);

        const bin_path = try fs_utils.getBunBinPath(allocator, version);
        defer allocator.free(bin_path);

        const global_packages_dir = try fs_utils.getBunGlobalPackagesDir(allocator, version);
        defer allocator.free(global_packages_dir);

        std.debug.print("  {s}{s}v{s}{s}\n", .{ c.bold, c.blue, version, c.reset });
        std.debug.print("    {s}│ {s} Directory:        {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, version_dir, c.reset });
        std.debug.print("    {s}│ {s} Bin:              {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, bin_path, c.reset });
        std.debug.print("    {s}└─{s} Global Packages:  {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, global_packages_dir, c.reset });
    }
}
