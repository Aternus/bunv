const std = @import("std");

pub fn getRandomHexLower(allocator: std.mem.Allocator, bytes_len: usize) ![]u8 {
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

pub fn getSha256ForFile(path: []const u8) ![32]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}
