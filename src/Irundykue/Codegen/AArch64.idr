module Irundykue.Codegen.AArch64

import Data.String

-- Placeholder dictionary emitter. It defines `forth_cold_boot`, the symbol
-- that boot.S jumps to, so that the kernel links and boots.
--
-- Console: the PL011 UART of the QEMU virt machine (0x09000000).
--
-- Inserted file: forth_file_Insert.bash places an image at SYRY_INPUT_ADDR
-- through QEMU's generic loader. The image is
--
--     offset  0   8 bytes   magic "SYRYIN01"
--     offset  8   8 bytes   payload length, little endian
--     offset 16   n bytes   payload (Forth source text)
--
-- This stub only echoes the payload to the UART and then powers the machine
-- off through PSCI SYSTEM_OFF (HVC conduit on a virt machine without
-- virtualization), so that QEMU exits with status 0. Without an image it parks
-- in a WFE loop. The outer interpreter will consume the same buffer later.
--
-- The constants below must match forth_file_Insert.bash.

export
dictionaryAsm : String
dictionaryAsm = unlines
  [ "// Placeholder dictionary emitted by irundykue-gen."
  , "    .equ    UART0,            0x09000000"
  , "    .equ    SYRY_INPUT_ADDR,  0x41000000"
  , "    .equ    SYRY_INPUT_MAX,   0x100000"
  , "    .equ    PSCI_SYSTEM_OFF,  0x84000008"
  , ""
  , "    .global forth_cold_boot"
  , "    .text"
  , "forth_cold_boot:"
  , "    ldr     x1, =UART0"
  , "    adr     x2, banner"
  , "    bl      puts"
  , "    mrs     x4, CurrentEL"
  , "    lsr     x4, x4, #2"
  , "    add     w4, w4, #48"
  , "    strb    w4, [x1]"
  , "    mov     w4, #10"
  , "    strb    w4, [x1]"
  , ""
  , "    // Look for an inserted file: magic, length, payload."
  , "    ldr     x5, =SYRY_INPUT_ADDR"
  , "    ldr     x6, [x5]"
  , "    ldr     x7, =0x31304e4959525953"
  , "    cmp     x6, x7"
  , "    b.ne    park"
  , "    ldr     x8, [x5, #8]"
  , "    ldr     x9, =SYRY_INPUT_MAX"
  , "    cmp     x8, x9"
  , "    b.ls    echo"
  , "    adr     x2, too_large"
  , "    bl      puts"
  , "    b       park"
  , ""
  , "echo:"
  , "    add     x10, x5, #16"
  , "echo_loop:"
  , "    cbz     x8, echo_done"
  , "    ldrb    w3, [x10], #1"
  , "    strb    w3, [x1]"
  , "    sub     x8, x8, #1"
  , "    b       echo_loop"
  , "echo_done:"
  , "    ldr     x0, =PSCI_SYSTEM_OFF"
  , "    hvc     #0"
  , ""
  , "park:"
  , "    wfe"
  , "    b       park"
  , ""
  , "// puts: write the NUL-terminated string at x2 to the UART at x1."
  , "puts:"
  , "    ldrb    w3, [x2], #1"
  , "    cbz     w3, puts_done"
  , "    strb    w3, [x1]"
  , "    b       puts"
  , "puts_done:"
  , "    ret"
  , ""
  , "banner:"
  , "    .asciz  \"irundykue-syry: cold boot at EL\""
  , "too_large:"
  , "    .asciz  \"input: image too large\\n\""
  ]