// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2025 Matteo Cavestri
//
// POSIX-compliant mkdir utility - make directories
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");
const args_mod = @import("args");
const linux = std.os.linux;

/// Command-line options for mkdir
const Options = struct {
    parents: bool = false,
    mode: ?u32 = null,
    verbose: bool = false,
};

/// Create directories with specified permissions.
/// Per POSIX: creates directories, supports -p for parents, -m for mode.
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try args_mod.ArgsIterator.init(allocator);
    defer args.deinit();

    var options = Options{};
    var directories = std.ArrayList([]const u8).init(allocator);
    defer directories.deinit();

    // Parse command-line arguments
    while (args.next()) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
            var i: usize = 1;
            while (i < arg.len) : (i += 1) {
                switch (arg[i]) {
                    'p' => options.parents = true,
                    'v' => options.verbose = true,
                    'm' => {
                        const mode_str = args.next() orelse {
                            common.printError("mkdir: option requires an argument -- 'm'\n", .{});
                            common.printUsageAndExit(args.program_name, "[-p] [-m mode] directory...", .usage_error);
                        };

                        const mode = std.fmt.parseInt(u32, mode_str, 8) catch {
                            common.printError("mkdir: invalid mode: '{s}'\n", .{mode_str});
                            return @intFromEnum(common.ExitCode.usage_error);
                        };

                        // Validate mode (should be <= 0777)
                        if (mode > 0o777) {
                            common.printError("mkdir: invalid mode: '{s}'\n", .{mode_str});
                            return @intFromEnum(common.ExitCode.usage_error);
                        }

                        options.mode = mode;
                        break;
                    },
                    else => {
                        common.printError("mkdir: invalid option -- '{c}'\n", .{arg[i]});
                        common.printUsageAndExit(args.program_name, "[-p] [-m mode] directory...", .usage_error);
                    },
                }
            }
        } else {
            // Validate path is not empty
            if (arg.len == 0) {
                common.printError("mkdir: invalid empty directory name\n", .{});
                return @intFromEnum(common.ExitCode.usage_error);
            }
            try directories.append(arg);
        }
    }

    // POSIX requires at least one directory operand
    if (directories.items.len == 0) {
        common.printError("mkdir: missing operand\n", .{});
        common.printUsageAndExit(args.program_name, "[-p] [-m mode] directory...", .usage_error);
    }

    const default_mode: u32 = 0o777;
    const mode = options.mode orelse default_mode;

    var had_error = false;

    // Create each directory
    for (directories.items) |dir_path| {
        if (options.parents) {
            createDirectoryParents(allocator, dir_path, mode, options.verbose) catch |err| {
                handleDirectoryError(dir_path, err);
                had_error = true;
                continue;
            };
        } else {
            createDirectory(dir_path, mode) catch |err| {
                handleDirectoryError(dir_path, err);
                had_error = true;
                continue;
            };

            if (options.verbose) {
                const stdout = std.io.getStdOut().writer();
                stdout.print("mkdir: created directory '{s}'\n", .{dir_path}) catch {};
            }
        }
    }

    return if (had_error) @intFromEnum(common.ExitCode.failure) else @intFromEnum(common.ExitCode.success);
}

/// Create a single directory with the specified mode
fn createDirectory(path: []const u8, mode: u32) !void {
    const path_z = try std.heap.page_allocator.dupeZ(u8, path);
    defer std.heap.page_allocator.free(path_z);

    const rc = linux.mkdir(path_z.ptr, mode);

    switch (linux.E.init(rc)) {
        .SUCCESS => return,
        .EXIST => return error.PathAlreadyExists,
        .NOTDIR => return error.NotDir,
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        .PERM => return error.AccessDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        .NOSPC => return error.NoSpaceLeft,
        .NAMETOOLONG => return error.NameTooLong,
        .LOOP => return error.SymLinkLoop,
        .DQUOT => return error.DiskQuota,
        else => return error.UnexpectedError,
    }
}

/// Create directory with parent directories (-p option)
fn createDirectoryParents(
    allocator: std.mem.Allocator,
    path: []const u8,
    mode: u32,
    verbose: bool,
) !void {
    // Validate path length
    if (path.len > 4096) {
        return error.NameTooLong;
    }

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var stat_buf: linux.Stat = undefined;
    const stat_rc = linux.stat(path_z.ptr, &stat_buf);

    if (linux.E.init(stat_rc) == .SUCCESS) {
        if (linux.S.ISDIR(stat_buf.mode)) {
            // Already a directory, success (POSIX requirement with -p)
            return;
        } else {
            // Exists but not a directory
            return error.NotDir;
        }
    }

    var current_path = std.ArrayList(u8).init(allocator);
    defer current_path.deinit();

    // Handle absolute paths
    const is_absolute = path.len > 0 and path[0] == '/';
    if (is_absolute) {
        try current_path.append('/');
    }

    var iter = std.mem.splitScalar(u8, path, '/');

    while (iter.next()) |component| {
        if (component.len == 0) continue;

        if (current_path.items.len > 0 and current_path.items[current_path.items.len - 1] != '/') {
            try current_path.append('/');
        }

        try current_path.appendSlice(component);

        const level_path = try allocator.dupe(u8, current_path.items);
        defer allocator.free(level_path);

        createDirectory(level_path, mode) catch |err| {
            if (err == error.PathAlreadyExists) {
                const level_z = try allocator.dupeZ(u8, level_path);
                defer allocator.free(level_z);

                var check_stat: linux.Stat = undefined;
                const check_rc = linux.stat(level_z.ptr, &check_stat);

                if (linux.E.init(check_rc) == .SUCCESS) {
                    if (linux.S.ISDIR(check_stat.mode)) {
                        // It's a directory, continue
                        continue;
                    } else {
                        // Exists but not a directory
                        return error.NotDir;
                    }
                }
            }
            return err;
        };

        if (verbose) {
            const stdout = std.io.getStdOut().writer();
            stdout.print("mkdir: created directory '{s}'\n", .{level_path}) catch {};
        }
    }
}

/// Handle directory creation errors with specific messages
fn handleDirectoryError(path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.PathAlreadyExists => "File exists",
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.NotDir => "Not a directory",
        error.ReadOnlyFileSystem => "Read-only file system",
        error.NoSpaceLeft => "No space left on device",
        error.NameTooLong => "File name too long",
        error.SymLinkLoop => "Too many levels of symbolic links",
        error.DiskQuota => "Disk quota exceeded",
        error.OutOfMemory => "Out of memory",
        else => @errorName(err),
    };
    common.printError("mkdir: cannot create directory '{s}': {s}\n", .{ path, msg });
}
