-- | Some proof of concept tests for using the onchain builtin 'serialiseData'
-- function.
module Test.PoCSerialiseData (testScenario1) where

import Contract.Prelude

import Contract.Address as Address
import Contract.Log as Log
import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.PlutusData (Datum(Datum), PlutusData, Redeemer(Redeemer))
import Contract.PlutusData as PlutusData
import Contract.Prim.ByteArray (ByteArray)
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as ScriptLookups
import Contract.Scripts (Validator)
import Contract.Scripts as Scripts
import Contract.TextEnvelope (TextEnvelopeType(PlutusScriptV2))
import Contract.TextEnvelope as TextEnvelope
import Contract.Transaction
  ( Language(PlutusV2)
  )
import Contract.Transaction as Transaction
import Contract.TxConstraints
  ( DatumPresence(DatumWitness)
  , TxConstraints
  )
import Contract.TxConstraints as TxConstraints
import Contract.Value as Value
import Data.BigInt as BigInt
import Data.Map as Map
import RawScripts as RawScripts
import Serialization as Serialization
import Serialization.PlutusData as SerializationPlutusData
import Test.Utils as Utils
import Untagged.Union as Union

-- | 'serialiseData' is the offchain version of the Builtin 'serialiseData'.
serialiseData ∷ PlutusData → Maybe ByteArray
serialiseData = ((Serialization.toBytes <<< Union.asOneOf) <$> _) <<<
  SerializationPlutusData.convertPlutusData

-- | 'testScenario1' should succeed. It does the following.
--  1.
--      - Grabs the validator for 'RawScripts.rawPoCSerialiseData'
--  2.
--      - Build / submit the transaction to pay some ada to the
--      'RawScripts.rawPoCSerialiseData' validator which holds the cbor serialized
--      integer 69 as a datum.
--  3. Spend the transaction created in 2., with redeemer the builtin data of 69.
testScenario1 ∷ Contract () Unit
testScenario1 = do
  Log.logInfo' "PoCSerialiseData: testScenario1"

  -- 1.
  validatorBytes ← TextEnvelope.textEnvelopeBytes RawScripts.rawPoCSerialiseData
    PlutusScriptV2
  let
    validator = wrap $ wrap $ validatorBytes /\ PlutusV2 ∷ Validator
    validatorHash = Scripts.validatorHash validator
    validatorAddress = Address.scriptHashAddress validatorHash
  -- Getting this validators datum is a bit confusing..
  -- First, we have
  --  - The integer 69
  --  - Convert it to Plutus Data
  --  - Serialise it to cbor (this is ByteArray)
  --  - Then we need to conver the ByteArray back into PlutusData (types need to match!)
  validatorDat ← Datum <<< PlutusData.toData <$>
    Monad.liftedM "Failed to serialise data to cbor"
      (pure $ serialiseData $ PlutusData.toData $ BigInt.fromInt 69)

  -- 2.
  void do
    let
      constraints ∷ TxConstraints Void Void
      constraints = TxConstraints.mustPayToScript validatorHash validatorDat
        DatumWitness
        (Value.lovelaceValueOf one)

      lookups ∷ ScriptLookups Void
      lookups = mempty

    unbalancedTx ← Monad.liftedE $ ScriptLookups.mkUnbalancedTx lookups
      constraints
    balancedTx ← Monad.liftedE $ Transaction.balanceAndSignTxE unbalancedTx
    txId ← Transaction.submit balancedTx
    Log.logInfo' $ "Transaction submitted: " <> show txId
    Transaction.awaitTxConfirmed txId
    Log.logInfo' $ "Transaction confirmed: " <> show txId

  -- 3.
  void do
    (txIn /\ txOut) ← Utils.getUniqueUtxoAt validatorAddress
    let
      validatorRedeemer = Redeemer $ PlutusData.toData $ BigInt.fromInt 69

      constraints ∷ TxConstraints Void Void
      constraints = TxConstraints.mustSpendScriptOutput txIn validatorRedeemer

      lookups ∷ ScriptLookups Void
      lookups = ScriptLookups.unspentOutputs (Map.singleton txIn txOut)
        <> ScriptLookups.validator validator

    unbalancedTx ← Monad.liftedE $ ScriptLookups.mkUnbalancedTx lookups
      constraints
    balancedTx ← Monad.liftedE $ Transaction.balanceAndSignTxE unbalancedTx
    txId ← Transaction.submit balancedTx
    Log.logInfo' $ "Transaction submitted: " <> show txId
    Transaction.awaitTxConfirmed txId
    Log.logInfo' $ "Transaction confirmed: " <> show txId

  pure unit
