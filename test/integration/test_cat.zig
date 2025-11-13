// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for cat utility

const std = @import("std");
const helpers = @import("helpers");

test "cat - single file" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/cat",
        "test/fixtures/file1.txt",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdoutContains("Hello from file1");
}

test "cat - multiple files" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/cat",
        "test/fixtures/file1.txt",
        "test/fixtures/file2.txt",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdoutContains("Hello from file1");
    try result.expectStdoutContains("Hello from file2");
}

test "cat - stdin" {
    const input = "test input from stdin\n";
    var result = try helpers.runCommandWithStdin(
        std.testing.allocator,
        &[_][]const u8{helpers.BIN_DIR ++ "/cat"},
        input,
    );
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("test input from stdin\n");
}

test "cat - dash for stdin" {
    const input = "reading from stdin\n";
    var result = try helpers.runCommandWithStdin(
        std.testing.allocator,
        &[_][]const u8{ helpers.BIN_DIR ++ "/cat", "-" },
        input,
    );
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("reading from stdin\n");
}

test "cat - nonexistent file" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/cat",
        "/tmp/nonexistent_file_xyz_12345.txt",
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStderrContains("No such file or directory");
}

test "cat - multiple files with error" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/cat",
        "test/fixtures/file1.txt",
        "/tmp/nonexistent_xyz.txt",
        "test/fixtures/file2.txt",
    });
    defer result.deinit();

    try result.expectFailure();
    try result.expectStdoutContains("Hello from file1");
    try result.expectStderrContains("No such file or directory");
}

test "cat - empty file" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/cat",
        "test/fixtures/empty.txt",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("");
}

test "cat - mix file and stdin" {
    const input = "stdin content\n";
    var result = try helpers.runCommandWithStdin(
        std.testing.allocator,
        &[_][]const u8{
            helpers.BIN_DIR ++ "/cat",
            "test/fixtures/file1.txt",
            "-",
        },
        input,
    );
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdoutContains("Hello from file1");
    try result.expectStdoutContains("stdin content");
}

test "cat - no arguments reads stdin" {
    const input = "implicit stdin\n";
    var result = try helpers.runCommandWithStdin(
        std.testing.allocator,
        &[_][]const u8{helpers.BIN_DIR ++ "/cat"},
        input,
    );
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("implicit stdin\n");
}
