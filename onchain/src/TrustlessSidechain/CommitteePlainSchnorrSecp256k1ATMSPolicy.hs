{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TemplateHaskell #-}

{- | "TrustlessSidechain.CommitteePlainSchnorrSecp256k1ATMSPolicy" provides a token which verifies
 that the current committee has signed its token name with the plain (simply
 public key and signature concatenation) ATMS scheme with SchnorrSecp256k1 signatures.
-}
module TrustlessSidechain.CommitteePlainSchnorrSecp256k1ATMSPolicy (
  mkMintingPolicy,
  serialisableMintingPolicy,
) where

import Plutus.V2.Ledger.Api (
  Script,
  ScriptContext,
  fromCompiledCode,
 )
import PlutusTx qualified
import TrustlessSidechain.CommitteePlainATMSPolicy qualified as CommitteePlainATMSPolicy
import TrustlessSidechain.PlutusPrelude
import TrustlessSidechain.ScriptUtils (mkUntypedMintingPolicy)
import TrustlessSidechain.Types (
  ATMSRedeemer,
  CommitteeCertificateMint,
 )
import TrustlessSidechain.Versioning (VersionOracleConfig)

{-# INLINEABLE mkMintingPolicy #-}

{- | 'mkMintingPolicy' wraps
 'TrustlessSidechain.CommitteePlainATMSPolicy.mkMintingPolicy' and uses
 'verifySchnorrSecp256k1Signature' to verify the signatures
-}
mkMintingPolicy :: CommitteeCertificateMint -> VersionOracleConfig -> ATMSRedeemer -> ScriptContext -> Bool
mkMintingPolicy =
  CommitteePlainATMSPolicy.mkMintingPolicy
    verifySchnorrSecp256k1Signature

-- CTL hack
mkMintingPolicyUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> BuiltinData -> ()
mkMintingPolicyUntyped ccm versionOracleConfig =
  mkUntypedMintingPolicy
    (mkMintingPolicy (unsafeFromBuiltinData ccm) (unsafeFromBuiltinData versionOracleConfig))

serialisableMintingPolicy :: Script
serialisableMintingPolicy = fromCompiledCode $$(PlutusTx.compile [||mkMintingPolicyUntyped||])
