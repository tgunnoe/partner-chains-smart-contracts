-- Functions to serialise plutus scripts into a purescript readable TextEnvelope.textEnvelope
-- This should (only) be called when the scripts are modified, to update ctl scripts
module Main (main) where

import Cardano.Api (PlutusScriptV2, writeFileTextEnvelope)
import Cardano.Api.SerialiseTextEnvelope (serialiseToTextEnvelope)
import Cardano.Api.Shelley (PlutusScript (PlutusScriptSerialised))
import Codec.Serialise (serialise)
import Data.Aeson qualified as Aeson
import Data.Bifunctor qualified as Bifunctor
import Data.ByteString.Lazy (toStrict)
import Data.ByteString.Lazy.Char8 qualified as ByteString.Lazy.Char8
import Data.ByteString.Short (toShort)
import Data.Foldable qualified as Foldable
import Data.List qualified as List
import Data.String qualified as HString
import Ledger (Script, Versioned (unversioned), scriptHash)
import Plutonomy.UPLC qualified
import System.Console.GetOpt (
  ArgDescr (NoArg, OptArg, ReqArg),
  ArgOrder (RequireOrder),
  OptDescr (Option),
 )
import System.Console.GetOpt qualified as GetOpt
import System.Environment qualified as Environment
import System.FilePath qualified as FilePath
import System.IO (FilePath, Handle, print)
import System.IO qualified as IO
import System.IO.Error qualified as Error
import TrustlessSidechain.CandidatePermissionMintingPolicy qualified as CandidatePermissionMintingPolicy
import TrustlessSidechain.CheckpointValidator qualified as CheckpointValidator
import TrustlessSidechain.CommitteeCandidateValidator qualified as CommitteeCandidateValidator
import TrustlessSidechain.CommitteeSignedToken qualified as CommitteeSignedToken
import TrustlessSidechain.DistributedSet qualified as DistributedSet
import TrustlessSidechain.FUELMintingPolicy qualified as FUELMintingPolicy
import TrustlessSidechain.HaskellPrelude
import TrustlessSidechain.MerkleRootTokenMintingPolicy qualified as MerkleRootTokenMintingPolicy
import TrustlessSidechain.MerkleRootTokenValidator qualified as MerkleRootTokenValidator
import TrustlessSidechain.PoCECDSA qualified as PoCECDSA
import TrustlessSidechain.PoCInlineDatum qualified as PoCInlineDatum
import TrustlessSidechain.PoCReferenceInput qualified as PoCReferenceInput
import TrustlessSidechain.PoCReferenceScript qualified as PoCReferenceScript
import TrustlessSidechain.PoCSerialiseData qualified as PoCSerialiseData
import TrustlessSidechain.UpdateCommitteeHash qualified as UpdateCommitteeHash

-- * CLI parsing

-- | 'Options' is the CLI options that may be passed to the system.
data Options
  = -- | 'GenPlutusScripts'
    GenPlutusScripts
      { -- | 'oOutputDir' is the output directory of where the plutus scripts
        -- are dumped.
        gsOutputDir :: FilePath
      }
  | -- | 'GenPureScriptRawScripts' creates a purescript file of functions which
    -- return the plutus scripts.
    GenPureScriptRawScripts
      { -- | 'gpsrsOutputFile' is where to output the file. In the case that
        -- this is 'Nothing',  we output to stdout
        gpsrsOutputFile :: Maybe FilePath
      }
  | -- | 'PlutusScriptTargets' returns the names of the files generated by
    -- 'GenPlutusScripts'.
    PlutusScriptTargets

