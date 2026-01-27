const std = @import("std");
const mem = std.mem;

pub fn commandOutputEquals(allocator: mem.Allocator, argv: []const []const u8, expected: []const u8) bool {
    if (commandOutput(allocator, argv)) |stdout| {
        defer allocator.free(stdout);
        const trimmed = mem.trim(u8, stdout, &std.ascii.whitespace);
        return mem.eql(u8, trimmed, expected);
    }
    return false;
}

pub fn commandOutputHasAvx2(allocator: mem.Allocator, argv: []const []const u8) bool {
    if (commandOutput(allocator, argv)) |stdout| {
        defer allocator.free(stdout);
        return outputHasAvx2(stdout);
    }
    return false;
}

pub fn outputHasAvx2(output: []const u8) bool {
    return mem.indexOf(u8, output, "AVX2") != null or mem.indexOf(u8, output, "avx2") != null;
}

fn commandOutput(allocator: mem.Allocator, argv: []const []const u8) ?[]u8 {
    const proc = std.process.Child.run(.{ .allocator = allocator, .argv = argv }) catch return null;
    defer allocator.free(proc.stderr);
    if (proc.term.Exited != 0) {
        allocator.free(proc.stdout);
        return null;
    }
    return proc.stdout;
}
