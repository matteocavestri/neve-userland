// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for touch utility

const std = @import("std");
const helpers = @import("helpers");

test "touch - create new file" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/newfile.txt", .{temp_dir});
    defer std.testing.allocator.free(test_file);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
        test_file,
    });
    defer result.deinit();

    try result.expectSuccess();

    var file = try std.fs.openFileAbsolute(test_file, .{});
    file.close();
}

test "touch - create multiple files" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const file1 = try std.fmt.allocPrint(std.testing.allocator, "{s}/file1.txt", .{temp_dir});
    defer std.testing.allocator.free(file1);

    const file2 = try std.fmt.allocPrint(std.testing.allocator, "{s}/file2.txt", .{temp_dir});
    defer std.testing.allocator.free(file2);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
        file1,
        file2,
    });
    defer result.deinit();

    try result.expectSuccess();

    var f1 = try std.fs.openFileAbsolute(file1, .{});
    f1.close();

    var f2 = try std.fs.openFileAbsolute(file2, .{});
    f2.close();
}

test "touch - update existing file" {
    const temp_file = try helpers.createTempFile(std.testing.allocator, "existing content");
    defer helpers.cleanupTempFile(temp_file, std.testing.allocator);

    std.time.sleep(std.time.ns_per_ms * 10);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
        temp_file,
    });
    defer result.deinit();

    try result.expectSuccess();

    var file = try std.fs.openFileAbsolute(temp_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expectEqualStrings("existing content", content);
}

test "touch - with -c does not create file" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const nonexistent = try std.fmt.allocPrint(std.testing.allocator, "{s}/nonexistent.txt", .{temp_dir});
    defer std.testing.allocator.free(nonexistent);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
        "-c",
        nonexistent,
    });
    defer result.deinit();

    try result.expectSuccess();

    const file_exists = blk: {
        var file = std.fs.openFileAbsolute(nonexistent, .{}) catch {
            break :blk false;
        };
        file.close();
        break :blk true;
    };

    try std.testing.expect(!file_exists);
}

test "touch - no arguments fails" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("missing file operand");
}

test "touch - creates empty file" {
    const temp_dir = try helpers.createTempDir(std.testing.allocator);
    defer helpers.cleanupTempDir(temp_dir, std.testing.allocator);

    const test_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/empty.txt", .{temp_dir});
    defer std.testing.allocator.free(test_file);

    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/touch",
        test_file,
    });
    defer result.deinit();

    try result.expectSuccess();

    var file = try std.fs.openFileAbsolute(test_file, .{});
    defer file.close();

    const stat = try file.stat();
    try std.testing.expectEqual(@as(u64, 0), stat.size);
}
