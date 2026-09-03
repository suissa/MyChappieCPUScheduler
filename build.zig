const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "mychappie-cpu-scheduler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the scheduler example");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = root_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all scheduler tests");
    test_step.dependOn(&run_tests.step);

    const action_abi_module = b.createModule(.{
        .root_source_file = b.path("src/action_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const crypto_common_module = b.createModule(.{
        .root_source_file = b.path("actions/crypto_common.zig"),
        .target = target,
        .optimize = optimize,
    });
    crypto_common_module.addImport("action_abi", action_abi_module);

    const unknown_module = b.createModule(.{
        .root_source_file = b.path("actions/crypto-unknown/action.zig"),
        .target = target,
        .optimize = optimize,
    });
    unknown_module.addImport("action_abi", action_abi_module);
    unknown_module.addImport("crypto_common", crypto_common_module);
    const unknown_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "allas_crypto_unknown",
        .root_module = unknown_module,
    });
    b.installArtifact(unknown_lib);

    const known_module = b.createModule(.{
        .root_source_file = b.path("actions/crypto-known/action.zig"),
        .target = target,
        .optimize = optimize,
    });
    known_module.addImport("action_abi", action_abi_module);
    known_module.addImport("crypto_common", crypto_common_module);
    const known_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "allas_crypto_known",
        .root_module = known_module,
    });
    b.installArtifact(known_lib);

    const worker = b.addExecutable(.{
        .name = "action-worker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/action_worker.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(worker);

    const verifier = b.addExecutable(.{
        .name = "distributed-verifier",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/distributed_verify.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(verifier);

    const action_demo = b.addExecutable(.{
        .name = "dynamic-action-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/action_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_action_demo = b.addRunArtifact(action_demo);
    run_action_demo.addArtifactArg(unknown_lib);
    run_action_demo.addArtifactArg(known_lib);
    const action_test_step = b.step("action-test", "Load dynamic Actions, measure them and validate UNKNOWN/KNOWN distributed equivalence");
    action_test_step.dependOn(&run_action_demo.step);
}
