const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const mem = std.mem;
const utils = @import("utils.zig");
const vm = @import("vm.zig");
const c = @import("colors.zig");

pub const Options = struct {
    yes: bool = false,
};

const Source = enum {
    bunv,
    official,
    brew,
    linux_pkg,
    windows_pkg,
    unknown,
};

const Action = union(enum) {
    none,
    delete_tree: []const u8,
    command: [][]const u8,
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
    items: std.array_list.Managed(Item),
    known_bins: std.array_list.Managed([]const u8),

    fn init(allocator: mem.Allocator) Report {
        return .{
            .items = std.array_list.Managed(Item).init(allocator),
            .known_bins = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Report, allocator: mem.Allocator) void {
        for (self.items.items) |*item| {
            for (item.paths.items) |path| allocator.free(path);
            item.paths.deinit();
            allocator.free(item.label);
            if (item.warning) |warning| allocator.free(warning);
            switch (item.action) {
                .delete_tree => |path| allocator.free(path),
                .command => |argv| {
                    for (argv) |arg| allocator.free(arg);
                    allocator.free(argv);
                },
                else => {},
            }
        }
        self.items.deinit();

        for (self.known_bins.items) |path| allocator.free(path);
        self.known_bins.deinit();
    }

    fn addKnownBin(self: *Report, allocator: mem.Allocator, path: []const u8) !void {
        if (self.isKnownBin(path)) return;
        try self.known_bins.append(try allocator.dupe(u8, path));
    }

    fn isKnownBin(self: *Report, path: []const u8) bool {
        for (self.known_bins.items) |known| {
            if (mem.eql(u8, known, path)) return true;
        }
        return false;
    }
};

pub fn run(allocator: mem.Allocator, config_dir: []const u8, args: []const [:0]u8) !void {
    const options = try parseArgs(allocator, args);

    var report = try scanAll(allocator, config_dir, options);
    defer report.deinit(allocator);

    printReport(report);

    const actionable = countActionable(report.items.items);
    if (actionable == 0) {
        std.debug.print("{s}No removable Bun installations found{s}\n", .{ c.yellow, c.reset });
        return;
    }

    if (!options.yes) {
        try confirmRemoval();
    }

    try executeActions(allocator, report.items.items);
}

fn parseArgs(allocator: mem.Allocator, args: []const [:0]u8) !Options {
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
    std.debug.print("\n{s}{s}bunv prune{s} - Remove Bun installations from this machine{s}\n\n", .{ c.bold, c.yellow, c.reset, c.reset });
    std.debug.print("Usage:\n", .{});
    std.debug.print("  bunv prune [--yes|-y]\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --yes, -y    Skip confirmation prompt\n\n", .{});
}

fn scanAll(allocator: mem.Allocator, config_dir: []const u8, options: Options) !Report {
    var report = Report.init(allocator);
    errdefer report.deinit(allocator);

    try findBunvInstalls(allocator, config_dir, &report);
    try addBunvShimBin(allocator, config_dir, &report);
    try findOfficialInstall(allocator, config_dir, &report);

    switch (builtin.os.tag) {
        .macos => try findBrewInstall(allocator, &report, options),
        .linux => try findLinuxPackageManagers(allocator, &report, options),
        .windows => try findWindowsPackageManagers(allocator, &report, options),
        else => {},
    }

    try findUnknownPathBuns(allocator, &report);

    return report;
}

fn findBunvInstalls(allocator: mem.Allocator, config_dir: []const u8, report: *Report) !void {
    const installed_versions = try vm.getInstalledVersions(allocator, config_dir);
    defer {
        for (installed_versions.items) |item| allocator.free(item);
        installed_versions.deinit();
    }

    for (installed_versions.items) |version| {
        const version_dir = try vm.getVersionDir(allocator, config_dir, version);
        errdefer allocator.free(version_dir);
        const bin = try vm.getBinPath(allocator, config_dir, version);
        errdefer allocator.free(bin);

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
        try report.items.append(item);
        try report.addKnownBin(allocator, bin);
        allocator.free(bin);
    }
}

fn addBunvShimBin(allocator: mem.Allocator, config_dir: []const u8, report: *Report) !void {
    const bun_name = if (builtin.os.tag == .windows) "bun.exe" else "bun";
    const shim_bin = try fs.path.join(allocator, &[_][]const u8{ config_dir, "bin", bun_name });
    defer allocator.free(shim_bin);

    if (pathExists(shim_bin)) {
        try report.addKnownBin(allocator, shim_bin);
    }
}

fn findOfficialInstall(allocator: mem.Allocator, config_dir: []const u8, report: *Report) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const home_dir = try utils.getHomeDir(allocator);
    defer allocator.free(home_dir);

    const candidates = try officialInstallCandidates(allocator, env_map, home_dir);
    defer {
        for (candidates.items) |path| allocator.free(path);
        candidates.deinit();
    }

    for (candidates.items) |install_dir| {
        if (mem.startsWith(u8, install_dir, config_dir)) continue;

        const bin = try bunBinaryPath(allocator, install_dir);
        defer allocator.free(bin);
        if (!pathExists(bin)) continue;

        var paths = std.array_list.Managed([]const u8).init(allocator);
        try paths.append(try allocator.dupe(u8, install_dir));
        try paths.append(try allocator.dupe(u8, bin));

        const warning = try allocator.dupe(u8, "Shell profile edits (BUN_INSTALL/PATH) may need manual cleanup");

        const item = Item{
            .source = .official,
            .label = try allocator.dupe(u8, "Official installer"),
            .paths = paths,
            .action = .{ .delete_tree = try allocator.dupe(u8, install_dir) },
            .warning = warning,
            .safe_to_remove = true,
        };
        try report.items.append(item);
        try report.addKnownBin(allocator, bin);
    }
}

