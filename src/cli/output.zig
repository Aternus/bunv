const std = @import("std");
const mem = std.mem;
const fs_utils = @import("../utilities/fs.zig");
const c = @import("../utilities/colors.zig");
const config = @import("config");

pub fn fatal(msg: []const u8) noreturn {
    fatalFmt("{s}", .{msg});
}

pub fn fatalFmt(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("{s}Error: ", .{c.red});
    std.debug.print(fmt, args);
    std.debug.print("{s}\n", .{c.reset});
    std.process.exit(1);
}

pub fn errorMissingRemoveVersion() noreturn {
    std.debug.print("{s}Error: 'remove' command requires a version argument{s}\n", .{ c.red, c.reset });
    std.debug.print("Usage: bunv remove <version>\n", .{});
    std.process.exit(1);
}

pub fn errorUnknownCommand(command: []const u8) noreturn {
    std.debug.print("{s}Error: Unknown command '{s}'{s}\n", .{ c.red, command, c.reset });
    std.debug.print("Run 'bunv help' for usage information\n", .{});
    std.process.exit(1);
}

pub fn printHelp() void {
    std.debug.print("\n{s}{s}Bunv{s} - The Bun version manager {s}({f}){s}\n\n", .{ c.bold, c.blue, c.reset, c.dim, config.version, c.reset });
    std.debug.print("{s}Commands:{s}\n", .{ c.bold, c.reset });
    std.debug.print("                    List installed Bun versions\n", .{});
    std.debug.print("  {s}{s}remove{s} {s}<version>{s}  Remove an installed Bun version\n", .{ c.bold, c.yellow, c.reset, c.dim, c.reset });
    std.debug.print("  {s}{s}prune{s}             Remove Bun installs managed by bunv or the official installer\n", .{ c.bold, c.yellow, c.reset });
    std.debug.print("  {s}{s}help{s}              Show this help message\n", .{ c.bold, c.cyan, c.reset });
    std.debug.print("\n", .{});
}

pub fn printInstalledVersions(allocator: mem.Allocator, bunv_install_dir: []const u8, versions: std.array_list.Managed([]const u8)) !void {
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

pub fn printRemovingVersion(version: []const u8) void {
    std.debug.print("Removing Bun v{s}...\n", .{version});
}

pub fn printRemovedVersion(version: []const u8) void {
    std.debug.print("{s}✓{s} Successfully removed Bun v{s}\n", .{ c.green, c.reset, version });
}
