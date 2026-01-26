const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");

const vm = @import("../vm.zig");
const debug = @import("debug.zig");
const env_utils = @import("env.zig");
const fs_utils = @import("fs.zig");

pub const Cmd = enum {
    bun,
    bunx,
};

pub fn run(allocator: mem.Allocator, cmd: Cmd) !void {
    const is_debug = try env_utils.isDebug(allocator);
    if (is_debug) std.debug.print("Executable: {}\n", .{cmd});

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (cmd == .bun and args.len > 1 and mem.eql(u8, args[1], "upgrade")) {
        std.debug.print("bun upgrade is a no-op under bunv. Update your version file instead.\n", .{});
        std.debug.print("See: https://github.com/Aternus/bunv#upgrading-bun\n", .{});
        std.process.exit(0);
    }

    const bunv_install_dir = try fs_utils.getBunvInstallDir(allocator, is_debug);
    defer allocator.free(bunv_install_dir);

    if (is_debug) std.debug.print("Bunv Install Dir: {s}\n", .{bunv_install_dir});

    const project_version = try vm.detectProjectVersion(allocator, is_debug) orelse
        try vm.getLatestLocalVersion(allocator, is_debug, bunv_install_dir) orelse
        try vm.getLatestRemoteVersion(allocator, is_debug);
    defer allocator.free(project_version);

    try vm.ensureVersionDownloaded(allocator, bunv_install_dir, project_version);

    const bunv_version_dir = try fs_utils.getBunVersionDir(allocator, bunv_install_dir, project_version);
    defer allocator.free(bunv_version_dir);

    const bun_bin = try fs_utils.getBunBinPath(allocator, bunv_install_dir, project_version);
    defer allocator.free(bun_bin);

    var new_args = try std.array_list.Managed([]const u8).initCapacity(allocator, 5);
    defer new_args.deinit();

    try new_args.append(bun_bin);
    if (cmd == .bunx) try new_args.append("x");

    for (args[1..]) |arg| {
        try new_args.append(arg);
    }

    if (is_debug) {
        debug.printArgs("Original args", args);
        debug.printArgs("Modified args", new_args.items);
        std.debug.print("---\n", .{});
    }

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    try env_map.put("BUN_INSTALL", bunv_version_dir);

    return runBunCmd(allocator, new_args.items, &env_map);
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
