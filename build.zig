const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Coreutils da compilare
    const coreutils = [_][]const u8{
        "cat",
        "echo",
        "true",
        "false",
        "pwd",
        "ls",
        "mkdir",
        "touch",
    };

    // Crea moduli comuni per codice condiviso
    const common = b.addModule("common", .{
        .root_source_file = b.path("src/common/posix.zig"),
    });

    const args = b.addModule("args", .{
        .root_source_file = b.path("src/common/args.zig"),
    });

    // Compila ogni utility
    inline for (coreutils) |util| {
        const exe = b.addExecutable(.{
            .name = util,
            .root_source_file = b.path(b.fmt("src/coreutils/{s}.zig", .{util})),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        exe.root_module.addImport("common", common);
        exe.root_module.addImport("args", args);

        // Strip symbols per ridurre dimensione
        exe.root_module.strip = optimize != .Debug;

        b.installArtifact(exe);
    }

    // Test suite di integrazione
    const test_step = b.step("test", "Run integration tests");

    const helpers_mod = b.addModule("helpers", .{
        .root_source_file = b.path("test/helpers.zig"),
    });

    const integration_tests = [_][]const u8{
        "test_echo",
        "test_cat",
        "test_pwd",
        "test_true_false",
        "test_ls",
        "test_mkdir",
        "test_touch",
    };

    inline for (integration_tests) |test_name| {
        const tests = b.addTest(.{
            .name = test_name,
            .root_source_file = b.path(b.fmt("test/integration/{s}.zig", .{test_name})),
            .target = target,
            .optimize = optimize,
        });

        tests.root_module.addImport("helpers", helpers_mod);

        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
}
