-- | `UpdateCommitteeHash.Utils` contains utility functions relating to the
-- | update committee hash endpoint including:
-- |
-- |      - Creating the data for onchain validators / minting policies
-- |
-- |      - Mirroring functionality of onchain code
-- |
-- |      - Querying utxos regarding the update committee hash
-- |
-- | Note: the reason for the existence of this module is because there are some
-- | cyclic dependencies between `MerkleRoot` and `UpdateCommitteeHash` without
-- | this.
module UpdateCommitteeHash.Utils
  ( committeeHashPolicy
  , updateCommitteeHashValidator
  , initCommitteeHashMintTn
  , committeeHashAssetClass
  , aggregateKeys
  , findUpdateCommitteeHashUtxo
  , serialiseUchmHash
  , normalizeCommitteeHashParams
  ) where

import Contract.Prelude

import Contract.Address as Address
import Contract.Hashing as Hashing
import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.PlutusData as PlutusData
import Contract.Prim.ByteArray (ByteArray)
import Contract.Prim.ByteArray as ByteArray
import Contract.Scripts
  ( MintingPolicy(..)
  , Validator(..)
  )
import Contract.Scripts as Scripts
import Contract.TextEnvelope
  ( decodeTextEnvelope
  , plutusScriptV2FromEnvelope
  )
import Contract.Transaction
  ( TransactionInput
  , TransactionOutputWithRefScript
  )
import Contract.Value as Value
import Data.Array as Array
import Partial.Unsafe (unsafePartial)
import RawScripts as RawScripts
import Types (AssetClass, assetClass)
import UpdateCommitteeHash.Types
  ( InitCommitteeHashMint
  , UpdateCommitteeHash
  , UpdateCommitteeHashMessage
  , UpdateCommitteeHashParams(..)
  )
import Utils.Crypto (SidechainMessage, SidechainPublicKey)
import Utils.Crypto as Utils.Crypto
import Utils.SerialiseData as Utils.SerialiseData
import Utils.Utxos as Utils.Utxos

committeeHashPolicy ∷ InitCommitteeHashMint → Contract () MintingPolicy
committeeHashPolicy sp = do
  let
    script = decodeTextEnvelope RawScripts.rawCommitteeHashPolicy
      >>= plutusScriptV2FromEnvelope

  unapplied ← Monad.liftContractM "Decoding text envelope failed." script
  applied ← Monad.liftContractE $ Scripts.applyArgs unapplied
    [ PlutusData.toData sp ]
  pure $ PlutusMintingPolicy applied

updateCommitteeHashValidator ∷ UpdateCommitteeHash → Contract () Validator
updateCommitteeHashValidator sp = do
  let
    script = decodeTextEnvelope RawScripts.rawCommitteeHashValidator
      >>= plutusScriptV2FromEnvelope

  unapplied ← Monad.liftContractM "Decoding text envelope failed." script
  applied ← Monad.liftContractE $ Scripts.applyArgs unapplied
    [ PlutusData.toData sp ]
  pure $ Validator applied

-- | `normalizeCommitteeHashParams` modifies the following fields in
-- | `UpdateCommitteeHashParams` fields to satisfy the following properties
-- |    - `newCommitteePubKeys` is sorted (lexicographically), and
-- |    - `committeeSignatures` is sorted (lexicographically) by the
-- |    `SidechainPublicKey`.
normalizeCommitteeHashParams ∷
  UpdateCommitteeHashParams → UpdateCommitteeHashParams
normalizeCommitteeHashParams (UpdateCommitteeHashParams p) =
  UpdateCommitteeHashParams
    p
      { newCommitteePubKeys = Array.sort p.newCommitteePubKeys
      , committeeSignatures = Utils.Crypto.normalizeCommitteePubKeysAndSignatures
          p.committeeSignatures
      }

-- | `initCommitteeHashMintTn` is the token name of the NFT which identifies
-- | the utxo which contains the committee hash. We use an empty bytestring for
-- | this because the name really doesn't matter, so we mighaswell save a few
-- | bytes by giving it the empty name.
initCommitteeHashMintTn ∷ Value.TokenName
initCommitteeHashMintTn = unsafePartial $ fromJust $ Value.mkTokenName $
  ByteArray.hexToByteArrayUnsafe ""

-- | `committeeHashCurSymbol` is the asset class. See `initCommitteeHashMintTn`
-- | for details on the token name
{-# INLINEABLE committeeHashAssetClass #-}
committeeHashAssetClass ∷ InitCommitteeHashMint → Contract () AssetClass
committeeHashAssetClass ichm = do
  cp ← committeeHashPolicy ichm
  curSym ← Monad.liftContractM "Couldn't get committeeHash currency symbol"
    (Value.scriptCurrencySymbol cp)

  pure $ assetClass curSym initCommitteeHashMintTn

-- | `aggregateKeys` aggregates a list of keys s.t. the resulting `ByteArray`
-- | may be stored in the `UpdateCommitteeHashDatum` in an onchain compatible way.
-- | For this to be truly compatible with the onchain function, you need to ensure
-- | that the input list is sorted.
aggregateKeys ∷ Array SidechainPublicKey → ByteArray
aggregateKeys = Hashing.blake2b256Hash <<< foldMap
  Utils.Crypto.getSidechainPublicKeyByteArray

-- | `serialiseUchmHash` is an alias for (ignoring the `Maybe`)
-- | ```
-- | Contract.Hashing.blake2b256Hash <<< Utils.SerialiseData.serialiseToData
-- | ```
-- | The result of this function is what is signed by the committee members.
serialiseUchmHash ∷ UpdateCommitteeHashMessage → Maybe SidechainMessage
serialiseUchmHash = Utils.Crypto.sidechainMessage <=<
  ((Hashing.blake2b256Hash <$> _) <<< Utils.SerialiseData.serialiseToData)

-- | `findUpdateCommitteeHashUtxo` returns the (unique) utxo which hold the token which
-- | identifies the committee hash.
--
-- Time complexity: bad, it looks at all utxos at the update committee hash
-- validator, then linearly scans through each utxo to determine which has token
findUpdateCommitteeHashUtxo ∷
  UpdateCommitteeHash →
  Contract ()
    (Maybe { index ∷ TransactionInput, value ∷ TransactionOutputWithRefScript })
findUpdateCommitteeHashUtxo uch = do
  netId ← Address.getNetworkId
  validator ← updateCommitteeHashValidator uch
  let validatorHash = Scripts.validatorHash validator

  validatorAddress ← Monad.liftContractM
    "error 'findUpdateCommitteeHashUtxo': failed to get validator address"
    (Address.validatorHashEnterpriseAddress netId validatorHash)

  Utils.Utxos.findUtxoByValueAt validatorAddress \value →
    -- Note: there should either be 0 or 1 tokens of this committee hash nft.
    Value.valueOf value (fst (unwrap uch).uchAssetClass) initCommitteeHashMintTn
      /= zero
