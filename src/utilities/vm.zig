const std = @import("std");
const mem = std.mem;
const json = std.json;
const http = std.http;
const fs_utils = @import("fs.zig");
const c = @import("colors.zig");
const cmp = @import("cmp.zig");
const bun_releases = @import("bun_releases.zig");
const prompt = @import("../cli/prompt.zig");

const VersionFile = struct {
    name: []const u8,
    extractBunVersion: *const fn (allocator: mem.Allocator, contents: []u8) ?[]const u8,
};

const PackageJsonVersionFile = struct {
    fn init() VersionFile {
        return .{
            .name = "package.json",
            .extractBunVersion = &extractBunVersion,
        };
    }
    fn extractBunVersion(allocator: mem.Allocator, contents: []u8) ?[]const u8 {
        const parsed = json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch |err| switch (err) {
            else => return null,
        };
        defer parsed.deinit();

        // "bun@X.Y.Z"
        if (parsed.value.object.get("packageManager")) |package_manager| {
            const str = package_manager.string;
            if (mem.eql(u8, str[0..4], "bun@")) {
                return allocator.dupe(u8, str[4..]) catch return null;
            }
        }
        return null;
    }
};

const BunVersionFile = struct {
    fn init() VersionFile {
        return .{
            .name = ".bun-version",
            .extractBunVersion = &extractBunVersion,
        };
    }
    fn extractBunVersion(allocator: mem.Allocator, contents: []u8) ?[]u8 {
        return allocator.dupe(u8, mem.trim(u8, contents, &std.ascii.whitespace)) catch |err| switch (err) {
            else => return null,
        };
    }
};

const ToolVersionsFile = struct {
    fn init() VersionFile {
        return .{
            .name = ".tool-versions",
            .extractBunVersion = &extractBunVersion,
        };
    }
    fn extractBunVersion(allocator: mem.Allocator, contents: []u8) ?[]u8 {
        var lines_it = mem.splitScalar(u8, contents, '\n');
        while (lines_it.next()) |line| {
            // Skip empty lines and comments
            if (line.len == 0 or line[0] == '#') {
                continue;
            }

            // Check if line starts with "bun "
            if (mem.startsWith(u8, line, "bun ")) {
                // Extract version part after "bun "
                const version_part = mem.trim(u8, line[4..], &std.ascii.whitespace);
                if (version_part.len > 0) {
                    return allocator.dupe(u8, version_part) catch return null;
                }
            }
        }
        return null;
    }
};

