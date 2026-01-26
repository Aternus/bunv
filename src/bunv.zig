const std = @import("std");
const utils = @import("utils.zig");
const builtin = @import("builtin");
const config = @import("config");
const cli_args = @import("cli/args.zig");
const commands = @import("commands/index.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const is_debug = try utils.isDebug(allocator);

    if (is_debug) {
        std.debug.print("Bunv Version: {f}\n", .{config.version});
        std.debug.print("Operating System: {s}\n", .{@tagName(builtin.os.tag)});
        std.debug.print("Architecture: {s}\n", .{@tagName(builtin.cpu.arch)});
    }

    const bunv_install_dir = try utils.getBunvInstallDir(allocator, is_debug);
    defer allocator.free(bunv_install_dir);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsed = cli_args.parseArgs(args);
    try commands.dispatch(allocator, bunv_install_dir, parsed);
}
