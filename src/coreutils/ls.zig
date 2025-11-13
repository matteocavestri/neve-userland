// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2025 Matteo Cavestri
//
// POSIX-compliant ls utility - list directory contents
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");
const args_mod = @import("args");
const builtin = @import("builtin");
const linux = std.os.linux;

/// Command-line options for ls
const Options = struct {
    show_all: bool = false,
    show_almost_all: bool = false,
    long_format: bool = false,
    human_readable: bool = false,
    show_hidden: bool = false,
    reverse: bool = false,
    sort_by_time: bool = false,
    recursive: bool = false,
    one_per_line: bool = false,
};

/// Information about a file/directory entry
const FileInfo = struct {
    name: []const u8,
    stat: linux.Stat,

    fn lessThan(context: void, a: FileInfo, b: FileInfo) bool {
        _ = context;
        return std.mem.lessThan(u8, a.name, b.name);
    }

    fn lessThanByTime(context: void, a: FileInfo, b: FileInfo) bool {
        _ = context;
        const a_time = @as(i128, a.stat.mtim.tv_sec) * 1_000_000_000 + a.stat.mtim.tv_nsec;
        const b_time = @as(i128, b.stat.mtim.tv_sec) * 1_000_000_000 + b.stat.mtim.tv_nsec;
        return a_time > b_time;
    }
};

const UserCache = std.AutoHashMap(u32, []const u8);
const GroupCache = std.AutoHashMap(u32, []const u8);

/// List directory contents with various formatting options.
/// Per POSIX: lists files and directories, supports sorting and formatting options.
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try args_mod.ArgsIterator.init(allocator);
    defer args.deinit();

    var options = Options{};
    var paths = std.ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    // Parse command-line arguments
    while (args.next()) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
            var i: usize = 1;
            while (i < arg.len) : (i += 1) {
                switch (arg[i]) {
                    'a' => options.show_all = true,
                    'A' => options.show_almost_all = true,
                    'l' => options.long_format = true,
                    'h' => options.human_readable = true,
                    'r' => options.reverse = true,
                    't' => options.sort_by_time = true,
                    'R' => options.recursive = true,
                    '1' => options.one_per_line = true,
                    else => {
                        common.printError("ls: invalid option -- '{c}'\n", .{arg[i]});
                        common.printUsageAndExit(args.program_name, "[-aAlhrtR1] [file ...]", .usage_error);
                    },
                }
            }
        } else {
            try paths.append(arg);
        }
    }

    // Default to current directory if no paths specified
    if (paths.items.len == 0) {
        try paths.append(".");
    }

    options.show_hidden = options.show_all or options.show_almost_all;

    // Initialize caches for user/group name lookups
    var user_cache = UserCache.init(allocator);
    defer {
        var it = user_cache.valueIterator();
        while (it.next()) |value| {
            allocator.free(value.*);
        }
        user_cache.deinit();
    }

    var group_cache = GroupCache.init(allocator);
    defer {
        var it = group_cache.valueIterator();
        while (it.next()) |value| {
            allocator.free(value.*);
        }
        group_cache.deinit();
    }

    var had_error = false;

    // Process each path
    for (paths.items, 0..) |path, idx| {
        if (paths.items.len > 1 and idx > 0) {
            std.io.getStdOut().writer().writeByte('\n') catch {};
        }

        if (paths.items.len > 1) {
            std.io.getStdOut().writer().print("{s}:\n", .{path}) catch {};
        }

        listPath(allocator, path, options, &user_cache, &group_cache) catch |err| {
            handlePathError(path, err);
            had_error = true;
            continue;
        };
    }

    return if (had_error) @intFromEnum(common.ExitCode.failure) else @intFromEnum(common.ExitCode.success);
}

