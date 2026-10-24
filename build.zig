const std = @import("std");

// CPU features requested for the kernel. Names are resolved at compile time
// so that one build.zig works across Zig releases: pauth replaced
// paca / pacg, and tme is absent from newer toolchains. Features that
// the running Zig does not know are skipped.
const wanted_cpu_features = [_][]const u8{ "sve2", "pauth", "paca", "pacg", "tme" };

pub fn build(b: *std.Build) void {
    const cpu_features = comptime blk: {
        const Feature = std.Target.aarch64.Feature;
        var found: [wanted_cpu_features.len]Feature = undefined;
        var count: usize = 0;
        for (wanted_cpu_features) |name| {
            if (@hasField(Feature, name)) {
                found[count] = @field(Feature, name);
                count += 1;
            }
        }
        break :blk found[0..count].*;
    };

    // ObjCopy renamed its format enum (RawFormat to Format) and the raw
    // binary member (bin to binary) between Zig releases.
    const ObjCopyFormat = if (@hasDecl(std.Build.Step.ObjCopy, "Format"))
        std.Build.Step.ObjCopy.Format
    else
        std.Build.Step.ObjCopy.RawFormat;
    const objcopy_format = @field(ObjCopyFormat, if (@hasField(ObjCopyFormat, "binary")) "binary" else "bin");

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.aarch64.featureSet(&cpu_features),
    });

    const optimize = b.standardOptimizeOption(.{});

    // Step 1: Run the Idris 2 compiler to generate the Forth dictionary assembly
    const run_idris_pkg = b.addSystemCommand(&[_][]const u8{
        "idris2",
        "--build",
        "irundykue.ipkg",
    });

    const run_gen = b.addSystemCommand(&[_][]const u8{
        "./build/exec/irundykue-gen",
        "--emit-asm",
        "generated/forth_dict.S",
    });
    run_gen.step.dependOn(&run_idris_pkg.step);

    // Step 2: Build the Bare-Metal AArch64 ELF kernel
    const kernel_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .strip = false,
    });
    kernel_module.addAssemblyFile(b.path("src/arch/aarch64/boot.S"));
    kernel_module.addAssemblyFile(b.path("src/arch/aarch64/vectors.S"));
    kernel_module.addAssemblyFile(b.path("generated/forth_dict.S"));

    const elf = b.addExecutable(.{
        .name = "irundykue-syry.elf",
        .root_module = kernel_module,
    });
    elf.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));

    elf.step.dependOn(&run_gen.step);
    b.installArtifact(elf);

    // Step 3: Emit raw flat binary for QEMU / Bare-metal flash
    const bin = b.addObjCopy(elf.getEmittedBin(), .{
        .format = objcopy_format,
    });
    const install_bin = b.addInstallBinFile(bin.getOutput(), "irundykue-syry.bin");
    b.getInstallStep().dependOn(&install_bin.step);

    // Step 4: Run target in QEMU virt machine. Without virtualization=on the
    // kernel is entered at EL1, which is what boot.S expects.
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-aarch64",
        "-M", "virt",
        "-cpu", "max",
        "-smp", "4",
        "-m", "512M",
        "-nographic",
        "-kernel",
    });
    qemu_cmd.addArtifactArg(elf);

    const run_step = b.step("run", "Run bare-metal kernel in QEMU");
    run_step.dependOn(&qemu_cmd.step);
}
