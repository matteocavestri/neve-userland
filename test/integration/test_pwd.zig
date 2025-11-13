// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024 Matteo Cavestri
//
// Integration tests for pwd utility

const std = @import("std");
const helpers = @import("helpers");

test "pwd - prints current directory" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/pwd",
    });
    defer result.deinit();

    try result.expectSuccess();

    const cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(cwd);

    const expected = try std.fmt.allocPrint(std.testing.allocator, "{s}\n", .{cwd});
    defer std.testing.allocator.free(expected);

    try result.expectStdout(expected);
}

test "pwd - output is absolute path" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/pwd",
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expectEqual(@as(u8, '/'), result.stdout[0]);
}

test "pwd - ignores arguments" {
    var result = try helpers.runCommand(std.testing.allocator, &[_][]const u8{
        helpers.BIN_DIR ++ "/pwd",
        "ignored_arg",
    });
    defer result.deinit();

    try result.expectSuccess();
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expectEqual(@as(u8, '/'), result.stdout[0]);
}
