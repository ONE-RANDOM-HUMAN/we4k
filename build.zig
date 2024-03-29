const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const optimise = b.standardOptimizeOption(.{});

    const asm_ = b.addObject(.{
    	.name = "asm",
    	.root_source_file = .{ .path = "src/asm/combined.o" },
    	.target = target,
    	.optimize = optimise,
    });

    const exe = b.addExecutable(.{
    	.name = "we4k",
    	.root_source_file = .{ .path = "src/main.zig" },
    	.target = target,
    	.optimize = optimise,
    });

    exe.want_lto = true;
    exe.addObject(asm_);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
    	.name = "we4k",
    	.root_source_file = .{ .path = "src/main.zig" },
    	.target = target,
    	.optimize = optimise,
    });
    exe_tests.optimize = optimise;
    exe_tests.addObject(asm_);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
