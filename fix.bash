#!/usr/bin/env bash
#
# fix.bash - Apply verified fixes to a repository created by init.bash.
#
# Fixes applied (each one is idempotent):
#   1. src/Main.idr
#        - corrects design comments that overstated the upstream material
#        - repairs the recovery branch of `prog` so that it type-checks
#        - adds `--emit-asm PATH`, which build.zig already passes
#   2. src/Irundykue/Codegen/AArch64.idr
#        - replaces the placeholder with a minimal dictionary emitter that
#          defines `forth_cold_boot`, so that the kernel links and boots
#   3. build.zig
#        - ports the build graph to the current Zig API when `zig` is 0.14+;
#          CPU feature names (pauth/paca/pacg/tme) and the ObjCopy format are
#          resolved at compile time, so one file works on Zig 0.14 to 0.17
#          (the result is checked with `zig build --help` before install)
#        - boots the QEMU virt machine at EL1 (drops `virtualization=on`)
#   4. src/arch/aarch64/boot.S
#        - clears x28 (the CO-EXECUTE recovery token) before the first word
#   5. docs/REFERENCES.md
#        - installs the revised correspondence table
#
# Files that you have modified are never overwritten silently: the proposed
# content is written next to the file with a ".new" suffix instead, unless
# --force is given. Every file that is changed is first copied to
# ".fix-backup/<timestamp>/".
#
# Usage: ./fix.bash [--dir PATH] [--dry-run] [--force] [--verify]
#                   [--zig-api auto|current|legacy] [--help]

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

TARGET_DIR="."
DRY_RUN=0
FORCE=0
VERIFY=0
ZIG_API="auto"
CHANGED=0
UNCHANGED=0
NEEDS_REVIEW=0
BACKUP_DIR=""
SCRATCH=""

# SHA-256 digests of files as written by earlier versions of init.bash.
readonly HASH_BUILD_ZIG_V1="83e8c0c437223a6c7124b32cae08dcb3bb6983c7c7838b887f060fab55197499"
readonly HASH_REFERENCES_V1="56491adc3c98853bee2e32d05f2a081885c600240abe16c4e47d99a1457435d8"
readonly HASH_REFERENCES_V2="8fa7d9527e206b5d247ff889da10aa9d08424b1a1defa77ba72e1296055e5417"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<__USAGE__
Usage: ${0##*/} [options]

Apply verified fixes to a repository created by init.bash.

Options:
  -d, --dir PATH        Repository root (default: current directory)
  -n, --dry-run         Report what would change without modifying anything
  -f, --force           Overwrite files even if they were modified locally
      --verify          After fixing, run "idris2 --build" and "zig build"
      --zig-api MODE    auto (default), current (Zig 0.14+) or legacy
  -h, --help            Show this help and exit
__USAGE__
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '  %-9s %s\n' "$1" "$2"
}

warn() {
  printf '  %-9s %s\n' "warning" "$*" >&2
}

cleanup() {
  if [[ -n "${SCRATCH}" && -d "${SCRATCH}" ]]; then
    rm -rf "${SCRATCH}"
  fi
  return 0
}
trap cleanup EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# capture VAR: store standard input in VAR without its final newline.
capture() {
  local value
  IFS= read -r -d '' value || true
  value="${value%$'\n'}"
  printf -v "$1" '%s' "${value}"
}

backup_file() {
  local rel="$1"
  local path="${TARGET_DIR}/${rel}"
  [[ -e "${path}" ]] || return 0
  if [[ -z "${BACKUP_DIR}" ]]; then
    BACKUP_DIR="${TARGET_DIR}/.fix-backup/$(date +%Y%m%d-%H%M%S)"
  fi
  mkdir -p "${BACKUP_DIR}/$(dirname "${rel}")"
  cp -p "${path}" "${BACKUP_DIR}/${rel}"
}

# patch_text REL LABEL OLD NEW
#   Replaces the first occurrence of OLD by NEW in a text file. Reports
#   "ok" when NEW is already present and "skip" when OLD cannot be found.
patch_text() {
  local rel="$1" label="$2" old="$3" new="$4"
  local path="${TARGET_DIR}/${rel}"
  local content

  if [[ ! -e "${path}" ]]; then
    warn "${rel} not found; cannot apply: ${label}"
    NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    return 0
  fi

  content="$(cat "${path}"; printf x)"
  content="${content%x}"

  if [[ "${content}" == *"${new}"* ]]; then
    log "ok" "${rel}: ${label} (already applied)"
    UNCHANGED=$(( UNCHANGED + 1 ))
    return 0
  fi
  if [[ "${content}" != *"${old}"* ]]; then
    warn "${rel}: ${label}: expected text not found; edit manually"
    NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    return 0
  fi

  if (( DRY_RUN )); then
    log "would" "${rel}: ${label}"
  else
    backup_file "${rel}"
    content="${content/"${old}"/"${new}"}"
    printf '%s' "${content}" >"${path}"
    log "patched" "${rel}: ${label}"
  fi
  CHANGED=$(( CHANGED + 1 ))
}

