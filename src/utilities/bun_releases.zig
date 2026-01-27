const std = @import("std");
const mem = std.mem;
const http = std.http;
const json = std.json;
const http_utils = @import("http.zig");

pub const Error = error{
    UnsupportedPlatform,
    InvalidSha256Hex,
};

pub fn assetName(os_tag: std.Target.Os.Tag, cpu_arch: std.Target.Cpu.Arch) Error![]const u8 {
    return switch (os_tag) {
        .macos => switch (cpu_arch) {
            .aarch64 => "bun-darwin-aarch64.zip",
            .x86_64 => "bun-darwin-x64.zip",
            else => Error.UnsupportedPlatform,
        },
        .linux => switch (cpu_arch) {
            .aarch64 => "bun-linux-aarch64.zip",
            .x86_64 => "bun-linux-x64.zip",
            else => Error.UnsupportedPlatform,
        },
        .windows => switch (cpu_arch) {
            .aarch64 => "bun-windows-aarch64.zip",
            .x86_64 => "bun-windows-x64.zip",
            else => Error.UnsupportedPlatform,
        },
        else => Error.UnsupportedPlatform,
    };
}

pub fn assetNameForTarget(allocator: mem.Allocator, target: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "bun-{s}.zip", .{target});
}

pub fn tagName(allocator: mem.Allocator, version: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "bun-v{s}", .{version});
}

pub fn archiveUrl(allocator: mem.Allocator, version: []const u8, asset: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/oven-sh/bun/releases/download/bun-v{s}/{s}",
        .{ version, asset },
    );
}

pub const default_shasums_filenames = [_][]const u8{
    "SHASUMS256.txt",
    "SHASUMS256",
};

pub fn shasumsUrl(allocator: mem.Allocator, version: []const u8, shasums_filename: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/oven-sh/bun/releases/download/bun-v{s}/{s}",
        .{ version, shasums_filename },
    );
}

pub fn parseShasums256ForAsset(shasums: []const u8, asset: []const u8) Error!?[32]u8 {
    var it = mem.splitScalar(u8, shasums, '\n');
    while (it.next()) |line_raw| {
        const line = mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;

        var toks = mem.tokenizeAny(u8, line, " \t");
        const hash_hex = toks.next() orelse continue;
        var file_name = toks.next() orelse continue;
        if (file_name.len > 0 and file_name[0] == '*') file_name = file_name[1..];

        if (!mem.eql(u8, file_name, asset)) continue;
        if (hash_hex.len != 64) return Error.InvalidSha256Hex;

        var out: [32]u8 = undefined;
        for (0..32) |i| {
            out[i] = try parseHexByte(hash_hex[i * 2 .. i * 2 + 2]);
        }
        return out;
    }
    return null;
}

pub fn downloadShasums256(allocator: mem.Allocator, client: *http.Client, version: []const u8) ![]u8 {
    const tag = try tagName(allocator, version);
    defer allocator.free(tag);

    const endpoints = [_][]const u8{
        "https://ungh.cc/repos/oven-sh/bun/releases/tags/{s}",
        "https://ungh.cc/repos/oven-sh/bun/releases/tag/{s}",
        "https://ungh.cc/repos/oven-sh/bun/releases/{s}",
    };

    var ungh_body: ?[]u8 = null;
    defer if (ungh_body) |body| allocator.free(body);

    inline for (endpoints) |fmt| {
        const url = try std.fmt.allocPrint(allocator, fmt, .{tag});
        defer allocator.free(url);
        if (http_utils.httpGetAlloc(allocator, client, url, true, 1024 * 1024 * 4, false)) |body| {
            ungh_body = body;
            break;
        } else |_| {}
    }

    if (ungh_body) |body| {
        if (json.parseFromSlice(std.json.Value, allocator, body, .{})) |p| {
            defer p.deinit();
            if (findUnghShasumsUrl(allocator, p.value)) |shasums_url| {
                defer allocator.free(shasums_url);
                if (http_utils.httpGetAlloc(allocator, client, shasums_url, false, 1024 * 1024 * 4, false)) |txt| {
                    return txt;
                } else |_| {}
            }
        } else |_| {}
    }

    for (default_shasums_filenames) |name| {
        const url = try shasumsUrl(allocator, version, name);
        defer allocator.free(url);
        if (http_utils.httpGetAlloc(allocator, client, url, false, 1024 * 1024 * 4, false)) |txt| {
            return txt;
        } else |_| {}
    }

    return error.ShasumsNotFound;
}

fn findUnghShasumsUrl(allocator: mem.Allocator, root: std.json.Value) ?[]u8 {
    const release_val = root.object.get("release") orelse return null;
    const release_obj = release_val.object;
    const assets_val = release_obj.get("assets") orelse return null;
    const assets = assets_val.array;

    for (assets.items) |asset_val| {
        const obj = asset_val.object;
        const name_val = obj.get("name") orelse continue;
        const name = name_val.string;

        var is_shasums = false;
        for (default_shasums_filenames) |cand| {
            if (mem.eql(u8, name, cand)) {
                is_shasums = true;
                break;
            }
        }
        if (!is_shasums) continue;

        const url_val =
            obj.get("browser_download_url") orelse
            obj.get("download_url") orelse
            obj.get("url") orelse continue;

        return allocator.dupe(u8, url_val.string) catch {
            return null;
        };
    }

    return null;
}

fn parseHexByte(two: []const u8) Error!u8 {
    if (two.len != 2) return Error.InvalidSha256Hex;
    const hi = try parseHexNibble(two[0]);
    const lo = try parseHexNibble(two[1]);
    return (hi << 4) | lo;
}

fn parseHexNibble(ch: u8) Error!u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => Error.InvalidSha256Hex,
    };
}
