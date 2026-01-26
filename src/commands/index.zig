const std = @import("std");
const mem = std.mem;
const cli_args = @import("../cli/args.zig");
const output = @import("../cli/output.zig");
const list_cmd = @import("list.zig");
const remove_cmd = @import("remove.zig");
const prune_cmd = @import("prune.zig");

pub fn dispatch(allocator: mem.Allocator, config_dir: []const u8, parsed: cli_args.ParsedArgs) !void {
    switch (parsed.command) {
        .list => try list_cmd.run(allocator, config_dir),
        .rm => try remove_cmd.run(allocator, config_dir, parsed.version.?),
        .prune => try prune_cmd.run(allocator, config_dir, parsed.prune_args),
        .help => output.printHelp(),
    }
}
