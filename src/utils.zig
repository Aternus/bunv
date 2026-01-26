const std = @import("std");
const os = std.os;
const mem = std.mem;
const fs = std.fs;
const json = std.json;
const builtin = @import("builtin");
const vm = @import("vm.zig");

pub const Cmd = enum {
    bun,
    bunx,
};

pub fn run(allocator: mem.Allocator, cmd: Cmd) !void {
    const is_debug = try isDebug(allocator);
    if (is_debug) std.debug.print("Executable: {}\n", .{cmd});

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (cmd == .bun and args.len > 1 and mem.eql(u8, args[1], "upgrade")) {
        std.debug.print("bun upgrade is a no-op under bunv. Update your version file instead.\n", .{});
        std.debug.print("See: https://github.com/Aternus/bunv#upgrading-bun\n", .{});
        std.process.exit(0);
    }

    const config_dir = try getConfigDir(allocator, is_debug);
    defer allocator.free(config_dir);

    if (is_debug) std.debug.print("Config Dir: {s}\n", .{config_dir});

    const project_version = try vm.detectProjectVersion(allocator, is_debug) orelse try vm.getLatestLocalVersion(allocator, is_debug, config_dir) orelse try vm.getLatestRemoteVersion(allocator, is_debug);
    defer allocator.free(project_version);

    try vm.ensureVersionDownloaded(allocator, config_dir, project_version);

    // Run bun command

    const bin = try fs.path.join(allocator, &[_][]const u8{ config_dir, "versions", project_version, "bin", "bun" });
    defer allocator.free(bin);

    const global_install_dir = try fs.path.join(allocator, &[_][]const u8{
        config_dir,
        "versions",
        project_version,
        "install",
        "global",
    });
    defer allocator.free(global_install_dir);

    const global_bin_dir = try fs.path.join(allocator, &[_][]const u8{ config_dir, "versions", project_version, "bin" });
    defer allocator.free(global_bin_dir);

    var new_args = try std.array_list.Managed([]const u8).initCapacity(allocator, 5);
    defer new_args.deinit();

    try new_args.append(bin);
    if (cmd == .bunx) try new_args.append("x");

    for (args[1..]) |arg| {
        try new_args.append(arg);
    }

    if (is_debug) {
        printArgs("Original args", args);
        printArgs("Modified args", new_args.items);
        std.debug.print("---\n", .{});
    }

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    try env_map.put("BUN_INSTALL_GLOBAL_DIR", global_install_dir);
    try env_map.put("BUN_INSTALL_BIN", global_bin_dir);

    return runBunCmd(allocator, new_args.items, &env_map);
}

fn printArgs(label: []const u8, args: anytype) void {
    std.debug.print("{s}: {{ ", .{label});
    for (args, 0..) |arg, index| {
        if (index != 0) std.debug.print(", ", .{});
        std.debug.print("{s}", .{argToSlice(arg)});
    }
    std.debug.print(" }}\n", .{});
}

fn argToSlice(arg: anytype) []const u8 {
    return switch (@TypeOf(arg)) {
        [:0]const u8, [:0]u8 => mem.sliceTo(arg, 0),
        []const u8 => arg,
        else => @compileError("Unsupported argument type for printArgs"),
    };
}

/// Grab the user's home directory
pub fn getHomeDir(allocator: mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("HOME")) |home_path| {
        return allocator.dupe(u8, home_path);
    } else if (env_map.get("USERPROFILE")) |profile_path| {
        return allocator.dupe(u8, profile_path);
    } else {
        return error.HomeDirNotFound;
    }
}

/// Grab the BUNV_INSTALL environment variable or use ".bunv", and resolve relative to the home directory
pub fn getConfigDir(allocator: mem.Allocator, is_debug: bool) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const bunv_install = env_map.get("BUNV_INSTALL") orelse ".bunv";

    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    if (is_debug) std.debug.print("Home Dir: {s}\n", .{home_dir});

    const config_dir = try fs.path.join(allocator, &[_][]const u8{ home_dir, bunv_install });

    if (is_debug) std.debug.print("Config Dir: {s}\n", .{config_dir});

    return config_dir;
}

/// Check to see if the DEBUG environment variable is set to "bunv"
pub fn isDebug(allocator: mem.Allocator) !bool {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("DEBUG")) |value| {
        return mem.eql(u8, value, "bunv");
    }

    return false;
}

pub fn file_exists(file: []u8) !bool {
    std.fs.accessAbsolute(file, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

fn runBunCmd(
    allocator: mem.Allocator,
    args: [][]const u8,
    env_map: *const std.process.EnvMap,
) (std.process.ExecvError || std.process.Child.SpawnError) {
    if (builtin.os.tag != .windows) {
        return std.process.execve(allocator, args, env_map);
    } else {
        var proc = std.process.Child.init(args, allocator);
        proc.stdin_behavior = .Inherit;
        proc.stdout_behavior = .Inherit;
        proc.stderr_behavior = .Inherit;
        proc.env_map = env_map;
        try proc.spawn();
        switch (try proc.wait()) {
            .Exited => |code| std.process.exit(code),
            else => std.process.exit(1),
        }
    }
}
