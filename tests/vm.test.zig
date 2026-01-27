const std = @import("std");
const bun_releases = @import("tests").bun_releases;
const platform = @import("tests").platform;

test "bun release assetName mapping" {
    try std.testing.expectEqualStrings("bun-darwin-aarch64.zip", try bun_releases.assetName(.macos, .aarch64));
    try std.testing.expectEqualStrings("bun-darwin-x64.zip", try bun_releases.assetName(.macos, .x86_64));
    try std.testing.expectEqualStrings("bun-linux-aarch64.zip", try bun_releases.assetName(.linux, .aarch64));
    try std.testing.expectEqualStrings("bun-linux-x64.zip", try bun_releases.assetName(.linux, .x86_64));
    try std.testing.expectEqualStrings("bun-windows-aarch64.zip", try bun_releases.assetName(.windows, .aarch64));
    try std.testing.expectEqualStrings("bun-windows-x64.zip", try bun_releases.assetName(.windows, .x86_64));

    try std.testing.expectError(bun_releases.Error.UnsupportedPlatform, bun_releases.assetName(.macos, .riscv64));
    try std.testing.expectError(bun_releases.Error.UnsupportedPlatform, bun_releases.assetName(.freebsd, .x86_64));
}

test "bun release archiveUrl formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const url = try bun_releases.archiveUrl(a, "1.2.3", "bun-darwin-aarch64.zip");
    try std.testing.expectEqualStrings(
        "https://github.com/oven-sh/bun/releases/download/bun-v1.2.3/bun-darwin-aarch64.zip",
        url,
    );
}

test "parse SHASUMS256 selects asset hash" {
    const asset = "bun-linux-x64.zip";
    const shasums =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  other.zip\n" ++
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  *bun-linux-x64.zip\n" ++
        "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  bun-windows-x64.zip\n";

    const digest = (try bun_releases.parseShasums256ForAsset(shasums, asset)) orelse return error.TestUnexpectedResult;
    const expected = [_]u8{0xaa} ** 32;
    try std.testing.expectEqualSlices(u8, expected[0..], digest[0..]);
}

test "assetNameForTarget formats archive name" {
    const allocator = std.testing.allocator;
    const name = try bun_releases.assetNameForTarget(allocator, "darwin-x64");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("bun-darwin-x64.zip", name);
}

test "buildTargetFromOptions selects musl target on alpine" {
    const allocator = std.testing.allocator;
    const result = try platform.buildTargetFromOptions(allocator, .{
        .os_tag = .linux,
        .cpu_arch = .x86_64,
        .is_musl = true,
        .is_rosetta = false,
        .has_avx2 = true,
    });
    defer allocator.free(result.target);
    try std.testing.expectEqualStrings("linux-x64-musl", result.target);
    try std.testing.expect(!result.used_rosetta);
}

test "buildTargetFromOptions selects baseline for x64 without avx2" {
    const allocator = std.testing.allocator;
    const result = try platform.buildTargetFromOptions(allocator, .{
        .os_tag = .linux,
        .cpu_arch = .x86_64,
        .is_musl = false,
        .is_rosetta = false,
        .has_avx2 = false,
    });
    defer allocator.free(result.target);
    try std.testing.expectEqualStrings("linux-x64-baseline", result.target);
}

test "buildTargetFromOptions uses darwin-aarch64 under rosetta" {
    const allocator = std.testing.allocator;
    const result = try platform.buildTargetFromOptions(allocator, .{
        .os_tag = .macos,
        .cpu_arch = .x86_64,
        .is_musl = false,
        .is_rosetta = true,
        .has_avx2 = true,
    });
    defer allocator.free(result.target);
    try std.testing.expectEqualStrings("darwin-aarch64", result.target);
    try std.testing.expect(result.used_rosetta);
}
