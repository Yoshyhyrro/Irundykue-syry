module Main

-- configuration_file_Generate.idr
--
-- Generates the project manifest (project.syryaml) of Irundykue-syry.
--
-- The manifest is first collected as raw strings (Draft), then validated in
-- one pass into a typed Manifest, and only then rendered. File names carry
-- their extension in the type: a `KPath k` can only be built for a path whose
-- extension matches the file kind `k`, so a manifest that names
-- `src/main.4th` as its executable cannot be constructed.
--
-- All problems are reported together. The program writes the manifest to
-- standard output and diagnostics to standard error; the driver script
-- configuration_file_Generate.bash takes care of the file system.
--
-- Run with --help for the command line.

import Data.List
import Data.List1
import Data.Maybe
import Data.So
import Data.String
import System
import System.File

%default total

-- ---------------------------------------------------------------------------
-- File kinds and extensions
-- ---------------------------------------------------------------------------

data Kind = ManifestFile | ExecutableFile | DefinitionFile | LegacyFile

allKinds : List Kind
allKinds = [ManifestFile, ExecutableFile, DefinitionFile, LegacyFile]

extensionOf : Kind -> String
extensionOf ManifestFile   = ".syryaml"
extensionOf ExecutableFile = ".tatatina"
extensionOf DefinitionFile = ".irundykue"
extensionOf LegacyFile     = ".4th"

describeKind : Kind -> String
describeKind ManifestFile   = "project manifest"
describeKind ExecutableFile = "main executable stream"
describeKind DefinitionFile = "definitions and specifications"
describeKind LegacyFile     = "legacy Forth asset"

-- ---------------------------------------------------------------------------
-- Character classes and relative paths
-- ---------------------------------------------------------------------------

isLowerAscii : Char -> Bool
isLowerAscii c = c >= 'a' && c <= 'z'

isUpperAscii : Char -> Bool
isUpperAscii c = c >= 'A' && c <= 'Z'

isDigitAscii : Char -> Bool
isDigitAscii c = c >= '0' && c <= '9'

isAlnumAscii : Char -> Bool
isAlnumAscii c = isLowerAscii c || isUpperAscii c || isDigitAscii c

isControlChar : Char -> Bool
isControlChar c = ord c < 32 || ord c == 127

isPathChar : Char -> Bool
isPathChar c = isAlnumAscii c || c == '_' || c == '.' || c == '/' || c == '-'

segments : String -> List String
segments s = forget (split (== '/') s)

-- A relative path made of non-empty segments, none of which is "." or "..".
isSafeRelPath : String -> Bool
isSafeRelPath s =
     s /= ""
  && all isPathChar (unpack s)
  && all okSegment (segments s)
  where
    okSegment : String -> Bool
    okSegment seg = seg /= "" && seg /= "." && seg /= ".."

-- The last segment must end with the extension and have a non-empty stem.
hasExtension : String -> String -> Bool
hasExtension ext path =
  case last' (segments path) of
    Nothing   => False
    Just base => isSuffixOf ext base && length (unpack base) > length (unpack ext)

-- A path whose extension is fixed by its kind.
data KPath : Kind -> Type where
  MkKPath : {k : Kind} -> (text : String)
         -> {auto 0 ok : So (isSafeRelPath text && hasExtension (extensionOf k) text)}
         -> KPath k

pathText : KPath k -> String
pathText (MkKPath text) = text

badPath : String -> String
badPath s =
  "invalid path '" ++ s ++ "': expected a relative path of [A-Za-z0-9_./-] "
  ++ "without empty, '.' or '..' segments"

diagnosePath : Kind -> String -> String
diagnosePath k s =
  if not (isSafeRelPath s)
    then badPath s
    else "'" ++ s ++ "' must end with the extension " ++ extensionOf k
         ++ " (" ++ describeKind k ++ ") and have a non-empty file name"

