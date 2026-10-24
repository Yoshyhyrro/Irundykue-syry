# Irundykue-syry

A Forth dialect for Armv8-A / Armv9-A, generated from an Idris 2 front end that
checks stack discipline at compile time. The generator emits AArch64 assembly,
Zig assembles and links it into a bare-metal kernel, and QEMU runs the result.

Forth 2012 compatibility is a design goal of the dialect. Conformance has not
been assessed yet, and no claim is made.

**Status: early prototype (version 0.1.0).** The type-level front end and the
build pipeline work end to end. The Forth inner interpreter and the real
dictionary do not exist yet; the kernel currently boots, prints a banner and
parks the core. See [Status](#status) for the exact scope.

## How it works

```
[ Idris 2 (irundykue.ipkg) ]
        |  type-checks data stack depth, orthogonal stack depth,
        |  Ext^1 recovery paths and transaction state
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

## Quick start

```sh
idris2 --build irundykue.ipkg   # type-checks and builds build/exec/irundykue-gen
zig build                       # runs the generator, assembles and links the kernel
zig build run                   # boots the kernel in QEMU
```

Expected output from `zig build run`:

```
irundykue-syry: cold boot at EL1
```

The kernel parks in a `WFE` loop afterwards. Press `Ctrl-A` then `X` to leave
QEMU.

`zig build` runs `idris2 --build` itself, so the first command is only needed
when you want to type-check without building the kernel.

### Using the generator directly

```sh
./build/exec/irundykue-gen                                # print the sample program as Forth text
./build/exec/irundykue-gen --emit-asm generated/forth_dict.S   # write the dictionary assembly
```

The sample program in `src/Main.idr` compiles to:

```forth
10 0 [: / ;] [: EXT1 DROP DROP DROP DROP 9999 ;] CO-EXECUTE 1 2 3 4 >ORTHO [H CL-CONTRACT ]H ORTHO>
```

The text uses quotation words (`[:` and `;]`) and words defined by this dialect
(`CO-EXECUTE`, `EXT1`, `>ORTHO`, `ORTHO>`, `CL-CONTRACT`, `[H`, `]H`).

## Prerequisites

| Tool                  | Purpose                                  | Verified with                          |
|-----------------------|------------------------------------------|----------------------------------------|
| Idris 2               | Front end and host-side generator        | 0.8.0 (used by CI)                     |
| A C compiler          | Required by the `refc` Idris 2 backend   | GCC                                    |
| Zig                   | Cross assembler, linker and build driver | 0.14.1, 0.15.2, 0.16.0, 0.17.0         |
| `qemu-system-aarch64` | Running the kernel image                 | 8.2.2                                  |

Idris 2 is built from source with a Chez Scheme bootstrap (`make bootstrap
SCHEME=chezscheme`); on Debian and Ubuntu you need `chezscheme`, `libgmp-dev`
and `make`. See the [Idris 2 installation guide](https://idris2.readthedocs.io)
for details.

`build.zig` resolves CPU feature names and the `ObjCopy` format at compile time,
so the same file builds on Zig 0.14 and newer. Versions older than 0.14 are not
supported.

## The type-level model

Every Forth word is a constructor of one indexed type:

```idris
data Forth : (sd : Nat) -> (od : Nat) -> (tx : Bool) ->
             (sd' : Nat) -> (od' : Nat) -> (tx' : Bool) -> Type
```

| Index | Meaning                                     |
|-------|---------------------------------------------|
| `sd`  | Data stack depth                            |
| `od`  | Orthogonal (SVE2) stack depth               |
| `tx`  | Transaction state: `True` while inside `[H` |

A value of type `Forth sd od tx sd' od' tx'` is a program that starts in state
`(sd, od, tx)` and ends in state `(sd', od', tx')`. Sequencing (`>>>`) only
type-checks when the end state of the left program equals the start state of
the right one.

| Constructor            | Emitted text  | Effect on the indices                                                    |
|------------------------|---------------|--------------------------------------------------------------------------|
| `Push n`               | `n`           | `sd + 1`                                                                 |
| `Drop`                 | `DROP`        | `sd - 1`                                                                 |
| `Add`                  | `+`           | `sd - 1` (consumes two, produces one)                                    |
| `Div`                  | `/`           | `sd - 1` (consumes two, produces one)                                    |
| `Ext1`                 | `EXT1`        | `sd + 1` (the residue slot)                                              |
| `CoExecute xt1 xt2`    | `CO-EXECUTE`  | Both branches must end at the same depth; `xt2` starts one item deeper   |
| `ToOrtho`              | `>ORTHO`      | Moves exactly four items from the data stack to the orthogonal stack     |
| `FromOrtho`            | `ORTHO>`      | Moves exactly four items back                                            |
| `ClContract`           | `CL-CONTRACT` | No change to depths                                                      |
| `TxBegin`              | `[H`          | `tx` must be `False`, becomes `True` (no nesting)                        |
| `TxEnd`                | `]H`          | `tx` must be `True`, becomes `False`                                     |
| `Raw s`                | `s`           | No change; emits `s` verbatim                                            |

### Recovery with `CoExecute`

`CoExecute xt1 xt2` pairs a primary operator with a recovery operator. If the
primary operator raises a synchronous exception, control moves to `xt2` and the
exception syndrome is passed as a residue, which is why `xt2` begins with one
extra item on the stack. The type forces both paths to converge to the same
depth, so the code that follows never needs to know which path ran.

The sample program divides 10 by 0 and falls back to 9999:

```idris
CoExecute Div (Ext1 >>> Drop >>> Drop >>> Drop >>> Drop >>> Push 9999)
```

The recovery branch starts at depth 3 (two operands plus the residue) and must
end at depth 1, the depth the primary branch leaves.

## Runtime conventions

| Item                         | Convention                                                                   |
|------------------------------|------------------------------------------------------------------------------|
| Entry                        | `_start` in `boot.S`, running at EL1                                         |
| Data stack                   | `SP_EL0`, 32 KiB, top at `__forth_dstack_top`                                |
| Return / exception stack     | `SP_EL1`, 32 KiB, top at `__forth_rstack_top`                                |
| Memory map                   | 128 MiB of RAM at `0x40000000` (QEMU `virt`)                                 |
| Vector table                 | `el1_vector_table`, 16 entries of 128 bytes, aligned to 2 KiB                |
| Recovery token               | `x28` holds the address of `xt2`, or 0 when no `CO-EXECUTE` is active        |
| Recovery path                | A synchronous exception at EL1 with `SP_ELx` (vector offset `0x200`) loads `ELR_EL1` from `x28`, passes `ESR_EL1` in `x0`, clears `x28` and executes `ERET` |
| Fatal path                   | Any other exception, or a synchronous exception with `x28 = 0`, parks in `WFE` |
| Boot hand-off                | `boot.S` jumps to `forth_cold_boot`, which the generated dictionary defines  |

`boot.S` enables FP, ASIMD and SVE/SVE2 without trapping (`CPACR_EL1`), installs
the vector base, sets up both stacks and clears `x28` before the first word
runs.

## Repository layout

```
.github/workflows/ci.yml            Continuous integration
irundykue.ipkg                      Idris 2 package description
build.zig                           Zig build graph
src/Main.idr                        Generator entry point and the prototype AST
src/Irundykue/AST.idr               Indexed Forth AST (planned home, currently a stub)
src/Irundykue/Codegen/AArch64.idr   AArch64 assembly emission (placeholder dictionary)
src/Irundykue/Types/Singularity.idr Type-level singularity machinery (stub)
src/arch/aarch64/boot.S             Reset entry: CPACR_EL1, VBAR_EL1, stacks
src/arch/aarch64/vectors.S          EL1 exception vector table and recovery handler
src/arch/aarch64/linker.ld          Memory map for the QEMU virt machine
generated/                          Output of irundykue-gen (git-ignored)
docs/REFERENCES.md                  Design background and upstream correspondence
test/                               Tests (empty so far)
```

## Continuous integration

The workflow in `.github/workflows/ci.yml` runs on pushes and pull requests to
`feature/init`, and on manual dispatch. It:

1. installs QEMU, Chez Scheme and GMP, and sets up Zig (pinned to 0.17.0);
2. builds Idris 2 from source (cached) and type-checks the package;
3. runs `zig build` and inspects the ELF;
4. boots the kernel in QEMU for five seconds and requires the banner
   `cold boot at EL1` and a timeout exit status (124);
5. uploads `irundykue-syry.elf` and `irundykue-syry.bin` as artifacts.

The smoke test uses `-M virt` without `virtualization=on`, because QEMU enters
the kernel at EL2 when virtualization is enabled while `boot.S` expects EL1. It
also passes `-nic none`; the default network device needs the `efi-virtio.rom`
option ROM from the `ipxe-qemu` package, which is not installed with
`--no-install-recommends`. If `zig build run` fails with `failed to find romfile
"efi-virtio.rom"` on your machine, install `ipxe-qemu` or add `-nic none` to the
QEMU arguments in `build.zig`.

## Status

Working:

- the indexed `Forth` AST, the `>>>` combinator and compilation to Forth text;
- `--emit-asm`, which writes a placeholder dictionary defining
  `forth_cold_boot`;
- the EL1 boot path, vector table and recovery handler, assembled and linked
  by Zig;
- booting under QEMU and printing the banner and the current exception level
  over the PL011 UART.

Not implemented yet:

- the Forth inner interpreter and the real dictionary;
- the Forth 2012 core word set and any conformance testing;
- the split of `src/Main.idr` into `Irundykue.AST`, `Irundykue.Codegen.AArch64`
  and `Irundykue.Types.Singularity` (the prototype AST still lives in `Main`);
- tests.

## Known limitations

- **Division by zero does not trap.** AArch64 `SDIV` and `UDIV` return 0 for a
  zero divisor without raising an exception. The `/` word has to test the
  divisor and raise an exception explicitly for `CO-EXECUTE` recovery to
  trigger.
- **TME cannot be assembled or run with the current toolchain.** Zig 0.17.0 has
  no `tme` CPU feature and QEMU 8.2.2 with `-cpu max` reports
  `ID_AA64ISAR0_EL1.TME = 0`. `TxBegin` and `TxEnd` are type-checked and emitted
  as text only. Older Zig releases (0.14 to 0.16 were checked) do list `tme`,
  and `build.zig` enables it when the running Zig provides it.
- **The types check shape, not meaning.** `CoExecute` enforces that both paths
  end at the same stack depth. It does not yet express that the recovery result
  is independent of the failure that triggered it, nor that it distinguishes
  exactly the failures it should.
- **Non-nesting of transactions is an implementation rule.** The `Bool` index
  forbids nested `[H`, which is a discipline of this dialect and not a property
  taken from the background material.

## Background

The design draws on a set of Agda notes about recovering information lost by a
coarse map with a second operator, and about Clifford and Heisenberg structures
over Cayley-Dickson algebras. The relation between those notes and the words of
this dialect is a set of analogies, not a formal derivation. Each construct is
classified as grounded, analogy, name only, mismatch or open in
[`docs/REFERENCES.md`](docs/REFERENCES.md), together with the upstream
statements it corresponds to.

## License

BSD-3-Clause license