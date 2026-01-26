const std = @import("std");
const mem = std.mem;

pub fn getUserHomeDir(allocator: mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("HOME")) |home_path| {
        return allocator.dupe(u8, home_path);
    } else if (env_map.get("USERPROFILE")) |profile_path| {
        return allocator.dupe(u8, profile_path);
    } else {
        return error.HomeDirNotFound;
    }
}

pub fn isDebug(allocator: mem.Allocator) !bool {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("DEBUG")) |value| {
        return mem.eql(u8, value, "bunv");
    }

    return false;
}
