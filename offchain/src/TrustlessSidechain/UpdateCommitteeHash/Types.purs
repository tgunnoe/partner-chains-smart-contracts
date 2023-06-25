-- | `UpdateCommitteeHash.Types` contains the types relating to the update
-- | committee hash endpoint.
-- |
-- | Note: the reason for the existence of this module is because without this
-- | there are some cyclic dependencies between `MerkleRoot` and `UpdateCommitteeHash`
module TrustlessSidechain.UpdateCommitteeHash.Types
  ( UpdateCommitteeDatum(UpdateCommitteeDatum)
  , UpdateCommitteeHash(UpdateCommitteeHash)
  , UpdateCommitteeHashMessage(UpdateCommitteeHashMessage)
  , UpdateCommitteeHashRedeemer(UpdateCommitteeHashRedeemer)
  ) where

import Contract.Prelude

import Contract.Address (Address)
import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class FromData
  , class ToData
  , PlutusData(Constr)
  , fromData
  , toData
  )
import Contract.Value (CurrencySymbol)
import Data.BigInt (BigInt)
import TrustlessSidechain.MerkleTree (RootHash)
import TrustlessSidechain.SidechainParams (SidechainParams)

-- | `UpdateCommitteeDatum` is the datum for the update committee hash
-- | validator
-- | This corresponds to the onchain type. In the future, the
-- | `aggregatePubKeys` type that this is instantiated with may change as we
-- | implement different ATMS schemes.
newtype UpdateCommitteeDatum aggregatePubKeys = UpdateCommitteeDatum
  { aggregatePubKeys ∷ aggregatePubKeys
  , sidechainEpoch ∷ BigInt
  }

instance
  ToData aggregatePubKeys ⇒
  ToData (UpdateCommitteeDatum aggregatePubKeys) where
  toData (UpdateCommitteeDatum { aggregatePubKeys, sidechainEpoch }) = Constr
    (BigNum.fromInt 0)
    [ toData aggregatePubKeys, toData sidechainEpoch ]

instance
  FromData aggregatePubKeys ⇒
  FromData (UpdateCommitteeDatum aggregatePubKeys) where
  fromData (Constr n [ a, b ])
    | n == BigNum.fromInt 0 =
        UpdateCommitteeDatum <$>
          ( { aggregatePubKeys: _, sidechainEpoch: _ }
              <$> fromData a
              <*> fromData b
          )
  fromData _ = Nothing

-- | `UpdateCommitteeHashRedeemer` is the redeemer for the update committee hash
-- | validator
-- | This corresponds to the onchain type.
newtype UpdateCommitteeHashRedeemer = UpdateCommitteeHashRedeemer
  { previousMerkleRoot ∷ Maybe RootHash
  }

derive instance Generic UpdateCommitteeHashRedeemer _

derive instance Newtype UpdateCommitteeHashRedeemer _

instance ToData UpdateCommitteeHashRedeemer where
  toData (UpdateCommitteeHashRedeemer { previousMerkleRoot }) = toData
    previousMerkleRoot

instance FromData UpdateCommitteeHashRedeemer where
  fromData d = UpdateCommitteeHashRedeemer <$>
    ({ previousMerkleRoot: _ } <$> fromData d)

-- | `UpdateCommitteeHash` paramaterizes the the validator for the update
-- | committee hash policy.
newtype UpdateCommitteeHash = UpdateCommitteeHash
  { sidechainParams ∷ SidechainParams
  , committeeOracleCurrencySymbol ∷ CurrencySymbol
  , committeeCertificateVerificationCurrencySymbol ∷ CurrencySymbol
  , merkleRootTokenCurrencySymbol ∷ CurrencySymbol
  }

derive instance Generic UpdateCommitteeHash _

derive instance Newtype UpdateCommitteeHash _

instance ToData UpdateCommitteeHash where
  toData
    ( UpdateCommitteeHash
        { sidechainParams
        , committeeOracleCurrencySymbol
        , committeeCertificateVerificationCurrencySymbol
        , merkleRootTokenCurrencySymbol
        }
    ) = Constr (BigNum.fromInt 0)
    [ toData sidechainParams
    , toData committeeOracleCurrencySymbol
    , toData committeeCertificateVerificationCurrencySymbol
    , toData merkleRootTokenCurrencySymbol
    ]

-- | `UpdateCommitteeHashMessage` corresponds to the on chain type which is
-- | signed by the committee (technically, if `uchm` is an
-- | `UpdateCommitteeHashMessage`, then the committee signs
-- | `blake2b256Hash(serialiseToData (toBuiltinData uchm))`)
newtype UpdateCommitteeHashMessage aggregatePubKeys = UpdateCommitteeHashMessage
  { sidechainParams ∷ SidechainParams
  , -- `newAggregatePubKeys` is the new committee public keys and _should_
    -- be sorted lexicographically (recall that we can trust the bridge, so it
    -- should do this for us
    -- newAggregatePubKeys ∷ Array SidechainPublicKey
    -- TODO: fix the documentation here
    newAggregatePubKeys ∷ aggregatePubKeys
  , previousMerkleRoot ∷ Maybe RootHash
  , sidechainEpoch ∷ BigInt
  , validatorAddress ∷ Address
  }

instance
  ToData aggregatePubKeys ⇒
  ToData (UpdateCommitteeHashMessage aggregatePubKeys) where
  toData
    ( UpdateCommitteeHashMessage
        { sidechainParams
        , newAggregatePubKeys
        , previousMerkleRoot
        , sidechainEpoch
        , validatorAddress
        }
    ) = Constr (BigNum.fromInt 0)
    [ toData sidechainParams
    , toData newAggregatePubKeys
    , toData previousMerkleRoot
    , toData sidechainEpoch
    , toData validatorAddress
    ]
