-- Functions to serialise plutus scripts into a purescript readable TextEnvelope.textEnvelope
-- This should (only) be called when the scripts are modified, to update ctl scripts
module Main (main) where

import Cardano.Api (PlutusScriptV2, serialiseToTextEnvelope, writeFileTextEnvelope)
import Cardano.Api.Shelley (PlutusScript)
import Data.Aeson qualified as Aeson
import Data.Bifunctor qualified as Bifunctor
import Data.ByteString.Lazy.Char8 qualified as ByteString.Lazy.Char8
import Data.Foldable qualified as Foldable
import Data.List qualified as List
import Data.String qualified as HString
import Plutus.V2.Ledger.Api (Script)
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
import TrustlessSidechain.CommitteePlainEcdsaSecp256k1ATMSPolicy qualified as CommitteePlainEcdsaSecp256k1ATMSPolicy
import TrustlessSidechain.CommitteePlainSchnorrSecp256k1ATMSPolicy qualified as CommitteePlainSchnorrSecp256k1ATMSPolicy
import TrustlessSidechain.DParameter qualified as DParameter
import TrustlessSidechain.DistributedSet qualified as DistributedSet
import TrustlessSidechain.FUELMintingPolicy qualified as FUELMintingPolicy
import TrustlessSidechain.FUELProxyPolicy qualified as FUELProxyPolicy
import TrustlessSidechain.HaskellPrelude
import TrustlessSidechain.IlliquidCirculationSupply qualified as IlliquidCirculationSupply
import TrustlessSidechain.InitToken qualified as InitToken
import TrustlessSidechain.MerkleRootTokenMintingPolicy qualified as MerkleRootTokenMintingPolicy
import TrustlessSidechain.MerkleRootTokenValidator qualified as MerkleRootTokenValidator
import TrustlessSidechain.PermissionedCandidates qualified as PermissionedCandidates
import TrustlessSidechain.PoCAlwaysPassingScripts qualified as PoCAlwaysPassing
import TrustlessSidechain.PoCECDSA qualified as PoCECDSA
import TrustlessSidechain.PoCInlineDatum qualified as PoCInlineDatum
import TrustlessSidechain.PoCMintingPolicy as PoCMintingPolicy
import TrustlessSidechain.PoCReferenceInput qualified as PoCReferenceInput
import TrustlessSidechain.PoCReferenceScript qualified as PoCReferenceScript
import TrustlessSidechain.PoCSchnorr qualified as PoCSchnorr
import TrustlessSidechain.PoCSerialiseData qualified as PoCSerialiseData
import TrustlessSidechain.Reserve qualified as Reserve
import TrustlessSidechain.ScriptCache qualified as ScriptCache
import TrustlessSidechain.UpdateCommitteeHash qualified as UpdateCommitteeHash
import TrustlessSidechain.Utils (scriptToPlutusScript)
import TrustlessSidechain.Versioning qualified as Versioning
import TrustlessSidechain.Governance.MultiSig qualified as MultiSig

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
  | -- | 'GenPureScriptPoCRawScripts' creates a purescript file of
    -- proof-of-concept functions which return the plutus scripts.
    GenPureScriptPoCRawScripts
      { -- | 'gpspocrsOutputFile' is where to output the file. In the case that
        -- this is 'Nothing',  we output to stdout
        gpspocrsOutputFile :: Maybe FilePath
      }
  | -- | 'PlutusScriptTargets' returns the names of the files generated by
    -- 'GenPlutusScripts'.
    PlutusScriptTargets

-- | 'getOpts' is a high level function to convert the CLI arguments to
-- 'Options'
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
      , Option
          ['c']
          ["purescript-plutus-poc-scripts"]
          ( OptArg
              (\outputFilePath -> GenPureScriptPoCRawScripts {gpspocrsOutputFile = outputFilePath})
              "FILE"
          )
          "output a purescript module to the specified file path (stdout if no file path is given) that contains proof-of-concept functions that return the plutus scripts"
      ]