# install_from_file REL SOURCE [KNOWN_SHA256 ...]
#   Installs SOURCE as REL. An existing file is replaced only when it equals
#   one of the known earlier versions (or --force is given); otherwise the
#   proposed content is written to REL.new.
install_from_file() {
  local rel="$1" src="$2"
  shift 2
  local path="${TARGET_DIR}/${rel}"
  local current proposed known replace=0

  if [[ ! -e "${path}" ]]; then
    if (( DRY_RUN )); then
      log "would" "create ${rel}"
    else
      mkdir -p "$(dirname "${path}")"
      cp "${src}" "${path}"
      log "create" "${rel}"
    fi
    CHANGED=$(( CHANGED + 1 ))
    return 0
  fi

  current="$(sha256_of "${path}")"
  proposed="$(sha256_of "${src}")"
  if [[ "${current}" == "${proposed}" ]]; then
    log "ok" "${rel} (up to date)"
    UNCHANGED=$(( UNCHANGED + 1 ))
    return 0
  fi

  if (( FORCE )); then
    replace=1
  else
    for known in "$@"; do
      if [[ "${current}" == "${known}" ]]; then
        replace=1
      fi
    done
  fi

  if (( replace )); then
    if (( DRY_RUN )); then
      log "would" "update ${rel}"
    else
      backup_file "${rel}"
      cp "${src}" "${path}"
      log "update" "${rel}"
    fi
    CHANGED=$(( CHANGED + 1 ))
  else
    if (( DRY_RUN )); then
      log "would" "write ${rel}.new (local modifications detected)"
    else
      cp "${src}" "${path}.new"
      warn "${rel} was modified locally; proposed version written to ${rel}.new"
    fi
    NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
  fi
}

# stage_content NAME: save standard input to a scratch file and print its path.
stage_content() {
  local file="${SCRATCH}/$1"
  cat >"${file}"
  printf '%s' "${file}"
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
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --verify)
      VERIFY=1
      shift
      ;;
    --zig-api)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      case "$2" in
        auto|current|legacy) ZIG_API="$2" ;;
        *) die "invalid value for --zig-api: $2" ;;
      esac
      shift 2
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

[[ -d "${TARGET_DIR}" ]] || die "directory not found: ${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
[[ -f "${TARGET_DIR}/irundykue.ipkg" ]] \
  || die "irundykue.ipkg not found in ${TARGET_DIR}; run init.bash first"

SCRATCH="$(mktemp -d)"

if (( DRY_RUN )); then
  printf 'Dry run: no files will be modified.\n'
fi
printf 'Fixing %s\n' "${TARGET_DIR}"

# ---------------------------------------------------------------------------
# Fix 1: src/Main.idr
# ---------------------------------------------------------------------------

printf '\nsrc/Main.idr\n'

capture OLD_IMPORT <<'__EOF__'
import Data.String
__EOF__
capture NEW_IMPORT <<'__EOF__'
import Data.String
import System
import System.File

import Irundykue.Codegen.AArch64
__EOF__
patch_text "src/Main.idr" "imports for --emit-asm" "${OLD_IMPORT}" "${NEW_IMPORT}"

patch_text "src/Main.idr" "heading of the CoExecute block" \
  "  -- The Koszul Complex (Singularity Resolution)" \
  "  -- Coarse Map and Second Operator (Singularity Recovery)"

