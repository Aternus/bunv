const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");
const fs_utils = @import("fs.zig");
const process_utils = @import("process.zig");

pub const TargetSelection = struct {
    target: []u8,
    used_rosetta: bool,
};

pub const TargetOptions = struct {
    os_tag: std.Target.Os.Tag,
    cpu_arch: std.Target.Cpu.Arch,
    is_musl: bool,
    is_rosetta: bool,
    has_avx2: bool,
};

pub fn buildTargetFromOptions(allocator: mem.Allocator, opts: TargetOptions) !TargetSelection {
    const os_part = switch (opts.os_tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "windows",
        else => return error.UnsupportedPlatform,
    };
    var arch_part = switch (opts.cpu_arch) {
        .aarch64 => "aarch64",
        .x86_64 => "x64",
        else => return error.UnsupportedPlatform,
    };

    var used_rosetta = false;
    if (opts.os_tag == .macos and opts.cpu_arch == .x86_64 and opts.is_rosetta) {
        arch_part = "aarch64";
        used_rosetta = true;
    }

    var target = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ os_part, arch_part });
    errdefer allocator.free(target);

    if (opts.os_tag == .linux and opts.is_musl) {
        const next = try std.fmt.allocPrint(allocator, "{s}-musl", .{target});
        allocator.free(target);
        target = next;
    }

    if ((opts.os_tag == .linux or opts.os_tag == .macos) and opts.cpu_arch == .x86_64 and !opts.has_avx2 and !used_rosetta) {
        const next = try std.fmt.allocPrint(allocator, "{s}-baseline", .{target});
        allocator.free(target);
        target = next;
    }

    return .{
        .target = target,
        .used_rosetta = used_rosetta,
    };
}

pub fn resolveBunTarget(allocator: mem.Allocator) !TargetSelection {
    const is_musl = builtin.os.tag == .linux and isAlpineLinux();
    const is_rosetta = builtin.os.tag == .macos and builtin.cpu.arch == .x86_64 and isRosettaTranslated(allocator);

    var has_avx2 = true;
    if ((builtin.os.tag == .linux or builtin.os.tag == .macos) and builtin.cpu.arch == .x86_64 and !is_rosetta) {
        has_avx2 = detectAvx2(allocator);
    }

    return buildTargetFromOptions(allocator, .{
        .os_tag = builtin.os.tag,
        .cpu_arch = builtin.cpu.arch,
        .is_musl = is_musl,
        .is_rosetta = is_rosetta,
        .has_avx2 = has_avx2,
    });
}

fn isAlpineLinux() bool {
    if (builtin.os.tag != .linux) return false;
    return fs_utils.fileExists("/etc/alpine-release") catch false;
}

fn isRosettaTranslated(allocator: mem.Allocator) bool {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .x86_64) return false;
    return process_utils.commandOutputEquals(allocator, &[_][]const u8{ "sysctl", "-n", "sysctl.proc_translated" }, "1");
}

fn detectAvx2(allocator: mem.Allocator) bool {
    return switch (builtin.os.tag) {
        .linux => hasAvx2Linux(allocator),
        .macos => hasAvx2Mac(allocator),
        else => true,
    };
}

fn hasAvx2Linux(allocator: mem.Allocator) bool {
    var file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch return false;
    defer file.close();

    const stat = file.stat() catch return false;
    const raw_size: usize = @intCast(stat.size);
    const size = @min(raw_size, 1024 * 1024);
    if (size == 0) return false;

    const buf = allocator.alloc(u8, size) catch return false;
    defer allocator.free(buf);

    const n = file.readAll(buf) catch return false;
    return process_utils.outputHasAvx2(buf[0..n]);
}

fn hasAvx2Mac(allocator: mem.Allocator) bool {
    if (process_utils.commandOutputHasAvx2(allocator, &[_][]const u8{ "sysctl", "-n", "machdep.cpu.leaf7_features" })) return true;
    if (process_utils.commandOutputHasAvx2(allocator, &[_][]const u8{ "sysctl", "-n", "machdep.cpu.features" })) return true;
    if (process_utils.commandOutputHasAvx2(allocator, &[_][]const u8{ "sysctl", "-a" })) return true;
    return false;
}
