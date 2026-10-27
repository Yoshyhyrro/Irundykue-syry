#!/usr/bin/env bash
#
# forth_file_Insert.bash - Run the Irundykue-syry kernel in QEMU with Forth
# source files inserted into guest memory.
#
# The kernel has no file system, so source files travel as a memory image.
# This script concatenates the given files into one payload, prefixes it with
# a 16-byte header and asks QEMU's generic loader to place the image at a fixed
# guest address before the first instruction runs:
#
#     offset  0   8 bytes   magic "SYRYIN01"
#     offset  8   8 bytes   payload length, little endian
#     offset 16   n bytes   payload
#
# The address and the size limit below must match the kernel
# (src/Irundykue/Codegen/AArch64.idr). QEMU's serial console is connected to
# this terminal, so everything the kernel prints appears on standard output.
#
# Exit status: that of QEMU, or 124 on timeout, 3 when an --expect pattern is
# missing from the output, 1 on any usage or input error.
#
# Usage: ./forth_file_Insert.bash [options] [FILE ...] [-- QEMU_OPTIONS...]

set -euo pipefail

readonly IMAGE_MAGIC='SYRYIN01'
readonly INPUT_ADDR='0x41000000'
readonly INPUT_MAX=1048576
readonly MIN_MEMORY_MIB=32
readonly ALLOWED_EXTENSIONS=(.4th .tatatina .irundykue)
readonly KERNEL_NAME='irundykue-syry.elf'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL=""
QEMU="${QEMU:-qemu-system-aarch64}"
MEMORY="512M"
TIMEOUT=""
LOG_FILE=""
EMIT_IMAGE=""
DRY_RUN=0
ANY_EXTENSION=0
FILES=()
EXPECTS=()
QEMU_EXTRA=()
SCRATCH=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<__USAGE__
Usage: ${0##*/} [options] [FILE ...] [-- QEMU_OPTIONS...]

Run the Irundykue-syry kernel in QEMU and insert Forth source files into its
memory. Use "-" to read one file from standard input. Without files the kernel
starts without input and runs until you stop it (Ctrl-A, then X).

Options:
  -k, --kernel PATH     Kernel ELF (default: \$SYRY_KERNEL, else ${KERNEL_NAME} or
                        zig-out/bin/${KERNEL_NAME} next to this script, in its parent
                        directory, or in the current directory)
      --qemu PATH       QEMU executable (default: \$QEMU, else qemu-system-aarch64)
  -m, --memory SIZE     Guest memory, at least ${MIN_MEMORY_MIB}M (default: ${MEMORY})
  -t, --timeout SEC     Stop QEMU after SEC seconds; 0 disables the limit
                        (default: 30 with files, none without)
      --expect REGEX    Require the output to match REGEX (extended regular
                        expression); may be repeated
      --log FILE        Also save the kernel output to FILE
      --emit-image FILE Write the insertion image to FILE and exit
      --any-extension   Accept files whose extension is not one of:
                        ${ALLOWED_EXTENSIONS[*]}
  -n, --dry-run         Build the image and print the QEMU command only
  -h, --help            Show this help and exit

Everything after "--" is passed to QEMU unchanged.

Files are concatenated in the order given, each followed by a newline. The
payload may be at most ${INPUT_MAX} bytes.
__USAGE__
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*" >&2
}

# shellcheck disable=SC2329  # invoked through the EXIT trap below
cleanup() {
  if [[ -n "${SCRATCH}" && -d "${SCRATCH}" ]]; then
    rm -rf "${SCRATCH}"
  fi
  return 0
}
trap cleanup EXIT

# write_le64 VALUE: print VALUE as eight little-endian bytes.
write_le64() {
  local value="$1" i hex
  for (( i = 0; i < 8; i++ )); do
    printf -v hex '%02x' $(( (value >> (8 * i)) & 255 ))
    printf '%b' "\\x${hex}"
  done
}