-- * CTL serialization

-- Note: CTL uses the usual TextEnvelope format now.

serialiseScript :: FilePath -> FilePath -> Script -> IO ()
serialiseScript outputDir name script =
  let out :: PlutusScript PlutusScriptV2
      out = scriptToPlutusScript script
      file = outputDir FilePath.</> name
   in do
        IO.putStrLn $ "serialising " <> file
        writeFileTextEnvelope file Nothing out >>= either print pure

serialiseScriptsToPurescript ::
  -- | Purescript module name
  HString.String ->
  -- | Name of the script, and the associated script Entries should be unique
  -- w.r.t the name; and the names should match data constructor names of
  -- ScriptId data type.  See Note [Serialized script names].
  --
  -- NOTE: The names should not include any Unicode characters, which are
  -- nonetheless valid names in PureScript.
  [(HString.String, Script)] ->
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

  IO.hPutStrLn handle "  , rawScripts"
  IO.hPutStrLn handle "  ) where"

  IO.hPutStrLn handle ""
  IO.hPutStrLn handle "import Contract.Prelude"
  IO.hPutStrLn handle ""
  IO.hPutStrLn handle "import Data.Map as Map"
  IO.hPutStrLn handle "import TrustlessSidechain.Versioning.ScriptId (ScriptId(..))"

  Foldable.for_ plutusScripts $ \(name, script) -> do
    IO.hPutStrLn handle ""
    IO.hPutStrLn handle $ prependPrefix name <> " ∷ Tuple ScriptId String"
    IO.hPutStrLn handle $ prependPrefix name <> " ="
    ByteString.Lazy.Char8.hPutStrLn handle $
      ByteString.Lazy.Char8.concat
        [ "  ( "
        , fromString name
        , " /\\"
        ]
    ByteString.Lazy.Char8.hPutStrLn handle $
      ByteString.Lazy.Char8.concat
        [ "      "
        , ByteString.Lazy.Char8.replicate 3 '"'
        , Aeson.encode $
            serialiseToTextEnvelope Nothing $
              scriptToPlutusScript script
        , ByteString.Lazy.Char8.replicate 3 '"'
        ]
    IO.hPutStrLn handle "  )"

  IO.hPutStrLn handle ""
  IO.hPutStrLn handle "rawScripts ∷ Map.Map ScriptId String"
  IO.hPutStrLn handle "rawScripts = Map.fromFoldable"
  IO.hPutStr handle "  [ "
  case plutusScripts of
    [] -> pure ()
    (x : xs) -> do
      IO.hPutStrLn handle $ prependPrefix (fst x)
      Foldable.for_ xs $ \(name, _) ->
        IO.hPutStrLn handle $ "  , " <> prependPrefix name
  IO.hPutStrLn handle "  ]"

serialisePoCScriptsToPurescript ::
  -- | Purescript module name
  HString.String ->
  -- | Name of the script, and the associated script
  -- Entries should be unique w.r.t the name; and the name should be
  -- characters for a valid purescript identifier
  [(HString.String, Script)] ->
  -- | Handle to append the purescript module to.
  --
  -- Note: one probably wants to clear the file before calling this function.
  Handle ->
  IO ()
