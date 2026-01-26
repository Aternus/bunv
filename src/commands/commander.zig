const std = @import("std");
const mem = std.mem;
const cli_args = @import("../cli/args.zig");
const output = @import("../cli/output.zig");
const list_cmd = @import("list.zig");
const remove_cmd = @import("remove.zig");
const prune_cmd = @import("prune.zig");

pub fn dispatch(allocator: mem.Allocator, install_dir: []const u8, parsedArgs: cli_args.ParsedArgs) !void {
    switch (parsedArgs.command) {
        .list => try list_cmd.run(allocator, install_dir),
        .remove => try remove_cmd.run(allocator, install_dir, parsedArgs.version.?),
        .prune => try prune_cmd.run(allocator, install_dir, parsedArgs.prune_args),
        .help => output.printHelp(),
    }
}
