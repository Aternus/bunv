const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const env_utils = @import("env.zig");
const fs_utils = @import("fs.zig");

pub fn pathExists(path: []const u8) bool {
    fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub fn fileExists(file: []const u8) anyerror!bool {
    fs.accessAbsolute(file, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
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

pub fn openDirAbsolute(path: []const u8, options: fs.Dir.OpenOptions) anyerror!fs.Dir {
    return fs.openDirAbsolute(path, options);
}

pub fn openFileAbsolute(path: []const u8, options: fs.File.OpenFlags) anyerror!fs.File {
    return fs.openFileAbsolute(path, options);
}

pub fn deleteTreeAbsolute(path: []const u8) anyerror!void {
    return fs.deleteTreeAbsolute(path);
}

pub fn makeDirAbsolute(path: []const u8) anyerror!void {
    return fs.makeDirAbsolute(path);
}

pub fn ensureDirAbsolute(path: []const u8) anyerror!void {
    std.debug.assert(fs.path.isAbsolute(path));

    var it = try fs.path.componentIterator(path);
    while (it.next()) |component| {
        fs.makeDirAbsolute(component.path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

pub fn joinPath(allocator: mem.Allocator, parts: []const []const u8) anyerror![]u8 {
    return fs.path.join(allocator, parts);
}

pub fn dirname(path: []const u8) ?[]const u8 {
    return fs.path.dirname(path);
}

pub fn realpathAlloc(allocator: mem.Allocator, path: []const u8) anyerror![]u8 {
    return fs.cwd().realpathAlloc(allocator, path);
}

pub fn getTempDir(allocator: mem.Allocator) anyerror![]u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const keys = if (builtin.os.tag == .windows)
        [_][]const u8{ "TEMP", "TMP", "TMPDIR" }
    else
        [_][]const u8{ "TMPDIR", "TMP", "TEMP" };

    for (keys) |key| {
        if (env_map.get(key)) |value| {
            if (value.len > 0) return allocator.dupe(u8, value);
        }
    }

    if (builtin.os.tag == .windows) {
        return allocator.dupe(u8, "C:\\\\Windows\\\\Temp");
    }
    return allocator.dupe(u8, "/tmp");
}

pub fn getBunvInstallDir(allocator: mem.Allocator) anyerror![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const bunv_install = env_map.get("BUNV_INSTALL") orelse ".bunv";

    const user_home_dir = try env_utils.getUserHomeDir(allocator);
    defer allocator.free(user_home_dir);

    const bunv_install_dir = try joinPath(allocator, &[_][]const u8{ user_home_dir, bunv_install });

    return bunv_install_dir;
}

pub fn getBunvVersionsDir(allocator: mem.Allocator) anyerror![]u8 {
    const install_dir = try fs_utils.getBunvInstallDir(allocator);
    defer allocator.free(install_dir);
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions" });
}

pub fn getBunVersionDir(allocator: mem.Allocator, version: []const u8) anyerror![]u8 {
    const install_dir = try fs_utils.getBunvInstallDir(allocator);
    defer allocator.free(install_dir);
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions", version });
}

pub fn getBunBinPath(allocator: mem.Allocator, version: []const u8) anyerror![]u8 {
    const install_dir = try fs_utils.getBunvInstallDir(allocator);
    defer allocator.free(install_dir);
    var bin_name = "bun";
    if (builtin.os.tag == .windows) {
        bin_name = "bun.exe";
    }
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions", version, "bin", bin_name });
}

pub fn getBunGlobalPackagesDir(allocator: mem.Allocator, version: []const u8) anyerror![]u8 {
    const install_dir = try fs_utils.getBunvInstallDir(allocator);
    defer allocator.free(install_dir);
    return try joinPath(allocator, &[_][]const u8{ install_dir, "versions", version, "install", "global" });
}

pub fn findRelPathByBasename(
    allocator: mem.Allocator,
    root_dir: fs.Dir,
    basename: []const u8,
) anyerror!?[]u8 {
    var pending = std.ArrayList([]u8).empty;
    defer {
        for (pending.items) |p| allocator.free(p);
        pending.deinit(allocator);
    }

    try pending.append(allocator, try allocator.dupe(u8, ""));

    while (pending.items.len > 0) {
        const idx = pending.items.len - 1;
        const rel_dir = pending.items[idx];
        pending.items.len -= 1;
        defer allocator.free(rel_dir);

        var dir = if (rel_dir.len == 0)
            root_dir
        else
            try root_dir.openDir(rel_dir, .{ .iterate = true });
        defer if (rel_dir.len != 0) dir.close();

        var it = dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    if (!mem.eql(u8, entry.name, basename)) continue;
                    if (rel_dir.len == 0) return try allocator.dupe(u8, entry.name);
                    return try joinPath(allocator, &[_][]const u8{ rel_dir, entry.name });
                },
                .directory => {
                    const next_rel = if (rel_dir.len == 0)
                        try allocator.dupe(u8, entry.name)
                    else
                        try joinPath(allocator, &[_][]const u8{ rel_dir, entry.name });
                    try pending.append(allocator, next_rel);
                },
                else => {},
            }
        }
    }

    return null;
}