mkKPath : (k : Kind) -> String -> Either String (KPath k)
mkKPath k s =
  case choose (isSafeRelPath s && hasExtension (extensionOf k) s) of
    Left ok => Right (MkKPath {k} s {ok})
    Right _ => Left (diagnosePath k s)

-- ---------------------------------------------------------------------------
-- Target description
-- ---------------------------------------------------------------------------

data Arch = AArch64NoneElf

archName : Arch -> String
archName AArch64NoneElf = "aarch64-none-elf"

parseArch : String -> Maybe Arch
parseArch s = if s == "aarch64-none-elf" then Just AArch64NoneElf else Nothing

data Feature = Sve2 | Pac | Tme

Eq Feature where
  Sve2 == Sve2 = True
  Pac  == Pac  = True
  Tme  == Tme  = True
  _    == _    = False

allFeatures : List Feature
allFeatures = [Sve2, Pac, Tme]

featureName : Feature -> String
featureName Sve2 = "sve2"
featureName Pac  = "pac"
featureName Tme  = "tme"

parseFeature : String -> Maybe Feature
parseFeature s = find (\f => featureName f == s) allFeatures

-- Facts about toolchain support that the manifest cannot express.
caveat : Feature -> Maybe String
caveat Tme = Just ("feature 'tme' (FEAT_TME) is not provided by every toolchain: "
                   ++ "it is absent from Zig 0.17.0 and not emulated by QEMU 8.2.2 (-cpu max)")
caveat _   = Nothing

-- ---------------------------------------------------------------------------
-- Validation that collects every error
-- ---------------------------------------------------------------------------

data V : Type -> Type where
  Bad : List String -> V a
  Ok  : a -> V a

Functor V where
  map f (Ok x)  = Ok (f x)
  map _ (Bad e) = Bad e

Applicative V where
  pure = Ok
  Ok f   <*> Ok x   = Ok (f x)
  Ok _   <*> Bad e  = Bad e
  Bad e  <*> Ok _   = Bad e
  Bad e1 <*> Bad e2 = Bad (e1 ++ e2)

failWith : String -> V a
failWith msg = Bad [msg]

-- Attaches a field name to the error of an Either.
liftField : String -> Either String a -> V a
liftField _     (Right x) = Ok x
liftField field (Left e)  = failWith (field ++ ": " ++ e)

-- ---------------------------------------------------------------------------
-- The manifest
-- ---------------------------------------------------------------------------

record Manifest where
  constructor MkManifest
  mName         : String
  mDescription  : String
  mVersion      : String
  mLicense      : String
  mAuthors      : List String
  mExecutable   : KPath ExecutableFile
  mSourceDirs   : List String
  mArch         : Arch
  mFeatures     : List Feature
  mDependencies : List (KPath LegacyFile)

-- Raw, unvalidated values.
record Draft where
  constructor MkDraft
  dName         : String
  dDescription  : String
  dVersion      : String
  dLicense      : String
  dAuthors      : List String
  dExecutable   : String
  dSourceDirs   : List String
  dArch         : String
  dFeatures     : List String
  dDependencies : List String

defaultDraft : Draft
defaultDraft = MkDraft
  { dName         = "irundykue_app"
  , dDescription  = "AArch64 bare-metal Forth kernel with singularity resolution"
  , dVersion      = "0.1.0"
  , dLicense      = "BSD-3-Clause"
  , dAuthors      = ["Irundykue-syry Team"]
  , dExecutable   = "src/main" ++ extensionOf ExecutableFile
  , dSourceDirs   = ["src", "lib"]
  , dArch         = "aarch64-none-elf"
  , dFeatures     = ["sve2", "pac", "tme"]
  , dDependencies = ["vendor/compat" ++ extensionOf LegacyFile]
  }

duplicates : List String -> List String
duplicates xs = nub (filter (\x => length (filter (== x) xs) > 1) xs)

