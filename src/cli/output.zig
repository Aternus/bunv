const std = @import("std");
const mem = std.mem;
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
