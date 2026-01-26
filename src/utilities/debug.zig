const std = @import("std");
const mem = std.mem;

pub fn printArgs(label: []const u8, args: anytype) void {
    std.debug.print("{s}: {{ ", .{label});
    for (args, 0..) |arg, index| {
        if (index != 0) std.debug.print(", ", .{});
        std.debug.print("{s}", .{argToSlice(arg)});
    }
    std.debug.print(" }}\n", .{});
}

fn argToSlice(arg: anytype) []const u8 {
    return switch (@TypeOf(arg)) {
        [:0]const u8, [:0]u8 => mem.sliceTo(arg, 0),
        []const u8 => arg,
        else => @compileError("Unsupported argument type for printArgs"),
    };
}