validName : String -> V String
validName s =
  if okName (unpack s)
    then Ok s
    else failWith ("name: '" ++ s ++ "' is invalid; use lowercase letters, digits and "
                   ++ "'_', starting with a letter")
  where
    okName : List Char -> Bool
    okName []        = False
    okName (c :: cs) = isLowerAscii c && all (\x => isLowerAscii x || isDigitAscii x || x == '_') cs

validText : String -> String -> V String
validText field s =
  if s == "" then failWith (field ++ ": must not be empty")
  else if any isControlChar (unpack s) then failWith (field ++ ": must not contain control characters")
  else if trim s /= s then failWith (field ++ ": must not start or end with whitespace")
  else Ok s

validVersion : String -> V String
validVersion s =
  if length parts == 3 && all okNumber parts
    then Ok s
    else failWith ("version: '" ++ s ++ "' is invalid; expected MAJOR.MINOR.PATCH")
  where
    parts : List String
    parts = forget (split (== '.') s)

    okNumber : String -> Bool
    okNumber p = p /= "" && all isDigitAscii (unpack p) && (p == "0" || not (isPrefixOf "0" p))

validLicense : String -> V String
validLicense s =
  if s /= "" && all (\c => isAlnumAscii c || c == '.' || c == '-' || c == '+') (unpack s)
    then Ok s
    else failWith ("license: '" ++ s ++ "' is invalid; expected an SPDX identifier such as BSD-3-Clause")

validAuthors : List String -> V (List String)
validAuthors [] = failWith "authors: at least one author is required"
validAuthors xs = traverse (validText "authors") xs

validDirs : List String -> V (List String)
validDirs [] = failWith "source-dirs: at least one directory is required"
validDirs xs =
  traverse check xs <* dupCheck
  where
    check : String -> V String
    check d = if isSafeRelPath d
                then Ok d
                else failWith ("source-dirs: " ++ badPath d)

    dupCheck : V ()
    dupCheck = case duplicates xs of
                 []      => Ok ()
                 (d :: _) => failWith ("source-dirs: '" ++ d ++ "' is listed more than once")

validArch : String -> V Arch
validArch s = case parseArch s of
  Just a  => Ok a
  Nothing => failWith ("target.arch: unsupported '" ++ s ++ "'; supported: aarch64-none-elf")

validFeatures : List String -> V (List Feature)
validFeatures xs =
  traverse check xs <* dupCheck
  where
    check : String -> V Feature
    check s = case parseFeature s of
      Just f  => Ok f
      Nothing => failWith ("target.features: unknown feature '" ++ s ++ "'; supported: "
                           ++ joinBy ", " (map featureName allFeatures))

    dupCheck : V ()
    dupCheck = case duplicates xs of
                 []       => Ok ()
                 (f :: _) => failWith ("target.features: '" ++ f ++ "' is listed more than once")

validate : Draft -> V Manifest
validate d =
  MkManifest
    <$> validName d.dName
    <*> validText "description" d.dDescription
    <*> validVersion d.dVersion
    <*> validLicense d.dLicense
    <*> validAuthors d.dAuthors
    <*> liftField "executable" (mkKPath ExecutableFile d.dExecutable)
    <*> validDirs d.dSourceDirs
    <*> validArch d.dArch
    <*> validFeatures d.dFeatures
    <*> traverse (liftField "dependencies" . mkKPath LegacyFile) d.dDependencies

-- ---------------------------------------------------------------------------
-- YAML rendering
-- ---------------------------------------------------------------------------

-- Words that YAML 1.1 reads as booleans or null.
reservedWords : List String
reservedWords = ["true", "false", "null", "yes", "no", "on", "off", "y", "n", "~"]

-- True for text that YAML would read as a plain number such as 12 or 1.5.
looksNumeric : String -> Bool
looksNumeric s =
  case unpack s of
    ('-' :: rest) => body (pack rest)
    ('+' :: rest) => body (pack rest)
    _             => body s
  where
    body : String -> Bool
    body t =
      let parts = forget (split (== '.') t)
      in  any isDigitAscii (unpack t)
          && length parts <= 2
          && all (all isDigitAscii . unpack) parts

