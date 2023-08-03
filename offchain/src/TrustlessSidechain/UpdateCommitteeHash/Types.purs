-- | `UpdateCommitteeHash.Types` contains the types relating to the update
-- | committee hash endpoint.
-- |
-- | Note: the reason for the existence of this module is because without this
-- | there are some cyclic dependencies between `MerkleRoot` and `UpdateCommitteeHash`
module TrustlessSidechain.UpdateCommitteeHash.Types
  ( UpdateCommitteeHashDatum(UpdateCommitteeHashDatum)
  , UpdateCommitteeHash(UpdateCommitteeHash)
  , InitCommitteeHashMint(InitCommitteeHashMint)
  , UpdateCommitteeHashRedeemer(UpdateCommitteeHashRedeemer)
  , UpdateCommitteeHashParams(UpdateCommitteeHashParams)
  , UpdateCommitteeHashMessage(UpdateCommitteeHashMessage)
  ) where

import Contract.Prelude

import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class FromData
  , class ToData
  , PlutusData(Constr)
  , toData
  )
import Contract.Prim.ByteArray (ByteArray)
import Contract.Transaction (TransactionInput)
import Contract.Value (CurrencySymbol)
import Data.BigInt (BigInt)
import TrustlessSidechain.MerkleTree (RootHash)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Types (AssetClass)
import TrustlessSidechain.Utils.Crypto
  ( EcdsaSecp256k1PubKey
  , EcdsaSecp256k1Signature
  )
import TrustlessSidechain.Utils.Data
  ( productFromData2
  , productToData2
  , productToData3
  , productToData4
  )

-- | `UpdateCommitteeHashDatum` is the datum for the update committee hash
-- | validator
newtype UpdateCommitteeHashDatum = UpdateCommitteeHashDatum
  { committeeHash ∷ ByteArray
  , sidechainEpoch ∷ BigInt
  }

derive instance Generic UpdateCommitteeHashDatum _

derive instance Newtype UpdateCommitteeHashDatum _

instance ToData UpdateCommitteeHashDatum where
  toData (UpdateCommitteeHashDatum { committeeHash, sidechainEpoch }) =
    productToData2 committeeHash sidechainEpoch

instance FromData UpdateCommitteeHashDatum where
  fromData = productFromData2
    ( \x y → UpdateCommitteeHashDatum
        { committeeHash: x
        , sidechainEpoch: y
        }
    )

-- | `UpdateCommitteeHash` paramaterizes the the validator for the update
-- | committee hash policy.
newtype UpdateCommitteeHash = UpdateCommitteeHash
  { sidechainParams ∷ SidechainParams
  , uchAssetClass ∷ AssetClass
  , merkleRootTokenCurrencySymbol ∷ CurrencySymbol
  }

derive instance Generic UpdateCommitteeHash _

derive instance Newtype UpdateCommitteeHash _

instance ToData UpdateCommitteeHash where
  toData
    ( UpdateCommitteeHash
        { sidechainParams, uchAssetClass, merkleRootTokenCurrencySymbol }
    ) = productToData3 sidechainParams
    uchAssetClass
    merkleRootTokenCurrencySymbol

-- | `InitCommitteeHashMint` parameterizes the minting policy which identifies
-- | the utxo with the update committee hash validator script.
newtype InitCommitteeHashMint = InitCommitteeHashMint
  { icTxOutRef ∷ TransactionInput }

derive instance Generic InitCommitteeHashMint _

derive instance Newtype InitCommitteeHashMint _

instance ToData InitCommitteeHashMint where
  toData (InitCommitteeHashMint { icTxOutRef }) =
    toData icTxOutRef

-- | `UpdateCommitteeHashRedeemer` is the redeemer for the update committee
-- | hash validator.
data UpdateCommitteeHashRedeemer = UpdateCommitteeHashRedeemer
  { committeeSignatures ∷ Array EcdsaSecp256k1Signature
  , committeePubKeys ∷ Array EcdsaSecp256k1PubKey
  , newCommitteePubKeys ∷ Array EcdsaSecp256k1PubKey
  , previousMerkleRoot ∷ Maybe RootHash
  }

derive instance Generic UpdateCommitteeHashRedeemer _

instance ToData UpdateCommitteeHashRedeemer where
  toData
    ( UpdateCommitteeHashRedeemer
        { committeeSignatures
        , committeePubKeys
        , newCommitteePubKeys
        , previousMerkleRoot
        }
    ) = productToData4 committeeSignatures
    committeePubKeys
    newCommitteePubKeys
    previousMerkleRoot

-- | `UpdateCommitteeHashParams` is the offchain parameter for the update
-- | committee hash endpoint.
newtype UpdateCommitteeHashParams = UpdateCommitteeHashParams
  { sidechainParams ∷ SidechainParams
  , newCommitteePubKeys ∷ Array EcdsaSecp256k1PubKey
  , committeeSignatures ∷
      Array (EcdsaSecp256k1PubKey /\ Maybe EcdsaSecp256k1Signature)
  , previousMerkleRoot ∷ Maybe RootHash
  , sidechainEpoch ∷ BigInt -- sidechain epoch of the new committee
  }

derive newtype instance Show UpdateCommitteeHashParams

derive instance Newtype UpdateCommitteeHashParams _

-- | `UpdateCommitteeHashMessage` corresponds to the on chain type which is
-- | signed by the committee (technically, if `uchm` is an
-- | `UpdateCommitteeHashMessage`, then the committee signs
-- | `blake2b256Hash(serialiseToData (toBuiltinData uchm))`)
newtype UpdateCommitteeHashMessage = UpdateCommitteeHashMessage
  { sidechainParams ∷ SidechainParams
  , -- `newCommitteePubKeys` is the new committee public keys and _should_
    -- be sorted lexicographically (recall that we can trust the bridge, so it
    -- should do this for us
    newCommitteePubKeys ∷ Array EcdsaSecp256k1PubKey
  , previousMerkleRoot ∷ Maybe RootHash
  , sidechainEpoch ∷ BigInt
  }

derive instance Generic UpdateCommitteeHashMessage _

instance ToData UpdateCommitteeHashMessage where
  toData
    ( UpdateCommitteeHashMessage
        { sidechainParams
        , newCommitteePubKeys
        , previousMerkleRoot
        , sidechainEpoch
        }
    ) = Constr (BigNum.fromInt 0)
    [ toData sidechainParams
    , toData newCommitteePubKeys
    , toData previousMerkleRoot
    , toData sidechainEpoch
    ]
