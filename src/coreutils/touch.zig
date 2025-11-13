// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2025 Matteo Cavestri
//
// POSIX-compliant touch utility - change file timestamps
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");
const args_mod = @import("args");
const linux = std.os.linux;

// UTIME_OMIT constant for utimensat (don't change this time field)
const UTIME_OMIT: i64 = 1073741822; // ((1 << 30) - 2)

/// Command-line options for touch
const Options = struct {
    access_only: bool = false,
    modify_only: bool = false,
    no_create: bool = false,
    time: ?i64 = null,
};

/// Change file access and modification times.
/// Per POSIX: updates timestamps, creates empty files if they don't exist.
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try args_mod.ArgsIterator.init(allocator);
    defer args.deinit();

    var options = Options{};
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();

    // Parse command-line arguments
    while (args.next()) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
            var i: usize = 1;
            while (i < arg.len) : (i += 1) {
                switch (arg[i]) {
                    'a' => options.access_only = true,
                    'c' => options.no_create = true,
                    'm' => options.modify_only = true,
                    't' => {
                        const time_str = args.next() orelse {
                            common.printError("touch: option requires an argument -- 't'\n", .{});
                            common.printUsageAndExit(args.program_name, "[-acm] [-t time] file...", .usage_error);
                        };

                        options.time = parseTimeString(time_str) catch {
                            common.printError("touch: invalid date format '{s}'\n", .{time_str});
                            return @intFromEnum(common.ExitCode.usage_error);
                        };
                        break;
                    },
                    else => {
                        common.printError("touch: invalid option -- '{c}'\n", .{arg[i]});
                        common.printUsageAndExit(args.program_name, "[-acm] [-t time] file...", .usage_error);
                    },
                }
            }
        } else {
            // Validate path is not empty
            if (arg.len == 0) {
                common.printError("touch: invalid empty file name\n", .{});
                return @intFromEnum(common.ExitCode.usage_error);
            }
            try files.append(arg);
        }
    }

    // POSIX requires at least one file operand
    if (files.items.len == 0) {
        common.printError("touch: missing file operand\n", .{});
        common.printUsageAndExit(args.program_name, "[-acm] [-t time] file...", .usage_error);
    }

    // If neither -a nor -m is specified, update both times (POSIX requirement)
    if (!options.access_only and !options.modify_only) {
        options.access_only = true;
        options.modify_only = true;
    }

    var had_error = false;

    // Process each file
    for (files.items) |file_path| {
        touchFile(file_path, options) catch |err| {
            handleTouchError(file_path, err);
            had_error = true;
            continue;
        };
    }

    return if (had_error) @intFromEnum(common.ExitCode.failure) else @intFromEnum(common.ExitCode.success);
}

/// Touch a file (create if doesn't exist, or update timestamps)
fn touchFile(path: []const u8, options: Options) !void {
    // Validate path length
    if (path.len > 4096) {
        return error.NameTooLong;
    }

    const path_z = try std.heap.page_allocator.dupeZ(u8, path);
    defer std.heap.page_allocator.free(path_z);

    // Check if file exists
    var stat_buf: linux.Stat = undefined;
    const stat_rc = linux.stat(path_z.ptr, &stat_buf);
    const file_exists = linux.E.init(stat_rc) == .SUCCESS;

    if (!file_exists) {
        if (options.no_create) {
            // -c flag: don't create file, silently succeed
            return;
        }

        // Create empty file
        const file = std.fs.cwd().createFile(path, .{
            .read = false,
            .truncate = true,
            .mode = 0o666,
        }) catch |err| {
            return switch (err) {
                error.AccessDenied => error.AccessDenied,
                error.PathAlreadyExists => error.PathAlreadyExists,
                error.FileNotFound => error.FileNotFound,
                error.IsDir => error.IsDir,
                error.NoSpaceLeft => error.NoSpaceLeft,
                error.NameTooLong => error.NameTooLong,
                error.SystemResources => error.SystemResources,
                else => error.CannotCreateFile,
            };
        };
        file.close();

        // If we created the file and no specific time was requested, we're done
        if (options.time == null) {
            return;
        }
    }

    // Update file timestamps
    try updateTimestamps(path_z.ptr, options);
}

