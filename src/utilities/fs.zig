const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const env_utils = @import("env.zig");

pub fn isFileExists(file: []u8) !bool {
    std.fs.accessAbsolute(file, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

pub fn getBunvInstallDir(allocator: mem.Allocator, is_debug: bool) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const bunv_install = env_map.get("BUNV_INSTALL") orelse ".bunv";

    const user_home_dir = try env_utils.getUserHomeDir(allocator);
    defer allocator.free(user_home_dir);

    if (is_debug) std.debug.print("User Home Dir: {s}\n", .{user_home_dir});

    const bunv_install_dir = try fs.path.join(allocator, &[_][]const u8{ user_home_dir, bunv_install });

    if (is_debug) std.debug.print("Bunv Install Dir: {s}\n", .{bunv_install_dir});

    return bunv_install_dir;
}

pub fn getBunvVersionsDir(allocator: mem.Allocator, bunv_install_dir: []const u8) ![]u8 {
    return try fs.path.join(allocator, &[_][]const u8{ bunv_install_dir, "versions" });
}

pub fn getBunVersionDir(allocator: mem.Allocator, bunv_install_dir: []const u8, version: []const u8) ![]u8 {
    return try fs.path.join(allocator, &[_][]const u8{ bunv_install_dir, "versions", version });
}

pub fn getBunBinPath(allocator: mem.Allocator, bunv_install_dir: []const u8, version: []const u8) ![]u8 {
    return try fs.path.join(allocator, &[_][]const u8{ bunv_install_dir, "versions", version, "bin", "bun" });
}

pub fn getBunGlobalPackagesPath(allocator: mem.Allocator, bunv_install_dir: []const u8, version: []const u8) ![]u8 {
    return try fs.path.join(allocator, &[_][]const u8{ bunv_install_dir, "versions", version, "install", "global" });
}