isPlainSafe : String -> Bool
isPlainSafe s =
     s /= ""
  && trim s == s
  && not (any isControlChar (unpack s))
  && not (elem (toLower s) reservedWords)
  && not (looksNumeric s)
  && not (any (\c => elem c (unpack "-?:,[]{}#&*!|>'\"%@`")) (take 1 (unpack s)))
  && not (isInfixOf ": " s)
  && not (isInfixOf " #" s)
  && not (isSuffixOf ":" s)

escapeChar : Char -> String
escapeChar '"'  = "\\\""
escapeChar '\\' = "\\\\"
escapeChar c    = singleton c

quoted : String -> String
quoted s = "\"" ++ concatMap escapeChar (unpack s) ++ "\""

scalar : String -> String
scalar s = if isPlainSafe s then s else quoted s

inlineList : List String -> String
inlineList xs = "[" ++ concat (intersperse ", " xs) ++ "]"

listBlock : String -> List String -> List String
listBlock key []  = [key ++ ": []"]
listBlock key xs  = (key ++ ":") :: map (\x => "  - " ++ scalar x) xs

renderManifest : Manifest -> String
renderManifest m = unlines $
     [ "# Project metadata (Alire-inspired minimalist manifest)"
     , "name: " ++ scalar m.mName
     , "description: " ++ scalar m.mDescription
     , "version: " ++ scalar m.mVersion
     , "licenses: " ++ scalar m.mLicense
     , "authors:"
     ]
  ++ map (\a => "  - " ++ quoted a) m.mAuthors
  ++ [ ""
     , "# Main executable entrypoint (live execution stream)"
     , "executable: " ++ scalar (pathText m.mExecutable)
     , ""
     , "# Library search paths for definitions and specifications ("
         ++ extensionOf DefinitionFile ++ ")"
     ]
  ++ listBlock "source-dirs" m.mSourceDirs
  ++ [ ""
     , "# Hardware target profile (Armv9 bare-metal)"
     , "target:"
     , "  arch: " ++ archName m.mArch
     , "  features: " ++ inlineList (map featureName m.mFeatures)
     , ""
     , "# External libraries and legacy Forth assets (" ++ extensionOf LegacyFile ++ ")"
     ]
  ++ listBlock "dependencies" (map pathText m.mDependencies)

-- One "kind<TAB>path" line per file-system entry that the manifest refers to.
listFiles : Manifest -> String
listFiles m = unlines $
     map (\d => "source-dir\t" ++ d) m.mSourceDirs
  ++ ["executable\t" ++ pathText m.mExecutable]
  ++ map (\p => "dependency\t" ++ pathText p) m.mDependencies

extensionTable : String
extensionTable = unlines (map row allKinds)
  where
    row : Kind -> String
    row k = extensionOf k ++ "\t" ++ describeKind k

-- ---------------------------------------------------------------------------
-- Command line
-- ---------------------------------------------------------------------------

data RunMode = Render | ListFiles | ListExtensions | Help

-- Options that take a value, in the order of the help text.
valueFlags : List String
valueFlags =
  [ "--name", "--description", "--version", "--license", "--author"
  , "--executable", "--source-dir", "--arch", "--features", "--dependency" ]

usage : String
usage = unlines
  [ "Usage: configuration_file_Generate [mode] [options]"
  , ""
  , "Writes the project manifest to standard output. Without options it produces"
  , "the default Irundykue-syry manifest."
  , ""
  , "Modes:"
  , "  --list-files        Print the files and directories that the manifest refers to"
  , "  --list-extensions   Print the registered file extensions"
  , "  --help              Show this help"
  , ""
  , "Options (repeat --author, --source-dir and --dependency to build a list;"
  , "a repeated list option replaces the default list):"
  , "  --name NAME            Project name (lowercase letters, digits, '_')"
  , "  --description TEXT     One-line description"
  , "  --version X.Y.Z        Version"
  , "  --license SPDX         SPDX license identifier"
  , "  --author TEXT          Author"
  , "  --executable PATH      Main executable, ending in " ++ extensionOf ExecutableFile
  , "  --source-dir DIR       Source directory"
  , "  --arch TRIPLE          Target (aarch64-none-elf)"
  , "  --features A,B,...     CPU features: " ++ joinBy ", " (map featureName allFeatures)
  , "  --dependency PATH      Legacy asset, ending in " ++ extensionOf LegacyFile
  ]

