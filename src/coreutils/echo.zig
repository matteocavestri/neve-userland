// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2025 Matteo Cavestri
//
// POSIX-compliant echo utility - write arguments to standard output
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");
const args_mod = @import("args");

/// Write arguments to standard output, separated by spaces and followed by a newline.
/// Per POSIX: supports -n flag to suppress the trailing newline.
/// Note: POSIX echo does NOT interpret backslash escapes by default.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try args_mod.ArgsIterator.init(allocator);
    defer args.deinit();

    const stdout = std.io.getStdOut().writer();
    var print_newline = true;

    // Collect all arguments
    var arg_list = std.ArrayList([]const u8).init(allocator);
    defer arg_list.deinit();

    while (args.next()) |arg| {
        try arg_list.append(arg);
    }

    // Check if first argument is -n (suppress newline)
    var start_idx: usize = 0;
    if (arg_list.items.len > 0 and std.mem.eql(u8, arg_list.items[0], "-n")) {
        print_newline = false;
        start_idx = 1;
    }

    // Print remaining arguments separated by spaces
    for (arg_list.items[start_idx..], 0..) |arg, i| {
        if (i > 0) {
            stdout.writeByte(' ') catch |err| {
                handleWriteError(err);
                return;
            };
        }
        stdout.writeAll(arg) catch |err| {
            handleWriteError(err);
            return;
        };
    }

    if (print_newline) {
        stdout.writeByte('\n') catch |err| {
            handleWriteError(err);
            return;
        };
    }
}

/// Handle write errors, with special handling for broken pipe
fn handleWriteError(err: anyerror) void {
    // POSIX behavior: exit silently on broken pipe
    if (err == error.BrokenPipe) {
        return;
    }

    const msg = switch (err) {
        error.NoSpaceLeft => "no space left on device",
        error.InputOutput => "input/output error",
        error.AccessDenied => "permission denied",
        else => @errorName(err),
    };
    common.printError("echo: write error: {s}\n", .{msg});
}
