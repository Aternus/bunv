const std = @import("std");
const json = std.json;
const builtin = @import("builtin");
const zlinter = @import("zlinter");

const bun = "bun";
const bunx = "bunx";
const bunv = "bunv";

pub fn build(b: *std.Build) anyerror!void {
    const required_zig_version = try std.SemanticVersion.parse("0.15.2");
    if (std.SemanticVersion.order(builtin.zig_version, required_zig_version) != .eq) {
        std.debug.print("Zig 0.15.2 toolchain is required to build Bunv, got {f}", .{builtin.zig_version});
        return error.InvalidZigVersion;
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version_json = @embedFile("package.json");
    var parsed = try json.parseFromSlice(std.json.Value, b.allocator, version_json, .{});
    defer parsed.deinit();
    const version_str = parsed.value.object.get("version").?.string;
    const version = try std.SemanticVersion.parse(version_str);

    try addLinter(b);
    try addUnitTests(b, target, optimize);

    addExe(b, target, optimize, version, bun);
    addExe(b, target, optimize, version, bunx);
    addExe(b, target, optimize, version, bunv);
}

fn addLinter(b: *std.Build) anyerror!void {
    const lint_step = b.step("lint", "Lint source code");

    var zbuilder = zlinter.builder(b, .{});
    inline for (std.meta.fields(zlinter.BuiltinLintRule)) |f| {
        // excludes
        const is_require_doc_comment = comptime std.mem.eql(u8, f.name, "require_doc_comment");
        if (is_require_doc_comment) continue;

        const rule = @field(zlinter.BuiltinLintRule, f.name);
        zbuilder.addRule(.{ .builtin = rule }, .{});
    }

    lint_step.dependOn(zbuilder.build());
}

fn addUnitTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) anyerror!void {
    const test_step = b.step("test", "Run unit tests");

    var test_dir = try b.build_root.handle.openDir("tests", .{ .iterate = true });
    defer test_dir.close();

    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    var test_files = std.ArrayList([]const u8).empty;
    defer {
        for (test_files.items) |path| b.allocator.free(path);
        test_files.deinit(b.allocator);
    }

    var it = test_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".test.zig")) continue;

        const path = try std.fmt.allocPrint(b.allocator, "tests/{s}", .{entry.name});
        try test_files.append(b.allocator, path);
    }

    const ctx = struct {};
    const lessThan = struct {
        fn less(_: ctx, a: []const u8, b2: []const u8) bool {
            return std.mem.lessThan(u8, a, b2);
        }
    }.less;
    std.sort.heap([]const u8, test_files.items, ctx{}, lessThan);

    for (test_files.items) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        unit_tests.root_module.addImport("tests", tests_module);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}

fn addExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, version: std.SemanticVersion, comptime name: []const u8) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = version,
    });

    const options = b.addOptions();
    options.addOption(std.SemanticVersion, "version", version);
    exe.root_module.addOptions("config", options);

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    const run_exe = b.addRunArtifact(exe);
    const run_exe_step = b.step(name, "Run the " ++ name ++ " executable");
    run_exe_step.dependOn(&run_exe.step);
    run_exe_step.dependOn(&install_exe.step);
}
