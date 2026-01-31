const exec_utils = @import("utilities/exec.zig");
const std = @import("std");

pub fn main() anyerror!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    try exec_utils.run(allocator, exec_utils.Cmd.bun);
}
