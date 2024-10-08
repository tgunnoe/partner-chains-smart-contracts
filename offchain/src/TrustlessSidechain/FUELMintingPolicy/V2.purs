module TrustlessSidechain.FUELMintingPolicy.V2
  ( FuelMintParams(..)
  , getFuelMintingPolicy
  , mkMintFuelLookupAndConstraints
  , dummyTokenName
  ) where

import Contract.Prelude

import Cardano.ToData (toData)
import Cardano.Types.AssetName (AssetName)
import Cardano.Types.Int as Int
import Cardano.Types.PlutusScript (PlutusScript)
import Cardano.Types.PlutusScript as PlutusScript
import Cardano.Types.ScriptHash (ScriptHash)
import Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput(TransactionUnspentOutput)
  )
import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( RedeemerDatum(RedeemerDatum)
  )
import Contract.PlutusData as PlutusData
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as Lookups
import Contract.TxConstraints
  ( InputWithScriptRef(RefInput)
  , TxConstraints
  )
import Contract.TxConstraints as Constraints
import JS.BigInt (BigInt)
import Partial.Unsafe (unsafePartial)
import Run (Run)
import Run.Except (EXCEPT)
import TrustlessSidechain.Effects.Transaction (TRANSACTION)
import TrustlessSidechain.Effects.Wallet (WALLET)
import TrustlessSidechain.Error (OffchainError)
import TrustlessSidechain.RawScripts (rawOnlyMintMintingPolicy)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Utils.Asset (unsafeMkAssetName)
import TrustlessSidechain.Utils.Scripts
  ( mkMintingPolicyWithParams'
  )
import TrustlessSidechain.Versioning.Types
  ( ScriptId(FUELMintingPolicy)
  , VersionOracle(VersionOracle)
  )
import TrustlessSidechain.Versioning.Utils as Versioning
import Type.Row (type (+))

-- | `FuelMintParams` is the data for the FUEL mint endpoint.
data FuelMintParams = FuelMintParams
  { amount ∷ BigInt
  }

dummyTokenName ∷ AssetName
dummyTokenName = unsafeMkAssetName "Dummy tokens"

-- | Get the OnlyMintMintingPolicy by applying `SidechainParams` to the dummy
-- | minting policy.
decodeOnlyMintMintingPolicy ∷
  ∀ r. SidechainParams → Run (EXCEPT OffchainError + r) PlutusScript
decodeOnlyMintMintingPolicy sidechainParams = do
  case rawOnlyMintMintingPolicy of
    (_ /\ onlyMintMintingPolicy) →
      mkMintingPolicyWithParams'
        onlyMintMintingPolicy
        [ toData sidechainParams ]

getFuelMintingPolicy ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + r)
    { fuelMintingPolicy ∷ PlutusScript
    , fuelMintingCurrencySymbol ∷ ScriptHash
    }
getFuelMintingPolicy sidechainParams = do
  fuelMintingPolicy ← decodeOnlyMintMintingPolicy sidechainParams
  let fuelMintingCurrencySymbol = PlutusScript.hash fuelMintingPolicy
  pure { fuelMintingPolicy, fuelMintingCurrencySymbol }

mkMintFuelLookupAndConstraints ∷
  ∀ r.
  SidechainParams →
  FuelMintParams →
  Run (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    { lookups ∷ ScriptLookups
    , constraints ∷ TxConstraints
    }
mkMintFuelLookupAndConstraints sidechainParams (FuelMintParams { amount }) = do
  { fuelMintingPolicy } ← getFuelMintingPolicy sidechainParams

  (scriptRefTxInput /\ scriptRefTxOutput) ← Versioning.getVersionedScriptRefUtxo
    sidechainParams
    ( VersionOracle
        { version: BigNum.fromInt 2, scriptId: FUELMintingPolicy }
    )

  let
    lookups ∷ ScriptLookups
    lookups = Lookups.plutusMintingPolicy fuelMintingPolicy

    constraints ∷ TxConstraints
    constraints =
      Constraints.mustMintCurrencyWithRedeemerUsingScriptRef
        (PlutusScript.hash fuelMintingPolicy)
        (RedeemerDatum $ PlutusData.toData unit)
        dummyTokenName
        (unsafePartial $ fromJust $ Int.fromBigInt amount)
        ( RefInput $ TransactionUnspentOutput
            { input: scriptRefTxInput, output: scriptRefTxOutput }
        )

  pure { lookups, constraints }
