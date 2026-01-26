const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const mem = std.mem;
const env_utils = @import("env.zig");

pub fn pathExists(path: []const u8) bool {
    fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub fn fileExists(file: []const u8) !bool {
    fs.accessAbsolute(file, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

pub fn dirExists(path: []const u8) bool {
    var dir = fs.openDirAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.NotDir => return false,
        else => return false,
    };
    dir.close();
    return true;
}

pub fn openDirAbsolute(path: []const u8, options: fs.Dir.OpenOptions) !fs.Dir {
    return fs.openDirAbsolute(path, options);
}

pub fn openFileAbsolute(path: []const u8, options: fs.File.OpenFlags) !fs.File {
    return fs.openFileAbsolute(path, options);
}

pub fn deleteTreeAbsolute(path: []const u8) !void {
    return fs.deleteTreeAbsolute(path);
}

pub fn makeDirAbsolute(path: []const u8) !void {
    return fs.makeDirAbsolute(path);
}

pub fn ensureDirAbsolute(path: []const u8) !void {
    fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
}

pub fn joinPath(allocator: mem.Allocator, parts: []const []const u8) ![]u8 {
    return fs.path.join(allocator, parts);
}

pub fn dirname(path: []const u8) ?[]const u8 {
    return fs.path.dirname(path);
}

pub fn realpathAlloc(allocator: mem.Allocator, path: []const u8) ![]u8 {
    return fs.cwd().realpathAlloc(allocator, path);
}

pub fn getBunvInstallDir(allocator: mem.Allocator, is_debug: bool) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const bunv_install = env_map.get("BUNV_INSTALL") orelse ".bunv";

    const user_home_dir = try env_utils.getUserHomeDir(allocator);
    defer allocator.free(user_home_dir);

    if (is_debug) std.debug.print("User Home Dir: {s}\n", .{user_home_dir});

    const bunv_install_dir = try joinPath(allocator, &[_][]const u8{ user_home_dir, bunv_install });

    if (is_debug) std.debug.print("Bunv Install Dir: {s}\n", .{bunv_install_dir});

    return bunv_install_dir;
}

pub fn getBunvVersionsDir(allocator: mem.Allocator, install_dir: []const u8) ![]u8 {
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions" });
}

pub fn getBunVersionDir(allocator: mem.Allocator, install_dir: []const u8, version: []const u8) ![]u8 {
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions", version });
}

pub fn getBunBinaryPath(allocator: mem.Allocator, install_dir: []const u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        return try joinPath(allocator, &[_][]const u8{ install_dir, "bin", "bun.exe" });
    }
    return try joinPath(allocator, &[_][]const u8{ install_dir, "bin", "bun" });
}

pub fn getBunGlobalPackagesDir(allocator: mem.Allocator, install_dir: []const u8, version: []const u8) ![]u8 {
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions", version, "install", "global" });
}
