const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");

const vm = @import("vm.zig");
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

    const project_version = try vm.getProjectVersion(allocator, is_debug) orelse
        try vm.getLatestLocalVersion(allocator, is_debug) orelse
        try vm.getLatestRemoteVersion(allocator, is_debug);
    defer allocator.free(project_version);

    try vm.ensureVersionInstalled(allocator, project_version);

    const bin_path = try fs_utils.getBunBinPath(allocator, project_version);
    defer allocator.free(bin_path);

    var new_args = try std.array_list.Managed([]const u8).initCapacity(allocator, 5);
    defer new_args.deinit();

    try new_args.append(bin_path);
    if (cmd == .bunx) try new_args.append("x");

    for (args[1..]) |arg| {
        try new_args.append(arg);
    }

    if (is_debug) {
        debug.printArgs("Original args", args);
        debug.printArgs("Modified args", new_args.items);
        std.debug.print("---\n", .{});
    }

    const version_dir = try fs_utils.getBunVersionDir(allocator, project_version);
    defer allocator.free(version_dir);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    try env_map.put("BUN_INSTALL", version_dir);

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