pub fn getInstalledVersions(allocator: mem.Allocator) !std.array_list.Managed([]const u8) {
    const versions_dir_path = try fs_utils.getBunvVersionsDir(allocator);
    defer allocator.free(versions_dir_path);

    var result = std.array_list.Managed([]const u8).init(allocator);

    var versions_dir = fs_utils.openDirAbsolute(versions_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    defer versions_dir.close();

    var versions_iter = versions_dir.iterateAssumeFirstIteration();
    while (try versions_iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        _ = std.SemanticVersion.parse(entry.name) catch continue;

        const version = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(version);

        const version_dir = try fs_utils.getBunVersionDir(allocator, version);
        defer allocator.free(version_dir);

        const bin = try fs_utils.getBunBinPath(allocator, version);
        defer allocator.free(bin);

        if (try fs_utils.fileExists(bin)) {
            try result.append(version);
        } else {
            allocator.free(version);
        }
    }

    std.sort.heap([]const u8, result.items, {}, cmp.semVerDESC);
    return result;
}

pub fn getProjectVersion(allocator: mem.Allocator, is_debug: bool) !?[]const u8 {
    if (is_debug) std.debug.print("Figuring out the Bun version required for the project...\n", .{});

    const files = comptime [_]VersionFile{
        PackageJsonVersionFile.init(),
        BunVersionFile.init(),
        ToolVersionsFile.init(),
    };

    var current_dir = try fs_utils.realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    while (true) {
        if (is_debug) std.debug.print("  Checking dir: {s}\n", .{current_dir});
        for (files) |version_file| {
            const file_path = try fs_utils.joinPath(allocator, &[_][]const u8{ current_dir, version_file.name });
            defer allocator.free(file_path);

            const file = fs_utils.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            defer file.close();

            const file_size = try file.getEndPos();
            const buffer = try allocator.alloc(u8, file_size);
            defer allocator.free(buffer);

            _ = try file.readAll(buffer);
            if (version_file.extractBunVersion(allocator, buffer)) |version| {
                if (is_debug) std.debug.print("  Found v{s} in: {s}\n", .{ version, file_path });
                return try allocator.dupe(u8, version);
            }
        }

        const parent_dir = fs_utils.dirname(current_dir) orelse break;
        if (mem.eql(u8, parent_dir, current_dir)) break;

        const new_dir = try allocator.dupe(u8, parent_dir);
        allocator.free(current_dir);
        current_dir = new_dir;
    }

    return null;
}

pub fn getLatestLocalVersion(allocator: mem.Allocator, is_debug: bool) !?[]const u8 {
    if (is_debug) std.debug.print("Figuring out the latest Bun version installed locally...\n", .{});

    const installed_versions = try getInstalledVersions(allocator);
    defer {
        for (installed_versions.items) |item| {
            allocator.free(item);
        }
        installed_versions.deinit();
    }

    if (is_debug) std.debug.print("{d} versions: {any}\n", .{ installed_versions.items.len, installed_versions.items });

    if (installed_versions.items.len == 0) {
        return null;
    }
    return try allocator.dupe(u8, installed_versions.items[0]);
}

pub fn getLatestRemoteVersion(allocator: mem.Allocator, is_debug: bool) ![]const u8 {
    if (is_debug) std.debug.print("Figuring out the latest Bun version on the remote server...\n", .{});

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const accept_header = http.Header{
        .name = "accept",
        .value = "application/json",
    };

    const uri = try std.Uri.parse("https://ungh.cc/repos/oven-sh/bun/releases/latest");
    var req = try client.request(.GET, uri, .{
        .keep_alive = false,
        .headers = .{ .accept_encoding = .omit },
        .extra_headers = &[_]http.Header{accept_header},
    });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    var transfer_buffer: [4 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    const body = try reader.allocRemaining(allocator, .limited(1024 * 1024 * 4));
    defer allocator.free(body);

    if (is_debug) std.debug.print("Latest release: {s}\n", .{body});

    const parsed = try json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const release = parsed.value.object.get("release").?.object;
    // "bun-v1.1.27"
    const gitTag = release.get("tag").?.string;

    // strip off "bun-v"
    const tag = gitTag[5..];
    return allocator.dupe(u8, tag);
}

pub fn ensureVersionInstalled(allocator: mem.Allocator, version: []const u8) !void {
    const version_dir = try fs_utils.getBunVersionDir(allocator, version);
    defer allocator.free(version_dir);

    const bin_path = try fs_utils.getBunBinPath(allocator, version);
    defer allocator.free(bin_path);

    if (try fs_utils.fileExists(bin_path)) {
        return;
    }

    try ensureInstallAllowed(version);

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();
    try bun_releases.installVersion(allocator, &client, version_dir, version);
}

fn ensureInstallAllowed(version: []const u8) !void {
    var env_map = try std.process.getEnvMap(std.heap.page_allocator);
    defer env_map.deinit();

    if (env_map.get("BUNV_AUTO_INSTALL")) |value| {
        if (mem.eql(u8, value, "1")) {
            std.debug.print("{s}Bun v{s} is not installed. Auto-installing...{s}\n", .{ c.yellow, version, c.reset });
            return;
        }
    }

    const stdin_file = std.fs.File.stdin();
    const is_interactive = stdin_file.isTty();

    if (is_interactive) {
        var prompt_buf: [512]u8 = undefined;
        const prompt_msg = try std.fmt.bufPrint(
            &prompt_buf,
            "{s}Bun v{s} is not installed. Do you want to install it? [y/N]{s} ",
            .{ c.yellow, version, c.reset },
        );

        if (try prompt.promptConfirm(prompt_msg)) return;
    } else {
        std.debug.print("{s}Bun v{s} is not installed. Run in an interactive terminal to install or set BUNV_AUTO_INSTALL=1.{s}\n", .{ c.yellow, version, c.reset });
    }

    std.debug.print("Installation aborted by user\n", .{});
    std.process.exit(1);
}
