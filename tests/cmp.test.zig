const std = @import("std");
const cmp = @import("tests").cmp;

test "cmp.semVerDESC" {
    const allocator = std.testing.allocator;

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    try versions.append(allocator, try allocator.dupe(u8, "1.2.0"));
    try versions.append(allocator, try allocator.dupe(u8, "1.2.0-canary.2"));
    try versions.append(allocator, try allocator.dupe(u8, "1.2.0-canary.10"));
    try versions.append(allocator, try allocator.dupe(u8, "1.10.0"));
    try versions.append(allocator, try allocator.dupe(u8, "2.0.0-rc.1"));
    try versions.append(allocator, try allocator.dupe(u8, "2.0.0"));

    std.sort.heap([]const u8, versions.items, {}, cmp.semVerDESC);

    try std.testing.expectEqualStrings("2.0.0", versions.items[0]);
    try std.testing.expectEqualStrings("2.0.0-rc.1", versions.items[1]);
    try std.testing.expectEqualStrings("1.10.0", versions.items[2]);
    try std.testing.expectEqualStrings("1.2.0", versions.items[3]);
    try std.testing.expectEqualStrings("1.2.0-canary.10", versions.items[4]);
    try std.testing.expectEqualStrings("1.2.0-canary.2", versions.items[5]);
}
