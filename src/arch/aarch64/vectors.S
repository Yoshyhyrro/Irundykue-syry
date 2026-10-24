// vectors.S - EL1 exception vector table and the Ext^1 recovery handler.
//
// VBAR_EL1 requires 2 KiB alignment. The table holds 16 entries of 128 bytes
// each, grouped by the source of the exception:
//
//   0x000  Current EL with SP_EL0
//   0x200  Current EL with SP_ELx
//   0x400  Lower EL, AArch64
//   0x600  Lower EL, AArch32
//
// Within each group the entries are: Synchronous, IRQ, FIQ, SError.
//
// Register convention for recovery:
//   x28  Recovery token installed by CO-EXECUTE (address of xt2), or 0.
//   x0   On entry to xt2: ESR_EL1 value, used as the Ext^1 residue token.

    .global el1_vector_table

    .macro vector_entry handler
    .balign 128
    b       \handler
    .endm

    .section .text.vectors, "ax"
    .balign 2048
el1_vector_table:
    // Current EL with SP_EL0
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception

    // Current EL with SP_ELx
    vector_entry sync_handler
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception

    // Lower EL, AArch64
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception

    // Lower EL, AArch32
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception
    vector_entry unhandled_exception

    .balign 4
sync_handler:
    // Read the Exception Syndrome Register to identify the cause.
    mrs     x1, esr_el1

    // Without an active recovery token the fault cannot be resolved.
    cbz     x28, fatal_crash

    // Pass the ESR_EL1 value to xt2 as the Ext^1 residue token in x0.
    // ERET resumes at ELR_EL1, so the recovery token is installed there.
    // The token is cleared so that a nested fault is treated as fatal.
    mov     x0, x1
    msr     elr_el1, x28
    mov     x28, #0
    eret

unhandled_exception:
    b       fatal_crash

fatal_crash:
    wfe
    b       fatal_crash
