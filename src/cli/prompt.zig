const std = @import("std");
const mem = std.mem;

pub fn promptConfirm(prompt: []const u8) anyerror!bool {
    const stdin_file = std.fs.File.stdin();
    if (!stdin_file.isTty()) return false;

    var stdout_buf = std.mem.zeroes([1024]u8);
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var stdin_buf = std.mem.zeroes([1024]u8);
    var stdin = stdin_file.reader(&stdin_buf);

    try stdout.interface.print("{s}", .{prompt});
    try stdout.interface.flush();
    const user_input = stdin.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => return false,
        error.EndOfStream => return false,
        else => return err,
    };

    return mem.eql(u8, user_input, "y");
}
