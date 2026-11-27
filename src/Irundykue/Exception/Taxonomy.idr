module Irundykue.Exception.Taxonomy

import Data.List
import Data.So
import Data.String

%default total

-- THROW codes of Irundykue-syry.
--
-- Forth 2012, section 9.3.1, divides the THROW values:
--
--   -255 ... -1       used only as assigned by the standard (Table 9.1)
--   -4095 ... -256    used only as assigned by a system
--
-- and 9.3.4 requires a system that throws on a condition listed in Table 9.1
-- to use the listed code. This module therefore follows two rules:
--
--   1. A condition that Table 9.1 lists always keeps its standard number,
--      whether it is thrown by the dialect or absorbed by CO-EXECUTE.
--   2. A condition that is specific to this dialect gets a system number in
--      -4095 ... -256. The type `Code` makes any other choice a type error.
--
-- The standard does not require a system to throw every code of Table 9.1, so
-- this table is deliberately partial. The scope (version 1) is documented in
-- docs/EXCEPTIONS.md, which must be updated together with this module. It is the "values used in the system by
-- CATCH and THROW" that 9.4.1.1 asks implementations to document.

public export
data Origin = Standard | System

public export
inRange : Origin -> Int -> Bool
inRange Standard n = n >= -255 && n <= -1
inRange System   n = n >= -4095 && n <= -256

-- A THROW code together with the proof that it lies in the range of its origin.
public export
data Code : Origin -> Type where
  MkCode : {o : Origin} -> (n : Int) -> {auto 0 ok : So (inRange o n)} -> Code o

public export
codeValue : Code o -> Int
codeValue (MkCode n) = n

public export
data AnyCode = Std (Code Standard) | Sys (Code System)

public export
anyValue : AnyCode -> Int
anyValue (Std c) = codeValue c
anyValue (Sys c) = codeValue c

-- Conditions that CO-EXECUTE can absorb. The residue handed to the recovery
-- operator is the same number that THROW would carry, so code written against
-- the standard sees the same value in both cases.
public export
data SingularityToken
  = DivByZeroResidue     -- -10 division by zero
  | TranslationAbort     -- -9  invalid memory address
  | ContractionDefect    -- -11 result out of range (checked arithmetic only)

public export
tokenCode : SingularityToken -> Code Standard
tokenCode DivByZeroResidue  = MkCode (-10)
tokenCode TranslationAbort  = MkCode (-9)
tokenCode ContractionDefect = MkCode (-11)

public export
data CoreException
  -- Standard conditions that the dialect keeps.
  = AbortExplicit                      -- -1  ABORT
  | AbortWithMessage                   -- -2  ABORT"
  | DictionaryOverflow                 -- -8  dictionary overflow
  | ReadOnlyFault                      -- -20 write to a read-only location
  | AlignmentFault                     -- -23 address alignment exception
  -- A singularity raised outside CO-EXECUTE: thrown with the standard code.
  | Unabsorbed SingularityToken
  -- Armv9-A conditions with no counterpart in Table 9.1: system codes.
  | TmeConflict                        -- hardware transaction aborted
  | PacViolation                       -- pointer authentication failed
  | Sve2DimensionError                 -- a transfer is not exactly four cells

public export
classify : CoreException -> AnyCode
classify AbortExplicit      = Std (MkCode (-1))
classify AbortWithMessage   = Std (MkCode (-2))
classify DictionaryOverflow = Std (MkCode (-8))
classify ReadOnlyFault      = Std (MkCode (-20))
classify AlignmentFault     = Std (MkCode (-23))
classify (Unabsorbed t)     = Std (tokenCode t)
classify TmeConflict        = Sys (MkCode (-256))
classify PacViolation       = Sys (MkCode (-257))
classify Sve2DimensionError = Sys (MkCode (-258))

public export
toThrowCode : CoreException -> Int
toThrowCode = anyValue . classify

public export
tokenValue : SingularityToken -> Int
tokenValue = codeValue . tokenCode

public export
describe : CoreException -> String
describe AbortExplicit                    = "ABORT"
describe AbortWithMessage                 = "ABORT\""
describe DictionaryOverflow               = "dictionary overflow"
describe ReadOnlyFault                    = "write to a read-only location"
describe AlignmentFault                   = "address alignment exception"
describe (Unabsorbed DivByZeroResidue)    = "division by zero"
describe (Unabsorbed TranslationAbort)    = "invalid memory address"
describe (Unabsorbed ContractionDefect)   = "result out of range"
describe TmeConflict                      = "hardware transaction aborted"
describe PacViolation                     = "pointer authentication failed"
describe Sve2DimensionError               = "orthogonal stack transfer is not exactly four cells"

public export
allExceptions : List CoreException
allExceptions =
  [ AbortExplicit, AbortWithMessage, DictionaryOverflow, ReadOnlyFault, AlignmentFault
  , Unabsorbed DivByZeroResidue, Unabsorbed TranslationAbort, Unabsorbed ContractionDefect
  , TmeConflict, PacViolation, Sve2DimensionError ]

public export
fromThrowCode : Int -> Maybe CoreException
fromThrowCode n = find (\e => toThrowCode e == n) allExceptions

-- ---------------------------------------------------------------------------
-- Properties checked by the compiler
-- ---------------------------------------------------------------------------

-- Every THROW code the dialect uses, in table order.
public export
usedCodes : List Int
usedCodes = map toThrowCode allExceptions

-- No two exceptions share a THROW code.
export
distinctCodes : nub Taxonomy.usedCodes = Taxonomy.usedCodes
distinctCodes = Refl

-- Every code can be decoded back to the exception that produced it.
export
roundTrip : (e : CoreException) -> fromThrowCode (toThrowCode e) = Just e
roundTrip AbortExplicit                  = Refl
roundTrip AbortWithMessage               = Refl
roundTrip DictionaryOverflow             = Refl
roundTrip ReadOnlyFault                  = Refl
roundTrip AlignmentFault                 = Refl
roundTrip (Unabsorbed DivByZeroResidue)  = Refl
roundTrip (Unabsorbed TranslationAbort)  = Refl
roundTrip (Unabsorbed ContractionDefect) = Refl
roundTrip TmeConflict                    = Refl
roundTrip PacViolation                   = Refl
roundTrip Sve2DimensionError             = Refl

-- A singularity keeps its standard code whether it is absorbed or thrown.
export
singularityKeepsCode : (t : SingularityToken) -> toThrowCode (Unabsorbed t) = tokenValue t
singularityKeepsCode DivByZeroResidue  = Refl
singularityKeepsCode TranslationAbort  = Refl
singularityKeepsCode ContractionDefect = Refl

-- One "code<TAB>name<TAB>origin" row per exception, for the documentation.
public export
exceptionTable : String
exceptionTable = unlines (map row allExceptions)
  where
    originName : AnyCode -> String
    originName (Std _) = "standard"
    originName (Sys _) = "system"

    row : CoreException -> String
    row e = show (toThrowCode e) ++ "\t" ++ describe e ++ "\t" ++ originName (classify e)