fn findBrewInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "brew")) return;

    const brew_check = try runCommandCapture(allocator, &[_][]const u8{ "brew", "list", "--versions", "bun" });
    defer allocator.free(brew_check.stdout);
    defer allocator.free(brew_check.stderr);
    if (brew_check.exit_code != 0 or brew_check.stdout.len == 0) return;

    const label = try allocator.dupe(u8, "Homebrew bun");
    var paths = std.array_list.Managed([]const u8).init(allocator);

    const prefix_result = try runCommandCapture(allocator, &[_][]const u8{ "brew", "--prefix", "bun" });
    defer allocator.free(prefix_result.stdout);
    defer allocator.free(prefix_result.stderr);
    if (prefix_result.exit_code == 0) {
        const trimmed = mem.trim(u8, prefix_result.stdout, &std.ascii.whitespace);
        if (trimmed.len > 0) {
            const prefix_bin = try fs.path.join(allocator, &[_][]const u8{ trimmed, "bin", "bun" });
            defer allocator.free(prefix_bin);
            if (pathExists(prefix_bin)) {
                try paths.append(try allocator.dupe(u8, prefix_bin));
                try report.addKnownBin(allocator, prefix_bin);
            }
        }
    }

    const argv = try brewUninstallArgv(allocator, options);

    const item = Item{
        .source = .brew,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = null,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findLinuxPackageManagers(allocator: mem.Allocator, report: *Report, options: Options) !void {
    try findDpkgInstall(allocator, report, options);
    try findPacmanInstall(allocator, report, options);
    try findRpmInstall(allocator, report, options);
    try findSnapInstall(allocator, report, options);
}

fn findDpkgInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "dpkg")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "dpkg", "-s", "bun" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    const label = try allocator.dupe(u8, "dpkg/apt bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);

    const argv = try dpkgUninstallArgv(allocator, options);

    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .linux_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findPacmanInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "pacman")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "pacman", "-Qi", "bun" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    const label = try allocator.dupe(u8, "pacman bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);
    const argv = try pacmanUninstallArgv(allocator, options);
    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .linux_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findRpmInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "rpm")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "rpm", "-q", "bun" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    const label = try allocator.dupe(u8, "rpm bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);

    const argv = try rpmUninstallArgv(allocator, options);

    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .linux_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findSnapInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "snap")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "snap", "list", "bun" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    const label = try allocator.dupe(u8, "snap bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);
    const argv = try snapUninstallArgv(allocator, options);
    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .linux_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findWindowsPackageManagers(allocator: mem.Allocator, report: *Report, options: Options) !void {
    try findScoopInstall(allocator, report, options);
    try findChocoInstall(allocator, report, options);
}

fn findScoopInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "scoop")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "scoop", "list" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    if (!lineContainsPackage(result.stdout, "bun")) return;

    const label = try allocator.dupe(u8, "scoop bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);
    const argv = try scoopUninstallArgv(allocator, options);

    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .windows_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findChocoInstall(allocator: mem.Allocator, report: *Report, options: Options) !void {
    if (!try commandExists(allocator, "choco")) return;

    const result = try runCommandCapture(allocator, &[_][]const u8{ "choco", "list", "--local-only", "--exact", "bun" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.exit_code != 0) return;

    if (!lineContainsPackage(result.stdout, "bun")) return;

    const label = try allocator.dupe(u8, "choco bun");
    const paths = std.array_list.Managed([]const u8).init(allocator);
    const argv = try chocoUninstallArgv(allocator, options);
    const warning = try allocator.dupe(u8, "Package removal may require elevated privileges");

    const item = Item{
        .source = .windows_pkg,
        .label = label,
        .paths = paths,
        .action = .{ .command = argv },
        .warning = warning,
        .safe_to_remove = true,
    };
    try report.items.append(item);
}

fn findUnknownPathBuns(allocator: mem.Allocator, report: *Report) !void {
    var paths = std.array_list.Managed([]const u8).init(allocator);

    const bun_name = if (builtin.os.tag == .windows) "bun.exe" else "bun";
    const found = try findExecutablesInPath(allocator, bun_name);
    defer {
        for (found.items) |path| allocator.free(path);
        found.deinit();
    }

    for (found.items) |path| {
        if (report.isKnownBin(path)) continue;
        try paths.append(try allocator.dupe(u8, path));
    }

    if (paths.items.len == 0) {
        paths.deinit();
        return;
    }

    const warning = try allocator.dupe(u8, "Unknown install source; not removing automatically");
    const item = Item{
        .source = .unknown,
        .label = try allocator.dupe(u8, "Unknown PATH installs"),
        .paths = paths,
        .action = .none,
        .warning = warning,
        .safe_to_remove = false,
    };
    try report.items.append(item);
}

fn printReport(report: Report) void {
    std.debug.print("{s}Bun installations found:{s}\n", .{ c.bold, c.reset });

    printSection(report.items.items, .bunv, "Bunv managed versions", c.yellow);
    printSection(report.items.items, .official, "Official installer", c.bold);
    printSection(report.items.items, .brew, "Homebrew", c.bold);
    printSection(report.items.items, .linux_pkg, "Linux package managers", c.bold);
    printSection(report.items.items, .windows_pkg, "Windows package managers", c.bold);
    printSection(report.items.items, .unknown, "Unknown / unmanaged", c.bold);
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
        std.debug.print("  {s}- {s}{s}\n", .{ c.blue, item.label, c.reset });
        for (item.paths.items) |path| {
            std.debug.print("    {s}•{s} {s}\n", .{ c.grey, c.reset, path });
        }
        _ = item.action;
        if (item.warning) |warning| {
            std.debug.print("    {s}Warning:{s} {s}\n", .{ c.yellow, c.reset, warning });
        }
    }
}

fn countActionable(items: []Item) usize {
    var count: usize = 0;
    for (items) |item| {
        if (!item.safe_to_remove) continue;
        switch (item.action) {
            .none => {},
            else => count += 1,
        }
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

fn executeActions(allocator: mem.Allocator, items: []Item) !void {
    var failed = false;

    for (items) |item| {
        if (!item.safe_to_remove) continue;
        switch (item.action) {
            .delete_tree => |path| {
                var item_failed = false;
                std.debug.print("Removing {s}...\n", .{item.label});
                std.fs.deleteTreeAbsolute(path) catch |err| {
                    std.debug.print("{s}Error: failed to remove {s}: {s}{s}\n", .{ c.red, item.label, @errorName(err), c.reset });
                    failed = true;
                    item_failed = true;
                };
                if (!item_failed) std.debug.print("{s}✓{s} Removed {s}\n", .{ c.green, c.reset, item.label });
            },
            .command => |argv| {
                std.debug.print("Running: ", .{});
                for (argv) |arg| std.debug.print("{s} ", .{arg});
                std.debug.print("\n", .{});

                const result = try runCommandCapture(allocator, argv);
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.exit_code != 0) {
                    std.debug.print("{s}Error: command failed for {s}{s}\n", .{ c.red, item.label, c.reset });
                    if (result.stderr.len > 0) {
                        std.debug.print("STDERR:\n{s}\n", .{result.stderr});
                    }
                    if (result.stdout.len > 0) {
                        std.debug.print("STDOUT:\n{s}\n", .{result.stdout});
                    }
                    failed = true;
                } else {
                    std.debug.print("{s}✓{s} Removed {s}\n", .{ c.green, c.reset, item.label });
                }
            },
            .none => {},
        }
    }

    if (failed) std.process.exit(1);
}

fn bunBinaryPath(allocator: mem.Allocator, install_dir: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        return fs.path.join(allocator, &[_][]const u8{ install_dir, "bin", "bun.exe" });
    }
    return fs.path.join(allocator, &[_][]const u8{ install_dir, "bin", "bun" });
}

fn pathExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    return true;
}

