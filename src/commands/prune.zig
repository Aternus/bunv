const std = @import("std");
const mem = std.mem;
const env_utils = @import("../utilities/env.zig");
const fs_utils = @import("../utilities/fs.zig");
const vm = @import("../vm.zig");
const c = @import("../utilities/colors.zig");

pub const Options = struct {
    yes: bool = false,
};

const Source = enum {
    bunv,
    official,
};

const Action = union(enum) {
    delete_tree: []const u8,
};

const Item = struct {
    source: Source,
    label: []const u8,
    paths: std.array_list.Managed([]const u8),
    action: Action,
    warning: ?[]const u8,
    safe_to_remove: bool,
};

const Report = struct {
    items_list: std.array_list.Managed(Item),
    items: []Item,

    fn init(allocator: mem.Allocator) Report {
        return .{
            .items_list = std.array_list.Managed(Item).init(allocator),
            .items = &[_]Item{},
        };
    }

    fn deinit(self: *Report, allocator: mem.Allocator) void {
        for (self.items_list.items) |*item| {
            for (item.paths.items) |path| allocator.free(path);
            item.paths.deinit();
            allocator.free(item.label);
            if (item.warning) |warning| allocator.free(warning);
            switch (item.action) {
                .delete_tree => |path| allocator.free(path),
            }
        }
        self.items_list.deinit();
        self.items = &[_]Item{};
    }

    fn append(self: *Report, item: Item) !void {
        try self.items_list.append(item);
        self.items = self.items_list.items;
    }
};

pub fn run(allocator: mem.Allocator, bunv_install_dir: []const u8, args: []const []const u8) !void {
    const options = try parseArgs(allocator, args);

    var report = try scanAll(allocator, bunv_install_dir);
    defer report.deinit(allocator);

    try printReport(allocator, report);

    const actionable = countActionable(report.items);
    if (actionable == 0) {
        std.debug.print("{s}No removable Bun installations found{s}\n", .{ c.yellow, c.reset });
        return;
    }

    if (!options.yes) {
        try confirmRemoval();
    }

    try executeActions(report.items);
}

fn parseArgs(allocator: mem.Allocator, args: []const []const u8) !Options {
    _ = allocator;
    var options = Options{};
    for (args) |arg| {
        if (mem.eql(u8, arg, "--yes") or mem.eql(u8, arg, "-y")) {
            options.yes = true;
        } else if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else {
            std.debug.print("{s}Error: Unknown option '{s}'{s}\n", .{ c.red, arg, c.reset });
            std.debug.print("Usage: bunv prune [--yes|-y]\n", .{});
            std.process.exit(1);
        }
    }
    return options;
}

fn printHelp() void {
    std.debug.print("\n{s}{s}bunv prune{s} - Remove Bun installs managed by bunv or the official installer{s}\n\n", .{ c.bold, c.yellow, c.reset, c.reset });
    std.debug.print("Usage:\n", .{});
    std.debug.print("  bunv prune [--yes|-y]\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --yes, -y    Skip confirmation prompt\n\n", .{});
}

fn scanAll(allocator: mem.Allocator, bunv_install_dir: []const u8) !Report {
    var report = Report.init(allocator);
    errdefer report.deinit(allocator);

    try findBunvInstalls(allocator, bunv_install_dir, &report);
    try findOfficialInstall(allocator, bunv_install_dir, &report);

    return report;
}

fn printReport(allocator: mem.Allocator, report: Report) !void {
    _ = allocator;
    printSection(report.items, .bunv, "Bunv-managed installations", c.bold);
    printSection(report.items, .official, "Official installer installations", c.bold);
    std.debug.print("\n", .{});
}

fn printSection(items: []Item, source: Source, title: []const u8, color: []const u8) void {
    var count: usize = 0;
    for (items) |item| {
        if (item.source == source) count += 1;
    }
    if (count == 0) return;

    std.debug.print("{s}{s}:{s}\n", .{ color, title, c.reset });
    for (items) |item| {
        if (item.source != source) continue;
        std.debug.print("  {s}{s}{s}\n", .{ c.blue, item.label, c.reset });
        for (item.paths.items) |path| {
            std.debug.print("    {s}\n", .{path});
        }
        if (item.warning) |warning| {
            std.debug.print("    {s}Warning:{s} {s}\n", .{ c.yellow, c.reset, warning });
        }
    }
}

fn countActionable(items: []Item) usize {
    var count: usize = 0;
    for (items) |item| {
        if (!item.safe_to_remove) continue;
        count += 1;
    }
    return count;
}

