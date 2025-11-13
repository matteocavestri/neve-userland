// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2024 Matteo Cavestri
//
// POSIX-compliant pwd utility - print working directory
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");

/// Print the absolute pathname of the current working directory to stdout.
/// Per POSIX: outputs the current directory followed by a newline.
/// Exit status: 0 on success, non-zero on error.
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get current working directory
    const cwd = std.process.getCwdAlloc(allocator) catch |err| {
        handleGetCwdError(err);
        return @intFromEnum(common.ExitCode.failure);
    };
    defer allocator.free(cwd);

    // Validate path (should be absolute)
    if (cwd.len == 0 or cwd[0] != '/') {
        common.printError("pwd: invalid current directory\n", .{});
        return @intFromEnum(common.ExitCode.failure);
    }

    // Write to stdout with newline
    const stdout = std.io.getStdOut().writer();
    stdout.print("{s}\n", .{cwd}) catch |err| {
        handleWriteError(err);
        return @intFromEnum(common.ExitCode.failure);
    };

    return @intFromEnum(common.ExitCode.success);
}

/// Handle errors when getting current working directory
fn handleGetCwdError(err: anyerror) void {
    const msg = switch (err) {
        error.OutOfMemory => "out of memory",
        error.NameTooLong => "current directory path too long",
        error.CurrentWorkingDirectoryUnlinked => "current directory has been unlinked",
        else => @errorName(err),
    };
        common.printError("pwd: cannot get current directory: {s}\n", .{msg});
}

/// Handle errors when writing to stdout
fn handleWriteError(err: anyerror) void {
    const msg = switch (err) {
        error.BrokenPipe => return, // Silent on broken pipe (POSIX behavior)
        error.NoSpaceLeft => "no space left on device",
        error.InputOutput => "input/output error",
        else => @errorName(err),
    };
        common.printError("pwd: write error: {s}\n", .{msg});
}