fn commandExists(allocator: mem.Allocator, name: []const u8) !bool {
    const maybe_path = try findExecutableInPath(allocator, name);
    if (maybe_path) |path| {
        allocator.free(path);
        return true;
    }
    return false;
}

fn findExecutableInPath(allocator: mem.Allocator, name: []const u8) !?[]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const path_var = env_map.get("PATH") orelse return null;
    const delimiter: u8 = if (builtin.os.tag == .windows) ';' else ':';

    var it = mem.splitScalar(u8, path_var, delimiter);
    while (it.next()) |dir| {
        if (dir.len == 0) continue;

        if (builtin.os.tag == .windows) {
            const exts = [_][]const u8{ "", ".exe", ".cmd", ".bat" };
            for (exts) |ext| {
                const candidate = try std.fmt.allocPrint(allocator, "{s}{s}", .{ name, ext });
                defer allocator.free(candidate);
                const full = try fs.path.join(allocator, &[_][]const u8{ dir, candidate });
                if (pathExists(full)) return full;
                allocator.free(full);
            }
        } else {
            const full = try fs.path.join(allocator, &[_][]const u8{ dir, name });
            if (pathExists(full)) return full;
            allocator.free(full);
        }
    }
    return null;
}

fn findExecutablesInPath(allocator: mem.Allocator, name: []const u8) !std.array_list.Managed([]const u8) {
    var result = std.array_list.Managed([]const u8).init(allocator);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const path_var = env_map.get("PATH") orelse return result;
    const delimiter: u8 = if (builtin.os.tag == .windows) ';' else ':';

    var it = mem.splitScalar(u8, path_var, delimiter);
    while (it.next()) |dir| {
        if (dir.len == 0) continue;

        const full = try fs.path.join(allocator, &[_][]const u8{ dir, name });
        defer allocator.free(full);
        if (pathExists(full)) {
            try result.append(try allocator.dupe(u8, full));
        }
    }
    return result;
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

fn runCommandCapture(allocator: mem.Allocator, argv: []const []const u8) !CommandResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = switch (result.term) {
            .Exited => |code| code,
            else => 1,
        },
    };
}

