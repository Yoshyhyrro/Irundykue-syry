# `.nanduti`: a symbolic Piet dialect

Status: the intended scope of the dialect. Nothing in this document is implemented
yet. The extension `.nanduti` is registered in the extension registry of the manifest
generator (`configuration_file_Generate.idr`); the `--list-extensions` option of the
generator lists it.

## Base

A `.nanduti` file is a symbolic program in a dialect of Piet. The dialect starts
from the commands of Piet and gives them a different semantics. Piet has 17
commands; they are selected by the change of hue and lightness between two blocks
in a table of 18 cells, and the cell without a change carries no command.

## Nodes

A node holds a command word, not a single command:

```
N_i = (P_i, S_i, R_i)
```

- `P_i`: the command word, a sequence of Piet commands;
- `S_i`: the execution state;
- `R_i`: the residue information that the node has received.

Edges between nodes carry a value `E_ij`:

```
E_ij = 0   the normal propagation from node i to node j is blocked
E_ij = 1   the propagation is allowed
E_ij = c   the propagation is conditional
```

## Layers

| Layer | Name                | Content                                                                                   |
|-------|---------------------|-------------------------------------------------------------------------------------------|
| 3     | Meta-Piet           | Comparison, selection, composition and evaluation of command words.                       |
| 2     | Piet node network   | Groups of nodes that hold several command words; local evaluation and feature extraction. |
| 1     | Algebraic residue   | Kernel, image, cokernel, residue classes and exception information.                       |

Layer 3 compares command words by their traces on the same failure packet `F`:

```
Compare(Trace(P_1, F), Trace(P_2, F), Trace(P_3, F))
```

## The failure packet

```
F = (e, x, w_u, w_v, ρ)
```

- `e`: the THROW code of the failure, one of the codes of `docs/EXCEPTIONS.md`;
- `x`, `w_u`, `w_v`: the operands, as in `test/neuron.tatatina`;
- `ρ`: the residue, described next.

## Cokernel-aware execution

In scope v1 the value that `EXT1` carries is the THROW code `e`, a plain exception
number. The dialect extends it to a residue type that depends on an operator:

```
Residue(R_b) = A / im(R_b)
```

where `R_b` is an operator and `A` the module that contains its image. A
representative and an element of the quotient are distinguished. The runtime keeps
the information that it needs to interpret a class, namely the basis, the
dimension and the identity of the operator. This information is passed to every
node of a `.nanduti` program as `R_i`.

## Relation to the rest of the repository

- `docs/EXCEPTIONS.md` fixes `e`; the extension to `ρ` does not change the codes.
- `docs/ARCHITECTURE.dot` shows the layers and their status.
- `docs/REFERENCES.md` lists the upstream results that the residue layer is built
  on: the cokernel as `Ext^1`, the normal form of `CappedResidue.agda`, and the
  fibre criterion of `AssociatorRelation.agda`.