parseArgs : List String -> Either String (RunMode, List (String, String))
parseArgs = go Render []
  where
    go : RunMode -> List (String, String) -> List String -> Either String (RunMode, List (String, String))
    go m acc []                         = Right (m, reverse acc)
    go _ acc ("--help" :: rest)         = go Help acc rest
    go _ acc ("--list-files" :: rest)   = go ListFiles acc rest
    go _ acc ("--list-extensions" :: rest) = go ListExtensions acc rest
    go m acc (flag :: value :: rest)    =
      if elem flag valueFlags
        then go m ((flag, value) :: acc) rest
        else Left ("unknown option: " ++ flag)
    go _ _ [flag]                       =
      if elem flag valueFlags
        then Left ("option " ++ flag ++ " requires a value")
        else Left ("unknown option: " ++ flag)

valuesOf : String -> List (String, String) -> List String
valuesOf flag opts = map snd (filter (\o => fst o == flag) opts)

-- The last occurrence of a scalar option wins.
scalarOpt : String -> String -> List (String, String) -> String
scalarOpt flag fallback opts = fromMaybe fallback (last' (valuesOf flag opts))

-- A list option given at least once replaces the default list.
listOpt : String -> List String -> List (String, String) -> List String
listOpt flag fallback opts =
  case valuesOf flag opts of
    [] => fallback
    vs => vs

splitCommas : String -> List String
splitCommas s = filter (/= "") (map trim (forget (split (== ',') s)))

applyOptions : List (String, String) -> Draft
applyOptions opts = MkDraft
  { dName         = scalarOpt "--name" defaultDraft.dName opts
  , dDescription  = scalarOpt "--description" defaultDraft.dDescription opts
  , dVersion      = scalarOpt "--version" defaultDraft.dVersion opts
  , dLicense      = scalarOpt "--license" defaultDraft.dLicense opts
  , dAuthors      = listOpt "--author" defaultDraft.dAuthors opts
  , dExecutable   = scalarOpt "--executable" defaultDraft.dExecutable opts
  , dSourceDirs   = listOpt "--source-dir" defaultDraft.dSourceDirs opts
  , dArch         = scalarOpt "--arch" defaultDraft.dArch opts
  , dFeatures     = case valuesOf "--features" opts of
                      [] => defaultDraft.dFeatures
                      vs => concatMap splitCommas vs
  , dDependencies = listOpt "--dependency" defaultDraft.dDependencies opts
  }

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

report : String -> IO ()
report line = ignore (fPutStrLn stderr line)

die : List String -> IO a
die errors = do
  traverse_ (\e => report ("error: " ++ e)) errors
  exitWith (ExitFailure 1)

run : RunMode -> Draft -> IO ()
run mode draft =
  case validate draft of
    Bad errors => die errors
    Ok manifest => do
      traverse_ (\f => traverse_ (\c => report ("note: " ++ c)) (caveat f)) manifest.mFeatures
      case mode of
        ListFiles => putStr (listFiles manifest)
        _         => putStr (renderManifest manifest)

main : IO ()
main = do
  args <- getArgs
  case parseArgs (drop 1 args) of
    Left err => do
      report usage
      die [err]
    Right (Help, _)           => putStr usage
    Right (ListExtensions, _) => putStr extensionTable
    Right (mode, opts)        => run mode (applyOptions opts)
