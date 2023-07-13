{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module TrustlessSidechain.Types where

import Ledger.Crypto (PubKey, PubKeyHash, Signature)
import Ledger.Value (AssetClass, CurrencySymbol)
import Plutus.V2.Ledger.Api (Address, ValidatorHash)
import Plutus.V2.Ledger.Tx (TxOutRef)
import PlutusTx (FromData, ToData, UnsafeFromData)
import PlutusTx qualified
import TrustlessSidechain.HaskellPrelude qualified as TSPrelude
import TrustlessSidechain.MerkleTree (MerkleProof)
import TrustlessSidechain.PlutusPrelude

-- * Sidechain Parametrization and general data

-- | Parameters uniquely identifying a sidechain
data SidechainParams = SidechainParams
  { chainId :: Integer
  , genesisHash :: GenesisHash
  , -- | 'genesisUtxo' is a 'TxOutRef' used to initialize the internal
    -- policies in the side chain (e.g. for the 'UpdateCommitteeHash' endpoint)
    genesisUtxo :: TxOutRef
  , -- | 'thresholdNumerator' is the numerator for the ratio of the committee
    -- needed to sign off committee handovers / merkle roots
    thresholdNumerator :: Integer
  , -- | 'thresholdDenominator' is the denominator for the ratio of the
    -- committee needed to sign off committee handovers / merkle roots
    thresholdDenominator :: Integer
  }

newtype GenesisHash = GenesisHash {getGenesisHash :: BuiltinByteString}
  deriving newtype
    ( TSPrelude.Show
    , ToData
    , FromData
    , UnsafeFromData
    , IsString
    )

PlutusTx.makeIsDataIndexed ''SidechainParams [('SidechainParams, 0)]

-- | 'SidechainPubKey' is compressed DER Secp256k1 public key.
newtype SidechainPubKey = SidechainPubKey
  { getSidechainPubKey :: BuiltinByteString
  }
  deriving newtype
    ( TSPrelude.Eq
    , TSPrelude.Ord
    , ToData
    , FromData
    , UnsafeFromData
    )

-- * Committee Candidate Validator data

-- | Endpoint parameters for committee candidate registration
data RegisterParams = RegisterParams
  { sidechainParams :: SidechainParams
  , spoPubKey :: PubKey
  , sidechainPubKey :: BuiltinByteString
  , spoSig :: Signature
  , sidechainSig :: Signature
  , inputUtxo :: TxOutRef
  }

{- | 'CandidatePermissionMint' is used to parameterize the minting policy in
 'TrustlessSidechain.CommitteeCandidateMintingPolicy'.
-}
data CandidatePermissionMint = CandidatePermissionMint
  { cpmSidechainParams :: SidechainParams
  , cpmUtxo :: TxOutRef
  }

PlutusTx.makeIsDataIndexed ''CandidatePermissionMint [('CandidatePermissionMint, 0)]

-- | Endpoint parameters for committee candidate deregistration
data DeregisterParams = DeregisterParams
  { sidechainParams :: SidechainParams
  , spoPubKey :: PubKey
  }

data BlockProducerRegistration = BlockProducerRegistration
  { -- | SPO cold verification key hash
    bprSpoPubKey :: PubKey -- own cold verification key hash
  , -- | public key in the sidechain's desired format
    bprSidechainPubKey :: BuiltinByteString
  , -- | Signature of the SPO
    bprSpoSignature :: Signature
  , -- | Signature of the SPO
    bprSidechainSignature :: Signature
  , -- | A UTxO that must be spent by the transaction
    bprInputUtxo :: TxOutRef
  , -- | Owner public key hash
    bprOwnPkh :: PubKeyHash
  }

PlutusTx.makeIsDataIndexed ''BlockProducerRegistration [('BlockProducerRegistration, 0)]

data BlockProducerRegistrationMsg = BlockProducerRegistrationMsg
  { bprmSidechainParams :: SidechainParams
  , bprmSidechainPubKey :: BuiltinByteString
  , -- | A UTxO that must be spent by the transaction
    bprmInputUtxo :: TxOutRef
  }

PlutusTx.makeIsDataIndexed ''BlockProducerRegistrationMsg [('BlockProducerRegistrationMsg, 0)]

-- * Merkle Root Token data

{- | 'MerkleTreeEntry' (abbr. mte and pl. mtes) is the data which are the elements in the merkle tree
 for the MerkleRootToken.
-}
data MerkleTreeEntry = MerkleTreeEntry
  { -- | 32 bit unsigned integer, used to provide uniqueness among transactions within the tree
    mteIndex :: Integer
  , -- | 256 bit unsigned integer that represents amount of tokens being sent out of the bridge
    mteAmount :: Integer
  , -- | arbitrary length bytestring that represents decoded bech32 cardano
    -- address. See [here](https://cips.cardano.org/cips/cip19/) for more details
    -- of bech32
    mteRecipient :: BuiltinByteString
  , -- | the previous merkle root to ensure that the hashed entry is unique
    mtePreviousMerkleRoot :: Maybe BuiltinByteString
  }

PlutusTx.makeIsDataIndexed ''MerkleTreeEntry [('MerkleTreeEntry, 0)]

{- | 'MerkleRootInsertionMessage' is a data type for which committee members
 create signatures for
 >  blake2b(cbor(MerkleRootInsertionMessage))
-}
data MerkleRootInsertionMessage = MerkleRootInsertionMessage
  { mrimSidechainParams :: SidechainParams
  , mrimMerkleRoot :: BuiltinByteString
  , mrimPreviousMerkleRoot :: Maybe BuiltinByteString
  }

PlutusTx.makeIsDataIndexed ''MerkleRootInsertionMessage [('MerkleRootInsertionMessage, 0)]

{- | 'SignedMerkleRootRedeemer' is the redeemer for the signed merkle root
 minting policy
-}
newtype SignedMerkleRootRedeemer = SignedMerkleRootRedeemer
  { previousMerkleRoot :: Maybe BuiltinByteString
  }
  deriving newtype
    ( ToData
    , FromData
    , UnsafeFromData
    )

-- | 'SignedMerkleRootMint' is used to parameterize 'mkMintingPolicy'.
data SignedMerkleRootMint = SignedMerkleRootMint
  { -- | 'sidechainParams' includes the 'SidechainParams'
    sidechainParams :: SidechainParams
  , -- | 'committeeCertificateVerificationCurrencySymbol' is the 'CurrencySymbol' which
    -- provides a committee certificate for a message.
    committeeCertificateVerificationCurrencySymbol :: CurrencySymbol
  , -- | 'validatorHash' is the validator hash corresponding to
    -- 'TrustlessSidechain.MerkleRootTokenValidator.mkMptRootTokenValidator'
    -- to ensure that this token gets minted to the "right" place.
    validatorHash :: ValidatorHash
  }

PlutusTx.makeIsDataIndexed ''SignedMerkleRootMint [('SignedMerkleRootMint, 0)]

{- | 'CombinedMerkleProof' is a product type to include both the
 'MerkleTreeEntry' and the 'MerkleProof'.

 This exists as for testing in #249.
-}
data CombinedMerkleProof = CombinedMerkleProof
  { cmpTransaction :: MerkleTreeEntry
  , cmpMerkleProof :: MerkleProof
  }

PlutusTx.makeIsDataIndexed ''CombinedMerkleProof [('CombinedMerkleProof, 0)]

-- * FUEL Minting Policy data

-- | The Redeemer that's to be passed to onchain policy, indicating its mode of usage.
data FUELRedeemer
  = MainToSide BuiltinByteString -- Recipient's sidechain address
  | -- | 'SideToMain' indicates that we wish to mint FUEL on the mainchain.
    -- So, this includes which transaction in the sidechain we are
    -- transferring over to the main chain (hence the 'MerkleTreeEntry'), and
    -- the proof tha this actually happened on the sidechain (hence the
    -- 'MerkleProof')
    SideToMain MerkleTreeEntry MerkleProof

-- Recipient address is in FUELRedeemer just for reference on the mainchain,
-- it's actually useful (and verified) on the sidechain, so it needs to be
-- recorded in the mainchain.

PlutusTx.makeIsDataIndexed ''FUELRedeemer [('MainToSide, 0), ('SideToMain, 1)]

{- | 'FUELMint' is the data type to parameterize the minting policy. See
 'mkMintingPolicy' for details of why we need the datum in 'FUELMint'
-}
data FUELMint = FUELMint
  { -- 'fmMptRootTokenValidator' is the hash of the validator script
    -- which /should/ have a token which has the merkle root in the token
    -- name. See 'TrustlessSidechain.MerkleRootTokenValidator' for
    -- details.
    -- > fmMptRootTokenValidator :: ValidatorHash
    -- N.B. We don't need this! We're really only interested in the token,
    -- and indeed; anyone can pay a token to this script so there really
    -- isn't a reason to use this validator script as the "identifier" for
    -- MerkleRootTokens.

    -- | 'fmMptRootTokenCurrencySymbol' is the 'CurrencySymbol' of a token
    -- which contains a merkle root in the 'TokenName'. See
    -- 'TrustlessSidechain.MerkleRootTokenMintingPolicy' for details.
    fmMptRootTokenCurrencySymbol :: CurrencySymbol
  , -- | 'fmSidechainParams' is the sidechain parameters
    fmSidechainParams :: SidechainParams
  , -- | 'fmDsKeyCurrencySymbol' is th currency symbol for the tokens which
    -- hold the key for the distributed set. In particular, this allows the
    -- FUEL minting policy to verify if a string has /just been inserted/ into
    -- the distributed set.
    fmDsKeyCurrencySymbol :: CurrencySymbol
  }

PlutusTx.makeIsDataIndexed ''FUELMint [('FUELMint, 0)]

-- * Update Committee Hash data

{- | Datum for the committee. This is used to verify
 signatures for sidechain to mainchain transfers.

 The actual representation of the committee's public key depends on the ATMS
 implementation.
-}
data UpdateCommitteeDatum aggregatePubKeys = UpdateCommitteeDatum
  { aggregateCommitteePubKeys :: aggregatePubKeys
  , sidechainEpoch :: Integer
  }

PlutusTx.makeIsDataIndexed ''UpdateCommitteeDatum [('UpdateCommitteeDatum, 0)]

newtype ATMSPlainAggregatePubKey = ATMSPlainAggregatePubKey BuiltinByteString
  deriving newtype (FromData, ToData, UnsafeFromData, Eq, Ord)

-- | 'UpdateCommitteeHash' is used as the parameter for the validator.
data UpdateCommitteeHash = UpdateCommitteeHash
  { sidechainParams :: SidechainParams
  , -- | 'committeeOracleCurrencySymbol' is the 'CurrencySymbol' of the NFT that is used to
    -- identify the transaction the current committee.
    committeeOracleCurrencySymbol :: CurrencySymbol
  , -- | 'committeeCertificateVerificationCurrencySymbol' is the currency
    -- symbol for the committee certificate verification policy i.e., the
    -- currency symbol whose minted token name indicates that the current
    -- committee has signed the token name.
    committeeCertificateVerificationCurrencySymbol :: CurrencySymbol
  , -- | 'mptRootTokenCurrencySymbol' is the currency symbol of the corresponding merkle
    -- root token. This is needed for verifying that the previous merkle root is verified.
    mptRootTokenCurrencySymbol :: CurrencySymbol
  }

PlutusTx.makeIsDataIndexed ''UpdateCommitteeHash [('UpdateCommitteeHash, 0)]

data UpdateCommitteeHashMessage aggregatePubKeys = UpdateCommitteeHashMessage
  { sidechainParams :: SidechainParams
  , -- | 'newCommitteePubKeys' is the new aggregate committee public keys
    newAggregateCommitteePubKeys :: aggregatePubKeys
  , previousMerkleRoot :: Maybe BuiltinByteString
  , sidechainEpoch :: Integer
  , validatorAddress :: Address
  }

PlutusTx.makeIsDataIndexed ''UpdateCommitteeHashMessage [('UpdateCommitteeHashMessage, 0)]

newtype UpdateCommitteeHashRedeemer = UpdateCommitteeHashRedeemer
  { previousMerkleRoot :: Maybe BuiltinByteString
  }
  deriving newtype
    ( ToData
    , FromData
    , UnsafeFromData
    )

-- | Datum for a checkpoint
data CheckpointDatum = CheckpointDatum
  { checkpointBlockHash :: BuiltinByteString
  , checkpointBlockNumber :: Integer
  }

PlutusTx.makeIsDataIndexed ''CheckpointDatum [('CheckpointDatum, 0)]

{- | 'CommitteeCertificateMint' is the type to parameterize committee
 certificate verification minting policies.
 See SIP05 in @docs/SIPs/@ for details.
-}
data CommitteeCertificateMint = CommitteeCertificateMint
  { committeeOraclePolicy :: CurrencySymbol
  , thresholdNumerator :: Integer
  , thresholdDenominator :: Integer
  }

PlutusTx.makeIsDataIndexed ''CommitteeCertificateMint [('CommitteeCertificateMint, 0)]

{- | 'ATMSPlainMultisignature' corresponds to SIP05 in @docs/SIPs/@.
 This is used as redeemer for the
 "TrustlessSidechain.CommitteePlainATMSPolicy".
-}
data ATMSPlainMultisignature = ATMSPlainMultisignature
  { plainPublicKeys :: [BuiltinByteString]
  , plainSignatures :: [BuiltinByteString]
  }

PlutusTx.makeIsDataIndexed ''ATMSPlainMultisignature [('ATMSPlainMultisignature, 0)]

{- | The Redeemer that is passed to the on-chain validator to update the
 checkpoint
-}
data CheckpointRedeemer = CheckpointRedeemer
  { newCheckpointBlockHash :: BuiltinByteString
  , newCheckpointBlockNumber :: Integer
  }

PlutusTx.makeIsDataIndexed ''CheckpointRedeemer [('CheckpointRedeemer, 0)]

-- | 'Checkpoint' is used as the parameter for the validator.
data CheckpointParameter = CheckpointParameter
  { checkpointSidechainParams :: SidechainParams
  , -- | 'checkpointAssetClass' is the 'AssetClass' of the NFT that is used to
    -- identify the transaction.
    checkpointAssetClass :: AssetClass
  , -- | 'checkpointCommitteeOracleCurrencySymbol' is the
    -- currency symbol of the currency symbol which uniquely identifies the
    -- current committee.
    checkpointCommitteeOracleCurrencySymbol :: CurrencySymbol
  , -- | 'checkpointCommitteeCertificateVerificationCurrencySymbol' is the
    -- currency symbol of the committee certificate verification minting policy
    checkpointCommitteeCertificateVerificationCurrencySymbol :: CurrencySymbol
  }

PlutusTx.makeIsDataIndexed ''CheckpointParameter [('CheckpointParameter, 0)]

data CheckpointMessage = CheckpointMessage
  { checkpointMsgSidechainParams :: SidechainParams
  , checkpointMsgBlockHash :: BuiltinByteString
  , checkpointMsgBlockNumber :: Integer
  , checkpointMsgSidechainEpoch :: Integer
  }

PlutusTx.makeIsDataIndexed ''CheckpointMessage [('CheckpointMessage, 0)]
