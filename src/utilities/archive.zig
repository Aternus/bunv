const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");
const fs_utils = @import("fs.zig");
const crypto_utils = @import("crypto.zig");

pub fn extractBunFromZip(allocator: mem.Allocator, archive_path: []const u8, bin_path: []const u8) !void {
    const temp_dir = try fs_utils.getTempDir(allocator);
    defer allocator.free(temp_dir);

    const rand_hex = try crypto_utils.randomHexLower(allocator, 8);
    defer allocator.free(rand_hex);

    const extract_name = try std.fmt.allocPrint(allocator, "bunv-extract-{s}", .{rand_hex});
    defer allocator.free(extract_name);

    const extract_dir = try fs_utils.joinPath(allocator, &[_][]const u8{ temp_dir, extract_name });
    defer allocator.free(extract_dir);
    errdefer fs_utils.deleteTreeAbsolute(extract_dir) catch {};

    try fs_utils.ensureDirAbsolute(extract_dir);

    if (builtin.os.tag == .windows) {
        const cmd = try std.fmt.allocPrint(
            allocator,
            "Expand-Archive -Force -Path '{s}' -DestinationPath '{s}'",
            .{ archive_path, extract_dir },
        );
        defer allocator.free(cmd);

        const proc = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "powershell", "-NoProfile", "-NonInteractive", "-Command", cmd },
        }) catch |err| {
            std.debug.print("Failed to extract archive (PowerShell Expand-Archive): {any}\n", .{err});
            return err;
        };
        defer allocator.free(proc.stderr);
        defer allocator.free(proc.stdout);
        if (proc.term.Exited != 0) return error.ExtractFailed;
    } else {
        const unzip_proc = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "unzip", "-q", archive_path, "-d", extract_dir },
        }) catch |err| {
            std.debug.print("Failed to run `unzip` ({any}). Install `unzip` or run on a system with it available.\n", .{err});
            return err;
        };
        allocator.free(unzip_proc.stderr);
        allocator.free(unzip_proc.stdout);
        if (unzip_proc.term.Exited != 0) return error.ExtractFailed;
    }

    var dir = try std.fs.openDirAbsolute(extract_dir, .{ .iterate = true });
    defer dir.close();

    const bun_name = if (builtin.os.tag == .windows) "bun.exe" else "bun";
    const rel_path = (try fs_utils.findRelPathByBasename(allocator, dir, bun_name)) orelse {
        std.debug.print("Failed to locate {s} in downloaded archive\n", .{bun_name});
        return error.BunBinaryNotFound;
    };

    var src = try dir.openFile(rel_path, .{});
    defer src.close();

    var dest = try std.fs.createFileAbsolute(bin_path, .{ .truncate = true });
    defer dest.close();

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try src.read(&buf);
        if (n == 0) break;
        try dest.writeAll(buf[0..n]);
    }

    if (builtin.os.tag != .windows) {
        try dest.chmod(0o755);
    }

    try fs_utils.deleteTreeAbsolute(extract_dir);
}
