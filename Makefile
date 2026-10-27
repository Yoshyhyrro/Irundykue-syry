# Makefile - build, test and package Irundykue-syry.
#
# Requires GNU make and bash. Run "make help" for the list of targets.
#
# The Makefile is the only build-time driver besides build.zig. It generates
# project.syryaml with the Idris 2 generator, builds the kernel, inserts Forth
# source files into the kernel under QEMU, runs the golden-output tests and
# assembles the release bundle. The same Makefile is shipped inside the bundle,
# where "run", "test" and "check-insertion" work without any sources.

SHELL := /bin/bash

# ---------------------------------------------------------------------------
# Configuration (override on the command line, for example: make run FILES=a.4th)
# ---------------------------------------------------------------------------

IDRIS2   ?= idris2
ZIG      ?= zig
QEMU     ?= qemu-system-aarch64
MEMORY   ?= 512M
TIMEOUT  ?= 30
FILES    ?=
ANY_EXT  ?=
VERBOSE  ?=
VERSION  ?=
GEN_SRC  ?= configuration_file_Generate.idr
GEN_ARGS ?=
TEST_DIR ?= test
CACHE    ?= .cache

KERNEL_NAME  := irundykue-syry.elf
KERNEL_BUILT := zig-out/bin/$(KERNEL_NAME)
KERNEL_BIN   := zig-out/bin/irundykue-syry.bin
KERNEL       ?= $(if $(wildcard $(KERNEL_NAME)),$(KERNEL_NAME),$(KERNEL_BUILT))

# The insertion image format. These constants must match the kernel
# (src/Irundykue/Codegen/AArch64.idr).
IMAGE_MAGIC := SYRYIN01
INPUT_ADDR  := 0x41000000
INPUT_MAX   := 1048576
BANNER      := ^irundykue-syry: cold boot at EL

TIMEOUT_CMD    := $(shell command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)
TIMEOUT_PREFIX := $(if $(and $(TIMEOUT_CMD),$(filter-out 0,$(TIMEOUT))),$(TIMEOUT_CMD) $(TIMEOUT)s)
SHA256         := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo shasum -a 256)
QEMU_FLAGS     := -M virt -cpu max -m $(MEMORY) -nographic -nic none

GEN_DIR := $(CACHE)/configuration_file_Generate
GEN_EXE := $(GEN_DIR)/exec/configuration_file_Generate
WORK    := $(CACHE)/make

MANIFEST_ARGS := $(GEN_ARGS)$(if $(VERSION), --version $(VERSION))

KERNEL_SOURCES := $(shell find src -type f \( -name '*.idr' -o -name '*.S' -o -name '*.ld' \) 2>/dev/null) \
                  $(wildcard build.zig irundykue.ipkg)

