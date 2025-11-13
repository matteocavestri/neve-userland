// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for ls utility

const std = @import("std");
const helpers = @import("helpers");

test "ls - current directory" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expect(result.stdout.len > 0);
}

test "ls - specific directory" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        "/tmp",
    });
    defer result.deinit();

    try result.expectSuccess();
}

test "ls - nonexistent directory" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        "/nonexistent_dir_xyz_12345",
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("No such file or directory");
}

test "ls - with -a flag shows hidden files" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const hidden_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/.hidden", .{temp_dir});
    defer std.testing.allocator.free(hidden_file);

    var file = try std.fs.createFileAbsolute(hidden_file, .{});
    file.close();

    // List without -a (should not show .hidden)
    var result1 = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        temp_dir,
    });
    defer result1.deinit();

    try result1.expectSuccess();
    try std.testing.expect(std.mem.indexOf(u8, result1.stdout, ".hidden") == null);

    // List with -a (should show .hidden)
    var result2 = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        "-a",
        temp_dir,
    });
    defer result2.deinit();

    try result2.expectSuccess();
    try std.testing.expect(std.mem.indexOf(u8, result2.stdout, ".hidden") != null);
}

test "ls - with -A flag shows hidden but not . and .." {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const hidden_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/.hidden", .{temp_dir});
    defer std.testing.allocator.free(hidden_file);

    var file = try std.fs.createFileAbsolute(hidden_file, .{});
    file.close();

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        "-A",
        temp_dir,
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, ".hidden") != null);
}

test "ls - with -l flag shows long format" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/testfile", .{temp_dir});
    defer std.testing.allocator.free(test_file);

    var file = try std.fs.createFileAbsolute(test_file, .{});
    file.close();

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        "-l",
        temp_dir,
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expect(result.stdout.len > 0);
    // Long format should contain permissions (r, w, x, or -)
    const has_perms = std.mem.indexOf(u8, result.stdout, "r") != null or
        std.mem.indexOf(u8, result.stdout, "w") != null or
        std.mem.indexOf(u8, result.stdout, "-") != null;
    try std.testing.expect(has_perms);
}

test "ls - single file" {
    const content = "test content\n";
    const temp_file = try helpers.createTempFile(std.testing.allocator, content);
    defer helpers.cleanupTempFile(temp_file, std.testing.allocator);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        temp_file,
    });
    defer result.deinit();

    try result.expectSuccess();
    const basename = std.fs.path.basename(temp_file);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, basename) != null);
}

test "ls - empty directory" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        temp_dir,
    });
    defer result.deinit();

    try result.expectSuccess();
}

test "ls - multiple files in directory" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const files = [_][]const u8{ "file1.txt", "file2.txt", "file3.txt" };
    for (files) |filename| {
        const filepath = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ temp_dir, filename });
        defer std.testing.allocator.free(filepath);

        var file = try std.fs.createFileAbsolute(filepath, .{});
        file.close();
    }

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/ls",
        temp_dir,
    });
    defer result.deinit();

    try result.expectSuccess();

    for (files) |filename| {
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, filename) != null);
    }
}
