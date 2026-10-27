#!/usr/bin/env bash
#
# configuration_file_Generate.bash - Generate project.syryaml.
#
# Builds configuration_file_Generate.idr (which must sit next to this script)
# with Idris 2, runs it, and manages the resulting manifest on disk:
#
#   - writes project.syryaml when it does not exist,
#   - leaves it alone when it is already up to date,
#   - refuses to overwrite a manifest that differs unless --force is given
#     (the old file is kept as project.syryaml.bak),
#   - with --check, verifies the manifest and the files it refers to without
#     writing anything (suitable for CI),
#   - with --scaffold, creates the directories and placeholder files that the
#     manifest refers to and that do not exist yet.
#
# Options after "--" are passed to the generator unchanged, for example:
#
#   ./configuration_file_Generate.bash -- --name my_app --version 0.2.0
#
# The generator is compiled into <root>/build/configuration_file_Generate and
# rebuilt only when its source is newer than the executable.
#
# Usage: ./configuration_file_Generate.bash [options] [-- GENERATOR_OPTIONS...]

set -euo pipefail

readonly GENERATOR_NAME="configuration_file_Generate"
readonly MANIFEST_EXTENSION=".syryaml"
readonly PLACEHOLDER='\ Placeholder created by configuration_file_Generate.bash.'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_SRC="${SCRIPT_DIR}/${GENERATOR_NAME}.idr"
IDRIS2="${IDRIS2:-idris2}"
ROOT="."
OUTPUT="project${MANIFEST_EXTENSION}"
FORCE=0
CHECK=0
SCAFFOLD=0
TO_STDOUT=0
REBUILD=0
GEN_ARGS=()
SCRATCH=""
BUILD_DIR=""
GENERATOR_EXE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<__USAGE__
Usage: ${0##*/} [options] [-- GENERATOR_OPTIONS...]

Generate the project manifest with the Idris 2 generator.

Options:
  -d, --dir PATH      Project root (default: current directory)
  -o, --output FILE   Manifest path relative to the root
                      (default: project${MANIFEST_EXTENSION}; must end in ${MANIFEST_EXTENSION})
  -f, --force         Overwrite a manifest that differs (a .bak copy is kept)
      --check         Write nothing; exit 1 if the manifest is missing, differs
                      from the generated one, or refers to missing files
      --scaffold      Create missing directories and placeholder files that
                      the manifest refers to
      --stdout        Print the manifest instead of writing it
      --rebuild       Rebuild the generator even if it is up to date
      --idris2 PATH   idris2 executable (default: \$IDRIS2, else idris2)
  -h, --help          Show this help and exit

Everything after "--" is passed to the generator. Run
"${0##*/} -- --help" to list the generator options.
__USAGE__
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '  %-9s %s\n' "$1" "$2"
}

cleanup() {
  if [[ -n "${SCRATCH}" && -d "${SCRATCH}" ]]; then
    rm -rf "${SCRATCH}"
  fi
  return 0
}
trap cleanup EXIT

# generator ARGS...: run the generator with the user's options appended.
generator() {
  "${GENERATOR_EXE}" "$@" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"}
}

build_generator() {
  BUILD_DIR="${ROOT}/build/${GENERATOR_NAME}"
  GENERATOR_EXE="${BUILD_DIR}/exec/${GENERATOR_NAME}"

  if (( ! REBUILD )) && [[ -x "${GENERATOR_EXE}" && ! "${GENERATOR_SRC}" -nt "${GENERATOR_EXE}" ]]; then
    return 0
  fi

  command -v "${IDRIS2}" >/dev/null 2>&1 \
    || die "idris2 not found (set IDRIS2 or use --idris2)"

  mkdir -p "${BUILD_DIR}"
  printf 'Building %s ...\n' "${GENERATOR_NAME}"
  if ! "${IDRIS2}" --build-dir "${BUILD_DIR}" --cg refc \
        -o "${GENERATOR_NAME}" "${GENERATOR_SRC}" >"${SCRATCH}/build.log" 2>&1; then
    cat "${SCRATCH}/build.log" >&2
    die "could not build ${GENERATOR_NAME}.idr"
  fi
  [[ -x "${GENERATOR_EXE}" ]] || die "build finished but ${GENERATOR_EXE} is missing"
}

# write_atomically SOURCE DESTINATION
write_atomically() {
  local tmp
  mkdir -p "$(dirname "$2")"
  tmp="$(mktemp "$2.XXXXXX")"
  cat "$1" >"${tmp}"
  chmod 0644 "${tmp}"
  mv -f "${tmp}" "$2"
}

# each_reference: print "kind<TAB>path" for every entry the manifest refers to.
each_reference() {
  cat "${SCRATCH}/references"
}

check_references() {
  local kind path missing=0
  while IFS=$'\t' read -r kind path; do
    [[ -n "${kind}" ]] || continue
    case "${kind}" in
      source-dir)
        if [[ -d "${ROOT}/${path}" ]]; then
          log "ok" "${path}/"
        else
          log "missing" "${path}/ (source directory)"
          missing=$(( missing + 1 ))
        fi
        ;;
      executable|dependency)
        if [[ -f "${ROOT}/${path}" ]]; then
          log "ok" "${path}"
        else
          log "missing" "${path} (${kind})"
          missing=$(( missing + 1 ))
        fi
        ;;
      *)
        die "unexpected reference kind from the generator: ${kind}"
        ;;
    esac
  done < <(each_reference)
  return "${missing}"
}

