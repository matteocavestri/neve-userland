// SPDX-License-Identifier: GPL-3.0-or-later
//
// Copyright (C) 2024 Matteo Cavestri
//
// POSIX-compliant false utility - always exits with failure
// Conforms to POSIX.1-2017

const std = @import("std");
const common = @import("common");

/// The false utility returns with a non-zero exit code.
/// Per POSIX: ignores all arguments, produces no output, always fails.
pub fn main() noreturn {
    // POSIX requirement: always exit with status 1
    // No error handling needed - this utility always fails by design
    std.process.exit(@intFromEnum(common.ExitCode.failure));
}
