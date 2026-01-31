const std = @import("std");

pub fn getRandomHexLower(allocator: std.mem.Allocator, bytes_len: usize) anyerror![]u8 {
    const bytes = try allocator.alloc(u8, bytes_len);
    defer allocator.free(bytes);
    std.crypto.random.bytes(bytes);

    const out = try allocator.alloc(u8, bytes_len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = toHexLower(b >> 4);
        out[i * 2 + 1] = toHexLower(b & 0x0f);
    }
    return out;
}

fn toHexLower(n: u8) u8 {
    return if (n < 10) '0' + n else 'a' + (n - 10);
}

pub fn getSha256ForFile(path: []const u8) anyerror![32]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var buf = std.mem.zeroes([64 * 1024]u8);
    while (true) {
        const bytes_read = try file.read(&buf);
        if (bytes_read == 0) break;
        hasher.update(buf[0..bytes_read]);
    }

    var out = std.mem.zeroes([32]u8);
    hasher.final(&out);
    return out;
}