capture OLD_CONVERGE <<'__EOF__'
  -- Both paths must converge to the exact same stack depth (sd').
__EOF__
capture NEW_CONVERGE <<'__EOF__'
  -- Both paths must converge to the exact same stack depth (sd').
  --
  -- Note: this type enforces depth convergence only. The upstream pair
  -- (L_u, L_v) anticommutes (fg + gf = 0 in the Clifford case, AC10),
  -- whereas a Koszul complex (AC8) concerns commuting operators. The
  -- invariance and completeness properties of the second operator are not
  -- yet expressed at the type level. See docs/REFERENCES.md.
__EOF__
patch_text "src/Main.idr" "note on what the CoExecute type enforces" \
  "${OLD_CONVERGE}" "${NEW_CONVERGE}"

capture OLD_QUANT <<'__EOF__'
  -- reflecting the mathematical proof of kernel quantization.
__EOF__
capture NEW_QUANT <<'__EOF__'
  -- matching dim Cl_N(2) = 4 (basis 1, X, Y, XY). No quantization theorem
  -- is claimed upstream; see docs/REFERENCES.md.
__EOF__
patch_text "src/Main.idr" "comment on the four orthogonal dimensions" \
  "${OLD_QUANT}" "${NEW_QUANT}"

capture OLD_TX <<'__EOF__'
  -- Prevents nested transactions and enforces closure via the Bool flag.
__EOF__
capture NEW_TX <<'__EOF__'
  -- Prevents nested transactions and enforces closure via the Bool flag.
  -- The flag is an implementation discipline; upstream makes no statement
  -- about transactions.
__EOF__
patch_text "src/Main.idr" "comment on the transaction flag" "${OLD_TX}" "${NEW_TX}"

patch_text "src/Main.idr" "recovery branch of prog (depth 3 -> 1)" \
  "CoExecute Div (Ext1 >>> Drop >>> Push 9999)" \
  "CoExecute Div (Ext1 >>> Drop >>> Drop >>> Drop >>> Drop >>> Push 9999)"

capture OLD_MAIN <<'__EOF__'
main : IO ()
main = do
  putStrLn "\\ Generated Forth 2012 (Armv8/v9 Singularity Dialect) code"
  putStrLn (compile prog)
__EOF__
capture NEW_MAIN <<'__EOF__'
-- Writes the placeholder dictionary assembly to PATH.
emitAsm : String -> IO ()
emitAsm path = do
  Right () <- writeFile path dictionaryAsm
    | Left err => do
        putStrLn ("error: cannot write " ++ path ++ ": " ++ show err)
        exitFailure
  putStrLn ("wrote " ++ path)

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "--emit-asm", path] => emitAsm path
    _ => do
      putStrLn "\\ Generated Forth 2012 (Armv8/v9 Singularity Dialect) code"
      putStrLn (compile prog)
__EOF__
patch_text "src/Main.idr" "--emit-asm entry point" "${OLD_MAIN}" "${NEW_MAIN}"

# ---------------------------------------------------------------------------
# Fix 2: src/Irundykue/Codegen/AArch64.idr
# ---------------------------------------------------------------------------

printf '\nsrc/Irundykue/Codegen/AArch64.idr\n'

CODEGEN_REL="src/Irundykue/Codegen/AArch64.idr"
CODEGEN_PATH="${TARGET_DIR}/${CODEGEN_REL}"
CODEGEN_SRC="$(stage_content codegen.idr <<'__EOF__'
module Irundykue.Codegen.AArch64

import Data.String

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
__EOF__
)"

if [[ ! -e "${CODEGEN_PATH}" ]]; then
  install_from_file "${CODEGEN_REL}" "${CODEGEN_SRC}"
elif grep -q 'dictionaryAsm' "${CODEGEN_PATH}"; then
  : # Written by an earlier run of fix.bash; the import is checked below.
elif grep -q 'Placeholder' "${CODEGEN_PATH}" && (( ! FORCE )); then
  # Still the stub written by init.bash.
  FORCE_SAVED="${FORCE}"
  FORCE=1
  install_from_file "${CODEGEN_REL}" "${CODEGEN_SRC}"
  FORCE="${FORCE_SAVED}"
else
  install_from_file "${CODEGEN_REL}" "${CODEGEN_SRC}"
fi

# `unlines` lives in Data.String, not in the Prelude. An earlier version of
# this script wrote the module without the import, so repair that as well.
if [[ -e "${CODEGEN_PATH}" ]]; then
  capture OLD_CODEGEN_HEAD <<'__EOF__'
module Irundykue.Codegen.AArch64
__EOF__
  capture NEW_CODEGEN_HEAD <<'__EOF__'
module Irundykue.Codegen.AArch64

import Data.String
__EOF__
  patch_text "${CODEGEN_REL}" "import Data.String (provides unlines)" \
    "${OLD_CODEGEN_HEAD}" "${NEW_CODEGEN_HEAD}"
fi

