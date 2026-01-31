const std = @import("std");
const mem = std.mem;
const Semver = std.SemanticVersion;

pub fn semVerDESC(_: void, a: []const u8, b: []const u8) bool {
    const a_version = Semver.parse(a) catch return mem.lessThan(u8, a, b);
    const b_version = Semver.parse(b) catch return mem.lessThan(u8, a, b);
    return Semver.order(a_version, b_version) == .gt;
}
