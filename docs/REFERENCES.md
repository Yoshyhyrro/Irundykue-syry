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