# ---------------------------------------------------------------------------
# Fix 3: build.zig
# ---------------------------------------------------------------------------

printf '\nbuild.zig\n'

BUILD_ZIG_SRC="$(stage_content build.zig <<'__EOF__'
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
__EOF__
)"

# zig_configures FILE: succeeds when `zig build --help` accepts FILE.
zig_configures() {
  local dir="${SCRATCH}/zigcheck"
  rm -rf "${dir}"
  mkdir -p "${dir}"
  cp "$1" "${dir}/build.zig"
  ( cd "${dir}" && zig build --help >/dev/null 2>&1 )
}

zig_minor_version() {
  local version rest
  version="$(zig version 2>/dev/null)" || return 1
  rest="${version#*.}"
  rest="${rest%%.*}"
  rest="${rest%%-*}"
  printf '%s.%s' "${version%%.*}" "${rest}"
}

# build.zig files written by earlier versions of init.bash and fix.bash. They
# may be replaced without --force because they were never edited by hand.
KNOWN_BUILD_ZIG_HASHES=(
  "${HASH_BUILD_ZIG_V1}"
  "ae4d1e4b5a0da15a7285565b836dec9b24fa62aa34e936bffd2eb896efa09eed"
  "e33f1354302a66ffe7c657ad25dc6f447c1190706f06a9870d6406f41cf8bd8c"
  "bcccb068efbfd76c41f2ed02935dea4a7de8b241974d207664a818651371d78a"
  "b6b2de30a7ce7ce2e276965a0ec30a4309102d232fec0ad84e149c7c76cbf326"
  "158073de8389d19f3118d57e9bdae773885ed57f892162d9baeaae53ae564c48"
  "f105d0377efa8f9e6fe73ad9031de7425c8baf3a8bf47d91560da74a11390dec"
  "2e6793f303d17e22c9420f02f5b4c411f95b7616eb835a677e82dbbc5b975434"
  "7fa37f190460da53f2370a690f863e583658064b2fef8a1ec15bf6016dce0909"
)

fix_build_zig() {
  local api="${ZIG_API}" version major minor

  if [[ ! -e "${TARGET_DIR}/build.zig" ]]; then
    warn "build.zig not found; skipping"
    NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    return 0
  fi

  if [[ "${api}" == "auto" ]]; then
    if ! command -v zig >/dev/null 2>&1; then
      warn "zig not found; cannot choose the build.zig API (use --zig-api)"
      api="legacy"
    else
      version="$(zig_minor_version)" || version="0.0"
      major="${version%%.*}"
      minor="${version#*.}"
      if (( major > 0 || minor >= 14 )); then
        api="current"
      else
        api="legacy"
      fi
      log "info" "zig ${version}: using the ${api} build.zig API"
    fi
  fi

  if [[ "${api}" == "legacy" ]]; then
    patch_text "build.zig" "boot QEMU at EL1 (drop virtualization=on)" \
      '"virt,virtualization=on"' '"virt"'
    return 0
  fi

  command -v zig >/dev/null 2>&1 || die "--zig-api current requires zig to verify build.zig"

  if ! zig_configures "${BUILD_ZIG_SRC}"; then
    warn "this zig rejected the proposed build.zig; left unchanged"
    NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    return 0
  fi

  # CPU feature names and the ObjCopy format are resolved at compile time, so
  # the same file works on Zig 0.14 and newer.
  install_from_file "build.zig" "${BUILD_ZIG_SRC}" "${KNOWN_BUILD_ZIG_HASHES[@]}"
}
fix_build_zig

# ---------------------------------------------------------------------------
# Fix 4: src/arch/aarch64/boot.S
# ---------------------------------------------------------------------------

printf '\nsrc/arch/aarch64/boot.S\n'

capture OLD_JUMP <<'__EOF__'
    // Jump to the Forth inner interpreter entry point
__EOF__
capture NEW_JUMP <<'__EOF__'
    // Clear the CO-EXECUTE recovery token. General-purpose registers have
    // UNKNOWN values after reset, and sync_handler tests x28 against zero.
    mov x28, #0

    // Jump to the Forth inner interpreter entry point
__EOF__
patch_text "src/arch/aarch64/boot.S" "initialize the recovery token" \
  "${OLD_JUMP}" "${NEW_JUMP}"

# ---------------------------------------------------------------------------
# Fix 5: .gitignore and docs/REFERENCES.md
# ---------------------------------------------------------------------------

printf '\nmetadata\n'