fn allocateArgv(allocator: mem.Allocator, argv: []const []const u8) ![][]const u8 {
    var out = try allocator.alloc([]const u8, argv.len);
    for (argv, 0..) |arg, i| {
        out[i] = try allocator.dupe(u8, arg);
    }
    return out;
}

fn lineContainsPackage(output: []const u8, package: []const u8) bool {
    var it = mem.splitScalar(u8, output, '\n');
    while (it.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (mem.eql(u8, trimmed, package)) return true;
        if (mem.startsWith(u8, trimmed, package)) {
            if (trimmed.len == package.len) return true;
            const next = trimmed[package.len];
            if (next == ' ' or next == '\t') return true;
        }
    }
    return false;
}

fn brewUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    _ = options;
    return allocateArgv(allocator, &[_][]const u8{ "brew", "uninstall", "bun" });
}

fn dpkgUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    if (try commandExists(allocator, "apt-get")) {
        if (options.yes) {
            return allocateArgv(allocator, &[_][]const u8{ "apt-get", "remove", "-y", "bun" });
        }
        return allocateArgv(allocator, &[_][]const u8{ "apt-get", "remove", "bun" });
    }

    return allocateArgv(allocator, &[_][]const u8{ "dpkg", "-r", "bun" });
}

fn pacmanUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    if (options.yes) {
        return allocateArgv(allocator, &[_][]const u8{ "pacman", "-Rns", "--noconfirm", "bun" });
    }
    return allocateArgv(allocator, &[_][]const u8{ "pacman", "-Rns", "bun" });
}

