# Error codes of Irundykue-syry (scope v1)

This table is the complete set of THROW codes that Irundykue-syry generates. The
source of truth is `src/Irundykue/Exception/Taxonomy.idr`: the Idris compiler
checks there that no two conditions share a code, that every code decodes back
to its condition, that standard conditions use only numbers in `-255 ... -1` and
dialect conditions only numbers in `-4095 ... -256`, and that a singularity keeps
its standard code whether it is thrown or absorbed. The Forth names of the codes are in
`lib/errors.irundykue`, the counterpart of `errno.h`; `make errors-check` compares that file
with the Idris module. This document must be updated together with both.

## Rules

1. Forth 2012, section 9.3.1: values in `-255 ... -1` are used only as assigned by
   the standard (Table 9.1), values in `-4095 ... -256` only as assigned by a
   system, and programs must not define values in `-4095 ... -1`.
2. Section 9.3.4: a system that throws on a condition listed in Table 9.1 uses the
   listed code. A condition of Table 9.1 therefore keeps its number here.
3. A condition that Table 9.1 does not list gets a system code in `-4095 ... -256`.
4. A failure is described by the packet `F = (e, x, w_u, w_v, rho)`: `e` is a THROW code
   of this table, `x`, `w_u` and `w_v` are the operands (as in `test/neuron.tatatina`), and
   `rho` is the residue (`docs/NANDUTI.md`). In this version the value that `CO-EXECUTE`
   hands to a recovery operator is `e` (for example `-10`), not the raw `ESR_EL1` value. A
   singularity outside `CO-EXECUTE` is thrown with the same code.
5. The standard does not require a system to throw every code. This table is
   deliberately partial, and it is the documentation of "values used by CATCH and
   THROW" that section 9.4.1.1 asks for.

## Generated codes

| Code   | Name                  | Forth name (`lib/errors.irundykue`) | Meaning (Table 9.1 wording for standard codes) | Raised by                                              | First testable when                          |
|--------|-----------------------|---------------------|-------------------------------------------------|--------------------------------------------------------|----------------------------------------------|
| `-1` | `AbortExplicit` | `ERR-ABORT` | ABORT                                           | the word `ABORT`                                       | the interpreter exists                       |
| `-2` | `AbortWithMessage` | `ERR-ABORT-MESSAGE` | ABORT"                                          | the word `ABORT"`                                      | the interpreter exists                       |
| `-8` | `DictionaryOverflow` | `ERR-DICT-OVERFLOW` | dictionary overflow                             | allocation beyond the reserved dictionary region       | the dictionary exists                        |
| `-9` | `TranslationAbort` | `ERR-INVALID-ADDRESS` | invalid memory address                          | a data abort, absorbed by `CO-EXECUTE` or thrown       | the MMU is configured (`boot.S` does not yet)|
| `-10` | `DivByZeroResidue` | `ERR-DIV-BY-ZERO` | division by zero                                | an explicit divisor test in `/` (AArch64 `SDIV` does not trap) | the word `/` exists                  |
| `-11` | `ContractionDefect` | `ERR-RESULT-RANGE` | result out of range                             | a checked arithmetic operation whose result is out of range (`docs/ARITHMETIC.md`) | checked arithmetic exists |
| `-20` | `ReadOnlyFault` | `ERR-READ-ONLY` | write to a read-only location                   | a permission fault                                     | page tables exist                            |
| `-23` | `AlignmentFault` | `ERR-ALIGNMENT` | address alignment exception                     | an alignment fault                                     | alignment checking is enabled                |
| `-256` | `TmeConflict` | `ERR-TME-ABORT` | hardware transaction aborted (system code)      | a non-zero failure status of `TSTART`                  | not with QEMU 8.2.2 or Zig 0.17.0 (no FEAT_TME) |
| `-257` | `PacViolation` | `ERR-PAC-FAILURE` | pointer authentication failed (system code)     | a failed authentication; hardware dependent            | pointer authentication is enabled            |
| `-258` | `Sve2DimensionError` | `ERR-ORTHO-SIZE` | orthogonal stack transfer is not exactly four cells (system code) | a transfer to or from the orthogonal stack | the interpreter exists                       |

Notes on single codes:

- `-256`: the failure status of `TSTART` has many bits and the code has one value,
  so the map from status to code is many-to-one and cannot be inverted. Keep the
  raw status in a separate cell if it is needed. Compare the quotient reading in
  `docs/REFERENCES.md`, where the upstream notes show `Cl_N(2)` to be a quotient of
  AC4 and not a cover.
- `-257`: with FEAT_FPAC a failed authentication raises a synchronous exception;
  without it the corrupted pointer is expected to fault later as an invalid
  address (`-9`). This is to be confirmed on the target hardware.
- `-258`: the rule that a transfer moves exactly four cells is the type of `ToOrtho`
  and `FromOrtho`. The phrase "a multiple of 4" of the first draft is kept only as
  the hardware reason (SVE vector lengths are multiples of 128 bits, that is, four
  32-bit lanes). It is not a statement about kernel dimensions: upstream, the
  kernels of single seeds `e_i + e_j` on `CD 4` have dimension 4 and at levels 5
  and 6 multiples of 4, but intersecting two seeds gives dimension 2 or 0.

## Not generated

Every other code of Table 9.1 is out of scope for this version, for example stack
overflow and underflow (`-3` to `-6`), undefined word (`-13`), compile-only word
(`-14`), control structure mismatch (`-22`) and the block, file, floating-point
and search-order codes. The standard allows a system not to throw on these
conditions (section 9.4.1.1 asks for the behaviour to be documented). The
behaviour of the system for these conditions is not specified in this version. The
arithmetic that produces `-11`, and what else is left open, is in `docs/ARITHMETIC.md`.