serialisePoCScriptsToPurescript moduleName plutusScripts handle = do
  let -- prepends the the prefix @raw@ to a given string.
      -- This is just the convention that is used for purescript function
      -- names.
      prependPrefix :: HString.String -> HString.String
      prependPrefix = ("raw" <>)

  -- Put the purescript module header i.e., put something like
  --
  -- > -- WARNING: This file is autogenerated. Do not modify by hand. Instead:
  -- > -- › Add your updated scripts to $project/app/serialise/Main.hs
  -- > -- › Manually run `make update-scripts`
  -- > -- > in this directory to update `src/RawScripts.purs`
  -- > module <moduleName>
  -- > ( <plutusScript1>
  -- > , <plutusScript2>
  -- > , <...>
  -- > ) where
  IO.hPutStrLn handle "-- WARNING: This file is autogenerated. Do not modify by hand. Instead:"
  IO.hPutStrLn handle "-- › Add your updated scripts to $project/onchain/app/serialise/Main.hs"
  IO.hPutStrLn handle "-- › Manually run `make update-scripts` in the `$project/offchain/` directory"
  IO.hPutStrLn handle "--   to update `test/Test/PoCRawScripts.purs`."
  IO.hPutStrLn handle "-- Note: if the modified times do not accurately capture an out of date"
  IO.hPutStrLn handle "-- `test/Test/PoCRawScripts.purs`, then run `make clean` before"
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
        , Aeson.encode $ serialiseToTextEnvelope Nothing $ scriptToPlutusScript script
        , ByteString.Lazy.Char8.replicate 3 '"'
        ]

-- Note [Serialized script names]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--
-- The names used when serializing scripts must match the names of data
-- constructors in ScriptId data type from the
-- TrustlessSidechain.Versioning.ScriptId module in off-chain.  This required
-- for this serializer to correctly build a map from ScriptId data constructors
-- to serialized scripts.

