-- Functions to serialise plutus scripts into a purescript readable TextEnvelope.texteEnvelope
-- This should (only) be called when the scripts are modified, to update ctl scripts
module Main (main) where

import Cardano.Api (PlutusScriptV1, writeFileTextEnvelope)
import Cardano.Api.Shelley (PlutusScript (PlutusScriptSerialised))
import Codec.Serialise (serialise)
import Data.ByteString.Lazy (toStrict)
import Data.ByteString.Short (toShort)
import Data.Foldable (traverse_)
import Ledger (Script, scriptHash)
import TrustlessSidechain.OnChain.CommitteeCandidateValidator qualified as CommitteeCandidateValidator
import TrustlessSidechain.OnChain.FUELMintingPolicy qualified as FUELMintingPolicy
import TrustlessSidechain.OnChain.MPTRootTokenMintingPolicy qualified as MPTRootTokenMintingPolicy
import TrustlessSidechain.OnChain.MPTRootTokenValidator qualified as MPTRootTokenValidator
import TrustlessSidechain.OnChain.UpdateCommitteeHash qualified as UpdateCommitteeHash
import Prelude

-- CTL uses the usual TextEnvelope format now.
serialiseScript :: FilePath -> Script -> IO ()
serialiseScript name script =
  let out = PlutusScriptSerialised @PlutusScriptV1 . toShort . toStrict $ serialise script
      file = "ctl-scaffold/Scripts/" <> name <> ".plutus"
   in do
        putStrLn $ "serialising " <> name <> ",\thash = " <> show (scriptHash script)
        writeFileTextEnvelope file Nothing out >>= either print pure

main :: IO ()
main =
  traverse_
    (uncurry serialiseScript)
    [ ("FUELMintingPolicy", FUELMintingPolicy.serialisableMintingPolicy)
    , ("UpdateCommitteeHash", UpdateCommitteeHash.serialisableCommitteHashPolicy)
    , ("MPTRootTokenValidator", MPTRootTokenValidator.serialisableValidator)
    , ("MPTRootTokenMintingPolicy", MPTRootTokenMintingPolicy.serialisableMintingPolicy)
    , ("CommitteeCandidateValidator", CommitteCandidateValidator.serialisablecommitteeCanditateValidator)
    ]