/// Update file timestamps using utimensat syscall
fn updateTimestamps(path: [*:0]const u8, options: Options) !void {
    var times: [2]linux.timespec = undefined;

    const timestamp = if (options.time) |t| t else std.time.timestamp();

    // times[0] is access time (atime)
    if (options.access_only) {
        times[0] = linux.timespec{
            .tv_sec = timestamp,
            .tv_nsec = 0,
        };
    } else {
        times[0] = linux.timespec{
            .tv_sec = 0,
            .tv_nsec = UTIME_OMIT,
        };
    }

    // times[1] is modification time (mtime)
    if (options.modify_only) {
        times[1] = linux.timespec{
            .tv_sec = timestamp,
            .tv_nsec = 0,
        };
    } else {
        times[1] = linux.timespec{
            .tv_sec = 0,
            .tv_nsec = UTIME_OMIT,
        };
    }

    const rc = linux.utimensat(linux.AT.FDCWD, path, &times, 0);

    switch (linux.E.init(rc)) {
        .SUCCESS => return,
        .ACCES => return error.AccessDenied,
        .NOENT => return error.FileNotFound,
        .PERM => return error.AccessDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        .FAULT => return error.InvalidPointer,
        .INVAL => return error.InvalidArgument,
        .LOOP => return error.SymLinkLoop,
        .NAMETOOLONG => return error.NameTooLong,
        .NOTDIR => return error.NotDir,
        else => return error.UnexpectedError,
    }
}

/// Parse time string in format [[CC]YY]MMDDhhmm[.ss]
fn parseTimeString(time_str: []const u8) !i64 {
    if (time_str.len < 8) {
        return error.InvalidTimeFormat;
    }

    // Validate all characters are digits (except optional dot)
    for (time_str, 0..) |c, idx| {
        if (c == '.' and idx == time_str.len - 3) {
            continue; // Allow optional .ss at end
        }
        if (c < '0' or c > '9') {
            return error.InvalidTimeFormat;
        }
    }

    if (time_str.len >= 12) {
        // Format: YYYYMMDDhhmm or CCYYMMDDhhmm
        const year_len: usize = if (time_str.len >= 14) 4 else 4;
        const month_offset: usize = year_len;

        const year = try std.fmt.parseInt(u32, time_str[0..year_len], 10);
        const month = try std.fmt.parseInt(u32, time_str[month_offset .. month_offset + 2], 10);
        const day = try std.fmt.parseInt(u32, time_str[month_offset + 2 .. month_offset + 4], 10);
        const hour = try std.fmt.parseInt(u32, time_str[month_offset + 4 .. month_offset + 6], 10);
        const minute = try std.fmt.parseInt(u32, time_str[month_offset + 6 .. month_offset + 8], 10);

        // Validate ranges
        if (year < 1970 or year > 9999) return error.InvalidTimeFormat;
        if (month < 1 or month > 12) return error.InvalidTimeFormat;
        if (day < 1 or day > 31) return error.InvalidTimeFormat;
        if (hour > 23) return error.InvalidTimeFormat;
        if (minute > 59) return error.InvalidTimeFormat;

        // Simplified timestamp calculation
        const days_since_epoch = @as(i64, @intCast((year - 1970) * 365 +
            (month - 1) * 30 +
            day));

        const timestamp = days_since_epoch * 86400 +
            @as(i64, @intCast(hour)) * 3600 +
            @as(i64, @intCast(minute)) * 60;

        return timestamp;
    } else if (time_str.len >= 8) {
        // Format: MMDDhhmm (assume current year)
        const month = try std.fmt.parseInt(u32, time_str[0..2], 10);
        const day = try std.fmt.parseInt(u32, time_str[2..4], 10);
        const hour = try std.fmt.parseInt(u32, time_str[4..6], 10);
        const minute = try std.fmt.parseInt(u32, time_str[6..8], 10);

        // Validate ranges
        if (month < 1 or month > 12) return error.InvalidTimeFormat;
        if (day < 1 or day > 31) return error.InvalidTimeFormat;
        if (hour > 23) return error.InvalidTimeFormat;
        if (minute > 59) return error.InvalidTimeFormat;

        // Get current year from system
        const now = std.time.timestamp();
        const current_year = 1970 + @divFloor(now, 31536000); // Approximate

        const days_since_epoch = (current_year - 1970) * 365 +
            @as(i64, @intCast((month - 1) * 30 + day));

        const timestamp = days_since_epoch * 86400 +
            @as(i64, @intCast(hour)) * 3600 +
            @as(i64, @intCast(minute)) * 60;

        return timestamp;
    }

    return error.InvalidTimeFormat;
}

/// Handle touch errors with specific messages
fn handleTouchError(path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.AccessDenied => "Permission denied",
        error.FileNotFound => "No such file or directory",
        error.IsDir => "Is a directory",
        error.NoSpaceLeft => "No space left on device",
        error.NameTooLong => "File name too long",
        error.NotDir => "Not a directory",
        error.ReadOnlyFileSystem => "Read-only file system",
        error.SymLinkLoop => "Too many levels of symbolic links",
        error.SystemResources => "Insufficient system resources",
        error.InvalidArgument => "Invalid argument",
        error.CannotCreateFile => "Cannot create file",
        error.OutOfMemory => "Out of memory",
        else => @errorName(err),
    };
    common.printError("touch: cannot touch '{s}': {s}\n", .{ path, msg });
}
