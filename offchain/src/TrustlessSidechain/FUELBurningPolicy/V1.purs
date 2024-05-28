module TrustlessSidechain.FUELBurningPolicy.V1
  ( FuelBurnParams(..)
  , fuelTokenName
  , getFuelBurningPolicy
  , mkBurnFuelLookupAndConstraints
  ) where

import Contract.Prelude

import Contract.PlutusData
  ( RedeemerDatum(RedeemerDatum)
  , toData
  )
import Contract.Prim.ByteArray (byteArrayFromAscii)
import Contract.ScriptLookups (ScriptLookups)
import Contract.Scripts as Scripts
import Cardano.Types.PlutusScript as PlutusScript
import Cardano.Types.PlutusScript (PlutusScript)
import Cardano.Types.ScriptHash (ScriptHash)
import Cardano.Types.TransactionUnspentOutput (TransactionUnspentOutput(TransactionUnspentOutput))
import Contract.TxConstraints
  ( InputWithScriptRef(RefInput)
  , TxConstraints
  )
import Contract.TxConstraints as Constraints
import Contract.Value
  ( CurrencySymbol
  , TokenName
  )
import Contract.Value as Value
import JS.BigInt (BigInt)
import JS.BigInt as BigInt
import Data.Maybe as Maybe
import Partial.Unsafe as Unsafe
import Contract.Numeric.BigNum as BigNum
import Run (Run)
import Run.Except (EXCEPT)
import TrustlessSidechain.Effects.Transaction (TRANSACTION)
import TrustlessSidechain.Effects.Wallet (WALLET)
import TrustlessSidechain.Error (OffchainError)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Utils.Scripts (mkMintingPolicyWithParams)
import TrustlessSidechain.Versioning.Types
  ( ScriptId(FUELBurningPolicy)
  , VersionOracle(VersionOracle)
  )
import TrustlessSidechain.Versioning.Utils as Versioning
import Type.Row (type (+))
import Cardano.Types.AssetName (AssetName)
import TrustlessSidechain.Utils.Asset (unsafeMkAssetName)
import Cardano.Types.Int as Int
import Partial.Unsafe (unsafePartial)

fuelTokenName ∷ TokenName
fuelTokenName = unsafeMkAssetName "FUEL"

-- | Gets the FUELBurningPolicy by applying `SidechainParams` to the FUEL
-- | burning policy
decodeFuelBurningPolicy ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + r) PlutusScript
decodeFuelBurningPolicy sidechainParams =
  mkMintingPolicyWithParams FUELBurningPolicy [ toData sidechainParams ]

getFuelBurningPolicy ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + r)
    { fuelBurningPolicy ∷ PlutusScript
    , fuelBurningCurrencySymbol ∷ ScriptHash
    }
getFuelBurningPolicy sidechainParams = do
  fuelBurningPolicy ← decodeFuelBurningPolicy sidechainParams
  let fuelBurningCurrencySymbol = PlutusScript.hash fuelBurningPolicy
  pure { fuelBurningPolicy, fuelBurningCurrencySymbol }

-- | `FuelBurnParams` is the data needed to mint FUELBurningToken
data FuelBurnParams = FuelBurnParams
  { amount ∷ BigInt
  , sidechainParams ∷ SidechainParams
  }

-- | Burn FUEL tokens using the Active Bridge configuration, verifying the
-- | Merkle proof
mkBurnFuelLookupAndConstraints ∷
  ∀ r.
  FuelBurnParams →
  Run (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    { lookups ∷ ScriptLookups, constraints ∷ TxConstraints }
mkBurnFuelLookupAndConstraints (FuelBurnParams { amount, sidechainParams }) = do
  (scriptRefTxInput /\ scriptRefTxOutput) ← Versioning.getVersionedScriptRefUtxo
    sidechainParams
    ( VersionOracle
        { version: BigNum.fromInt 1, scriptId: FUELBurningPolicy }
    )

  { fuelBurningPolicy: fuelBurningPolicy' } ← getFuelBurningPolicy
    sidechainParams

  pure
    { lookups: mempty
    , constraints:
        Constraints.mustMintCurrencyWithRedeemerUsingScriptRef
          (PlutusScript.hash fuelBurningPolicy')
          (RedeemerDatum $ toData unit)
          fuelTokenName
          (unsafePartial $ fromJust $ Int.fromBigInt amount)
          (RefInput $ TransactionUnspentOutput {input: scriptRefTxInput, output: scriptRefTxOutput})
    }
