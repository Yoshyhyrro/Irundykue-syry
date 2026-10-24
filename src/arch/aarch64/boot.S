// boot.S - Reset entry point.
//
// Expects the following symbols from other translation units:
//   el1_vector_table  (vectors.S)
//   forth_cold_boot   (generated/forth_dict.S)
//   __forth_dstack_top, __forth_rstack_top (linker.ld)

    .global _start
    .section .text.boot

_start:
    // Disable interrupts at EL1
    msr daifset, #0xf

    // Configure CPACR_EL1 to enable FP, ASIMD, and SVE/SVE2 without trapping
    mrs x0, cpacr_el1
    mov x1, #(0x3 << 20)      // FPEN bits: do not trap FP/SIMD
    mov x2, #(0x3 << 16)      // ZEN bits: do not trap SVE/SVE2
    orr x0, x0, x1
    orr x0, x0, x2
    msr cpacr_el1, x0
    isb

    // Initialize Exception Vector Base (for singularity handling)
    ldr x0, =el1_vector_table
    msr vbar_el1, x0
    isb

    // Setup initial stacks
    // SP_EL0: Forth Data Stack
    // SP_EL1: Return Stack / Hardware Exception Stack
    ldr x0, =__forth_dstack_top
    msr sp_el0, x0

    ldr x0, =__forth_rstack_top
    mov sp, x0

    // Jump to the Forth inner interpreter entry point
    ldr x20, =forth_cold_boot
    br  x20
