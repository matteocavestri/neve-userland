// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for mkdir utility

const std = @import("std");
const helpers = @import("helpers");

test "mkdir - create single directory" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/testdir", .{temp_dir});
    defer std.testing.allocator.free(test_dir);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        test_dir,
    });
    defer result.deinit();

    try result.expectSuccess();

    var dir = try std.fs.openDirAbsolute(test_dir, .{});
    dir.close();
}

test "mkdir - create multiple directories" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir1 = try std.fmt.allocPrint(std.testing.allocator, "{s}/dir1", .{temp_dir});
    defer std.testing.allocator.free(test_dir1);

    const test_dir2 = try std.fmt.allocPrint(std.testing.allocator, "{s}/dir2", .{temp_dir});
    defer std.testing.allocator.free(test_dir2);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        test_dir1,
        test_dir2,
    });
    defer result.deinit();

    try result.expectSuccess();

    var dir1 = try std.fs.openDirAbsolute(test_dir1, .{});
    dir1.close();

    var dir2 = try std.fs.openDirAbsolute(test_dir2, .{});
    dir2.close();
}

test "mkdir - fail on existing directory" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/existing", .{temp_dir});
    defer std.testing.allocator.free(test_dir);

    try std.fs.makeDirAbsolute(test_dir);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        test_dir,
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("File exists");
}

test "mkdir - with -p creates parent directories" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/parent/child/grandchild", .{temp_dir});
    defer std.testing.allocator.free(test_path);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        "-p",
        test_path,
    });
    defer result.deinit();

    try result.expectSuccess();

    var dir = try std.fs.openDirAbsolute(test_path, .{});
    dir.close();
}

test "mkdir - with -p succeeds on existing directory" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/existing", .{temp_dir});
    defer std.testing.allocator.free(test_dir);

    try std.fs.makeDirAbsolute(test_dir);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        "-p",
        test_dir,
    });
    defer result.deinit();

    try result.expectSuccess();
}

test "mkdir - with -m sets permissions" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/perms", .{temp_dir});
    defer std.testing.allocator.free(test_dir);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        "-m",
        "755",
        test_dir,
    });
    defer result.deinit();

    try result.expectSuccess();

    var dir = try std.fs.openDirAbsolute(test_dir, .{});
    dir.close();
}

test "mkdir - no arguments fails" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("missing operand");
}

test "mkdir - invalid mode fails" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/badmode", .{temp_dir});
    defer std.testing.allocator.free(test_dir);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/mkdir",
        "-m",
        "999",
        test_dir,
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("invalid mode");
}