{- | 'getOpts' is a high level function to convert the CLI arguments to
 'Options'
-}
getOpts :: IO Options
getOpts =
  Environment.getProgName >>= \progName ->
    Environment.getArgs >>= \argv ->
      let header =
            List.unwords
              [ "Usage:"
              , progName
              , "[OPTION...]"
              ]
       in case GetOpt.getOpt RequireOrder options argv of
            ([o], [], []) -> pure o
            (_, _nonOptions, errs) ->
              Error.ioError $
                Error.userError $
                  concat errs
                    <> GetOpt.usageInfo header options
  where
    options :: [OptDescr Options]
    options =
      [ Option
          ['o']
          ["plutus-scripts-output-dir"]
          (ReqArg (\str -> GenPlutusScripts {gsOutputDir = str}) "DIR")
          "output directory of Plutus scripts"
      , Option
          ['t']
          ["plutus-scripts-targets"]
          (NoArg PlutusScriptTargets)
          "output the filenames of the plutus scripts to be generated"
      , Option
          ['p']
          ["purescript-plutus-scripts"]
          ( OptArg
              (\outputFilePath -> GenPureScriptRawScripts {gpsrsOutputFile = outputFilePath})
              "FILE"
          )
          "output a purescript module to the specified file path (stdout if no file path is given) that contains functions that return the plutus scripts"
      ]

-- * CTL serialization

-- Note: CTL uses the usual TextEnvelope format now.

versionedScriptToPlutusScript :: Versioned Script -> PlutusScript PlutusScriptV2
versionedScriptToPlutusScript =
  PlutusScriptSerialised @PlutusScriptV2
    . toShort
    . toStrict
    . serialise
    . Plutonomy.UPLC.optimizeUPLC
    . unversioned

serialiseScript :: FilePath -> FilePath -> Versioned Script -> IO ()
serialiseScript outputDir name script =
  let out :: PlutusScript PlutusScriptV2
      out = versionedScriptToPlutusScript script
      file = outputDir FilePath.</> name
   in do
        IO.putStrLn $ "serialising " <> file <> ",\thash = " <> show (scriptHash script)
        writeFileTextEnvelope file Nothing out >>= either print pure

--
serialiseScriptsToPurescript ::
  -- | Purescript module name
  HString.String ->
  -- | Name of the script, and the associated script
  -- Entries should be unique w.r.t the name; and the name should be
  -- characters for a valid purescript identifier
  [(HString.String, Versioned Script)] ->
  -- | Handle to append the purescript module to.
  --
  -- Note: one probably wants to clear the file before calling this function.
  Handle ->
  IO ()
serialiseScriptsToPurescript moduleName plutusScripts handle = do
  let -- prepends the the prefix @raw@ to a given string.
      -- This is just the convention that is used for purescript function
      -- names.
      prependPrefix :: HString.String -> HString.String
      prependPrefix = ("raw" <>)

  -- Put the purescript module header i.e., put something like
  --
  -- > -- WARNING: This file is autogenerated. Do not modify by hand. Instead:
  -- > -- › Add your updated scripts to $project/app/serialise/Main.hs
  -- > -- › Manually run `make update-scripts` in this directory to update `src/RawScripts.purs`
  -- > module <moduleName>
  -- > ( <plutusScript1>
  -- > , <plutusScript2>
  -- > , <...>
  -- > ) where
  IO.hPutStrLn handle "-- WARNING: This file is autogenerated. Do not modify by hand. Instead:"
  IO.hPutStrLn handle "-- › Add your updated scripts to $project/onchain/app/serialise/Main.hs"
  IO.hPutStrLn handle "-- › Manually run `make update-scripts` in the `$project/offchain/` directory"
  IO.hPutStrLn handle "--   to update `src/TrustlessSidechain/RawScripts.purs`."
  IO.hPutStrLn handle "-- Note: if the modified times do not accurately capture an out of date"
  IO.hPutStrLn handle "-- `src/TrustlessSidechain/RawScripts.purs`, then run `make clean` before"
  IO.hPutStrLn handle "-- running `make update-scripts`."

  IO.hPutStrLn handle $ "module " <> moduleName
  IO.hPutStr handle "  ( "
  case fmap fst plutusScripts of
    [] -> pure ()
    p : ps -> do
      IO.hPutStrLn handle $ prependPrefix p
      Foldable.for_ ps $ \name -> IO.hPutStrLn handle $ "  , " <> prependPrefix name

  IO.hPutStrLn handle "  ) where"

  Foldable.for_ plutusScripts $ \(name, script) -> do
    IO.hPutStrLn handle ""
    IO.hPutStrLn handle $ prependPrefix name <> " ∷ String"
    IO.hPutStrLn handle $ prependPrefix name <> " ="
    ByteString.Lazy.Char8.hPutStrLn handle $
      ByteString.Lazy.Char8.concat
        [ "  "
        , ByteString.Lazy.Char8.replicate 3 '"'
        , Aeson.encode $ serialiseToTextEnvelope Nothing $ versionedScriptToPlutusScript script
        , ByteString.Lazy.Char8.replicate 3 '"'
        ]