has_allowed_extension() {
  local base="${1##*/}" ext
  for ext in "${ALLOWED_EXTENSIONS[@]}"; do
    if [[ "${base}" == *"${ext}" && ${#base} -gt ${#ext} ]]; then
      return 0
    fi
  done
  return 1
}

# memory_mib SIZE: print the size in MiB for values such as 512M or 1G.
memory_mib() {
  case "$1" in
    *[Mm]) printf '%s' "${1%[Mm]}" ;;
    *[Gg]) printf '%s' $(( ${1%[Gg]} * 1024 )) ;;
    *)     printf '%s' 0 ;;
  esac
}

find_timeout_command() {
  if command -v timeout >/dev/null 2>&1; then
    printf '%s' timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    printf '%s' gtimeout
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while (( $# )); do
  case "$1" in
    -k|--kernel)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      KERNEL="$2"
      shift 2
      ;;
    --qemu)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      QEMU="$2"
      shift 2
      ;;
    -m|--memory)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      MEMORY="$2"
      shift 2
      ;;
    -t|--timeout)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      TIMEOUT="$2"
      shift 2
      ;;
    --expect)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      EXPECTS+=("$2")
      shift 2
      ;;
    --log)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      LOG_FILE="$2"
      shift 2
      ;;
    --emit-image)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      EMIT_IMAGE="$2"
      shift 2
      ;;
    --any-extension)
      ANY_EXTENSION=1
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      QEMU_EXTRA=("$@")
      break
      ;;
    -)
      FILES+=("-")
      shift
      ;;
    -*)
      usage >&2
      die "unknown option: $1"
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${TIMEOUT}" && ! "${TIMEOUT}" =~ ^[0-9]+$ ]]; then
  die "the timeout must be a whole number of seconds: ${TIMEOUT}"
