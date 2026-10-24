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
