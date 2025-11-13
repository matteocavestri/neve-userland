// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2024 Matteo Cavestri
//
// POSIX-compliant true utility - always exits successfully
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");

/// The true utility returns with exit code zero.
/// Per POSIX: ignores all arguments, produces no output, always succeeds.
pub fn main() noreturn {
    // POSIX requirement: always exit with status 0
    // No error handling needed - this utility cannot fail
    std.process.exit(@intFromEnum(common.ExitCode.success));
}
