// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Test helpers

const std = @import("std");
const builtin = @import("builtin");

pub const BIN_DIR = "zig-out/bin";

var temp_file_counter = std.atomic.Value(u32).init(0);

pub const CommandResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CommandResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }

    pub fn expectSuccess(self: CommandResult) !void {
        if (self.exit_code != 0) {
            std.debug.print("Expected success but got exit code {d}\n", .{self.exit_code});
            std.debug.print("stderr: {s}\n", .{self.stderr});
            return error.UnexpectedExitCode;
        }
    }

    pub fn expectFailure(self: CommandResult) !void {
        if (self.exit_code == 0) {
            std.debug.print("Expected failure but got success\n", .{});
            return error.UnexpectedSuccess;
        }
    }

    pub fn expectStdout(self: CommandResult, expected: []const u8) !void {
        if (!std.mem.eql(u8, self.stdout, expected)) {
            std.debug.print("Expected stdout: '{s}'\n", .{expected});
            std.debug.print("Got stdout: '{s}'\n", .{self.stdout});
            return error.StdoutMismatch;
        }
    }

    pub fn expectStdoutContains(self: CommandResult, needle: []const u8) !void {
        if (std.mem.indexOf(u8, self.stdout, needle) == null) {
            std.debug.print("Expected stdout to contain: '{s}'\n", .{needle});
            std.debug.print("Got stdout: '{s}'\n", .{self.stdout});
            return error.StdoutDoesNotContain;
        }
    }

    pub fn expectStderrContains(self: CommandResult, needle: []const u8) !void {
        if (std.mem.indexOf(u8, self.stderr, needle) == null) {
            std.debug.print("Expected stderr to contain: '{s}'\n", .{needle});
            std.debug.print("Got stderr: '{s}'\n", .{self.stderr});
            return error.StderrDoesNotContain;
        }
    }
};

/// Get the absolute path to a binary in the build output directory
fn getBinaryPath(allocator: std.mem.Allocator, binary_name: []const u8) ![]const u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const path = try std.fs.path.join(allocator, &[_][]const u8{
        cwd,
        BIN_DIR,
        binary_name,
    });

    return path;
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !CommandResult {
    if (argv.len == 0) return error.EmptyArgv;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var argv_absolute = std.ArrayList([]const u8).init(arena_allocator);

    const first_arg = argv[0];
    const needs_absolute = std.mem.startsWith(u8, first_arg, BIN_DIR);

    if (needs_absolute) {
        const binary_name = std.fs.path.basename(first_arg);
        const abs_path = try getBinaryPath(arena_allocator, binary_name);
        try argv_absolute.append(abs_path);
    } else {
        try argv_absolute.append(first_arg);
    }

    for (argv[1..]) |arg| {
        try argv_absolute.append(arg);
    }

    var child = std.process.Child.init(argv_absolute.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |err| {
        std.debug.print("Failed to spawn process: {s}\n", .{@errorName(err)});
        std.debug.print("Command: {s}\n", .{argv_absolute.items[0]});
        return err;
    };

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = child.wait() catch |err| {
        std.debug.print("Failed to wait for process: {s}\n", .{@errorName(err)});
        allocator.free(stdout);
        allocator.free(stderr);
        return err;
    };

    const exit_code: u8 = switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => 128,
        .Stopped => 128,
        .Unknown => 128,
    };

    return CommandResult{
        .exit_code = exit_code,
        .stdout = stdout,
        .stderr = stderr,
        .allocator = allocator,
    };
}

pub fn runCommandWithStdin(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdin_content: []const u8,
) !CommandResult {
    if (argv.len == 0) return error.EmptyArgv;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var argv_absolute = std.ArrayList([]const u8).init(arena_allocator);

    const first_arg = argv[0];
    const needs_absolute = std.mem.startsWith(u8, first_arg, BIN_DIR);

    if (needs_absolute) {
        const binary_name = std.fs.path.basename(first_arg);
        const abs_path = try getBinaryPath(arena_allocator, binary_name);
        try argv_absolute.append(abs_path);
    } else {
        try argv_absolute.append(first_arg);
    }

    for (argv[1..]) |arg| {
        try argv_absolute.append(arg);
    }

    var child = std.process.Child.init(argv_absolute.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |err| {
        std.debug.print("Failed to spawn process: {s}\n", .{@errorName(err)});
        std.debug.print("Command: {s}\n", .{argv_absolute.items[0]});
        return err;
    };

    child.stdin.?.writeAll(stdin_content) catch |err| {
        std.debug.print("Warning: failed to write to stdin: {s}\n", .{@errorName(err)});
    };
    child.stdin.?.close();
    child.stdin = null;

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = child.wait() catch |err| {
        std.debug.print("Failed to wait for process: {s}\n", .{@errorName(err)});
        allocator.free(stdout);
        allocator.free(stderr);
        return err;
    };

    const exit_code: u8 = switch (term) {
        .Exited => |code| @intCast(code),
        else => 128,
    };

    return CommandResult{
        .exit_code = exit_code,
        .stdout = stdout,
        .stderr = stderr,
        .allocator = allocator,
    };
}

pub fn createTempFile(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    const timestamp = std.time.milliTimestamp();
    const counter = temp_file_counter.fetchAdd(1, .seq_cst);
    const thread_id = std.Thread.getCurrentId();

    const filename = try std.fmt.allocPrint(
        allocator,
        "/tmp/userland_test_{d}_{d}_{d}.txt",
        .{ timestamp, thread_id, counter },
    );
    errdefer allocator.free(filename);

    var file = try std.fs.createFileAbsolute(filename, .{});
    defer file.close();

    try file.writeAll(content);

    return filename;
}

pub fn cleanupTempFile(path: []const u8, allocator: std.mem.Allocator) void {
    std.fs.deleteFileAbsolute(path) catch {};
    allocator.free(path);
}

pub fn createTempDir(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.milliTimestamp();
    const counter = temp_file_counter.fetchAdd(1, .seq_cst);
    const thread_id = std.Thread.getCurrentId();

    const dirname = try std.fmt.allocPrint(
        allocator,
        "/tmp/userland_test_dir_{d}_{d}_{d}",
        .{ timestamp, thread_id, counter },
    );
    errdefer allocator.free(dirname);

    try std.fs.makeDirAbsolute(dirname);

    return dirname;
}

pub fn cleanupTempDir(path: []const u8, allocator: std.mem.Allocator) void {
    std.fs.deleteTreeAbsolute(path) catch {};
    allocator.free(path);
}