/// List a single path (file or directory)
fn listPath(
    allocator: std.mem.Allocator,
    path: []const u8,
    options: Options,
    user_cache: *UserCache,
    group_cache: *GroupCache,
) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var stat_buf: linux.Stat = undefined;
    const rc = linux.stat(path_z.ptr, &stat_buf);

    if (linux.E.init(rc) != .SUCCESS) {
        return error.FileNotFound;
    }

    const is_dir = linux.S.ISDIR(stat_buf.mode);

    if (!is_dir) {
        try printEntry(allocator, path, stat_buf, options, user_cache, group_cache);
        return;
    }

    try listDirectory(allocator, path, options, user_cache, group_cache);
}

/// List contents of a directory
fn listDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    options: Options,
    user_cache: *UserCache,
    group_cache: *GroupCache,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        return err;
    };
    defer dir.close();

    var entries = std.ArrayList(FileInfo).init(allocator);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.name);
        }
        entries.deinit();
    }

    // Add . and .. if -a flag is set
    if (options.show_all) {
        const dir_fd = dir.fd;
        var dot_stat: linux.Stat = undefined;
        _ = linux.fstat(dir_fd, &dot_stat);

        try entries.append(.{
            .name = try allocator.dupe(u8, "."),
            .stat = dot_stat,
        });

        const dotdot_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, ".." });
        defer allocator.free(dotdot_path);

        const dotdot_path_z = try allocator.dupeZ(u8, dotdot_path);
        defer allocator.free(dotdot_path_z);

        var dotdot_stat: linux.Stat = undefined;
        _ = linux.stat(dotdot_path_z.ptr, &dotdot_stat);

        try entries.append(.{
            .name = try allocator.dupe(u8, ".."),
            .stat = dotdot_stat,
        });
    }

    // Iterate through directory entries
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!options.show_hidden and entry.name[0] == '.') {
            continue;
        }

        if (options.show_almost_all and
            (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")))
        {
            continue;
        }

        if (options.show_all and
            (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")))
        {
            continue;
        }

        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(full_path);

        const full_path_z = try allocator.dupeZ(u8, full_path);
        defer allocator.free(full_path_z);

        var stat_buf: linux.Stat = undefined;
        const rc = linux.stat(full_path_z.ptr, &stat_buf);

        if (linux.E.init(rc) != .SUCCESS) {
            allocator.free(name);
            continue;
        }

        try entries.append(.{
            .name = name,
            .stat = stat_buf,
        });
    }

    // Sort entries
    if (options.sort_by_time) {
        std.mem.sort(FileInfo, entries.items, {}, FileInfo.lessThanByTime);
    } else {
        std.mem.sort(FileInfo, entries.items, {}, FileInfo.lessThan);
    }

    if (options.reverse) {
        std.mem.reverse(FileInfo, entries.items);
    }

    // Print entries
    const stdout = std.io.getStdOut().writer();

    for (entries.items) |entry| {
        if (options.long_format) {
            printLongFormat(allocator, entry.name, entry.stat, options, user_cache, group_cache) catch |err| {
                handleWriteError(err);
                continue;
            };
        } else {
            stdout.print("{s}\n", .{entry.name}) catch |err| {
                handleWriteError(err);
                continue;
            };
        }
    }

    // Recursive listing
    if (options.recursive) {
        for (entries.items) |entry| {
            const is_dir = linux.S.ISDIR(entry.stat.mode);

            if (is_dir) {
                if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
                    continue;
                }

                stdout.print("\n{s}/{s}:\n", .{ dir_path, entry.name }) catch |err| {
                    handleWriteError(err);
                    continue;
                };

                const subdir_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                defer allocator.free(subdir_path);

                listDirectory(allocator, subdir_path, options, user_cache, group_cache) catch |err| {
                    handlePathError(subdir_path, err);
                    continue;
                };
            }
        }
    }
}

/// Print a single entry
fn printEntry(
    allocator: std.mem.Allocator,
    name: []const u8,
    stat: linux.Stat,
    options: Options,
    user_cache: *UserCache,
    group_cache: *GroupCache,
) !void {
    const stdout = std.io.getStdOut().writer();

    if (options.long_format) {
        try printLongFormat(allocator, name, stat, options, user_cache, group_cache);
    } else {
        try stdout.print("{s}\n", .{name});
    }
}

/// Resolve user ID to username
fn getUserName(allocator: std.mem.Allocator, uid: u32, cache: *UserCache) ![]const u8 {
    if (cache.get(uid)) |name| {
        return name;
    }

    const passwd_file = std.fs.openFileAbsolute("/etc/passwd", .{}) catch {
        const uid_str = try std.fmt.allocPrint(allocator, "{d}", .{uid});
        try cache.put(uid, uid_str);
        return uid_str;
    };
    defer passwd_file.close();

    var buf_reader = std.io.bufferedReader(passwd_file.reader());
    var reader = buf_reader.reader();

    var line_buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        var iter = std.mem.splitScalar(u8, line, ':');

        const username = iter.next() orelse continue;
        _ = iter.next();
        const uid_str = iter.next() orelse continue;

        const line_uid = std.fmt.parseInt(u32, uid_str, 10) catch continue;

        if (line_uid == uid) {
            const name = try allocator.dupe(u8, username);
            try cache.put(uid, name);
            return name;
        }
    }

    const uid_str = try std.fmt.allocPrint(allocator, "{d}", .{uid});
    try cache.put(uid, uid_str);
    return uid_str;
}

