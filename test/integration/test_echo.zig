// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for echo utility

const std = @import("std");
const helpers = @import("helpers");

test "echo - no arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("\n");
}

test "echo - single argument" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "hello",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("hello\n");
}

test "echo - multiple arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "hello",
        "world",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("hello world\n");
}

test "echo - flag -n suppresses newline" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "-n",
        "hello",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("hello");
}

test "echo - flag -n with multiple arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "-n",
        "hello",
        "world",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("hello world");
}

test "echo - treats -n as text if not first" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "hello",
        "-n",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("hello -n\n");
}

test "echo - empty string" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("\n");
}

test "echo - special characters" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/echo",
        "!@#$%^&*()",
    });
    defer result.deinit();

    try result.expectSuccess();
    try result.expectStdout("!@#$%^&*()\n");
}