fn rpmUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    if (try commandExists(allocator, "dnf")) {
        if (options.yes) {
            return allocateArgv(allocator, &[_][]const u8{ "dnf", "remove", "-y", "bun" });
        }
        return allocateArgv(allocator, &[_][]const u8{ "dnf", "remove", "bun" });
    }
    if (try commandExists(allocator, "yum")) {
        if (options.yes) {
            return allocateArgv(allocator, &[_][]const u8{ "yum", "remove", "-y", "bun" });
        }
        return allocateArgv(allocator, &[_][]const u8{ "yum", "remove", "bun" });
    }
    return allocateArgv(allocator, &[_][]const u8{ "rpm", "-e", "bun" });
}

fn snapUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    _ = options;
    return allocateArgv(allocator, &[_][]const u8{ "snap", "remove", "bun" });
}

fn scoopUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    if (options.yes) {
        return allocateArgv(allocator, &[_][]const u8{ "scoop", "uninstall", "-y", "bun" });
    }
    return allocateArgv(allocator, &[_][]const u8{ "scoop", "uninstall", "bun" });
}

fn chocoUninstallArgv(allocator: mem.Allocator, options: Options) ![][]const u8 {
    if (options.yes) {
        return allocateArgv(allocator, &[_][]const u8{ "choco", "uninstall", "bun", "-y" });
    }
    return allocateArgv(allocator, &[_][]const u8{ "choco", "uninstall", "bun" });
}

fn officialInstallCandidates(
    allocator: mem.Allocator,
    env_map: std.process.EnvMap,
    home_dir: []const u8,
) !std.array_list.Managed([]const u8) {
    var candidates = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (candidates.items) |path| allocator.free(path);
        candidates.deinit();
    }

    if (env_map.get("BUN_INSTALL")) |bun_install| {
        try candidates.append(try allocator.dupe(u8, bun_install));
    }

    const default_install = try fs.path.join(allocator, &[_][]const u8{ home_dir, ".bun" });
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