/// Resolve group ID to group name
fn getGroupName(allocator: std.mem.Allocator, gid: u32, cache: *GroupCache) ![]const u8 {
    if (cache.get(gid)) |name| {
        return name;
    }

    const group_file = std.fs.openFileAbsolute("/etc/group", .{}) catch {
        const gid_str = try std.fmt.allocPrint(allocator, "{d}", .{gid});
        try cache.put(gid, gid_str);
        return gid_str;
    };
    defer group_file.close();

    var buf_reader = std.io.bufferedReader(group_file.reader());
    var reader = buf_reader.reader();

    var line_buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        var iter = std.mem.splitScalar(u8, line, ':');

        const groupname = iter.next() orelse continue;
        _ = iter.next();
        const gid_str = iter.next() orelse continue;

        const line_gid = std.fmt.parseInt(u32, gid_str, 10) catch continue;

        if (line_gid == gid) {
            const name = try allocator.dupe(u8, groupname);
            try cache.put(gid, name);
            return name;
        }
    }

    const gid_str = try std.fmt.allocPrint(allocator, "{d}", .{gid});
    try cache.put(gid, gid_str);
    return gid_str;
}

/// Print file information in long format
fn printLongFormat(
    allocator: std.mem.Allocator,
    name: []const u8,
    stat: linux.Stat,
    options: Options,
    user_cache: *UserCache,
    group_cache: *GroupCache,
) !void {
    const stdout = std.io.getStdOut().writer();

    const file_type: u8 = if (linux.S.ISDIR(stat.mode))
        'd'
    else if (linux.S.ISLNK(stat.mode))
        'l'
    else if (linux.S.ISBLK(stat.mode))
        'b'
    else if (linux.S.ISCHR(stat.mode))
        'c'
    else if (linux.S.ISFIFO(stat.mode))
        'p'
    else if (linux.S.ISSOCK(stat.mode))
        's'
    else
        '-';

    try stdout.writeByte(file_type);

    const mode = stat.mode;
    try stdout.writeAll(if (mode & linux.S.IRUSR != 0) "r" else "-");
    try stdout.writeAll(if (mode & linux.S.IWUSR != 0) "w" else "-");
    try stdout.writeAll(if (mode & linux.S.IXUSR != 0) "x" else "-");
    try stdout.writeAll(if (mode & linux.S.IRGRP != 0) "r" else "-");
    try stdout.writeAll(if (mode & linux.S.IWGRP != 0) "w" else "-");
    try stdout.writeAll(if (mode & linux.S.IXGRP != 0) "x" else "-");
    try stdout.writeAll(if (mode & linux.S.IROTH != 0) "r" else "-");
    try stdout.writeAll(if (mode & linux.S.IWOTH != 0) "w" else "-");
    try stdout.writeAll(if (mode & linux.S.IXOTH != 0) "x" else "-");

    try stdout.print(" {d:>3}", .{stat.nlink});

    const username = try getUserName(allocator, stat.uid, user_cache);
    const groupname = try getGroupName(allocator, stat.gid, group_cache);

    try stdout.print(" {s} {s}", .{ username, groupname });

    if (options.human_readable) {
        const size_str = formatHumanReadable(@intCast(stat.size));
        try stdout.print(" {s:>5}", .{size_str});
    } else {
        try stdout.print(" {d:>8}", .{stat.size});
    }

    const time_str = formatTime(stat.mtim.tv_sec);
    try stdout.print(" {s}", .{time_str});

    try stdout.print(" {s}\n", .{name});
}

