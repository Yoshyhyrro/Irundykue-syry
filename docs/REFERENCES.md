# References

## Upstream material

- Repository: <https://github.com/Yoshyhyrro/hatsu-yakitori>
- Branch: `feature/sedenion_bridge_Agda`
- `dist-proof/Agda/src/CayleyDicksonQuiver/AbelianCurse/SecondOperatorLemmas.agda`
- `dist-proof/Agda/note/AbelianCurseHypotheses.lagda.md`
- `dist-proof/Agda/note/CarabinerHypotheses.lagda.md`
- `Hypotheses.agda` (module `CayleyDicksonQuiver.Hypotheses`), the `--safe`
  part of the Carabiner scratchpad.
- `dist-proof/Agda/src/CayleyDicksonQuiver/AssociatorRelation.agda` (new; not
  imported by `Everything`, may contain holes) and the changes to
  `CayleyDicksonQuiver/Properties.agda` and to the Carabiner note.

The Agda statements of the latest upstream change were read for this table but
not type-checked here. Its numerical claims about kernel dimensions were
recomputed independently with the repository's Cayley-Dickson multiplication and
all of them reproduce (see the `ToOrtho` row).

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
- `PathEquivT t` (`AssociatorRelation.agda`) adds to `PathEquiv` the relation
  "arrows of equal type `t` give equivalent one-step paths". For every `t`, a
  monoid-valued assignment respects it exactly when it is constant on the
  fibres of `t` (`Eval.respects⇒ev`, `ev⇒respects`); an assignment that
  separates five pairs cannot respect any `t` with four values
  (`NoGo.no-respect`); what always factors is the word of types along a path
  (`TypeWord.type-word-invariant`). `PathEquiv` alone has no generating
  relation and is propositional equality (`equiv⇒≡`), so well-definedness of a
  functor out of the path category is not a test of anything.
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
| `ToOrtho` / `FromOrtho`, exactly 4 slots | (a) AC10 `CliffordContraction`: `Cl_N(2)` has basis `1, X, Y, Z = XY`. (b) H15 and H17: the chain `n > nu1 > nu2 > 0` is `16 > 8 > 4 > 0` at `k = 4` but `8 > 4 > 2 > 0` at `k = 3`. (c) Carabiner note, kernel quiver: for exactly 42 of the 120 seeds `e_i + e_j` the kernel of `L_{e_i + e_j}` on `CD 4` has dimension 4; at levels 5 and 6 the nonzero kernel dimensions are multiples of 4 (4, 8, 12, and 4 to 28), but intersecting the kernels of two seeds gives dimension 2 (42 pairs) or 0 (819 pairs), and of three seeds 0. | (a) Agda. (b), (c) numerical; (c) recomputed independently for this project | Plausible source | Source (a) gives 4 for every `N`; in (b) and (c) the value 4 is specific to `CD 4`. A rule that a subspace size is a multiple of 4 (`Sve2DimensionError`) therefore holds for single-seed kernels only, and intersections break it. `quantized-kernel-drop-false` refutes a power-of-two quantization of kernel drops, so "quantization" must not be read as a theorem. SVE vector lengths are multiples of 128 bits, an independent hardware reason for multiples of 4 32-bit lanes. |
| `ClContract` | AC10 `CliffordContraction`: weight grading `mul-scale`, Heisenberg relations at `N = 0` or modulo a prime dividing `N` (`bracket-descends-at-0`, `bracket-drift-divisible`). | Agda | Name only | "Contraction" appears upstream only as a module name. `ClContract` has an identity stack effect and no defined semantics yet. |
| `TxBegin` / `TxEnd` | AC10: integral Heisenberg group `H` (`commutator-formula`, `even-central-is-commutator`; the loss is `[H,H] = {1 + 2kZ}`). H17: plan for `H_3(F_p)`. | AC10: Agda. H17: numerical; nothing about `H_3(F_p)` is formalized yet | Name only | Upstream says nothing about transactions or non-nesting. It also records that the Heisenberg relations hold where `S_ij = 0` and fail at genuine zero-divisor seeds (H16 case B), so the Heisenberg label and the singular path belong to opposite upstream regimes. |
| `Div` by zero as a singularity | H8 and H10 give the upstream link to zero divisors (see the singular case above). In the algebra, division by a zero divisor fails because `L_x` has a nonzero kernel; for the 42 seeds above that kernel has dimension 4. | numerical | Open | AArch64 `SDIV` and `UDIV` return 0 on a zero divisor without raising an exception, so the `/` word must test the divisor and raise explicitly. |
| Invariance of the recovery value (`test/neuron.tatatina`, question Q2) | `AssociatorRelation.agda`: `PathEquivT t`, `Eval.respects⇒ev` and `ev⇒respects`, `NoGo.no-respect`, `TypeWord.type-word-invariant`. | Agda, stated upstream; not re-checked here | Analogy (proposal) | A map respects the relation that identifies runs of equal type exactly when it is constant on the fibres of the type, and a map that separates more values than the type has cannot factor through it. For the recovery path of the neuron the type `(w_u = 0, w_v)` makes the question testable: the result must not change when only `x` changes, and it does change with `w_v`, so `w_u = 0` alone is too coarse. This is a proposal of this project: Forth runs are not paths of the upstream quiver, and the fibre statement is the universal property of a quotient, so it gives a way to state and test invariance, not a derived-category result. |

## Open questions

- Which notion of singular should the type system track: a runtime operand
  equal to zero, or a seed pair with `S_ij != 0`?
- Upstream lists a uniform completeness lemma (for any `T` with a verified
  Smith form) as open; the dialect cannot assume one.
- Derived categories and D-modules: `Ext^1` is a derived-functor object and the
  notes realise it as the cokernel of a coboundary map, but nothing upstream,
  including the latest change, concerns D-modules, differential operators or
  learning rules. Whether the second-operator lemmas can serve at A/0 in a
  derived-category-like way is a question of this project (`test/neuron.tatatina`,
  Q1 and Q2), not a statement of the notes.
- Which equivalence of runs is the "noise" for the neuron? The type
  `(w_u = 0, w_v)` is proposed in the `Invariance of the recovery value` row;
  the completeness half (the result changes only with the noise) has no
  counterpart yet.
- Kernel dimensions of single seeds are multiples of 4 (levels 4 to 6), but
  intersections of kernels are not (dimension 2 for pairs of seeds in the same
  `i XOR j` group at level 4). The orthogonal stack needs a decision: single-seed
  kernels only, or any intersection.
- FEAT_TME: the tooling used to verify this repository (Zig 0.17.0, QEMU
  8.2.2 with `-cpu max`) has no `tme` CPU feature and reports
  `ID_AA64ISAR0_EL1.TME = 0`. `TxBegin` / `TxEnd` can be type-checked and
  emitted as text but not assembled or executed there.