fn confirmRemoval() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    const stdin_file = std.fs.File.stdin();
    if (!stdin_file.isTty()) {
        try stdout.interface.print("{s}Refusing to prune without confirmation in non-interactive mode. Use --yes to proceed.{s}\n", .{ c.yellow, c.reset });
        std.process.exit(1);
    }

    var stdin_buf: [1024]u8 = undefined;
    var stdin = stdin_file.reader(&stdin_buf);

    try stdout.interface.print("{s}Remove the items listed above? [y/N]{s} ", .{ c.yellow, c.reset });
    try stdout.interface.flush();

    const user_input = stdin.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => "N",
        error.EndOfStream => "N",
        else => return err,
    };

    if (mem.eql(u8, user_input, "y")) return;

    std.debug.print("Aborted by user\n", .{});
    std.process.exit(1);
}

fn executeActions(items: []Item) !void {
    var failed = false;

    for (items) |item| {
        if (!item.safe_to_remove) continue;
        switch (item.action) {
            .delete_tree => |path| {
                var item_failed = false;
                std.debug.print("Removing {s}...\n", .{item.label});
                fs_utils.deleteTreeAbsolute(path) catch |err| {
                    std.debug.print("{s}Error: failed to remove {s}: {s}{s}\n", .{ c.red, item.label, @errorName(err), c.reset });
                    failed = true;
                    item_failed = true;
                };
                if (!item_failed) std.debug.print("{s}✓{s} Removed {s}\n", .{ c.green, c.reset, item.label });
            },
        }
    }

    if (failed) std.process.exit(1);
}

fn findBunvInstalls(allocator: mem.Allocator, bunv_install_dir: []const u8, report: *Report) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, bunv_install_dir);
    defer {
        for (installed_versions.items) |item| allocator.free(item);
        installed_versions.deinit();
    }

    for (installed_versions.items) |version| {
        const version_dir = try fs_utils.getBunVersionDir(allocator, bunv_install_dir, version);
        errdefer allocator.free(version_dir);
        var paths = std.array_list.Managed([]const u8).init(allocator);
        try paths.append(try allocator.dupe(u8, version_dir));

        const label = try std.fmt.allocPrint(allocator, "v{s}", .{version});

        const item = Item{
            .source = .bunv,
            .label = label,
            .paths = paths,
            .action = .{ .delete_tree = version_dir },
            .warning = null,
            .safe_to_remove = true,
        };
        try report.append(item);
    }
}

fn findOfficialInstall(allocator: mem.Allocator, bunv_install_dir: []const u8, report: *Report) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const home_dir = try env_utils.getUserHomeDir(allocator);
    defer allocator.free(home_dir);

    const candidates = try officialInstallCandidates(allocator, env_map, home_dir);
    defer {
        for (candidates.items) |path| allocator.free(path);
        candidates.deinit();
    }

    for (candidates.items) |install_dir| {
        if (mem.startsWith(u8, install_dir, bunv_install_dir)) continue;

        const bin = try fs_utils.getBunBinaryPath(allocator, install_dir);
        defer allocator.free(bin);
        const install_dir_exists = fs_utils.dirExists(install_dir);
        const bin_exists = fs_utils.pathExists(bin);
        if (!install_dir_exists and !bin_exists) continue;

        var paths = std.array_list.Managed([]const u8).init(allocator);
        try paths.append(try allocator.dupe(u8, install_dir));
        if (bin_exists) {
            try paths.append(try allocator.dupe(u8, bin));
        }

        const warning = if (!bin_exists)
            try allocator.dupe(u8, "bun binary not found; removing install dir only")
        else
            try allocator.dupe(u8, "Shell profile edits (BUN_INSTALL/PATH) may need manual cleanup");

        const item = Item{
            .source = .official,
            .label = try allocator.dupe(u8, "Official installer"),
            .paths = paths,
            .action = .{ .delete_tree = try allocator.dupe(u8, install_dir) },
            .warning = warning,
            .safe_to_remove = true,
        };
        try report.append(item);
    }
}

fn officialInstallCandidates(
    allocator: mem.Allocator,
    env_map: std.process.EnvMap,
    user_home_dir: []const u8,
) !std.array_list.Managed([]const u8) {
    var candidates = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (candidates.items) |path| allocator.free(path);
        candidates.deinit();
    }

    if (env_map.get("BUN_INSTALL")) |bun_install| {
        try candidates.append(try allocator.dupe(u8, bun_install));
    }

    const default_install = try fs_utils.joinPath(allocator, &[_][]const u8{ user_home_dir, ".bun" });
    defer allocator.free(default_install);
    if (!containsPath(candidates.items, default_install)) {
        try candidates.append(try allocator.dupe(u8, default_install));
    }

    return candidates;
}

fn containsPath(paths: []const []const u8, path: []const u8) bool {
    for (paths) |existing| {
        if (mem.eql(u8, existing, path)) return true;
    }
    return false;
}