TESTS        := $(sort $(patsubst $(TEST_DIR)/%.tatatina,%,$(wildcard $(TEST_DIR)/*.tatatina)))
STATUS_FILES := $(addprefix $(WORK)/test/,$(addsuffix .status,$(TESTS)))

.DEFAULT_GOAL := all

# ---------------------------------------------------------------------------
# Shell helpers shared by the recipes
# ---------------------------------------------------------------------------

# make_image OUT FILE...: concatenate the files and prefix the 16-byte header
# (magic, little-endian length). qemu_run [IMAGE]: run the kernel.
# run_test NAME: run one golden test and write its status file.
define SH_LIB
make_image() { \
  out=$$1; shift; payload=$$(mktemp); \
  for f in "$$@"; do \
    [ -f "$$f" ] || { echo "error: file not found: $$f" >&2; rm -f "$$payload"; return 1; }; \
    case "$$f" in \
      *.4th|*.tatatina|*.irundykue) ;; \
      *) if [ -z "$(ANY_EXT)" ]; then echo "error: $$f: expected .4th, .tatatina or .irundykue (set ANY_EXT=1 to allow other files)" >&2; rm -f "$$payload"; return 1; fi ;; \
    esac; \
    cat "$$f" >> "$$payload"; printf '\n' >> "$$payload"; \
  done; \
  len=$$(wc -c < "$$payload" | tr -d '[:space:]'); \
  if [ "$$len" -gt $(INPUT_MAX) ]; then echo "error: the payload is $$len bytes; the limit is $(INPUT_MAX)" >&2; rm -f "$$payload"; return 1; fi; \
  mkdir -p "$$(dirname "$$out")"; \
  { printf '%s' '$(IMAGE_MAGIC)'; i=0; while [ $$i -lt 8 ]; do printf '%b' "\\x$$(printf '%02x' $$(( (len >> (8 * i)) & 255 )))"; i=$$((i + 1)); done; cat "$$payload"; } > "$$out"; \
  rm -f "$$payload"; \
}; \
qemu_run() { \
  if [ -n "$$1" ]; then \
    $(TIMEOUT_PREFIX) $(QEMU) $(QEMU_FLAGS) -kernel '$(KERNEL)' -device "loader,file=$$1,addr=$(INPUT_ADDR),force-raw=on"; \
  else \
    $(QEMU) $(QEMU_FLAGS) -kernel '$(KERNEL)'; \
  fi; \
}; \
run_test() { \
  name=$$1; src='$(TEST_DIR)'/$$name.tatatina; golden='$(TEST_DIR)'/$$name.expected; \
  dir='$(WORK)/test'; sf=$$dir/$$name.status; mkdir -p "$$dir"; \
  xfail=0; \
  if [ -f '$(TEST_DIR)/XFAIL' ] && sed 's/[#].*//; s/^[[:space:]]*//; s/[[:space:]]*$$//' '$(TEST_DIR)/XFAIL' | grep -qx -- "$$name"; then xfail=1; fi; \
  if [ ! -f "$$golden" ]; then printf 'FAIL\t%s\tno %s.expected\n' "$$name" "$$name" > "$$sf"; return 0; fi; \
  if ! make_image "$$dir/$$name.img" "$$src" 2> "$$dir/$$name.err"; then printf 'FAIL\t%s\tcould not build the insertion image\n' "$$name" > "$$sf"; cat "$$dir/$$name.err" >> "$$sf"; return 0; fi; \
  rc=0; qemu_run "$$dir/$$name.img" > "$$dir/$$name.raw" 2> "$$dir/$$name.err" || rc=$$?; \
  if [ $$rc -ne 0 ]; then printf 'FAIL\t%s\tthe run ended with status %s\n' "$$name" "$$rc" > "$$sf"; tail -n 5 "$$dir/$$name.err" >> "$$sf"; return 0; fi; \
  if ! tr -d '\r' < "$$dir/$$name.raw" | grep -q '$(BANNER)'; then printf 'FAIL\t%s\tno boot banner in the output\n' "$$name" > "$$sf"; return 0; fi; \
  tr -d '\r' < "$$dir/$$name.raw" | sed -n '/$(BANNER)/,$$p' | sed '1d' | sed 's/[[:space:]]*$$//' > "$$dir/$$name.actual"; \
  sed 's/[[:space:]]*$$//' "$$golden" > "$$dir/$$name.golden"; \
  if diff -u --label "$$name.expected" --label "$$name (actual)" "$$dir/$$name.golden" "$$dir/$$name.actual" > "$$dir/$$name.diff"; then \
    if [ $$xfail -eq 1 ]; then printf 'XPASS\t%s\tunexpected pass: remove it from XFAIL\n' "$$name" > "$$sf"; else printf 'PASS\t%s\t\n' "$$name" > "$$sf"; fi; \
  else \
    if [ $$xfail -eq 1 ]; then printf 'XFAIL\t%s\tknown to fail\n' "$$name" > "$$sf"; else printf 'FAIL\t%s\toutput differs\n' "$$name" > "$$sf"; fi; \
    cat "$$dir/$$name.diff" >> "$$sf"; \
  fi; \
}
endef

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------

.PHONY: all kernel typecheck
all: kernel ## Build the kernel (default)

kernel: $(KERNEL) ## Build zig-out/bin/irundykue-syry.elf and .bin

$(KERNEL_BUILT): $(KERNEL_SOURCES)
	$(ZIG) build
	@touch $(KERNEL_BUILT) $(KERNEL_BIN)

typecheck: ## Type-check and build the Idris 2 package
	$(IDRIS2) --build irundykue.ipkg

# ---------------------------------------------------------------------------
# Manifest: project.syryaml is generated, never edited by hand
# ---------------------------------------------------------------------------

.PHONY: manifest manifest-check scaffold FORCE
FORCE:

$(GEN_SRC):
	@echo "error: the generator source $@ was not found (set GEN_SRC=...)" >&2; false

$(GEN_EXE): $(GEN_SRC)
	@command -v $(IDRIS2) >/dev/null 2>&1 || { echo "error: $(IDRIS2) not found" >&2; exit 1; }
	$(IDRIS2) --build-dir $(GEN_DIR) --cg refc -o configuration_file_Generate $(GEN_SRC)

# The generator arguments are part of the inputs of project.syryaml.
$(WORK)/manifest.args: FORCE
	@mkdir -p $(WORK)
	@printf '%s\n' '$(MANIFEST_ARGS)' | cmp -s - $@ || printf '%s\n' '$(MANIFEST_ARGS)' > $@

project.syryaml: $(GEN_EXE) $(WORK)/manifest.args
	$(GEN_EXE) $(MANIFEST_ARGS) > $@.tmp || { rm -f $@.tmp; exit 1; }
	@mv $@.tmp $@

manifest: project.syryaml ## Generate project.syryaml (VERSION=x.y.z, GEN_ARGS="--name ...")

manifest-check: $(GEN_EXE) ## Check project.syryaml against the generator and the files it names
	@set -eu; tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
	$(GEN_EXE) $(MANIFEST_ARGS) > "$$tmp" 2>/dev/null; \
	problems=0; \
	if [ ! -f project.syryaml ]; then echo "missing    project.syryaml (run: make manifest)"; problems=$$((problems + 1)); \
	elif cmp -s "$$tmp" project.syryaml; then echo "ok         project.syryaml matches the generated manifest"; \
	else echo "differs    project.syryaml"; diff -u project.syryaml "$$tmp" || true; problems=$$((problems + 1)); fi; \
	while IFS=$$'\t' read -r kind path; do \
	  case "$$kind" in \
	    source-dir) if [ -d "$$path" ]; then echo "ok         $$path/"; else echo "missing    $$path/ (source directory)"; problems=$$((problems + 1)); fi ;; \
	    *) if [ -f "$$path" ]; then echo "ok         $$path"; else echo "missing    $$path ($$kind)"; problems=$$((problems + 1)); fi ;; \
	  esac; \
	done < <($(GEN_EXE) --list-files $(MANIFEST_ARGS) 2>/dev/null); \
	if [ $$problems -ne 0 ]; then echo "$$problems problem(s) found."; exit 1; fi; echo "All checks passed."

