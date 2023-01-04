-- | `MPTRoot.Utils` contains utility functions relating to the
-- | MPT root endpoint including:
-- |
-- |      - Creating the data for onchain validators / minting policies
-- |
-- |      - Querying utxos regarding the MPT root
-- |
-- | Note: the reason for the existence of this module is because there are some
-- | cyclic dependencies between `MPTRoot` and `UpdateCommitteeHash` without
-- | this.
module MPTRoot.Utils
  ( mptRootTokenMintingPolicy
  , mptRootTokenValidator
  , findMptRootTokenUtxo
  , findPreviousMptRootTokenUtxo
  , serialiseMrimHash
  , normalizeSaveRootParams
  ) where

import Contract.Prelude

import Contract.Address as Address
import Contract.Hashing as Hashing
import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.PlutusData as PlutusData
import Contract.Scripts (MintingPolicy(..), Validator(..))
import Contract.Scripts as Scripts
import Contract.TextEnvelope (TextEnvelopeType(PlutusScriptV2))
import Contract.TextEnvelope as TextEnvelope
import Contract.Transaction (TransactionInput, TransactionOutputWithRefScript)
import Contract.Transaction as Transaction
import Contract.Value (TokenName)
import Contract.Value as Value
import MPTRoot.Types
  ( MerkleRootInsertionMessage
  , SaveRootParams(..)
  , SignedMerkleRootMint
  )
import MerkleTree (RootHash)
import MerkleTree as MerkleTree
import RawScripts as RawScripts
import SidechainParams (SidechainParams)
import Utils.Crypto (SidechainMessage)
import Utils.Crypto as Utils.Crypto
import Utils.SerialiseData as Utils.SerialiseData
import Utils.Utxos as Utils.Utxos

-- | `normalizeSaveRootParams` modifies the following fields in
-- | `SaveRootParams` fields to satisfy the following properties
-- |    - `committeeSignatures` is sorted (lexicographically) by the
-- |    `SidechainPublicKey`.
normalizeSaveRootParams ∷ SaveRootParams → SaveRootParams
normalizeSaveRootParams (SaveRootParams p) =
  SaveRootParams p
    { committeeSignatures = Utils.Crypto.normalizeCommitteePubKeysAndSignatures
        p.committeeSignatures
    }

-- | `mptRootTokenMintingPolicy` gets the minting policy corresponding to
-- | `RawScripts.rawMPTRootTokenMintingPolicy` paramaterized by the given
-- | `SignedMerkleRootMint`.
mptRootTokenMintingPolicy ∷ SignedMerkleRootMint → Contract () MintingPolicy
mptRootTokenMintingPolicy sp = do
  mptRootMP ← Transaction.plutusV2Script <$>
    TextEnvelope.textEnvelopeBytes
      RawScripts.rawMPTRootTokenMintingPolicy
      PlutusScriptV2
  applied ← Scripts.applyArgs mptRootMP [ PlutusData.toData sp ]
  PlutusMintingPolicy <$> Monad.liftContractE applied

-- | `mptRootTokenValidator` gets the validator corresponding to
-- | 'RawScripts.rawMPTRootTokenValidator' paramaterized by `SidechainParams`.
mptRootTokenValidator ∷ SidechainParams → Contract () Validator
mptRootTokenValidator sp = do
  mptRootVal ← Transaction.plutusV2Script <$>
    TextEnvelope.textEnvelopeBytes
      RawScripts.rawMPTRootTokenValidator
      PlutusScriptV2
  applied ← Scripts.applyArgs mptRootVal [ PlutusData.toData sp ]
  Validator <$> Monad.liftContractE applied

-- | `findMptRootTokenUtxo merkleRoot smrm` locates a utxo which
-- |
-- |    1. is sitting at the some utxo with validator address
-- |    `mptRootTokenValidator smrm.sidechainParams`
-- |
-- |    2. contains a token with `CurrencySymbol` `mptRootTokenMintingPolicy smrm`
-- |    and `TokenName` as `merkleRoot`.
-- |
-- | Note: in the case that there is more than such utxo, this returns the first
-- | such utxo it finds that satisifies the aforementioned properties.
findMptRootTokenUtxo ∷
  TokenName →
  SignedMerkleRootMint →
  Contract ()
    (Maybe { index ∷ TransactionInput, value ∷ TransactionOutputWithRefScript })
findMptRootTokenUtxo merkleRoot smrm = do
  netId ← Address.getNetworkId
  validator ← mptRootTokenValidator (unwrap smrm).sidechainParams
  let validatorHash = Scripts.validatorHash validator

  validatorAddress ← Monad.liftContractM
    "error 'findMptRootTokenUtxo': failed to get validator address"
    (Address.validatorHashEnterpriseAddress netId validatorHash)

  mintingPolicy ← mptRootTokenMintingPolicy smrm
  currencySymbol ←
    Monad.liftContractM
      "error 'findMptRootTokenUtxo': failed to get currency symbol for minting policy"
      $ Value.scriptCurrencySymbol mintingPolicy

  Utils.Utxos.findUtxoByValueAt validatorAddress \value →
    -- Note: we just need the existence of the token i.e., there is a nonzero
    -- amount
    Value.valueOf value currencySymbol merkleRoot /= zero

-- | `findPreviousMptRootTokenUtxo maybeLastMerkleRoot smrm` returns `Nothing` in
-- | the case that `maybeLastMerkleRoot` is `Nothing`, and `Just` the result of
-- | `findMptRootTokenUtxo lastMerkleRoot smrm` provided that `Just lastMerkleRoot = maybeLastMerkleRoot`
-- | and there are no other errors.
-- | Note: the `Maybe` return type does NOT denote the absense or existence of
-- | finding the utxo... rather it reflects the `Maybe` in the last merkle root
-- | of whether it exists or not.
findPreviousMptRootTokenUtxo ∷
  Maybe RootHash →
  SignedMerkleRootMint →
  Contract ()
    (Maybe { index ∷ TransactionInput, value ∷ TransactionOutputWithRefScript })
findPreviousMptRootTokenUtxo maybeLastMerkleRoot smrm =
  case maybeLastMerkleRoot of
    Nothing → pure Nothing
    Just lastMerkleRoot' → do
      lastMerkleRootTokenName ← Monad.liftContractM
        "error 'saveRoot': invalid lastMerkleRoot token name"
        (Value.mkTokenName $ MerkleTree.unRootHash lastMerkleRoot')
      lkup ← findMptRootTokenUtxo lastMerkleRootTokenName smrm
      lkup' ←
        Monad.liftContractM
          "error 'findPreviousMptRootTokenUtxo': failed to find last merkle root"
          $ lkup
      pure $ Just lkup'

-- | `serialiseMrimHash` is an alias for (ignoring the `Maybe`)
-- | ```purescript
-- | Contract.Hashing.blake2b256Hash <<< Utils.SerialiseData.serialiseToData
-- | ```
serialiseMrimHash ∷ MerkleRootInsertionMessage → Maybe SidechainMessage
serialiseMrimHash =
  Utils.Crypto.sidechainMessage <=<
    ((Hashing.blake2b256Hash <$> _) <<< Utils.SerialiseData.serialiseToData)
