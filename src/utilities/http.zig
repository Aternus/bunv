const std = @import("std");
const mem = std.mem;
const http = std.http;

pub fn httpDownloadToFile(
    allocator: mem.Allocator,
    client: *http.Client,
    url: []const u8,
    dest_path: []const u8,
    max_bytes: usize,
) anyerror!void {
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

        var header_buffer = std.mem.zeroes([8 * 1024]u8);
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

        var transfer_buffer = std.mem.zeroes([32 * 1024]u8);
        const reader = response.reader(&transfer_buffer);
        const body = reader.allocRemaining(allocator, .limited(max_bytes)) catch |err| switch (err) {
            error.StreamTooLong => return error.ResponseTooLarge,
            else => return err,
        };
        defer allocator.free(body);

        var writer_buffer = std.mem.zeroes([8 * 1024]u8);
        var writer = file.writer(&writer_buffer);
        try writer.interface.writeAll(body);
        try writer.interface.flush();

        return;
    }
}

pub const HttpGetOptions = struct {
    accept_json: bool = false,
    max_bytes: usize = 1024 * 1024 * 4,
    verbose: bool = false,
};

pub fn httpGetAlloc(
    allocator: mem.Allocator,
    client: *http.Client,
    url: []const u8,
    options: HttpGetOptions,
) anyerror![]u8 {
    var current_url = try allocator.dupe(u8, url);
    defer allocator.free(current_url);

    var redirects: usize = 0;
    while (true) : (redirects += 1) {
        if (redirects > 8) return error.TooManyRedirects;

        const uri = try std.Uri.parse(current_url);
        const accept_header = http.Header{
            .name = "accept",
            .value = if (options.accept_json) "application/json" else "*/*",
        };

        var req = try client.request(.GET, uri, .{
            .keep_alive = false,
            .headers = .{ .accept_encoding = .omit },
            .extra_headers = &[_]http.Header{accept_header},
        });
        defer req.deinit();

        try req.sendBodiless();

        var header_buffer = std.mem.zeroes([8 * 1024]u8);
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
                if (options.verbose) {
                    std.debug.print(
                        "HTTP GET failed ({d}) for {s}\n",
                        .{ @intFromEnum(response.head.status), current_url },
                    );
                }
                return error.BadHttpStatus;
            },
        }

        var transfer_buffer = std.mem.zeroes([4 * 1024]u8);
        const reader = response.reader(&transfer_buffer);
        return reader.allocRemaining(allocator, .limited(options.max_bytes));
    }
}
