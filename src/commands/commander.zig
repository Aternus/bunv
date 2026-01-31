const std = @import("std");
const mem = std.mem;
const cli_args = @import("../cli/args.zig");
const list_cmd = @import("list.zig");
const output = @import("../cli/output.zig");
const prune_cmd = @import("prune.zig");
const remove_cmd = @import("remove.zig");

pub fn dispatch(allocator: mem.Allocator, parsed_args: cli_args.ParsedArgs) anyerror!void {
    switch (parsed_args.command) {
        .list => try list_cmd.run(allocator),
        .remove => try remove_cmd.run(allocator, parsed_args.version.?),
        .prune => try prune_cmd.run(allocator, parsed_args.prune_args),
        .help => output.printHelp(),
    }
}
