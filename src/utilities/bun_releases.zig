const std = @import("std");
const mem = std.mem;
const http = std.http;
const builtin = @import("builtin");
const archive_utils = @import("archive.zig");
const crypto_utils = @import("crypto.zig");
const fs_utils = @import("fs.zig");
const http_utils = @import("http.zig");
const platform = @import("platform.zig");
const c = @import("colors.zig");

pub const ParseError = error{
    UnsupportedPlatform,
    InvalidSha256Hex,
};

const VerifyFailureKind = enum {
    shasums_download_failed,
    shasums_parse_failed,
    missing_entry,
    compute_failed,
    digest_mismatch,
};

const VerifyFailure = struct {
    kind: VerifyFailureKind,
    cause: ?anyerror = null,
    expected: [32]u8 = undefined,
    actual: [32]u8 = undefined,
};

fn parseHexByte(two: []const u8) ParseError!u8 {
    if (two.len != 2) return ParseError.InvalidSha256Hex;
    const hi = try parseHexNibble(two[0]);
    const lo = try parseHexNibble(two[1]);
    return (hi << 4) | lo;
}

fn parseHexNibble(ch: u8) ParseError!u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => ParseError.InvalidSha256Hex,
    };
}

fn getAssetName(allocator: mem.Allocator, target: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "bun-{s}.zip", .{target});
}

fn getArchiveUrl(allocator: mem.Allocator, version: []const u8, asset_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/oven-sh/bun/releases/download/bun-v{s}/{s}",
        .{ version, asset_name },
    );
}

fn getSha256SumsUrl(allocator: mem.Allocator, version: []const u8, shasums_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/oven-sh/bun/releases/download/bun-v{s}/{s}",
        .{ version, shasums_name },
    );
}

fn getSha256Sums(allocator: mem.Allocator, client: *http.Client, version: []const u8) ![]u8 {
    const default_shasums_filenames = [_][]const u8{
        "SHASUMS256.txt",
        "SHASUMS256",
    };
    for (default_shasums_filenames) |name| {
        const url = try getSha256SumsUrl(allocator, version, name);
        defer allocator.free(url);
        if (http_utils.httpGetAlloc(allocator, client, url, false, 1024 * 1024 * 4, false)) |txt| {
            return txt;
        } else |_| {}
    }

    return error.ShasumsNotFound;
}

fn getSha256ForAssetName(shasums: []const u8, asset_name: []const u8) ParseError!?[32]u8 {
    var it = mem.splitScalar(u8, shasums, '\n');
    while (it.next()) |line_raw| {
        const line = mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;

        var toks = mem.tokenizeAny(u8, line, " \t");
        const hash_hex = toks.next() orelse continue;
        var file_name = toks.next() orelse continue;
        if (file_name.len > 0 and file_name[0] == '*') file_name = file_name[1..];

        if (!mem.eql(u8, file_name, asset_name)) continue;
        if (hash_hex.len != 64) return ParseError.InvalidSha256Hex;

        var out: [32]u8 = undefined;
        for (0..32) |i| {
            out[i] = try parseHexByte(hash_hex[i * 2 .. i * 2 + 2]);
        }
        return out;
    }
    return null;
}

fn verifyArchiveChecksum(
    allocator: mem.Allocator,
    client: *http.Client,
    version: []const u8,
    asset: []const u8,
    tmp_archive_path: []const u8,
) ?VerifyFailure {
    const shasums = getSha256Sums(allocator, client, version) catch |err| {
        return .{ .kind = .shasums_download_failed, .cause = err };
    };
    defer allocator.free(shasums);

    const expected_digest = getSha256ForAssetName(shasums, asset) catch |err| {
        return .{ .kind = .shasums_parse_failed, .cause = err };
    } orelse {
        return .{ .kind = .missing_entry };
    };

    const actual_digest = crypto_utils.getSha256ForFile(tmp_archive_path) catch |err| {
        return .{ .kind = .compute_failed, .cause = err };
    };

    if (!mem.eql(u8, actual_digest[0..], expected_digest[0..])) {
        return .{
            .kind = .digest_mismatch,
            .expected = expected_digest,
            .actual = actual_digest,
        };
    }

    return null;
}

