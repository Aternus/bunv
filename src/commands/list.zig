const std = @import("std");
const mem = std.mem;
const vm = @import("../utilities/vm.zig");
const c = @import("../utilities/colors.zig");
const fs_utils = @import("../utilities/fs.zig");

pub fn run(allocator: mem.Allocator, install_dir: []const u8) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, install_dir);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit();
    }

    try printInstalledVersions(allocator, install_dir, installed_versions);
}

fn printInstalledVersions(allocator: mem.Allocator, bunv_install_dir: []const u8, versions: std.array_list.Managed([]const u8)) !void {
    std.debug.print("{s}Installed versions:{s}\n", .{ c.bold, c.reset });
    if (versions.items.len == 0) {
        std.debug.print("  {s}No versions installed{s}\n", .{ c.yellow, c.reset });
        return;
    }
    for (versions.items) |version| {
        const bun_version_dir = try fs_utils.getBunVersionDir(allocator, bunv_install_dir, version);
        defer allocator.free(bun_version_dir);

        const bun_bin_path = try fs_utils.getBunBinaryPath(allocator, bun_version_dir);
        defer allocator.free(bun_bin_path);

        const bun_global_packages_dir = try fs_utils.getBunGlobalPackagesDir(allocator, bunv_install_dir, version);
        defer allocator.free(bun_global_packages_dir);

        std.debug.print("  {s}{s}v{s}{s}\n", .{ c.bold, c.blue, version, c.reset });
        std.debug.print("    {s}│ {s} Directory:        {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, bun_version_dir, c.reset });
        std.debug.print("    {s}│ {s} Bin:              {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, bun_bin_path, c.reset });
        std.debug.print("    {s}└─{s} Global Packages:  {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, bun_global_packages_dir, c.reset });
    }
}
