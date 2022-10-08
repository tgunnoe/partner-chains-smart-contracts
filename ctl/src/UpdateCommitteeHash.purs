module UpdateCommitteeHash
  ( module UpdateCommitteeHash.Types
  , module UpdateCommitteeHash.Utils
  , updateCommitteeHash
  ) where

import Contract.Prelude

import BalanceTx.Extra (reattachDatumsInline)
import Contract.Log (logInfo')
import Contract.Monad
  ( Contract
  , liftContractM
  , liftedE
  , liftedM
  , throwContractError
  )
import Contract.PlutusData
  ( fromData
  , toData
  )
import Contract.ScriptLookups as Lookups
import Contract.Scripts as Scripts
import Contract.Transaction
  ( TransactionOutput(..)
  , TransactionOutputWithRefScript(..)
  , awaitTxConfirmed
  , balanceAndSignTx
  , submit
  )
import Contract.TxConstraints (DatumPresence(..))
import Contract.TxConstraints as TxConstraints
import Contract.Value as Value
import Data.Array as Array
import Data.Map as Map
import Data.Maybe (Maybe(..))
import MPTRoot.Types (SignedMerkleRootMint(SignedMerkleRootMint))
import MPTRoot.Utils as MPTRoot.Utils
import SidechainParams (SidechainParams(..))
import Types
  ( assetClass
  , assetClassValue
  )
import Types.Datum (Datum(..))
import Types.OutputDatum (outputDatumDatum)
import Types.Redeemer (Redeemer(..))
import UpdateCommitteeHash.Types
  ( InitCommitteeHashMint(InitCommitteeHashMint)
  , UpdateCommitteeHash(UpdateCommitteeHash)
  , UpdateCommitteeHashDatum(UpdateCommitteeHashDatum)
  , UpdateCommitteeHashMessage(UpdateCommitteeHashMessage)
  , UpdateCommitteeHashParams(UpdateCommitteeHashParams)
  , UpdateCommitteeHashRedeemer(UpdateCommitteeHashRedeemer)
  )
import UpdateCommitteeHash.Utils
  ( aggregateKeys
  , committeeHashAssetClass
  , committeeHashPolicy
  , findUpdateCommitteeHashUtxo
  , initCommitteeHashMintTn
  , serialiseUchmHash
  , updateCommitteeHashValidator
  )
import Utils.Crypto as Utils.Crypto

-- | 'updateCommitteeHash' is the endpoint to submit the transaction to update the committee hash.
-- check if we have the right committee. This gets checked on chain also
updateCommitteeHash ∷ UpdateCommitteeHashParams → Contract () Unit
updateCommitteeHash (UpdateCommitteeHashParams uchp) = do
  -- Getting the minting policy / currency symbol / token name for update
  -- committee hash
  -------------------------------------------------------------
  pol ← committeeHashPolicy
    ( InitCommitteeHashMint
        { icTxOutRef: (\(SidechainParams x) → x.genesisUtxo) uchp.sidechainParams
        }
    )

  cs ← liftContractM "Cannot get currency symbol"
    (Value.scriptCurrencySymbol pol)

  let tn = initCommitteeHashMintTn

  -- Getting the minting policy for the mpt root token
  -------------------------------------------------------------
  let
    smrm = SignedMerkleRootMint
      { sidechainParams: uchp.sidechainParams
      , updateCommitteeHashCurrencySymbol: cs
      }
  mptRootTokenMintingPolicy ← MPTRoot.Utils.mptRootTokenMintingPolicy smrm
  mptRootTokenCurrencySymbol ←
    liftContractM
      "error 'updateCommitteeHash': failed to get mptRootTokenCurrencySymbol"
      $ Value.scriptCurrencySymbol mptRootTokenMintingPolicy

  -- Building the new committee hash
  -------------------------------------------------------------
  when (null uchp.committeeSignatures) (throwContractError "Empty Committee")

  let newCommitteeHash = aggregateKeys $ Array.sort uchp.newCommitteePubKeys

  let
    curCommitteePubKeys /\ committeeSignatures =
      Utils.Crypto.normalizeCommitteePubKeysAndSignatures uchp.committeeSignatures
    curCommitteeHash = aggregateKeys curCommitteePubKeys

  -- Getting the validator / building the validator hash
  -------------------------------------------------------------
  let
    uch = UpdateCommitteeHash
      { sidechainParams: uchp.sidechainParams
      , uchAssetClass: assetClass cs tn
      , mptRootTokenCurrencySymbol
      }
  updateValidator ← updateCommitteeHashValidator uch
  let valHash = Scripts.validatorHash updateValidator

  -- Grabbing the old committee / verifying that it really is the old committee
  -------------------------------------------------------------
  lkup ← findUpdateCommitteeHashUtxo uch
  { index: oref
  , value: (TransactionOutputWithRefScript { output: TransactionOutput tOut })
  } ←
    liftContractM "error 'updateCommitteeHash': failed to find token" $ lkup

  rawDatum ← liftContractM "No inline datum found" (outputDatumDatum tOut.datum)
  UpdateCommitteeHashDatum datum ← liftContractM "cannot get datum"
    (fromData $ unwrap rawDatum)
  when (datum.committeeHash /= curCommitteeHash)
    (throwContractError "incorrect committee provided")

  -- Grabbing the last merkle root reference
  -------------------------------------------------------------
  maybePreviousMerkleRoot ← MPTRoot.Utils.findPreviousMptRootTokenUtxo
    uchp.previousMerkleRoot
    smrm

  -- Building / submitting the transaction.
  -------------------------------------------------------------
  let
    newDatum = Datum $ toData
      (UpdateCommitteeHashDatum { committeeHash: newCommitteeHash })
    value = assetClassValue (unwrap uch).uchAssetClass one
    redeemer = Redeemer $ toData
      ( UpdateCommitteeHashRedeemer
          { committeeSignatures
          , committeePubKeys: curCommitteePubKeys
          , newCommitteePubKeys: uchp.newCommitteePubKeys
          , previousMerkleRoot: uchp.previousMerkleRoot
          }
      )

    lookups ∷ Lookups.ScriptLookups Void
    lookups =
      Lookups.unspentOutputs
        ( Map.singleton oref
            ( TransactionOutputWithRefScript
                { output: TransactionOutput tOut, scriptRef: Nothing }
            )
        )
        <> Lookups.validator updateValidator
    constraints = TxConstraints.mustSpendScriptOutput oref redeemer
      <> TxConstraints.mustPayToScript valHash newDatum DatumWitness value
      <> case maybePreviousMerkleRoot of
        Nothing → mempty
        Just { index: previousMerkleRootORef } → TxConstraints.mustReferenceOutput
          previousMerkleRootORef

  ubTx ← liftedE (Lookups.mkUnbalancedTx lookups constraints)
  bsTx ← liftedM "Failed to balance/sign tx"
    (balanceAndSignTx (reattachDatumsInline ubTx))
  txId ← submit bsTx
  logInfo' "Submitted updateCommitteeHash transaction!"
  awaitTxConfirmed txId
  logInfo' "updateCommitteeHash transaction submitted successfully!"
