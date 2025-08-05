const std = @import("std");

const TAILWIND_VERSION = "v4.1.11";
const GITHUB_BASE_URL = "https://github.com/tailwindlabs/tailwindcss/releases/download/";

fn getPlatformExecutableName() []const u8 {
    const target = @import("builtin").target;

    const os_name = switch (target.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => @panic("Unsupported operating system"),
    };

    const arch_name = switch (target.cpu.arch) {
        .x86_64 => "x64",
        .aarch64 => "arm64",
        else => @panic("Unsupported architecture"),
    };

    const extension = switch (target.os.tag) {
        .windows => ".exe",
        else => "",
    };

    // For Linux, we'll use the musl variants for better compatibility
    const musl_suffix = switch (target.os.tag) {
        .linux => "-musl",
        else => "",
    };

    return std.fmt.comptimePrint("tailwindcss-{s}-{s}{s}{s}", .{ os_name, arch_name, musl_suffix, extension });
}

fn buildDownloadUri(allocator: std.mem.Allocator) !std.Uri {
    const executable_name = getPlatformExecutableName();
    const path = try std.fmt.allocPrint(allocator, "/tailwindlabs/tailwindcss/releases/download/{s}/{s}", .{ TAILWIND_VERSION, executable_name });

    return std.Uri{
        .scheme = "https",
        .host = .{ .raw = "github.com" },
        .path = .{ .raw = path },
    };
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    std.debug.assert(args.skip());
    const executable_path = args.next() orelse fatal("Missing output file argument.", .{});

    const output_file = try std.fs.cwd().createFile(executable_path, .{});
    defer output_file.close();
    const output_file_writer = output_file.writer();

    // Build the download URI dynamically based on target platform
    const download_uri = try buildDownloadUri(allocator);
    defer allocator.free(download_uri.path.raw);

    std.debug.print("Downloading Tailwind CSS executable for platform: {s}...\n", .{getPlatformExecutableName()});

    var http_client: std.http.Client = .{ .allocator = allocator };
    try http_client.initDefaultProxies(allocator);
    defer http_client.deinit();

    var server_header_buffer: [1024 * 1024]u8 = undefined;
    var request = try http_client.open(.GET, download_uri, .{ .server_header_buffer = &server_header_buffer });
    defer request.deinit();

    request.send() catch fatal("failed to fetch tailwindcss executable", .{});
    request.wait() catch fatal("failed to fetch tailwindcss executable", .{});

    if (request.response.status != .ok) {
        fatal("HTTP request failed with status: {d}\n", .{@intFromEnum(request.response.status)});
    }

    var buffer: [4 * 1024 * 1024]u8 = undefined;
    while (true) {
        const bytes_read = request.read(&buffer) catch fatal("failed to fetch tailwindcss executable", .{});
        if (bytes_read == 0) {
            break;
        }

        try output_file_writer.writeAll(buffer[0..bytes_read]);
    }

    try output_file.chmod(0o770);

    std.debug.print("Successfully downloaded Tailwind CSS executable to: {s}\n", .{executable_path});

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
