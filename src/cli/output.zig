const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const vm = @import("../vm.zig");
const c = @import("../colors.zig");
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

pub fn errorMissingRmVersion() noreturn {
    std.debug.print("{s}Error: 'rm' command requires a version argument{s}\n", .{ c.red, c.reset });
    std.debug.print("Usage: bunv rm <version>\n", .{});
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
    std.debug.print("                List installed Bun versions\n", .{});
    std.debug.print("  {s}{s}rm{s} {s}<version>{s}  Remove an installed Bun version\n", .{ c.bold, c.yellow, c.reset, c.dim, c.reset });
    std.debug.print("  {s}{s}prune{s}         Remove Bun installations found on this machine\n", .{ c.bold, c.yellow, c.reset });
    std.debug.print("  {s}{s}help{s}          Show this help message\n", .{ c.bold, c.cyan, c.reset });
    std.debug.print("\n", .{});
}

pub fn printInstalledVersions(allocator: mem.Allocator, bunv_install_dir: []const u8, versions: std.array_list.Managed([]const u8)) !void {
    std.debug.print("{s}Installed versions:{s}\n", .{ c.bold, c.reset });
    if (versions.items.len == 0) {
        std.debug.print("  {s}No versions installed{s}\n", .{ c.yellow, c.reset });
        return;
    }
    for (versions.items) |version| {
        try printVersionDetails(allocator, bunv_install_dir, version);
    }
}

pub fn printRemovingVersion(version: []const u8) void {
    std.debug.print("Removing Bun v{s}...\n", .{version});
}

pub fn printRemovedVersion(version: []const u8) void {
    std.debug.print("{s}✓{s} Successfully removed Bun v{s}\n", .{ c.green, c.reset, version });
}

fn printVersionDetails(allocator: mem.Allocator, bunv_install_dir: []const u8, version: []const u8) !void {
    const directory = try vm.getVersionDir(allocator, bunv_install_dir, version);
    defer allocator.free(directory);

    const bin = try vm.getBinPath(allocator, bunv_install_dir, version);
    defer allocator.free(bin);

    const global_dir = try fs.path.join(allocator, &[_][]const u8{ bunv_install_dir, "versions", version, "install", "global" });
    defer allocator.free(global_dir);

    std.debug.print("  {s}{s}v{s}{s}\n", .{ c.bold, c.blue, version, c.reset });
    std.debug.print("    {s}│ {s} Directory: {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, directory, c.reset });
    std.debug.print("    {s}│ {s} Global:    {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, global_dir, c.reset });
    std.debug.print("    {s}└─{s} Bin:       {s}{s}{s}\n", .{ c.grey, c.reset, c.cyan, bin, c.reset });
}