/// Format timestamp for display
fn formatTime(timestamp: i64) [12]u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    const days_since_epoch = @divFloor(timestamp, 86400);

    var year: i32 = 1970;
    var remaining_days = days_since_epoch;

    while (remaining_days >= 365) {
        const days_in_year: i64 = if (@mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0)) 366 else 365;
        if (remaining_days < days_in_year) break;
        remaining_days -= days_in_year;
        year += 1;
    }

    if (year > 9999) year = 9999;
    if (year < 1970) year = 1970;

    const month = @min(@divFloor(remaining_days, 30), 11);
    const day = @min(@mod(remaining_days, 30) + 1, 31);

    const seconds_today = @mod(timestamp, 86400);
    const hours = @divFloor(seconds_today, 3600);
    const minutes = @mod(@divFloor(seconds_today, 60), 60);

    const now = std.time.timestamp();
    const six_months: i64 = 6 * 30 * 24 * 3600;

    var result: [12]u8 = undefined;

    if (now - timestamp > six_months or now - timestamp < -six_months) {
        const written = std.fmt.bufPrint(&result, "{s} {d:>2}  {d:>4}", .{
            months[@intCast(month)],
            @as(u32, @intCast(day)),
            @as(u32, @intCast(year)),
        }) catch {
            _ = std.fmt.bufPrint(&result, "Jan  1  1970", .{}) catch unreachable;
            return result;
        };

        if (written.len < result.len) {
            @memset(result[written.len..], ' ');
        }
    } else {
        _ = std.fmt.bufPrint(&result, "{s} {d:>2} {d:0>2}:{d:0>2}", .{
            months[@intCast(month)],
            @as(u32, @intCast(day)),
            @as(u32, @intCast(hours)),
            @as(u32, @intCast(minutes)),
        }) catch unreachable;
    }

    return result;
}

/// Format file size in human-readable format
fn formatHumanReadable(size: u64) [6]u8 {
    var result: [6]u8 = undefined;

    if (size < 1024) {
        _ = std.fmt.bufPrint(&result, "{d}B", .{size}) catch unreachable;
    } else if (size < 1024 * 1024) {
        const kb = size / 1024;
        _ = std.fmt.bufPrint(&result, "{d}K", .{kb}) catch unreachable;
    } else if (size < 1024 * 1024 * 1024) {
        const mb = size / (1024 * 1024);
        _ = std.fmt.bufPrint(&result, "{d}M", .{mb}) catch unreachable;
    } else {
        const gb = size / (1024 * 1024 * 1024);
        _ = std.fmt.bufPrint(&result, "{d}G", .{gb}) catch unreachable;
    }

    return result;
}

/// Handle path access errors
fn handlePathError(path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.NotDir => "Not a directory",
        error.NameTooLong => "File name too long",
        error.SystemResources => "Too many open files",
        else => @errorName(err),
    };
    common.printError("ls: cannot access '{s}': {s}\n", .{ path, msg });
}

/// Handle write errors
fn handleWriteError(err: anyerror) void {
    if (err == error.BrokenPipe) {
        return; // Silent on broken pipe
    }
    const msg = switch (err) {
        error.NoSpaceLeft => "no space left on device",
        error.InputOutput => "input/output error",
        else => @errorName(err),
    };
    common.printError("ls: write error: {s}\n", .{msg});
}
