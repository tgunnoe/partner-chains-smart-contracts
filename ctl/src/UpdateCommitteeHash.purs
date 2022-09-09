module UpdateCommitteeHash where

import Contract.Prelude

import Contract.Address
  ( PubKeyHash
  , getNetworkId
  , validatorHashEnterpriseAddress
  )
import Contract.Log (logInfo')
import Contract.Monad
  ( Contract
  , liftContractM
  , liftedE
  , liftedM
  , throwContractError
  )
import Contract.PlutusData
  ( class FromData
  , class ToData
  , PlutusData(Constr)
  , fromData
  , toData
  )
import Contract.Prim.ByteArray (byteArrayFromAscii)
import Contract.ScriptLookups as Lookups
import Contract.Scripts
  ( MintingPolicy(..)
  , Validator(..)
  , applyArgs
  , validatorHash
  )
import Contract.TextEnvelope (TextEnvelopeType(..), textEnvelopeBytes)
import Contract.Transaction
  ( TransactionInput
  , TransactionOutput(..)
  , awaitTxConfirmed
  , balanceAndSignTx
  , submit
  )
import Contract.TxConstraints as Constraints
import Contract.Utxos (utxosAt)
import Contract.Value as Value
import Data.Array (toUnfoldable)
import Data.BigInt (fromInt)
import Data.Foldable (find)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import MerkleTree as MT
import RawScripts (rawUpdateCommitteeHash)
import SidechainParams (SidechainParams(..))
import Types.Datum (Datum(..))
import Types.OutputDatum (outputDatumDatum)
import Types.Redeemer (Redeemer(..))
import Types.Scripts (plutusV2Script)

newtype UpdateCommitteeHashDatum = UpdateCommitteeHashDatum
  { committeeHash ∷ String }

derive instance Generic UpdateCommitteeHashDatum _
derive instance Newtype UpdateCommitteeHashDatum _
instance ToData UpdateCommitteeHashDatum where
  toData (UpdateCommitteeHashDatum { committeeHash }) = Constr zero
    [ toData committeeHash ]

instance FromData UpdateCommitteeHashDatum where
  fromData (Constr n [ a ])
    | n == zero = UpdateCommitteeHashDatum <$> ({ committeeHash: _ }) <$>
        fromData a
  fromData _ = Nothing

-- plutus script is parameterised on AssetClass, which CTL doesn't have
-- the toData instance uses the underlying tuple so we do the same
newtype UpdateCommitteeHash = UpdateCommitteeHash
  { uchAssetClass ∷ Value.CurrencySymbol /\ Value.TokenName }

derive instance Generic UpdateCommitteeHash _
derive instance Newtype UpdateCommitteeHash _
instance ToData UpdateCommitteeHash where
  toData (UpdateCommitteeHash { uchAssetClass }) = Constr zero
    [ toData uchAssetClass ]

newtype InitCommitteeHashMint = InitCommitteeHashMint
  { icTxOutRef ∷ TransactionInput }

derive instance Generic InitCommitteeHashMint _
derive instance Newtype InitCommitteeHashMint _
instance ToData InitCommitteeHashMint where
  toData (InitCommitteeHashMint { icTxOutRef }) = Constr zero
    [ toData icTxOutRef ]

data UpdateCommitteeHashRedeemer = UpdateCommitteeHashRedeemer
  { committeeSignatures ∷ Array String -- String
  , committeePubKeys ∷ Array PubKeyHash -- TODO Check
  , newCommitteeHash ∷ String
  }

derive instance Generic UpdateCommitteeHashRedeemer _
instance ToData UpdateCommitteeHashRedeemer where
  toData
    ( UpdateCommitteeHashRedeemer
        { committeeSignatures, committeePubKeys, newCommitteeHash }
    ) = Constr zero
    [ toData committeeSignatures
    , toData committeePubKeys
    , toData newCommitteeHash
    ]

data UpdateCommitteeHashParams = UpdateCommitteeHashParams
  { sidechainParams ∷ SidechainParams
  , newCommitteePubKeys ∷ Array PubKeyHash
  , newCommitteeSignatures ∷ Array String
  , committeePubKeys ∷ Array PubKeyHash
  }

derive instance Generic UpdateCommitteeHashParams _
instance ToData UpdateCommitteeHashParams where
  toData
    ( UpdateCommitteeHashParams
        { sidechainParams
        , newCommitteePubKeys
        , newCommitteeSignatures
        , committeePubKeys
        }
    ) = Constr zero
    [ toData sidechainParams
    , toData newCommitteePubKeys
    , toData newCommitteeSignatures
    , toData committeePubKeys
    ]

committeeHashPolicy ∷ InitCommitteeHashMint → Contract () MintingPolicy
committeeHashPolicy sp = do
  policyUnapplied ← (plutusV2Script >>> MintingPolicy) <$> textEnvelopeBytes
    rawUpdateCommitteeHash
    PlutusScriptV2
  liftedE (applyArgs policyUnapplied [ toData sp ])

updateCommitteeHashValidator ∷ UpdateCommitteeHash → Contract () Validator
updateCommitteeHashValidator sp = do
  validatorUnapplied ← (plutusV2Script >>> Validator) <$> textEnvelopeBytes
    rawUpdateCommitteeHash
    PlutusScriptV2
  liftedE (applyArgs validatorUnapplied [ toData sp ])

-- N.B. on-chain code verifies the datum is contained in the output -- see Note [Committee hash in output datum]
-- | 'updateCommitteeHash' is the endpoint to submit the transaction to update the committee hash.
-- check if we have the right committee. This gets checked on chain also
updateCommitteeHash ∷ UpdateCommitteeHashParams → Contract () Unit
updateCommitteeHash (UpdateCommitteeHashParams uchp) = do
  pol ← committeeHashPolicy
    ( InitCommitteeHashMint
        { icTxOutRef: (\(SidechainParams x) → x.genesisUtxo) uchp.sidechainParams
        }
    )
  cs ← liftContractM "Cannot get currency symbol"
    (Value.scriptCurrencySymbol pol)
  tn ← liftContractM "Cannot get token name"
    (Value.mkTokenName =<< byteArrayFromAscii "") -- TODO init token name?
  when (null uchp.committeePubKeys) (throwContractError "Empty Committee")
  let
    aggregateKeys ∷ Array String → String -- pubkeyhash or String ?
    aggregateKeys ls = MT.unRootHash $ MT.rootHash
      (MT.fromList (toUnfoldable ls))
    uch = { uchAssetClass: cs /\ tn }
    -- show is our version of (getLedgerBytes . getPubKey)
    newCommitteeHash = aggregateKeys (show <$> uchp.newCommitteePubKeys) ∷ String -- aggregateKeys (newCommitteePubKeys uchp)
    curCommitteeHash = aggregateKeys (show <$> uchp.committeePubKeys)
  updateValidator ← updateCommitteeHashValidator (UpdateCommitteeHash uch)
  let valHash = validatorHash updateValidator
  netId ← getNetworkId
  valAddr ← liftContractM "updateCommitteeHash: get validator address"
    (validatorHashEnterpriseAddress netId valHash)
  scriptUtxos ←
    Map.toUnfoldable <<< unwrap <$> liftedM "Cannot get script utxos"
      (utxosAt valAddr) ∷
      Contract () (Array (TransactionInput /\ TransactionOutput))
  let
    uchCS /\ uchTN = uch.uchAssetClass
    findOwnValue (_tIN /\ tOUT) =
      Value.valueOf ((unwrap tOUT).amount) uchCS uchTN == fromInt 1
    found = find findOwnValue scriptUtxos
  (oref /\ (TransactionOutput tOut)) ← liftContractM
    "updateCommittee hash output not found"
    found
  rawDatum ← liftContractM "no datum" (outputDatumDatum tOut.datum)
  UpdateCommitteeHashDatum datum ← liftContractM "cannot get datum"
    (fromData $ unwrap rawDatum)
  --dat    ← liftContractM "no datahash" (tOut.dataHash)
  --datums ← getDatumsByHashes (mapMaybe (snd >>> unwrap >>> _.dataHash) scriptUtxos)
  --datum  ← liftContractM "no datum" =<< liftContractM "no datum"  ((fromData <<< unwrap) <$> (dat `Map.lookup` datums))
  when (datum.committeeHash /= curCommitteeHash)
    (throwContractError "incorrect committee provided")
  let
    newDatum = Datum $ toData
      (UpdateCommitteeHashDatum { committeeHash: newCommitteeHash })
    value = Value.singleton cs uchTN (fromInt 1)
    redeemer = Redeemer $ toData
      ( UpdateCommitteeHashRedeemer
          { committeeSignatures: uchp.newCommitteeSignatures
          , committeePubKeys: [] -- cmtPubKeys TODO
          , newCommitteeHash: newCommitteeHash
          }
      )

    lookups ∷ Lookups.ScriptLookups Void
    lookups = Lookups.unspentOutputs
      (Map.singleton oref (TransactionOutput tOut))
    constraints = Constraints.mustSpendScriptOutput oref redeemer
      <> Constraints.mustPayToScript valHash newDatum value
  ubTx ← liftedE (Lookups.mkUnbalancedTx lookups constraints)
  bsTx ← liftedM "Failed to balance/sign tx" (balanceAndSignTx ubTx)
  txId ← submit bsTx
  logInfo' "Submitted updateCommitteeHash transaction!"
  awaitTxConfirmed txId
  logInfo' "updateCommitteeHash transaction submitted successfully!"
