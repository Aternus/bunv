const std = @import("std");
const mem = std.mem;
const http = std.http;

pub fn httpDownloadToFile(
    allocator: mem.Allocator,
    client: *http.Client,
    url: []const u8,
    dest_path: []const u8,
    max_bytes: usize,
) !void {
    var current_url = try allocator.dupe(u8, url);
    defer allocator.free(current_url);

    var redirects: usize = 0;
    while (true) : (redirects += 1) {
        if (redirects > 8) return error.TooManyRedirects;

        const uri = try std.Uri.parse(current_url);
        var req = try client.request(.GET, uri, .{
            .keep_alive = false,
            .headers = .{ .accept_encoding = .omit },
        });
        defer req.deinit();

        try req.sendBodiless();

        var header_buffer: [8 * 1024]u8 = undefined;
        var response = try req.receiveHead(&header_buffer);

        switch (response.head.status.class()) {
            .success => {},
            .redirect => {
                const location = response.head.location orelse return error.MissingRedirectLocation;
                allocator.free(current_url);
                current_url = try allocator.dupe(u8, location);
                continue;
            },
            else => {
                std.debug.print(
                    "HTTP GET failed ({d}) for {s}\n",
                    .{ @intFromEnum(response.head.status), current_url },
                );
                return error.BadHttpStatus;
            },
        }

        var file = try std.fs.createFileAbsolute(dest_path, .{ .truncate = true });
        defer file.close();

        var transfer_buffer: [32 * 1024]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const body = reader.allocRemaining(allocator, .limited(max_bytes)) catch |err| switch (err) {
            error.StreamTooLong => return error.ResponseTooLarge,
            else => return err,
        };
        defer allocator.free(body);

        try file.writeAll(body);

        return;
    }
}

pub fn httpGetAlloc(
    allocator: mem.Allocator,
    client: *http.Client,
    url: []const u8,
    accept_json: bool,
    max_bytes: usize,
    verbose: bool,
) ![]u8 {
    var current_url = try allocator.dupe(u8, url);
    defer allocator.free(current_url);

    var redirects: usize = 0;
    while (true) : (redirects += 1) {
        if (redirects > 8) return error.TooManyRedirects;

        const uri = try std.Uri.parse(current_url);
        const accept_header = http.Header{
            .name = "accept",
            .value = if (accept_json) "application/json" else "*/*",
        };

        var req = try client.request(.GET, uri, .{
            .keep_alive = false,
            .headers = .{ .accept_encoding = .omit },
            .extra_headers = &[_]http.Header{accept_header},
        });
        defer req.deinit();

        try req.sendBodiless();

        var header_buffer: [8 * 1024]u8 = undefined;
        var response = try req.receiveHead(&header_buffer);

        switch (response.head.status.class()) {
            .success => {},
            .redirect => {
                const location = response.head.location orelse return error.MissingRedirectLocation;
                allocator.free(current_url);
                current_url = try allocator.dupe(u8, location);
                continue;
            },
            else => {
                if (verbose) {
                    std.debug.print(
                        "HTTP GET failed ({d}) for {s}\n",
                        .{ @intFromEnum(response.head.status), current_url },
                    );
                }
                return error.BadHttpStatus;
            },
        }

        var transfer_buffer: [4 * 1024]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        return reader.allocRemaining(allocator, .limited(max_bytes));
    }
}
