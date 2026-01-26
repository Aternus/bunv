const std = @import("std");
const mem = std.mem;
const output = @import("output.zig");

pub const Command = enum {
    list,
    remove,
    prune,
    help,
};

pub const ParsedArgs = struct {
    command: Command,
    version: ?[]const u8 = null,
    prune_args: []const []const u8 = &[_][]const u8{},
};

pub fn parseArgs(args: []const []const u8) ParsedArgs {
    if (args.len <= 1) {
        return .{ .command = .list };
    }

    const command = args[1];

    if (mem.eql(u8, command, "remove") or mem.eql(u8, command, "rm")) {
        if (args.len < 3) {
            output.errorMissingRemoveVersion();
        }
        return .{ .command = .remove, .version = args[2] };
    }

    if (mem.eql(u8, command, "prune")) {
        return .{ .command = .prune, .prune_args = args[2..] };
    }

    if (mem.eql(u8, command, "help") or mem.eql(u8, command, "--help") or mem.eql(u8, command, "-h")) {
        return .{ .command = .help };
    }

    output.errorUnknownCommand(command);
}
