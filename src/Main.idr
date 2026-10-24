module Main

import Data.String
import System
import System.File

import Irundykue.Codegen.AArch64

-- =====================================================================
-- AST for the Armv8/v9 Singularity Forth Dialect
--
-- The execution context is tracked at the type level using Peano numbers
-- and Booleans to guarantee memory and transaction safety at compile time.
--
-- Type indices:
-- 1. sd : Data Stack Depth (Nat)
-- 2. od : Orthogonal Stack (SVE2) Depth (Nat)
-- 3. tx : Heisenberg Transaction State (Bool)
-- =====================================================================

data Forth : (sd : Nat) -> (od : Nat) -> (tx : Bool) ->
             (sd' : Nat) -> (od' : Nat) -> (tx' : Bool) -> Type where

  -- Sequence combinator
  Seq : Forth s1 o1 t1 s2 o2 t2 -> Forth s2 o2 t2 s3 o3 t3 -> Forth s1 o1 t1 s3 o3 t3

  -- Core Forth Words
  Push : Int -> Forth sd od tx (S sd) od tx
  Drop : Forth (S sd) od tx sd od tx
  Add  : Forth (S (S sd)) od tx (S sd) od tx
  Div  : Forth (S (S sd)) od tx (S sd) od tx

  -- =====================================================================
  -- Coarse Map and Second Operator (Singularity Recovery)
  --
  -- CO-EXECUTE takes two execution tokens.
  -- xt1 : The primary operator (L_u) which may cause a singularity.
  -- xt2 : The secondary operator (L_v) for orthogonal recovery.
  --
  -- Notice the type of xt2: it starts with (S sd) because the singularity
  -- residue (Ext^1) is mathematically pushed onto the stack.
  -- Both paths must converge to the exact same stack depth (sd').
  --
  -- Note: this type enforces depth convergence only. The upstream pair
  -- (L_u, L_v) anticommutes (fg + gf = 0 in the Clifford case, AC10),
  -- whereas a Koszul complex (AC8) concerns commuting operators. The
  -- invariance and completeness properties of the second operator are not
  -- yet expressed at the type level. See docs/REFERENCES.md.
  -- =====================================================================
  CoExecute : (xt1 : Forth sd od tx sd' od tx) ->
              (xt2 : Forth (S sd) od tx sd' od tx) ->
              Forth sd od tx sd' od tx

  Ext1 : Forth sd od tx (S sd) od tx

  -- =====================================================================
  -- Clifford Contraction (4-dimensional quantization via SVE2)
  --
  -- Moving data to the orthogonal subspace requires exactly 4 dimensions,
  -- matching dim Cl_N(2) = 4 (basis 1, X, Y, XY). No quantization theorem
  -- is claimed upstream; see docs/REFERENCES.md.
  -- =====================================================================
  ToOrtho    : Forth (S (S (S (S sd)))) od tx sd (S (S (S (S od)))) tx
  FromOrtho  : Forth sd (S (S (S (S od)))) tx (S (S (S (S sd)))) od tx
  ClContract : Forth sd od tx sd od tx

  -- =====================================================================
  -- Heisenberg Transaction (TME)
  --
  -- Prevents nested transactions and enforces closure via the Bool flag.
  -- The flag is an implementation discipline; upstream makes no statement
  -- about transactions.
  -- =====================================================================
  TxBegin : Forth sd od False sd od True
  TxEnd   : Forth sd od True sd od False

  -- Raw code emission for words without side-effects on depth
  Raw : String -> Forth sd od tx sd od tx

-- Operator for chaining AST nodes
infixl 1 >>>
(>>>) : Forth s1 o1 t1 s2 o2 t2 -> Forth s2 o2 t2 s3 o3 t3 -> Forth s1 o1 t1 s3 o3 t3
(>>>) = Seq

-- Compiler: AST to Forth string
compile : Forth s1 o1 t1 s2 o2 t2 -> String
compile (Seq x y) = compile x ++ " " ++ compile y
compile (Push x) = show x
compile Drop = "DROP"
compile Add = "+"
compile Div = "/"
compile (CoExecute xt1 xt2) =
  "[: " ++ compile xt1 ++ " ;] [: " ++ compile xt2 ++ " ;] CO-EXECUTE"
compile Ext1 = "EXT1"
compile ToOrtho = ">ORTHO"
compile FromOrtho = "ORTHO>"
compile ClContract = "CL-CONTRACT"
compile TxBegin = "[H"
compile TxEnd = "]H"
compile (Raw s) = s

-- =====================================================================
-- Sample Program Definition
-- Starts with 0 stack depth, 0 ortho depth, and False transaction state.
-- Ends with 5 items on the stack.
-- =====================================================================
prog : Forth 0 0 False 5 0 False
prog =
  -- 1. Singularity Recovery (A/0)
  --    The recovery branch starts at depth 3 (two operands plus the Ext^1
  --    residue) and must end at depth 1, the depth left by the primary branch.
  Push 10 >>> Push 0 >>>
  CoExecute Div (Ext1 >>> Drop >>> Drop >>> Drop >>> Drop >>> Push 9999) >>>

  -- 2. Orthogonal Subspace and Heisenberg Transaction
  Push 1 >>> Push 2 >>> Push 3 >>> Push 4 >>>
  ToOrtho >>>
  TxBegin >>>
  ClContract >>>
  TxEnd >>>
  FromOrtho

-- Writes the placeholder dictionary assembly to PATH.
emitAsm : String -> IO ()
emitAsm path = do
  Right () <- writeFile path dictionaryAsm
    | Left err => do
        putStrLn ("error: cannot write " ++ path ++ ": " ++ show err)
        exitFailure
  putStrLn ("wrote " ++ path)

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "--emit-asm", path] => emitAsm path
    _ => do
      putStrLn "\\ Generated Forth 2012 (Armv8/v9 Singularity Dialect) code"
      putStrLn (compile prog)
