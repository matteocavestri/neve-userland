// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2025 Matteo Cavestri
//
// POSIX-compliant cat utility - concatenate and print files
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");
const args_mod = @import("args");

const BUFFER_SIZE = 16384; // Optimized buffer size (16KB)

/// Concatenate files and print on standard output.
/// Per POSIX: reads files sequentially, writing to stdout.
/// If no files specified or file is "-", reads from stdin.
/// Continues processing remaining files even if one fails.
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try args_mod.ArgsIterator.init(allocator);
    defer args.deinit();

    const stdout = std.io.getStdOut().writer();
    var has_files = false;
    var had_error = false;

    // Process each file argument
    while (args.next()) |arg| {
        // Validate argument
        if (arg.len == 0) {
            common.printError("cat: invalid empty file name\n", .{});
            had_error = true;
            continue;
        }

        has_files = true;

        if (std.mem.eql(u8, arg, "-")) {
            // Read from stdin
            catStream(std.io.getStdIn().reader(), stdout) catch |err| {
                handleStreamError("stdin", err);
                had_error = true;
                continue;
            };
        } else {
            // Open and read file
            const file = std.fs.cwd().openFile(arg, .{}) catch |err| {
                handleFileError(arg, err);
                had_error = true;
                continue;
            };
            defer file.close();

            catStream(file.reader(), stdout) catch |err| {
                handleStreamError(arg, err);
                had_error = true;
                continue;
            };
        }
    }

    // POSIX: if no files specified, read from stdin
    if (!has_files) {
        catStream(std.io.getStdIn().reader(), stdout) catch |err| {
            handleStreamError("stdin", err);
            return @intFromEnum(common.ExitCode.failure);
        };
    }

    return if (had_error)
        @intFromEnum(common.ExitCode.failure)
    else
        @intFromEnum(common.ExitCode.success);
}

/// Copy all data from reader to writer in chunks
fn catStream(reader: anytype, writer: anytype) !void {
    var buffer: [BUFFER_SIZE]u8 = undefined;

    while (true) {
        const bytes_read = reader.read(&buffer) catch |err| {
            return err;
        };
        if (bytes_read == 0) break;

        writer.writeAll(buffer[0..bytes_read]) catch |err| {
            // Handle SIGPIPE gracefully (broken pipe)
            if (err == error.BrokenPipe) {
                return; // Exit silently on broken pipe (POSIX behavior)
            }
            return err;
        };
    }
}

/// Handle file opening errors with specific messages
fn handleFileError(path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.IsDir => "Is a directory",
        error.NameTooLong => "File name too long",
        error.SystemResources => "Too many open files",
        error.ProcessFdQuotaExceeded => "Too many open files",
        error.InvalidUtf8 => "Invalid file name encoding",
        error.NoDevice => "No such device",
        error.DeviceBusy => "Device or resource busy",
        else => @errorName(err),
    };
    common.printError("cat: {s}: {s}\n", .{ path, msg });
}

/// Handle stream I/O errors with specific messages
fn handleStreamError(path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.InputOutput => "Input/output error",
        error.BrokenPipe => return, // Silent on broken pipe
        error.NoSpaceLeft => "No space left on device",
        error.AccessDenied => "Permission denied",
        error.WouldBlock => "Resource temporarily unavailable",
        error.ConnectionResetByPeer => "Connection reset by peer",
        error.OutOfMemory => "Out of memory",
        else => @errorName(err),
    };
    common.printError("cat: {s}: {s}\n", .{ path, msg });
}
