#!/usr/bin/env bash
#
# init.bash - Initialize the Irundykue-syry repository layout.
#
# Creates the directory tree, build files, bare-metal AArch64 sources and the
# Idris 2 package skeleton. Existing files are never overwritten unless
# --force is given, so the script is safe to re-run.
#
# Usage: ./init.bash [--dir PATH] [--force] [--no-git] [--help]

set -euo pipefail

readonly PROJECT_NAME="Irundykue-syry"
readonly PACKAGE_NAME="irundykue"

TARGET_DIR="."
FORCE=0
INIT_GIT=1
CREATED=0
SKIPPED=0
MISSING=0
TMP_FILE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<__USAGE__
Usage: ${0##*/} [options]

Initialize the ${PROJECT_NAME} repository layout.

Options:
  -d, --dir PATH   Target directory (default: current directory)
  -f, --force      Overwrite files that already exist
      --no-git     Do not run "git init"
  -h, --help       Show this help and exit
__USAGE__
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_FILE}" ]]; then
    rm -f "${TMP_FILE}"
  fi
  return 0
}
trap cleanup EXIT

# write_file RELATIVE_PATH
#   Reads the file body from standard input and writes it below TARGET_DIR.
#   An existing file is kept unless --force was given.
write_file() {
  local rel="$1"
  local path="${TARGET_DIR}/${rel}"
  local action="create"

  if [[ -e "${path}" ]]; then
    if (( FORCE )); then
      action="overwrite"
    else
      cat >/dev/null
      printf '  %-10s %s\n' "skip" "${rel}"
      SKIPPED=$(( SKIPPED + 1 ))
      return 0
    fi
  fi

  mkdir -p "$(dirname "${path}")"
  TMP_FILE="$(mktemp "${path}.XXXXXX")"
  cat >"${TMP_FILE}"
  chmod 0644 "${TMP_FILE}"
  mv -f "${TMP_FILE}" "${path}"
  TMP_FILE=""

  printf '  %-10s %s\n' "${action}" "${rel}"
  CREATED=$(( CREATED + 1 ))
}

