module Irundykue.Codegen.AArch64

-- Placeholder dictionary emitter. It defines `forth_cold_boot`, the symbol
-- that boot.S jumps to, so that the kernel links and boots. The banner and
-- the current exception level are written to the PL011 UART of the QEMU
-- virt machine (0x09000000); the core then parks in a WFE loop. The real
-- dictionary and inner interpreter will replace this text.

export
dictionaryAsm : String
dictionaryAsm = unlines
  [ "// Placeholder dictionary emitted by irundykue-gen."
  , "    .global forth_cold_boot"
  , "    .text"
  , "forth_cold_boot:"
  , "    mov     x1, #0x09000000"
  , "    adr     x2, banner"
  , "1:  ldrb    w3, [x2], #1"
  , "    cbz     w3, 2f"
  , "    strb    w3, [x1]"
  , "    b       1b"
  , "2:  mrs     x4, CurrentEL"
  , "    lsr     x4, x4, #2"
  , "    add     w4, w4, #48"
  , "    strb    w4, [x1]"
  , "    mov     w4, #10"
  , "    strb    w4, [x1]"
  , "3:  wfe"
  , "    b       3b"
  , "banner:"
  , "    .asciz  \"irundykue-syry: cold boot at EL\""
  ]
