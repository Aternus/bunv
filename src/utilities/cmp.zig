const std = @import("std");
const mem = std.mem;
const semver = std.SemanticVersion;

pub fn semVerDESC(_: void, a: []const u8, b: []const u8) bool {
    const av = semver.parse(a) catch return mem.lessThan(u8, a, b);
    const bv = semver.parse(b) catch return mem.lessThan(u8, a, b);
    return semver.order(av, bv) == .gt;
}
