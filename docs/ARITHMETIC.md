# Arithmetic of the dialect

## Decisions

1. `+` and `*` are fixed-width wraparound operations. The result is reduced modulo
   `2^w`, where `w` is the bit width of the operand type, and no THROW code is
   raised.
2. Signed and unsigned integers are different types, also when they have the same
   bit width.
3. A checked operation does not return a result when the exact result lies outside
   the range of its type: it throws `-11` (result out of range) and leaves no
   result on the stack.
4. `-11` is used for checked arithmetic only. A wraparound operation never raises
   it.

## Consequence for the recovery value

A wrapping cell is a residue modulo `2^w` that forgets the size
(`CappedResidue.agda`, `residue-loses-size`). In `test/neuron.tatatina` the
recovery value `ext1 * w_v`, with `ext1 = -10`, is therefore `0` both for
`w_v = 0` and for `w_v = -2^63` (Test 5). A checked multiplication throws `-11` in
the second case instead. The size bit of `CappedResidue.agda` is not used.

## Not specified in this version

- the details of implicit conversions between types;
- the correspondence of `-4` (stack underflow) and `-13` (undefined word) with the
  existing codes;
- the external representation of secondary errors, that is, errors raised while a
  recovery path runs;
- a limit on the recursive execution of recovery paths.
