// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for true and false utilities

const std = @import("std");
const helpers = @import("helpers");

test "true - returns exit code 0" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/true",
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "true - ignores arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/true",
        "arg1",
        "arg2",
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "false - returns exit code 1" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/false",
    });
    defer result.deinit();

    try result.expectFailure();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "false - ignores arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/false",
        "arg1",
        "arg2",
    });
    defer result.deinit();

    try result.expectFailure();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}