fi
if [[ -z "${TIMEOUT}" ]]; then
  if (( ${#FILES[@]} )); then TIMEOUT=30; else TIMEOUT=0; fi
fi
if [[ ! "${MEMORY}" =~ ^[0-9]+[MmGg]$ ]]; then
  die "invalid memory size '${MEMORY}'; use a form such as 512M or 1G"
fi
if (( $(memory_mib "${MEMORY}") < MIN_MEMORY_MIB )); then
  die "the inserted image lives at ${INPUT_ADDR}; use at least ${MIN_MEMORY_MIB}M of memory"
fi

stdin_count=0
for file in ${FILES[@]+"${FILES[@]}"}; do
  if [[ "${file}" == "-" ]]; then
    stdin_count=$(( stdin_count + 1 ))
  fi
done
(( stdin_count <= 1 )) || die "standard input can be inserted only once"

# ---------------------------------------------------------------------------
# Build the insertion image
# ---------------------------------------------------------------------------

SCRATCH="$(mktemp -d)"
IMAGE=""

if (( ${#FILES[@]} )); then
  : >"${SCRATCH}/payload"
  for file in "${FILES[@]}"; do
    if [[ "${file}" == "-" ]]; then
      cat >>"${SCRATCH}/payload"
    else
      [[ -f "${file}" ]] || die "file not found: ${file}"
      if (( ! ANY_EXTENSION )) && ! has_allowed_extension "${file}"; then
        die "${file}: unexpected extension; expected one of ${ALLOWED_EXTENSIONS[*]} (or use --any-extension)"
      fi
      if bad_line="$(LC_ALL=C grep -n -m1 -E '[^[:print:][:space:]]' "${file}")"; then
        note "warning: ${file}:${bad_line%%:*}: non-ASCII or control characters" \
             "(harmless in comments, but a Forth tokenizer reads them as part of a word)"
      fi
      cat "${file}" >>"${SCRATCH}/payload"
    fi
    printf '\n' >>"${SCRATCH}/payload"
  done

  length="$(wc -c <"${SCRATCH}/payload" | tr -d '[:space:]')"
  (( length <= INPUT_MAX )) || die "the payload is ${length} bytes; the limit is ${INPUT_MAX}"

  IMAGE="${SCRATCH}/input.img"
  {
    printf '%s' "${IMAGE_MAGIC}"
    write_le64 "${length}"
    cat "${SCRATCH}/payload"
  } >"${IMAGE}"
  note "inserting ${#FILES[@]} file(s), ${length} byte(s) of source at ${INPUT_ADDR}"
elif [[ -n "${EMIT_IMAGE}" ]]; then
  die "--emit-image needs at least one file"
fi

if [[ -n "${EMIT_IMAGE}" ]]; then
  cp "${IMAGE}" "${EMIT_IMAGE}"
  note "wrote ${EMIT_IMAGE} ($(wc -c <"${EMIT_IMAGE}" | tr -d '[:space:]') bytes)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Locate the kernel and QEMU, then run
# ---------------------------------------------------------------------------

if [[ -z "${KERNEL}" ]]; then
  KERNEL="${SYRY_KERNEL:-}"
fi
if [[ -z "${KERNEL}" ]]; then
  candidates=(
    "${SCRIPT_DIR}/${KERNEL_NAME}"
    "${SCRIPT_DIR}/zig-out/bin/${KERNEL_NAME}"
    "${SCRIPT_DIR}/../zig-out/bin/${KERNEL_NAME}"
    "${PWD}/${KERNEL_NAME}"
    "${PWD}/zig-out/bin/${KERNEL_NAME}"
  )
  searched=()
  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      KERNEL="${candidate}"
      break
    fi
    case " ${searched[*]-} " in
      *" ${candidate} "*) ;;
      *) searched+=("${candidate}") ;;
    esac
  done
  if [[ -z "${KERNEL}" ]]; then
    {
      printf 'error: kernel %s not found. Searched:\n' "${KERNEL_NAME}"
      printf '  %s\n' "${searched[@]}"
      printf 'Build it with "zig build" (it ends up in zig-out/bin/), copy it from a\n'
      printf 'release or CI artifact next to this script, or pass --kernel PATH\n'
      printf '(or set SYRY_KERNEL).\n'
    } >&2
    exit 1
  fi
fi
[[ -f "${KERNEL}" ]] || die "kernel not found: ${KERNEL}"

COMMAND=("${QEMU}" -M virt -cpu max -m "${MEMORY}" -nographic -nic none -kernel "${KERNEL}")
if [[ -n "${IMAGE}" ]]; then
  COMMAND+=(-device "loader,file=${IMAGE},addr=${INPUT_ADDR},force-raw=on")
fi
if (( ${#QEMU_EXTRA[@]} )); then
  COMMAND+=("${QEMU_EXTRA[@]}")
fi

if (( DRY_RUN )); then
  note "kernel:  ${KERNEL}"
  note "timeout: ${TIMEOUT}s (0 = none)"
  printf '%q ' "${COMMAND[@]}"
  printf '\n'
  exit 0
fi

command -v "${QEMU}" >/dev/null 2>&1 \
  || die "${QEMU} not found; install QEMU with AArch64 system emulation or pass --qemu PATH"

if (( TIMEOUT > 0 )); then
  timeout_cmd="$(find_timeout_command)"
  if [[ -n "${timeout_cmd}" ]]; then
    COMMAND=("${timeout_cmd}" "${TIMEOUT}s" "${COMMAND[@]}")
  else
    note "warning: no timeout command found; running without a time limit"
  fi
fi

OUTPUT="${LOG_FILE:-${SCRATCH}/output.log}"

set +e
"${COMMAND[@]}" 2>&1 | tee "${OUTPUT}"
status="${PIPESTATUS[0]}"
set -e

if (( status == 124 && TIMEOUT > 0 )); then
  note "note: stopped after ${TIMEOUT}s (the kernel did not power off)"
fi

for pattern in ${EXPECTS[@]+"${EXPECTS[@]}"}; do
  if ! grep -Eq -- "${pattern}" "${OUTPUT}"; then
    note "error: expected output matching '${pattern}' was not found"
    exit 3
  fi
done

exit "${status}"