GITIGNORE_PATH="${TARGET_DIR}/.gitignore"
if [[ -e "${GITIGNORE_PATH}" ]] && ! grep -qx '/.fix-backup/' "${GITIGNORE_PATH}"; then
  if (( DRY_RUN )); then
    log "would" ".gitignore: ignore /.fix-backup/"
  else
    backup_file ".gitignore"
    printf '\n# Backups written by fix.bash\n/.fix-backup/\n' >>"${GITIGNORE_PATH}"
    log "patched" ".gitignore: ignore /.fix-backup/"
  fi
  CHANGED=$(( CHANGED + 1 ))
fi

REFERENCES_SRC="$(stage_content REFERENCES.md <<'__EOF__'
# References

## Upstream material

- Repository: <https://github.com/Yoshyhyrro/hatsu-yakitori>
- Branch: `feature/sedenion_bridge_Agda`
- `dist-proof/Agda/src/CayleyDicksonQuiver/AbelianCurse/SecondOperatorLemmas.agda`
- `dist-proof/Agda/note/AbelianCurseHypotheses.lagda.md`
- `dist-proof/Agda/note/CarabinerHypotheses.lagda.md`
- `Hypotheses.agda` (module `CayleyDicksonQuiver.Hypotheses`), the `--safe`
  part of the Carabiner scratchpad.

Upstream describes itself as exploratory. The Abelian Curse note says "not
proofs", each Agda file proves only a small concrete instance, and no single
uniform second operator `S` is claimed. The Carabiner note is intentionally not
`--safe`-clean and is never imported from `Everything.agda`; only finished
statements are ported into `Hypotheses.agda`. This project inherits that
caution.

## Upstream vocabulary