scaffold: $(GEN_EXE) ## Create the directories and placeholder files that the manifest names
	@set -eu; \
	while IFS=$$'\t' read -r kind path; do \
	  case "$$kind" in \
	    source-dir) if [ -d "$$path" ]; then echo "ok         $$path/"; else mkdir -p "$$path"; echo "create     $$path/"; fi ;; \
	    *) if [ -e "$$path" ]; then echo "ok         $$path"; else mkdir -p "$$(dirname "$$path")"; printf '%s\n' '\ Placeholder created by make scaffold.' > "$$path"; echo "create     $$path"; fi ;; \
	  esac; \
	done < <($(GEN_EXE) --list-files $(MANIFEST_ARGS) 2>/dev/null)

# ---------------------------------------------------------------------------
# Running Forth source in the kernel
# ---------------------------------------------------------------------------

.PHONY: run check-insertion
run: $(KERNEL) ## Run the kernel; FILES="a.4th b.tatatina" inserts source files
	@set -eu; $(SH_LIB); \
	if [ -n '$(FILES)' ]; then \
	  img='$(WORK)/input.img'; make_image "$$img" $(FILES); \
	  echo "inserting: $(FILES)" >&2; qemu_run "$$img"; \
	else qemu_run ''; fi

check-insertion: $(KERNEL) ## Check that an inserted file reaches the kernel intact
	@set -eu; $(SH_LIB); tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	printf '%s\n' '\ round trip' '1 2 + .' > "$$tmp/roundtrip.tatatina"; \
	make_image "$$tmp/in.img" "$$tmp/roundtrip.tatatina"; \
	qemu_run "$$tmp/in.img" > "$$tmp/out" 2>&1 || { cat "$$tmp/out"; exit 1; }; \
	cat "$$tmp/out"; \
	grep -q '1 2 + \.' "$$tmp/out" && echo "insertion round trip: ok"