check_tool() {
  local tool="$1"
  local hint="$2"
  if command -v "${tool}" >/dev/null 2>&1; then
    printf '  %-22s found (%s)\n' "${tool}" "$(command -v "${tool}")"
  else
    printf '  %-22s MISSING - %s\n' "${tool}" "${hint}"
    MISSING=$(( MISSING + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while (( $# )); do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      TARGET_DIR="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --no-git)
      INIT_GIT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

mkdir -p "${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

printf 'Initializing %s in %s\n\n' "${PROJECT_NAME}" "${TARGET_DIR}"

# ---------------------------------------------------------------------------
# Repository metadata
# ---------------------------------------------------------------------------

write_file ".gitignore" <<'__GITIGNORE__'
# Idris 2 build products
/build/
*.ttc
*.ttm

# Zig build products
/zig-out/
/.zig-cache/
/zig-cache/

# Assembly emitted by irundykue-gen
/generated/*
!/generated/.gitkeep

# Local artifacts
*.elf
*.bin
*.o
*.log

# Editors and operating systems
.DS_Store
.vscode/
.idea/
*.swp
__GITIGNORE__

write_file ".gitattributes" <<'__GITATTRIBUTES__'
* text=auto eol=lf
*.S linguist-language=Assembly
*.ld linguist-language=Linker-Script
__GITATTRIBUTES__

write_file ".editorconfig" <<'__EDITORCONFIG__'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.{S,ld,zig}]
indent_size = 4

[*.md]
trim_trailing_whitespace = false
__EDITORCONFIG__

write_file "README.md" <<'__README__'
# Irundykue-syry

A Forth 2012 compatible dialect for Armv8-A / Armv9-A, generated from an
Idris 2 front end that type-checks stack discipline, `Ext^1` singularity
recovery and four-dimensional orthogonal-stack quantization at compile time.

## Pipeline

```
[ Idris 2 (irundykue.ipkg) ]
        |  type-checks stack depth, Ext^1 recovery, 4-dim quantization
        v
[ irundykue-gen (host executable) ]
        |  emits AArch64 assembly: dictionary and Forth words
        v
[ Zig build system (build.zig) ]
        |-- assembles boot.S and vectors.S (EL1 setup, SVE2/PAC, vectors)
        |-- assembles the emitted dictionary (generated/forth_dict.S)
        '-- links with linker.ld for aarch64-freestanding
        v
[ irundykue-syry.elf / .bin (bare-metal AArch64 kernel) ]
        |
        v
[ QEMU virt machine ]
```

## Prerequisites

| Tool                  | Purpose                              |
|-----------------------|--------------------------------------|
| `idris2`              | Front end and host-side generator    |
| a C compiler          | Required by the `refc` Idris backend |
| `zig`                 | Cross assembler, linker, build driver |
| `qemu-system-aarch64` | Running the kernel image             |

## Build

```sh
idris2 --build irundykue.ipkg   # produces build/exec/irundykue-gen
zig build                       # runs the generator, links the kernel
zig build run                   # boots the kernel in QEMU
```

## Layout

```
irundykue.ipkg                    Idris 2 package description
build.zig                         Zig build graph
src/Main.idr                      Generator entry point (prototype AST lives here for now)
src/Irundykue/AST.idr             Indexed Forth AST (planned home)
src/Irundykue/Codegen/AArch64.idr AArch64 assembly emission
src/Irundykue/Types/Singularity.idr  Type-level singularity machinery
src/arch/aarch64/boot.S           Reset entry: CPACR_EL1, VBAR_EL1, stacks
src/arch/aarch64/vectors.S        EL1 exception vector table and recovery handler
src/arch/aarch64/linker.ld        Memory map for the QEMU virt machine
generated/                        Output of irundykue-gen (git-ignored)
docs/                             Design notes and references
test/                             Tests
```
__README__

write_file "docs/REFERENCES.md" <<'__REFERENCES__'
# References

## Upstream material

- Repository: <https://github.com/Yoshyhyrro/hatsu-yakitori>
- Branch: `feature/sedenion_bridge_Agda`
- `dist-proof/Agda/src/CayleyDicksonQuiver/AbelianCurse/SecondOperatorLemmas.agda`
- `dist-proof/Agda/note/AbelianCurseHypotheses.lagda.md`
- Not yet reviewed: `dist-proof/Agda/note/CarabinerHypotheses.lagda.md`
  (cross-referenced upstream for H8, the left-multiplication matrix `L_x` of a
  sedenion seed, whose kernel is the set of zero-divisor partners).

Upstream describes itself as exploratory notes rather than proofs: each Agda
file proves only a small concrete instance, and no single uniform second
operator `S` is claimed across instances. This project inherits that caution.

## Upstream vocabulary

- Coarse map `U` loses information: there are `x != y` with `U x = U y`.
- Second operator `S` recovers what `U` loses.
- Invariance half: `S` is unchanged by the lost "noise". Proved once for
  cokernel-shaped constructions (Lemma 2, and Lemma 2' modulo `d`).
- Completeness half: `S` is unchanged only by the noise. Still proved per
  instance (for example `S-ext-complete`).

## Status legend

- Grounded: derived from a checked upstream statement.
- Analogy: shared shape or name, but no checked upstream statement.
- Open: no upstream counterpart.

## Correspondence table

| Forth construct | Upstream artifact | Status | Notes |
|-----------------|-------------------|--------|-------|
| `CoExecute xt1 xt2` | AC10 `HeisenbergSeedRelations`: `f = L_u`, `g = L_v`, `f^2 = g^2 = -N`, `fg + gf = 0`. AC6 `Ext1Extraction`: coarse map `U`, second operator `S`. | Analogy | The Idris type only forces both branches to end at the same stack depth. Neither the invariance half (`S-ext-invariant-under-all-coboundaries`) nor the completeness half (`S-ext-complete`) has a type-level counterpart yet. |
| `Ext1` and the residue slot | AC6 and AC7 (`Ext1Extraction`, `Ext1Torsion`): `Ext^1 = coker T`, `T(X) = X B - A X`. | Analogy | The upstream residue is a cokernel class, not a machine word. Using `ESR_EL1` as the residue token is a design choice with no upstream statement. |
| One residue level, no `Ext2` | "Is there room for Ext^1 and Ext^2 to separate?", item 1: one operator on Z-free modules gives `Ext^2 = 0`. | Consistent | A second residue level would only be motivated by item 2 (two commuting operators, AC8 `KoszulToy`). |
| "Koszul Complex" comment on `CoExecute` | AC8 `KoszulToy`: the complex `Z -> Z^2 -> Z` for two commuting operators. | Mismatch | The `L_u`, `L_v` of AC10 anticommute, which is the Clifford relation, not the commuting setting of AC8. Consider rewording the comment in `Main.idr`. |
| `ToOrtho` / `FromOrtho`, exactly 4 slots | AC10 `CliffordContraction`: `Cl_N(2)` has basis `1, X, Y, Z = XY`. | Plausible source | Upstream states no quantization theorem. The number 4 matches `dim Cl_N(2) = 2^2`; verify before citing it as a proof. |
| `ClContract` | AC10 `CliffordContraction`: weight grading `mul-scale`, Heisenberg relations at `N = 0` or modulo a prime dividing `N` (`bracket-descends-at-0`, `bracket-drift-divisible`). | Name only | "Contraction" appears upstream only as a module name. `ClContract` has an identity stack effect and no defined semantics yet. |
| `TxBegin` / `TxEnd` | AC10: integral Heisenberg group `H` (`commutator-formula`, `even-central-is-commutator`; the loss is `[H,H] = {1 + 2kZ}`). | Name only | Upstream says nothing about transactions or non-nesting. The `Bool` flag is an implementation discipline. |
| `Div` by zero as a singularity | None. Upstream lists the link to Cayley-Dickson zero divisors as open. `CarabinerHypotheses` H8 is the likely place to look. | Open | AArch64 `SDIV` and `UDIV` return 0 on a zero divisor without raising an exception, so the `/` word must test the divisor and raise explicitly. |
__REFERENCES__

write_file "generated/.gitkeep" </dev/null
write_file "test/.gitkeep" </dev/null

# ---------------------------------------------------------------------------
# Idris 2 package
# ---------------------------------------------------------------------------

write_file "irundykue.ipkg" <<'__IPKG__'
package irundykue

authors    = "Irundykue-syry Team"
version    = 0.1.0
sourcedir  = "src"
main       = Main
executable = irundykue-gen

modules = Main
        , Irundykue.AST
        , Irundykue.Codegen.AArch64
        , Irundykue.Types.Singularity

depends = base
        , contrib

opts = "--cg refc"
__IPKG__

write_file "src/Irundykue/AST.idr" <<'__IDR_AST__'
module Irundykue.AST

-- Placeholder. The indexed Forth AST currently lives in Main.idr and will be
-- moved here once its interface has stabilized.
__IDR_AST__

write_file "src/Irundykue/Codegen/AArch64.idr" <<'__IDR_CODEGEN__'
module Irundykue.Codegen.AArch64

-- Placeholder. AArch64 assembly emission (dictionary headers, threaded code
-- and primitive words) will be implemented here.
__IDR_CODEGEN__

write_file "src/Irundykue/Types/Singularity.idr" <<'__IDR_SING__'
module Irundykue.Types.Singularity

-- Placeholder. Type-level machinery for Ext^1 singularity tracking and the
-- four-dimensional Clifford contraction constraint will be defined here.
__IDR_SING__

write_file "src/Main.idr" <<'__IDR_MAIN__'
module Main

import Data.String

-- =====================================================================
-- AST for the Armv8/v9 Singularity Forth Dialect
--
-- The execution context is tracked at the type level using Peano numbers
-- and Booleans to guarantee memory and transaction safety at compile time.
--
-- Type indices:
-- 1. sd : Data Stack Depth (Nat)
-- 2. od : Orthogonal Stack (SVE2) Depth (Nat)
-- 3. tx : Heisenberg Transaction State (Bool)
-- =====================================================================

data Forth : (sd : Nat) -> (od : Nat) -> (tx : Bool) ->
             (sd' : Nat) -> (od' : Nat) -> (tx' : Bool) -> Type where

  -- Sequence combinator
  Seq : Forth s1 o1 t1 s2 o2 t2 -> Forth s2 o2 t2 s3 o3 t3 -> Forth s1 o1 t1 s3 o3 t3

  -- Core Forth Words
  Push : Int -> Forth sd od tx (S sd) od tx
  Drop : Forth (S sd) od tx sd od tx
  Add  : Forth (S (S sd)) od tx (S sd) od tx
  Div  : Forth (S (S sd)) od tx (S sd) od tx

  -- =====================================================================
  -- The Koszul Complex (Singularity Resolution)
  --
  -- CO-EXECUTE takes two execution tokens.
  -- xt1 : The primary operator (L_u) which may cause a singularity.
  -- xt2 : The secondary operator (L_v) for orthogonal recovery.
  --
  -- Notice the type of xt2: it starts with (S sd) because the singularity
  -- residue (Ext^1) is mathematically pushed onto the stack.
  -- Both paths must converge to the exact same stack depth (sd').
  -- =====================================================================
  CoExecute : (xt1 : Forth sd od tx sd' od tx) ->
              (xt2 : Forth (S sd) od tx sd' od tx) ->
              Forth sd od tx sd' od tx

  Ext1 : Forth sd od tx (S sd) od tx

  -- =====================================================================
  -- Clifford Contraction (4-dimensional quantization via SVE2)
  --
  -- Moving data to the orthogonal subspace requires exactly 4 dimensions,
  -- reflecting the mathematical proof of kernel quantization.
  -- =====================================================================
  ToOrtho    : Forth (S (S (S (S sd)))) od tx sd (S (S (S (S od)))) tx
  FromOrtho  : Forth sd (S (S (S (S od)))) tx (S (S (S (S sd)))) od tx
  ClContract : Forth sd od tx sd od tx

  -- =====================================================================
  -- Heisenberg Transaction (TME)
  --
  -- Prevents nested transactions and enforces closure via the Bool flag.
  -- =====================================================================
  TxBegin : Forth sd od False sd od True
  TxEnd   : Forth sd od True sd od False

  -- Raw code emission for words without side-effects on depth
  Raw : String -> Forth sd od tx sd od tx

-- Operator for chaining AST nodes
infixl 1 >>>
(>>>) : Forth s1 o1 t1 s2 o2 t2 -> Forth s2 o2 t2 s3 o3 t3 -> Forth s1 o1 t1 s3 o3 t3
(>>>) = Seq

-- Compiler: AST to Forth string
compile : Forth s1 o1 t1 s2 o2 t2 -> String
compile (Seq x y) = compile x ++ " " ++ compile y
compile (Push x) = show x
compile Drop = "DROP"
compile Add = "+"
compile Div = "/"
compile (CoExecute xt1 xt2) =
  "[: " ++ compile xt1 ++ " ;] [: " ++ compile xt2 ++ " ;] CO-EXECUTE"
compile Ext1 = "EXT1"
compile ToOrtho = ">ORTHO"
compile FromOrtho = "ORTHO>"
compile ClContract = "CL-CONTRACT"
compile TxBegin = "[H"
compile TxEnd = "]H"
compile (Raw s) = s

-- =====================================================================
-- Sample Program Definition
-- Starts with 0 stack depth, 0 ortho depth, and False transaction state.
-- Ends with 5 items on the stack.
-- =====================================================================
prog : Forth 0 0 False 5 0 False
prog =
  -- 1. Singularity Recovery (A/0)
  --    The recovery branch starts at depth 3 (two operands plus the Ext^1
  --    residue) and must end at depth 1, the depth left by the primary branch.
  Push 10 >>> Push 0 >>>
  CoExecute Div (Ext1 >>> Drop >>> Drop >>> Drop >>> Drop >>> Push 9999) >>>

  -- 2. Orthogonal Subspace and Heisenberg Transaction
  Push 1 >>> Push 2 >>> Push 3 >>> Push 4 >>>
  ToOrtho >>>
  TxBegin >>>
  ClContract >>>
  TxEnd >>>
  FromOrtho

main : IO ()
main = do
  putStrLn "\\ Generated Forth 2012 (Armv8/v9 Singularity Dialect) code"
  putStrLn (compile prog)
__IDR_MAIN__

# ---------------------------------------------------------------------------
# Zig build graph
# ---------------------------------------------------------------------------

write_file "build.zig" <<'__BUILD_ZIG__'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.aarch64.featureSet(&[_]std.Target.aarch64.Feature{
            .sve2,
            .paca,
            .pacg,
            .tme,
        }),
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
    const elf = b.addExecutable(.{
        .name = "irundykue-syry.elf",
        .target = target,
        .optimize = optimize,
        .strip = false,
    });

    elf.addAssemblyFile(b.path("src/arch/aarch64/boot.S"));
    elf.addAssemblyFile(b.path("src/arch/aarch64/vectors.S"));
    elf.addAssemblyFile(b.path("generated/forth_dict.S"));
    elf.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));

    elf.step.dependOn(&run_gen.step);
    b.installArtifact(elf);

    // Step 3: Emit raw flat binary for QEMU / Bare-metal flash
    const bin = b.addObjCopy(elf.getEmittedBin(), .{
        .format = .bin,
    });
    const install_bin = b.addInstallBinFile(bin.getOutput(), "irundykue-syry.bin");
    b.getInstallStep().dependOn(&install_bin.step);

    // Step 4: Run target in QEMU virt machine
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-aarch64",
        "-M", "virt,virtualization=on",
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
__BUILD_ZIG__

# ---------------------------------------------------------------------------
# Bare-metal AArch64 sources
# ---------------------------------------------------------------------------

write_file "src/arch/aarch64/boot.S" <<'__BOOT_S__'
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
__BOOT_S__

write_file "src/arch/aarch64/vectors.S" <<'__VECTORS_S__'
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
__VECTORS_S__

write_file "src/arch/aarch64/linker.ld" <<'__LINKER_LD__'
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 128M
}

SECTIONS
{
    . = 0x40000000;

    .text : {
        KEEP(*(.text.boot))
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    .bss (NOLOAD) : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(64);
        . += 0x8000;
        __forth_dstack_top = .;
        . += 0x8000;
        __forth_rstack_top = .;
    } > RAM
}
__LINKER_LD__

# ---------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------

printf '\n'
if (( INIT_GIT )); then
  if ! command -v git >/dev/null 2>&1; then
    printf 'git: not installed, skipping repository initialization\n'
  elif git -C "${TARGET_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git: existing work tree detected, skipping "git init"\n'
  else
    git -C "${TARGET_DIR}" init --quiet --initial-branch=main 2>/dev/null \
      || git -C "${TARGET_DIR}" init --quiet
    printf 'git: initialized an empty repository\n'
  fi
fi

# ---------------------------------------------------------------------------
# Toolchain check (informational only)
# ---------------------------------------------------------------------------

printf '\nToolchain:\n'
check_tool idris2              "install Idris 2 (https://www.idris-lang.org)"
check_tool zig                 "install Zig (https://ziglang.org/download)"
check_tool qemu-system-aarch64 "install QEMU with AArch64 system emulation"
check_tool cc                  "required by the Idris 2 refc backend"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nDone: %d created, %d skipped, %d tool(s) missing.\n' \
  "${CREATED}" "${SKIPPED}" "${MISSING}"

printf '\nFiles:\n'
(
  cd "${TARGET_DIR}"
  find . -path ./.git -prune -o -type f ! -name 'init.bash' -print | sort | sed 's|^\./|  |'
)

cat <<__NEXT__

Next steps:
  cd ${TARGET_DIR}
  idris2 --build ${PACKAGE_NAME}.ipkg
__NEXT__
