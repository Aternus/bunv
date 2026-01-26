const std = @import("std");
const env_utils = @import("utilities/env.zig");
const fs_utils = @import("utilities/fs.zig");
const builtin = @import("builtin");
const config = @import("config");
const cli_args = @import("cli/args.zig");
const commander = @import("commands/commander.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const is_debug = try env_utils.isDebug(allocator);

    if (is_debug) {
        std.debug.print("Bunv Version: {f}\n", .{config.version});
        std.debug.print("Operating System: {s}\n", .{@tagName(builtin.os.tag)});
        std.debug.print("Architecture: {s}\n", .{@tagName(builtin.cpu.arch)});
    }

    const install_dir = try fs_utils.getBunvInstallDir(allocator, is_debug);
    defer allocator.free(install_dir);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsedArgs = cli_args.parseArgs(args);
    try commander.dispatch(allocator, install_dir, parsedArgs);
}