# ---------------------------------------------------------------------------
# Tests: NAME.tatatina is compared with NAME.expected. Names listed in
# $(TEST_DIR)/XFAIL are known failures; one that passes is an error (XPASS).
# Setup failures (no QEMU, no banner, timeout) are never hidden by XFAIL.
# ---------------------------------------------------------------------------

.PHONY: test test-list
$(WORK)/test/%.status: $(TEST_DIR)/%.tatatina $(KERNEL) FORCE
	@set -eu; $(SH_LIB); run_test '$*'

test: $(STATUS_FILES) ## Run the golden-output tests (VERBOSE=1 shows known-failure diffs)
	@set -eu; \
	if [ -z '$(STATUS_FILES)' ]; then echo "no tests found in $(TEST_DIR)" >&2; exit 1; fi; \
	pass=0; fail=0; xfail=0; xpass=0; \
	for f in $(STATUS_FILES); do \
	  IFS=$$'\t' read -r state name msg < "$$f"; \
	  if [ -n "$$msg" ]; then printf '%-6s %s (%s)\n' "$$state" "$$name" "$$msg"; else printf '%-6s %s\n' "$$state" "$$name"; fi; \
	  case "$$state" in \
	    PASS) pass=$$((pass + 1)) ;; \
	    FAIL) fail=$$((fail + 1)); sed -n '2,$$p' "$$f" | sed 's/^/         | /' ;; \
	    XFAIL) xfail=$$((xfail + 1)); if [ -n '$(VERBOSE)' ]; then sed -n '2,$$p' "$$f" | sed 's/^/         | /'; fi ;; \
	    XPASS) xpass=$$((xpass + 1)) ;; \
	  esac; \
	done; \
	printf '\n%d passed, %d failed, %d expected failures, %d unexpected passes\n' $$pass $$fail $$xfail $$xpass; \
	[ $$fail -eq 0 ] && [ $$xpass -eq 0 ]

test-list: ## List the tests
	@for t in $(TESTS); do echo "$(TEST_DIR)/$$t.tatatina"; done

# ---------------------------------------------------------------------------
# Release bundle: dist/irundykue-syry-VERSION.tar.gz
# ---------------------------------------------------------------------------

.PHONY: dist
dist: kernel project.syryaml ## Assemble the release bundle in dist/
	@set -eu; \
	[ -f LICENSE ] || { echo "error: LICENSE is required: BSD-3-Clause asks binary distributions to carry it" >&2; exit 1; }; \
	ver=$$(sed -n 's/^version: *//p' project.syryaml | head -n 1); \
	name=irundykue-syry-$$ver; dir=dist/$$name; \
	rm -rf "$$dir" "dist/$$name.tar.gz"; mkdir -p "$$dir"; \
	cp $(KERNEL_BUILT) $(KERNEL_BIN) project.syryaml LICENSE README.md Makefile "$$dir/"; \
	if [ -d '$(TEST_DIR)' ]; then cp -R '$(TEST_DIR)' "$$dir/$(TEST_DIR)"; fi; \
	{ printf '%s\n' '#!/bin/sh' '# Generated by "make dist": run Forth source files in the kernel under QEMU.' \
	    'here=$$(cd "$$(dirname "$$0")" && pwd)' 'files=' 'for f in "$$@"; do' \
	    '  case "$$f" in /*) ;; *) f="$$PWD/$$f" ;; esac' '  files="$$files $$f"' 'done' \
	    'exec make --no-print-directory -C "$$here" run FILES="$$files"'; } > "$$dir/irundykue"; \
	chmod +x "$$dir/irundykue"; \
	( cd "$$dir" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | xargs $(SHA256) > SHA256SUMS ); \
	tar -czf "dist/$$name.tar.gz" -C dist "$$name"; \
	( cd dist && $(SHA256) "$$name.tar.gz" > "$$name.tar.gz.sha256" ); \
	echo "created dist/$$name.tar.gz"

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

.PHONY: clean distclean help
clean: ## Remove test results, images and the release bundle
	rm -rf $(WORK) dist

distclean: clean ## Also remove the kernel, the generator and the Zig cache
	rm -rf zig-out .zig-cache $(GEN_DIR)

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_.-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:[^#]*## /\t/' | awk -F'\t' '{printf "  %-16s %s\n", $$1, $$2}'
