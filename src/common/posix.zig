const std = @import("std");
const builtin = @import("builtin");

/// Exit codes POSIX standard
pub const ExitCode = enum(u8) {
    success = 0,
    failure = 1,
    usage_error = 2,
    _,

    pub fn fromError(err: anyerror) ExitCode {
        return switch (err) {
            error.InvalidArgument => .usage_error,
            else => .failure,
        };
    }
};

/// Scrive su stdout
pub fn writeStdout(bytes: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(bytes);
}

/// Scrive su stderr
pub fn writeStderr(bytes: []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(bytes);
}

/// Stampa un messaggio di errore formattato
pub fn printError(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt, args) catch {};
}

/// Stampa usage ed esce
pub fn printUsageAndExit(program_name: []const u8, usage: []const u8, exit_code: ExitCode) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("Usage: {s} {s}\n", .{ program_name, usage }) catch {};
    std.process.exit(@intFromEnum(exit_code));
}
