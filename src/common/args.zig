const std = @import("std");

/// Iterator per gli argomenti del comando
pub const ArgsIterator = struct {
    inner: std.process.ArgIterator,
    program_name: []const u8,

    pub fn init(allocator: std.mem.Allocator) !ArgsIterator {
        var inner = try std.process.argsWithAllocator(allocator);
        const program_name = inner.next() orelse "";

        return ArgsIterator{
            .inner = inner,
            .program_name = program_name,
        };
    }

    pub fn deinit(self: *ArgsIterator) void {
        self.inner.deinit();
    }

    pub fn next(self: *ArgsIterator) ?[]const u8 {
        return self.inner.next();
    }

    pub fn skip(self: *ArgsIterator) bool {
        return self.inner.skip();
    }
};