scaffold_references() {
  local kind path full
  while IFS=$'\t' read -r kind path; do
    [[ -n "${kind}" ]] || continue
    full="${ROOT}/${path}"
    case "${kind}" in
      source-dir)
        if [[ -d "${full}" ]]; then
          log "ok" "${path}/"
        else
          mkdir -p "${full}"
          log "create" "${path}/"
        fi
        ;;
      executable|dependency)
        if [[ -e "${full}" ]]; then
          log "ok" "${path}"
        else
          mkdir -p "$(dirname "${full}")"
          printf '%s\n' "${PLACEHOLDER}" >"${full}"
          log "create" "${path}"
        fi
        ;;
      *)
        die "unexpected reference kind from the generator: ${kind}"
        ;;
    esac
  done < <(each_reference)
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while (( $# )); do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      ROOT="$2"
      shift 2
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      OUTPUT="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --check)
      CHECK=1
      shift
      ;;
    --scaffold)
      SCAFFOLD=1
      shift
      ;;
    --stdout)
      TO_STDOUT=1
      shift
      ;;
    --rebuild)
      REBUILD=1
      shift
      ;;
    --idris2)
      [[ $# -ge 2 ]] || die "option $1 requires an argument"
      IDRIS2="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      GEN_ARGS=("$@")
      break
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

if (( CHECK )) && (( FORCE || SCAFFOLD || TO_STDOUT )); then
  die "--check cannot be combined with --force, --scaffold or --stdout"
fi
if (( TO_STDOUT )) && (( SCAFFOLD )); then
  die "--stdout cannot be combined with --scaffold"
fi
[[ "${OUTPUT}" == *"${MANIFEST_EXTENSION}" ]] \
  || die "the manifest path must end in ${MANIFEST_EXTENSION}: ${OUTPUT}"
[[ -f "${GENERATOR_SRC}" ]] || die "generator source not found: ${GENERATOR_SRC}"
[[ -d "${ROOT}" ]] || die "directory not found: ${ROOT}"

ROOT="$(cd "${ROOT}" && pwd)"
SCRATCH="$(mktemp -d)"
TARGET="${ROOT}/${OUTPUT}"

# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------

# Options that only print information are handled by the generator directly.
for arg in ${GEN_ARGS[@]+"${GEN_ARGS[@]}"}; do
  case "${arg}" in
    --help|--list-extensions)
      build_generator
      "${GENERATOR_EXE}" "${arg}"
      exit 0
      ;;
    *) ;;
  esac
done

build_generator

if ! generator >"${SCRATCH}/manifest"; then
  die "the generator rejected the configuration; nothing was written"
fi
generator --list-files >"${SCRATCH}/references" 2>/dev/null \
  || die "the generator could not list the referenced files"

if (( TO_STDOUT )); then
  cat "${SCRATCH}/manifest"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------

if (( CHECK )); then
  problems=0
  printf 'Checking %s\n' "${TARGET}"

  if [[ ! -f "${TARGET}" ]]; then
    log "missing" "${OUTPUT}"
    problems=$(( problems + 1 ))
  elif cmp -s "${SCRATCH}/manifest" "${TARGET}"; then
    log "ok" "${OUTPUT} matches the generated manifest"
  else
    log "differs" "${OUTPUT}"
    diff -u --label "${OUTPUT} (on disk)" --label "${OUTPUT} (generated)" \
      "${TARGET}" "${SCRATCH}/manifest" || true
    problems=$(( problems + 1 ))
  fi

  refs=0
  check_references || refs=$?
  problems=$(( problems + refs ))

  if (( problems )); then
    printf '\n%d problem(s) found.\n' "${problems}"
    exit 1
  fi
  printf '\nAll checks passed.\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Write mode
# ---------------------------------------------------------------------------

printf 'Generating %s\n' "${TARGET}"

if [[ ! -e "${TARGET}" ]]; then
  write_atomically "${SCRATCH}/manifest" "${TARGET}"
  log "create" "${OUTPUT}"
elif cmp -s "${SCRATCH}/manifest" "${TARGET}"; then
  log "ok" "${OUTPUT} (up to date)"
elif (( FORCE )); then
  cp -p "${TARGET}" "${TARGET}.bak"
  write_atomically "${SCRATCH}/manifest" "${TARGET}"
  log "overwrite" "${OUTPUT} (previous version kept as ${OUTPUT}.bak)"
else
  diff -u --label "${OUTPUT} (on disk)" --label "${OUTPUT} (generated)" \
    "${TARGET}" "${SCRATCH}/manifest" || true
  die "${OUTPUT} differs from the generated manifest; use --force to overwrite it"
fi

if (( SCAFFOLD )); then
  printf '\nScaffolding referenced files\n'
  scaffold_references
fi