- Coarse map `U` loses information: there are `x != y` with `U x = U y`.
- Second operator `S` recovers what `U` loses.
- Invariance half: `S` is unchanged by the lost "noise". Proved once for
  cokernel-shaped constructions (Lemma 2, and Lemma 2' modulo `d`).
- Completeness half: `S` is unchanged only by the noise. Still proved per
  instance (for example `S-ext-complete`).
- `L_x` is the integer matrix of left multiplication `y -> x * y` on `CD k`.
  For a pair seed `x = e_i + e_j`, `S_ij = L_i L_j + L_j L_i`.

## Status legend

- Grounded: derived from a checked upstream statement.
- Analogy: shared shape or name, but no checked upstream statement.
- Open: no upstream counterpart.

Evidence column: "Agda" means checked upstream (`--safe` where stated),
"numerical" means computed with SymPy or plain integer matrices upstream and
not proved in Agda.

## Correspondence table

| Forth construct | Upstream artifact | Evidence | Status | Notes |
|-----------------|-------------------|----------|--------|-------|
| `CoExecute xt1 xt2` | AC10 `HeisenbergSeedRelations`: `f = L_u`, `g = L_v`, `f^2 = g^2 = -N`, `fg + gf = 0`. AC6 `Ext1Extraction`: coarse map `U`, second operator `S`. | Agda | Analogy | The Idris type only forces both branches to end at the same stack depth. Neither the invariance half (`S-ext-invariant-under-all-coboundaries`) nor the completeness half (`S-ext-complete`) has a type-level counterpart yet. |
| Singular case of `xt1` | H10: a pair seed `e_i + e_j` is a zero divisor exactly when `L_i` and `L_j` fail to anticommute (`S_ij != 0`); `S_ij^3 = 4 S_ij`. H5: `left-alternative-fails-at-seed-a` (`Hypotheses.agda`). | numerical for `k = 3..6` (`S^3 = 4S` is not proved); Agda for the single seed | Analogy | Upstream singularity is a property of a seed pair, not of a runtime operand. Division by zero in the dialect is a different notion; adopting the upstream one would mean indexing `CoExecute` by a seed pair instead of by stack depths. |
| `Ext1` and the residue slot | AC6 and AC7 (`Ext1Extraction`, `Ext1Torsion`): `Ext^1 = coker T`, `T(X) = X B - A X`. H8: `ker L_x` is the set of zero-divisor partners, and the cokernel torsion still identifies the zero-divisor seeds after deformation `x = e_i + c e_j`. | AC6, AC7: Agda. H8: numerical, with a kernel basis for `e1 + e10` checked in Agda | Analogy | The upstream residue is a cokernel class, not a machine word. Using `ESR_EL1` as the residue token is a design choice with no upstream statement. |
| One residue level, no `Ext2` | "Is there room for Ext^1 and Ext^2 to separate?", item 1: one operator on Z-free modules gives `Ext^2 = 0`. | standard result, not formalized | Consistent | A second residue level would only be motivated by item 2 (two commuting operators, AC8 `KoszulToy`). |
| "Koszul Complex" comment on `CoExecute` | AC8 `KoszulToy`: the complex `Z -> Z^2 -> Z` for two commuting operators. | Agda (one coordinate, three pairs) | Mismatch | The `L_u`, `L_v` of AC10 anticommute, which is the Clifford relation. The comment in `Main.idr` is reworded by `fix.bash`. |
| `ToOrtho` / `FromOrtho`, exactly 4 slots | (a) AC10 `CliffordContraction`: `Cl_N(2)` has basis `1, X, Y, Z = XY`. (b) H15 and H17: the chain `n > nu1 > nu2 > 0` is `16 > 8 > 4 > 0` at `k = 4` but `8 > 4 > 2 > 0` at `k = 3`. | (a) Agda. (b) numerical | Plausible source | Source (a) gives 4 for every `N`; in (b) the value 4 is specific to `k = 4`. Upstream states no quantization theorem. |
| `ClContract` | AC10 `CliffordContraction`: weight grading `mul-scale`, Heisenberg relations at `N = 0` or modulo a prime dividing `N` (`bracket-descends-at-0`, `bracket-drift-divisible`). | Agda | Name only | "Contraction" appears upstream only as a module name. `ClContract` has an identity stack effect and no defined semantics yet. |
| `TxBegin` / `TxEnd` | AC10: integral Heisenberg group `H` (`commutator-formula`, `even-central-is-commutator`; the loss is `[H,H] = {1 + 2kZ}`). H17: plan for `H_3(F_p)`. | AC10: Agda. H17: numerical; nothing about `H_3(F_p)` is formalized yet | Name only | Upstream says nothing about transactions or non-nesting. It also records that the Heisenberg relations hold where `S_ij = 0` and fail at genuine zero-divisor seeds (H16 case B), so the Heisenberg label and the singular path belong to opposite upstream regimes. |
| `Div` by zero as a singularity | H8 and H10 give the upstream link to zero divisors (see the singular case above). | numerical | Open | AArch64 `SDIV` and `UDIV` return 0 on a zero divisor without raising an exception, so the `/` word must test the divisor and raise explicitly. |

## Open questions

- Which notion of singular should the type system track: a runtime operand
  equal to zero, or a seed pair with `S_ij != 0`?
- Upstream lists a uniform completeness lemma (for any `T` with a verified
  Smith form) as open; the dialect cannot assume one.
- FEAT_TME: the tooling used to verify this repository (Zig 0.17.0, QEMU
  8.2.2 with `-cpu max`) has no `tme` CPU feature and reports
  `ID_AA64ISAR0_EL1.TME = 0`. `TxBegin` / `TxEnd` can be type-checked and
  emitted as text but not assembled or executed there.
__EOF__
)"

install_from_file "docs/REFERENCES.md" "${REFERENCES_SRC}" \
  "${HASH_REFERENCES_V1}" "${HASH_REFERENCES_V2}"

# ---------------------------------------------------------------------------
# Optional verification
# ---------------------------------------------------------------------------

if (( VERIFY && ! DRY_RUN )); then
  printf '\nVerification\n'
  if command -v idris2 >/dev/null 2>&1; then
    if ( cd "${TARGET_DIR}" && idris2 --build irundykue.ipkg >/dev/null 2>&1 ); then
      log "ok" "idris2 --build irundykue.ipkg"
    else
      warn "idris2 --build failed; run it manually to see the errors"
      NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    fi
  else
    warn "idris2 not found; skipped"
  fi
  if command -v zig >/dev/null 2>&1; then
    if ( cd "${TARGET_DIR}" && zig build >/dev/null 2>&1 ); then
      log "ok" "zig build"
    else
      warn "zig build failed; run it manually to see the errors"
      NEEDS_REVIEW=$(( NEEDS_REVIEW + 1 ))
    fi
  else
    warn "zig not found; skipped"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nDone: %d changed, %d already up to date, %d need review.\n' \
  "${CHANGED}" "${UNCHANGED}" "${NEEDS_REVIEW}"
if [[ -n "${BACKUP_DIR}" ]]; then
  printf 'Backups: %s\n' "${BACKUP_DIR}"
fi