-- * Main function
main :: IO ()
main =
  getOpts >>= \options ->
    let plutusScripts =
          [ ("FUELMintingPolicy", FUELMintingPolicy.serialisableMintingPolicy)
          , ("MerkleRootTokenValidator", MerkleRootTokenValidator.serialisableValidator)
          , ("MerkleRootTokenMintingPolicy", MerkleRootTokenMintingPolicy.serialisableMintingPolicy)
          , ("CommitteeCandidateValidator", CommitteeCandidateValidator.serialisableValidator)
          , ("CandidatePermissionMintingPolicy", CandidatePermissionMintingPolicy.serialisableCandidatePermissionMintingPolicy)
          , ("CommitteeHashPolicy", UpdateCommitteeHash.serialisableCommitteeHashPolicy)
          , ("CommitteeHashValidator", UpdateCommitteeHash.serialisableCommitteeHashValidator)
          , ("CheckpointValidator", CheckpointValidator.serialisableCheckpointValidator)
          , ("CheckpointPolicy", CheckpointValidator.serialisableCheckpointPolicy)
          , ("CommitteeSignedToken", CommitteeSignedToken.serialisableMintingPolicy)
          , -- Distributed set validators / minting policies
            ("InsertValidator", DistributedSet.serialisableInsertValidator)
          , ("DsConfValidator", DistributedSet.serialisableDsConfValidator)
          , ("DsConfPolicy", DistributedSet.serialisableDsConfPolicy)
          , ("DsKeyPolicy", DistributedSet.serialisableDsKeyPolicy)
          , -- Validators for proof of concept tests.
            ("PoCInlineDatum", PoCInlineDatum.serialisablePoCInlineDatumValidator)
          , ("PoCToReferenceInput", PoCReferenceInput.serialisablePoCToReferenceInputValidator)
          , ("PoCReferenceInput", PoCReferenceInput.serialisablePoCReferenceInputValidator)
          , ("PoCToReferenceScript", PoCReferenceScript.serialisablePoCToReferenceScriptValidator)
          , ("PoCReferenceScript", PoCReferenceScript.serialisablePoCReferenceScriptValidator)
          , ("PoCSerialiseData", PoCSerialiseData.serialisablePoCSerialiseData)
          , ("PoCECDSA", PoCECDSA.serialisableValidator)
          ]
        plutusScriptsDotPlutus = fmap (Bifunctor.first (FilePath.<.> "plutus")) plutusScripts
     in case options of
          GenPlutusScripts {gsOutputDir = outputDir} ->
            Foldable.traverse_
              (uncurry (serialiseScript outputDir))
              plutusScriptsDotPlutus
          PlutusScriptTargets -> IO.putStrLn $ List.unwords $ fmap fst plutusScriptsDotPlutus
          GenPureScriptRawScripts {gpsrsOutputFile = outputFile} ->
            let moduleName = "TrustlessSidechain.RawScripts"
             in case outputFile of
                  Nothing -> serialiseScriptsToPurescript moduleName plutusScripts IO.stdout
                  Just filepath ->
                    IO.withFile filepath IO.ReadWriteMode $ \handle ->
                      -- clear the file first, then put our code in.
                      IO.hSetFileSize handle 0
                        >> serialiseScriptsToPurescript
                          moduleName
                          plutusScripts
                          handle