pub fn installVersion(
    allocator: mem.Allocator,
    client: *http.Client,
    version_dir: []const u8,
    version: []const u8,
) !void {
    std.debug.print("Installing...\n", .{});

    const bin_dir = try fs_utils.joinPath(allocator, &[_][]const u8{ version_dir, "bin" });
    defer allocator.free(bin_dir);

    try fs_utils.ensureDirAbsolute(bin_dir);

    const target = platform.resolveBunTarget(allocator) catch |err| {
        if (err != error.UnsupportedPlatform) return err;
        std.debug.print(
            "Unsupported platform: {s}/{s} (supported: macOS/Linux/Windows × x86_64/aarch64)\n",
            .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) },
        );
        std.process.exit(1);
    };
    defer allocator.free(target.target);

    if (target.used_rosetta) {
        std.debug.print("{s}Detected Rosetta translation. Using darwin-aarch64 build.{s}\n", .{ c.yellow, c.reset });
    }

    const asset_name = try getAssetName(allocator, target.target);
    defer allocator.free(asset_name);

    const archive_url = try getArchiveUrl(allocator, version, asset_name);
    defer allocator.free(archive_url);

    const temp_dir = try fs_utils.getTempDir(allocator);
    defer allocator.free(temp_dir);

    const rand_hex = try crypto_utils.getRandomHexLower(allocator, 8);
    defer allocator.free(rand_hex);

    const temp_name = try std.fmt.allocPrint(allocator, "bunv-bun-v{s}-{s}.zip", .{ version, rand_hex });
    defer allocator.free(temp_name);

    const temp_archive_path = try fs_utils.joinPath(allocator, &[_][]const u8{ temp_dir, temp_name });
    defer allocator.free(temp_archive_path);

    std.debug.print("Downloading {s}...\n", .{asset_name});
    http_utils.httpDownloadToFile(allocator, client, archive_url, temp_archive_path, 1024 * 1024 * 512) catch |err| {
        std.debug.print("Failed to download {s}: {any}\nURL: {s}\n", .{ asset_name, err, archive_url });
        std.fs.deleteFileAbsolute(temp_archive_path) catch {};
        std.process.exit(1);
    };

    if (verifyArchiveChecksum(allocator, client, version, asset_name, temp_archive_path)) |failure| {
        switch (failure.kind) {
            .shasums_download_failed => {
                std.debug.print("Failed to download checksum file for bun-v{s}: {any}\n", .{ version, failure.cause.? });
            },
            .shasums_parse_failed => {
                std.debug.print("Failed to parse checksum file for bun-v{s}: {any}\n", .{ version, failure.cause.? });
            },
            .missing_entry => {
                std.debug.print("Missing SHA-256 entry for {s} in release checksum file\n", .{asset_name});
            },
            .compute_failed => {
                std.debug.print("Failed to compute SHA-256 for downloaded archive: {any}\n", .{failure.cause.?});
            },
            .digest_mismatch => {
                const expected_hex = std.fmt.bytesToHex(failure.expected, .lower);
                const actual_hex = std.fmt.bytesToHex(failure.actual, .lower);
                std.debug.print(
                    "SHA-256 mismatch for {s}\nExpected: {s}\nActual:   {s}\n",
                    .{
                        asset_name,
                        expected_hex[0..],
                        actual_hex[0..],
                    },
                );
            },
        }
        std.fs.deleteFileAbsolute(temp_archive_path) catch {};
        std.process.exit(1);
    }

    const bin_path = try fs_utils.getBunBinPath(allocator, version);
    defer allocator.free(bin_path);

    archive_utils.extractBunFromZip(allocator, temp_archive_path, bin_path) catch |err| {
        std.debug.print("Failed to extract bun from archive: {any}\n", .{err});
        std.fs.deleteFileAbsolute(temp_archive_path) catch {};
        std.process.exit(1);
    };

    std.fs.deleteFileAbsolute(temp_archive_path) catch {};

    std.debug.print("{s}✓{s} Done! {s}Bun v{s}{s} is installed\n", .{ c.green, c.reset, c.cyan, version, c.reset });
}