-- * Main function
main :: IO ()
main =
  getOpts >>= \options ->
    -- See Note [Serialized script names]
    let plutusScripts =
          [ ("FUELMintingPolicy", FUELMintingPolicy.serialisableMintingPolicy)
          , ("FUELBurningPolicy", FUELMintingPolicy.serialisableBurningPolicy)
          , ("MerkleRootTokenValidator", MerkleRootTokenValidator.serialisableValidator)
          , ("MerkleRootTokenPolicy", MerkleRootTokenMintingPolicy.serialisableMintingPolicy)
          ,
            ( "CommitteeCandidateValidator"
            , CommitteeCandidateValidator.serialisableValidator
            )
          ,
            ( "CandidatePermissionPolicy"
            , CandidatePermissionMintingPolicy.serialisableCandidatePermissionMintingPolicy
            )
          ,
            ( "CommitteeOraclePolicy"
            , UpdateCommitteeHash.serialisableCommitteeOraclePolicy
            )
          ,
            ( "CommitteeHashValidator"
            , UpdateCommitteeHash.serialisableCommitteeHashValidator
            )
          , ("CheckpointValidator", CheckpointValidator.serialisableCheckpointValidator)
          , ("CheckpointPolicy", CheckpointValidator.serialisableCheckpointPolicy)
          , ("InitTokenPolicy", InitToken.serialisableInitTokenPolicy)
          , ("ScriptCache", ScriptCache.serialisableScriptCache)
          , -- Versioning System
            ("VersionOraclePolicy", Versioning.serialisableVersionOraclePolicy)
          , ("VersionOracleValidator", Versioning.serialisableVersionOracleValidator)
          , ("FUELProxyPolicy", FUELProxyPolicy.serialisableFuelProxyPolicy)
          , -- ATMS schemes

            ( "CommitteePlainEcdsaSecp256k1ATMSPolicy"
            , CommitteePlainEcdsaSecp256k1ATMSPolicy.serialisableMintingPolicy
            )
          ,
            ( "CommitteePlainSchnorrSecp256k1ATMSPolicy"
            , CommitteePlainSchnorrSecp256k1ATMSPolicy.serialisableMintingPolicy
            )
          , ( "MultiSigPolicy"
            , MultiSig.serialisableGovernanceMultiSigPolicy
            )
          , -- Distributed set validators / minting policies
            ("DsInsertValidator", DistributedSet.serialisableInsertValidator)
          , ("DsConfValidator", DistributedSet.serialisableDsConfValidator)
          , ("DsConfPolicy", DistributedSet.serialisableDsConfPolicy)
          , ("DsKeyPolicy", DistributedSet.serialisableDsKeyPolicy)
          , -- Scripts for DParameter
            ("DParameterPolicy", DParameter.serialisableMintingPolicy)
          , ("DParameterValidator", DParameter.serialisableValidator)
          , -- Scripts for PermissionedCandidates

            ( "PermissionedCandidatesPolicy"
            , PermissionedCandidates.serialisableMintingPolicy
            )
          ,
            ( "PermissionedCandidatesValidator"
            , PermissionedCandidates.serialisableValidator
            )
          , ("ReserveValidator", Reserve.serialisableReserveValidator)
          , ("ReserveAuthPolicy", Reserve.serialisableReserveAuthPolicy)
          ,
            ( "IlliquidCirculationSupplyValidator"
            , IlliquidCirculationSupply.serialisableIlliquidCirculationSupplyValidator
            )
          ]
        -- Validators for proof of concept tests.
        plutusPoCScripts =
          [
            ( "PoCInlineDatum"
            , PoCInlineDatum.serialisablePoCInlineDatumValidator
            )
          ,
            ( "PoCToReferenceInput"
            , PoCReferenceInput.serialisablePoCToReferenceInputValidator
            )
          ,
            ( "PoCReferenceInput"
            , PoCReferenceInput.serialisablePoCReferenceInputValidator
            )
          ,
            ( "PoCToReferenceScript"
            , PoCReferenceScript.serialisablePoCToReferenceScriptValidator
            )
          ,
            ( "PoCReferenceScript"
            , PoCReferenceScript.serialisablePoCReferenceScriptValidator
            )
          , ("PoCSerialiseData", PoCSerialiseData.serialisablePoCSerialiseData)
          , ("PoCECDSA", PoCECDSA.serialisableValidator)
          , ("PoCSchnorr", PoCSchnorr.serialisablePolicy)
          , ("PoCMintingPolicy", PoCMintingPolicy.serialisablePoCMintingPolicy)
          , ("PoCAlwaysPassingValidator", PoCAlwaysPassing.serialisableAlwaysPassingValidator)
          , ("PoCAlwaysPassingPolicy", PoCAlwaysPassing.serialisableAlwaysPassingPolicy)
          ]
        plutusScriptsDotPlutus =
          fmap
            (Bifunctor.first (FilePath.<.> "plutus"))
            (plutusScripts List.++ plutusPoCScripts)
     in case options of
          GenPlutusScripts {gsOutputDir = outputDir} ->
            Foldable.traverse_
              (uncurry (serialiseScript outputDir))
              plutusScriptsDotPlutus
          PlutusScriptTargets ->
            IO.putStrLn $
              List.unwords $
                fmap fst plutusScriptsDotPlutus
          GenPureScriptRawScripts {gpsrsOutputFile = outputFile} ->
            let moduleName = "TrustlessSidechain.RawScripts"
             in case outputFile of
                  Nothing ->
                    serialiseScriptsToPurescript
                      moduleName
                      plutusScripts
                      IO.stdout
                  Just filepath ->
                    IO.withFile filepath IO.ReadWriteMode $ \handle ->
                      -- clear the file first, then put our code in.
                      IO.hSetFileSize handle 0
                        >> serialiseScriptsToPurescript
                          moduleName
                          plutusScripts
                          handle
          GenPureScriptPoCRawScripts {gpspocrsOutputFile = outputFile} ->
            let moduleName = "Test.PoCRawScripts"
             in case outputFile of
                  Nothing ->
                    serialiseScriptsToPurescript
                      moduleName
                      plutusPoCScripts
                      IO.stdout
                  Just filepath ->
                    IO.withFile filepath IO.ReadWriteMode $ \handle ->
                      -- clear the file first, then put our code in.
                      IO.hSetFileSize handle 0
                        >> serialisePoCScriptsToPurescript
                          moduleName
                          plutusPoCScripts
                          handle
