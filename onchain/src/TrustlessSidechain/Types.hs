{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module TrustlessSidechain.Types where

import Ledger.Crypto (PubKey, PubKeyHash, Signature)
import Ledger.Value (AssetClass, CurrencySymbol)
import Plutus.V2.Ledger.Api (Address, LedgerBytes (LedgerBytes), ValidatorHash)
import Plutus.V2.Ledger.Tx (TxOutRef)
import PlutusTx (makeIsDataIndexed)
import TrustlessSidechain.HaskellPrelude qualified as TSPrelude
import TrustlessSidechain.MerkleTree (MerkleProof)
import TrustlessSidechain.PlutusPrelude

-- * Sidechain Parametrization and general data

newtype GenesisHash = GenesisHash {getGenesisHash :: LedgerBytes}
  deriving stock (TSPrelude.Eq, TSPrelude.Ord)
  deriving newtype
    ( Eq
    , Ord
    , ToData
    , FromData
    , UnsafeFromData
    )
  deriving (IsString, TSPrelude.Show) via LedgerBytes

{- | Parameters uniquely identifying a sidechain

 = Note

 The 'Data' serializations for this type /cannot/ change.
-}
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

PlutusTx.makeIsDataIndexed ''SidechainParams [('SidechainParams, 0)]

-- | @since Unreleased
instance HasField "chainId" SidechainParams Integer where
  {-# INLINE get #-}
  get = chainId
  {-# INLINE modify #-}
  modify f sp = sp {chainId = f (chainId sp)}

-- | @since Unreleased
instance HasField "genesisHash" SidechainParams GenesisHash where
  {-# INLINE get #-}
  get = genesisHash
  {-# INLINE modify #-}
  modify f sp = sp {genesisHash = f (genesisHash sp)}

-- | @since Unreleased
instance HasField "genesisUtxo" SidechainParams TxOutRef where
  {-# INLINE get #-}
  get = genesisUtxo
  {-# INLINE modify #-}
  modify f sp = sp {genesisUtxo = f (genesisUtxo sp)}

-- | @since Unreleased
instance HasField "thresholdNumerator" SidechainParams Integer where
  {-# INLINE get #-}
  get = thresholdNumerator
  {-# INLINE modify #-}
  modify f sp = sp {thresholdNumerator = f (thresholdNumerator sp)}

-- | @since Unreleased
instance HasField "thresholdDenominator" SidechainParams Integer where
  {-# INLINE get #-}
  get = thresholdDenominator
  {-# INLINE modify #-}
  modify f sp = sp {thresholdDenominator = f (thresholdDenominator sp)}

{- | Compressed DER SECP256k1 public key.
 = Important note

 The 'Data' serializations for this type /cannot/ change.
-}
newtype EcdsaSecp256k1PubKey = EcdsaSecp256k1PubKey
  { -- | @since Unreleased
    getEcdsaSecp256k1PubKey :: LedgerBytes
  }
  deriving stock (TSPrelude.Eq, TSPrelude.Ord)
  deriving newtype
    ( Eq
    , Ord
    , ToData
    , FromData
    , UnsafeFromData
    )
  deriving
    ( -- | @since Unreleased
      IsString
    , TSPrelude.Show
    )
    via LedgerBytes

-- * Committee Candidate Validator data

{- | 'CandidatePermissionMint' is used to parameterize the minting policy in
 'TrustlessSidechain.CommitteeCandidateMintingPolicy'.
-}
data CandidatePermissionMint = CandidatePermissionMint
  { -- | @since Unreleased
    sidechainParams :: SidechainParams
  , -- | @since Unreleased
    utxo :: TxOutRef
  }

-- | @since Unreleased
instance ToData CandidatePermissionMint where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (CandidatePermissionMint {..}) =
    productToData2 sidechainParams utxo

-- | @since Unreleased
instance FromData CandidatePermissionMint where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData2 CandidatePermissionMint

-- | @since Unreleased
instance UnsafeFromData CandidatePermissionMint where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData2 CandidatePermissionMint

-- | @since Unreleased
instance HasField "sidechainParams" CandidatePermissionMint SidechainParams where
  {-# INLINE get #-}
  get (CandidatePermissionMint sp _) = sp
  {-# INLINE modify #-}
  modify f (CandidatePermissionMint sp u) = CandidatePermissionMint (f sp) u

-- | @since Unreleased
instance HasField "utxo" CandidatePermissionMint TxOutRef where
  {-# INLINE get #-}
  get (CandidatePermissionMint _ u) = u
  {-# INLINE modify #-}
  modify f (CandidatePermissionMint sp u) = CandidatePermissionMint sp (f u)

{-
 The 'Data' serializations for this type /cannot/ change.
-}
data BlockProducerRegistration = BlockProducerRegistration
  { -- | SPO cold verification key hash
    -- | @since Unreleased
    spoPubKey :: PubKey -- own cold verification key hash
  , -- | public key in the sidechain's desired format
    sidechainPubKey :: LedgerBytes
  , -- | Signature of the SPO
    -- | @since Unreleased
    spoSignature :: Signature
  , -- | Signature of the sidechain
    -- | @since Unreleased
    sidechainSignature :: Signature
  , -- | A UTxO that must be spent by the transaction
    -- | @since Unreleased
    inputUtxo :: TxOutRef
  , -- | Owner public key hash
    -- | @since Unreleased
    ownPkh :: PubKeyHash
  }

PlutusTx.makeIsDataIndexed ''BlockProducerRegistration [('BlockProducerRegistration, 0)]

-- | @since Unreleased
instance HasField "spoPubKey" BlockProducerRegistration PubKey where
  {-# INLINE get #-}
  get (BlockProducerRegistration x _ _ _ _ _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration (f sPK) scPK sS scS u pkh

-- | @since Unreleased
instance HasField "ecdsaSecp256k1PubKey" BlockProducerRegistration LedgerBytes where
  {-# INLINE get #-}
  get (BlockProducerRegistration _ x _ _ _ _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration sPK (f scPK) sS scS u pkh

-- | @since Unreleased
instance HasField "spoSignature" BlockProducerRegistration Signature where
  {-# INLINE get #-}
  get (BlockProducerRegistration _ _ x _ _ _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration sPK scPK (f sS) scS u pkh

-- | @since Unreleased
instance HasField "sidechainSignature" BlockProducerRegistration Signature where
  {-# INLINE get #-}
  get (BlockProducerRegistration _ _ _ x _ _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration sPK scPK sS (f scS) u pkh

-- | @since Unreleased
instance HasField "inputUtxo" BlockProducerRegistration TxOutRef where
  {-# INLINE get #-}
  get (BlockProducerRegistration _ _ _ _ x _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration sPK scPK sS scS (f u) pkh

-- | @since Unreleased
instance HasField "ownPkh" BlockProducerRegistration PubKeyHash where
  {-# INLINE get #-}
  get (BlockProducerRegistration _ _ _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistration sPK scPK sS scS u pkh) =
    BlockProducerRegistration sPK scPK sS scS u (f pkh)

{- | = Important note

 The 'Data' serializations for this type /cannot/ change.
-}
data BlockProducerRegistrationMsg = BlockProducerRegistrationMsg
  { sidechainParams :: SidechainParams
  , sidechainPubKey :: LedgerBytes
  , -- | A UTxO that must be spent by the transaction
    -- | @since Unreleased
    inputUtxo :: TxOutRef
  }

PlutusTx.makeIsDataIndexed ''BlockProducerRegistrationMsg [('BlockProducerRegistrationMsg, 0)]

-- | @since Unreleased
instance HasField "sidechainParams" BlockProducerRegistrationMsg SidechainParams where
  {-# INLINE get #-}
  get (BlockProducerRegistrationMsg x _ _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistrationMsg sp spk u) =
    BlockProducerRegistrationMsg (f sp) spk u

-- | @since Unreleased
instance HasField "sidechainPubKey" BlockProducerRegistrationMsg LedgerBytes where
  {-# INLINE get #-}
  get (BlockProducerRegistrationMsg _ x _) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistrationMsg sp spk u) =
    BlockProducerRegistrationMsg sp (f spk) u

-- | @since Unreleased
instance HasField "inputUtxo" BlockProducerRegistrationMsg TxOutRef where
  {-# INLINE get #-}
  get (BlockProducerRegistrationMsg _ _ x) = x
  {-# INLINE modify #-}
  modify f (BlockProducerRegistrationMsg sp spk u) =
    BlockProducerRegistrationMsg sp spk (f u)

-- * Merkle Root Token data

{- | 'MerkleTreeEntry' (abbr. mte and pl. mtes) is the data which are the elements in the merkle tree
 for the MerkleRootToken.

 = Important note

 The 'Data' serializations for this type /cannot/ change.
-}
data MerkleTreeEntry = MerkleTreeEntry
  { -- | 32 bit unsigned integer, used to provide uniqueness among transactions within the tree
    -- | @since Unreleased
    index :: Integer
  , -- | 256 bit unsigned integer that represents amount of tokens being sent out of the bridge
    -- | @since Unreleased
    amount :: Integer
  , -- | arbitrary length bytestring that represents decoded bech32 cardano
    -- | address. See [here](https://cips.cardano.org/cips/cip19/) for more details
    -- | of bech32
    -- | @since Unreleased
    recipient :: LedgerBytes
  , -- | the previous merkle root to ensure that the hashed entry is unique
    -- | @since Unreleased
    previousMerkleRoot :: Maybe LedgerBytes
  }

PlutusTx.makeIsDataIndexed ''MerkleTreeEntry [('MerkleTreeEntry, 0)]

-- | @since Unreleased
instance HasField "index" MerkleTreeEntry Integer where
  {-# INLINE get #-}
  get (MerkleTreeEntry x _ _ _) = x
  {-# INLINE modify #-}
  modify f (MerkleTreeEntry i a r pmr) =
    MerkleTreeEntry (f i) a r pmr

-- | @since Unreleased
instance HasField "amount" MerkleTreeEntry Integer where
  {-# INLINE get #-}
  get (MerkleTreeEntry _ x _ _) = x
  {-# INLINE modify #-}
  modify f (MerkleTreeEntry i a r pmr) =
    MerkleTreeEntry i (f a) r pmr

-- | @since Unreleased
instance HasField "recipient" MerkleTreeEntry LedgerBytes where
  {-# INLINE get #-}
  get (MerkleTreeEntry _ _ x _) = x
  {-# INLINE modify #-}
  modify f (MerkleTreeEntry i a r pmr) =
    MerkleTreeEntry i a (f r) pmr

-- | @since Unreleased
instance HasField "previousMerkleRoot" MerkleTreeEntry (Maybe LedgerBytes) where
  {-# INLINE get #-}
  get (MerkleTreeEntry _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (MerkleTreeEntry i a r pmr) =
    MerkleTreeEntry i a r (f pmr)

{- | 'MerkleRootInsertionMessage' is a data type for which committee members
 create signatures for
 >  blake2b(cbor(MerkleRootInsertionMessage))

 = Important note

 The 'Data' serializations for this type /cannot/ change.
-}
data MerkleRootInsertionMessage = MerkleRootInsertionMessage
  { -- | @since Unreleased
    sidechainParams :: SidechainParams
  , -- | @since Unreleased
    merkleRoot :: LedgerBytes
  , -- | @since Unreleased
    previousMerkleRoot :: Maybe LedgerBytes
  }

PlutusTx.makeIsDataIndexed ''MerkleRootInsertionMessage [('MerkleRootInsertionMessage, 0)]

-- | @since Unreleased
instance HasField "sidechainParams" MerkleRootInsertionMessage SidechainParams where
  {-# INLINE get #-}
  get (MerkleRootInsertionMessage x _ _) = x
  {-# INLINE modify #-}
  modify f (MerkleRootInsertionMessage sp mr pmr) =
    MerkleRootInsertionMessage (f sp) mr pmr

-- | @since Unreleased
instance HasField "merkleRoot" MerkleRootInsertionMessage LedgerBytes where
  {-# INLINE get #-}
  get (MerkleRootInsertionMessage _ x _) = x
  {-# INLINE modify #-}
  modify f (MerkleRootInsertionMessage sp mr pmr) =
    MerkleRootInsertionMessage sp (f mr) pmr

-- | @since Unreleased
instance HasField "previousMerkleRoot" MerkleRootInsertionMessage (Maybe LedgerBytes) where
  {-# INLINE get #-}
  get (MerkleRootInsertionMessage _ _ x) = x
  {-# INLINE modify #-}
  modify f (MerkleRootInsertionMessage sp mr pmr) =
    MerkleRootInsertionMessage sp mr (f pmr)

{- | 'SignedMerkleRootRedeemer' is the redeemer for the signed merkle root
 minting policy
-}
newtype SignedMerkleRootRedeemer = SignedMerkleRootRedeemer
  { previousMerkleRoot :: Maybe LedgerBytes
  }
  deriving newtype
    ( ToData
    , FromData
    , UnsafeFromData
    )

instance HasField "previousMerkleRoot" SignedMerkleRootRedeemer (Maybe LedgerBytes) where
  {-# INLINE get #-}
  get (SignedMerkleRootRedeemer x) = x
  {-# INLINE modify #-}
  modify f (SignedMerkleRootRedeemer pmr) =
    SignedMerkleRootRedeemer (f pmr)

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

-- | @since Unreleased
instance ToData SignedMerkleRootMint where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (SignedMerkleRootMint {..}) =
    productToData3
      sidechainParams
      committeeCertificateVerificationCurrencySymbol
      validatorHash

-- | @since Unreleased
instance FromData SignedMerkleRootMint where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData3 SignedMerkleRootMint

-- | @since Unreleased
instance UnsafeFromData SignedMerkleRootMint where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData3 SignedMerkleRootMint

-- | @since Unreleased
instance HasField "sidechainParams" SignedMerkleRootMint SidechainParams where
  {-# INLINE get #-}
  get (SignedMerkleRootMint x _ _) = x
  {-# INLINE modify #-}
  modify f (SignedMerkleRootMint sp uchcs vh) =
    SignedMerkleRootMint (f sp) uchcs vh

-- | @since Unreleased
instance HasField "updateCommitteeHashCurrencySymbol" SignedMerkleRootMint CurrencySymbol where
  {-# INLINE get #-}
  get (SignedMerkleRootMint _ x _) = x
  {-# INLINE modify #-}
  modify f (SignedMerkleRootMint sp uchcs vh) =
    SignedMerkleRootMint sp (f uchcs) vh

-- | @since Unreleased
instance HasField "validatorHash" SignedMerkleRootMint ValidatorHash where
  {-# INLINE get #-}
  get (SignedMerkleRootMint _ _ x) = x
  {-# INLINE modify #-}
  modify f (SignedMerkleRootMint sp uchcs vh) =
    SignedMerkleRootMint sp uchcs (f vh)

{- | 'CombinedMerkleProof' is a product type to include both the
 'MerkleTreeEntry' and the 'MerkleProof'.

 This exists as for testing in #249.

 = Important note

 The 'Data' serializations of this type /cannot/ change.
-}
data CombinedMerkleProof = CombinedMerkleProof
  { -- | @since Unreleased
    transaction :: MerkleTreeEntry
  , -- | @since Unreleased
    merkleProof :: MerkleProof
  }

PlutusTx.makeIsDataIndexed ''CombinedMerkleProof [('CombinedMerkleProof, 0)]

-- | @since Unreleased
instance HasField "transaction" CombinedMerkleProof MerkleTreeEntry where
  {-# INLINE get #-}
  get (CombinedMerkleProof x _) = x
  {-# INLINE modify #-}
  modify f (CombinedMerkleProof t mp) =
    CombinedMerkleProof (f t) mp

-- | @since Unreleased
instance HasField "merkleProof" CombinedMerkleProof MerkleProof where
  {-# INLINE get #-}
  get (CombinedMerkleProof _ x) = x
  {-# INLINE modify #-}
  modify f (CombinedMerkleProof t mp) =
    CombinedMerkleProof t (f mp)

-- * FUEL Minting Policy data

-- | The Redeemer that's to be passed to onchain policy, indicating its mode of usage.
data FUELRedeemer
  = MainToSide LedgerBytes -- Recipient's sidechain address
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
    -- | which contains a merkle root in the 'TokenName'. See
    -- | 'TrustlessSidechain.MerkleRootTokenMintingPolicy' for details.
    -- |
    -- | @since Unreleased
    mptRootTokenCurrencySymbol :: CurrencySymbol
  , -- | 'fmSidechainParams' is the sidechain parameters
    -- |
    -- | @since Unreleased
    sidechainParams :: SidechainParams
  , -- | 'fmDsKeyCurrencySymbol' is th currency symbol for the tokens which
    -- | hold the key for the distributed set. In particular, this allows the
    -- | FUEL minting policy to verify if a string has /just been inserted/ into
    -- | the distributed set.
    -- |
    -- | @since Unreleased
    dsKeyCurrencySymbol :: CurrencySymbol
  }

-- | @since Unreleased
instance ToData FUELMint where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (FUELMint {..}) =
    productToData3
      mptRootTokenCurrencySymbol
      sidechainParams
      dsKeyCurrencySymbol

-- | @since Unreleased
instance FromData FUELMint where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData3 FUELMint

-- | @since Unreleased
instance UnsafeFromData FUELMint where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData3 FUELMint

-- | @since Unreleased
instance HasField "mptRootTokenCurrencySymbol" FUELMint CurrencySymbol where
  {-# INLINE get #-}
  get (FUELMint x _ _) = x
  {-# INLINE modify #-}
  modify f (FUELMint rtcs sp kcs) =
    FUELMint (f rtcs) sp kcs

-- | @since Unreleased
instance HasField "sidechainParams" FUELMint SidechainParams where
  {-# INLINE get #-}
  get (FUELMint _ x _) = x
  {-# INLINE modify #-}
  modify f (FUELMint rtcs sp kcs) =
    FUELMint rtcs (f sp) kcs

-- | @since Unreleased
instance HasField "dsKeyCurrencySymbol" FUELMint CurrencySymbol where
  {-# INLINE get #-}
  get (FUELMint _ _ x) = x
  {-# INLINE modify #-}
  modify f (FUELMint rtcs sp kcs) =
    FUELMint rtcs sp (f kcs)

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

-- | @since Unreleased
instance ToData aggregatePubKeys => ToData (UpdateCommitteeDatum aggregatePubKeys) where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (UpdateCommitteeDatum {..}) =
    productToData2 aggregateCommitteePubKeys sidechainEpoch

-- | @since Unreleased
instance FromData aggregatePubKeys => FromData (UpdateCommitteeDatum aggregatePubKeys) where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData2 UpdateCommitteeDatum

-- | @since Unreleased
instance UnsafeFromData aggregatePubKeys => UnsafeFromData (UpdateCommitteeDatum aggregatePubKeys) where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData2 UpdateCommitteeDatum

-- | @since Unreleased
instance HasField "aggregateCommitteePubKeys" (UpdateCommitteeDatum aggregatePubKeys) aggregatePubKeys where
  {-# INLINE get #-}
  get (UpdateCommitteeDatum x _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeDatum ch se) =
    UpdateCommitteeDatum (f ch) se

-- | @since Unreleased
instance HasField "sidechainEpoch" (UpdateCommitteeDatum aggregatePubKeys) Integer where
  {-# INLINE get #-}
  get (UpdateCommitteeDatum _ x) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeDatum ch se) =
    UpdateCommitteeDatum ch (f se)

newtype ATMSPlainAggregatePubKey = ATMSPlainAggregatePubKey LedgerBytes
  deriving newtype (FromData, ToData, UnsafeFromData, Eq, Ord, IsString)

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

-- | @since Unreleased
instance ToData UpdateCommitteeHash where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (UpdateCommitteeHash {..}) =
    productToData4 sidechainParams committeeOracleCurrencySymbol committeeCertificateVerificationCurrencySymbol mptRootTokenCurrencySymbol

-- | @since Unreleased
instance HasField "sidechainParams" UpdateCommitteeHash SidechainParams where
  {-# INLINE get #-}
  get (UpdateCommitteeHash x _ _ _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHash sp cocs ccvcs rtcs) =
    UpdateCommitteeHash (f sp) cocs ccvcs rtcs

-- | @since Unreleased
instance HasField "committeeOracleCurrencySymbol" UpdateCommitteeHash CurrencySymbol where
  {-# INLINE get #-}
  get (UpdateCommitteeHash _ x _ _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHash sp cocs ccvcs rtcs) =
    UpdateCommitteeHash sp (f cocs) ccvcs rtcs

-- | @since Unreleased
instance HasField "committeeCertificateVerificationCurrencySymbol" UpdateCommitteeHash CurrencySymbol where
  {-# INLINE get #-}
  get (UpdateCommitteeHash _ _ x _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHash sp cocs ccvcs rtcs) =
    UpdateCommitteeHash sp cocs (f ccvcs) rtcs

-- | @since Unreleased
instance HasField "mptRootTokenCurrencySymbol" UpdateCommitteeHash CurrencySymbol where
  {-# INLINE get #-}
  get (UpdateCommitteeHash _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHash sp cocs ccvcs rtcs) =
    UpdateCommitteeHash sp cocs ccvcs (f rtcs)

instance FromData UpdateCommitteeHash where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData4 UpdateCommitteeHash

-- | @since Unreleased
instance UnsafeFromData UpdateCommitteeHash where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData4 UpdateCommitteeHash

{- | = Important note

 The 'Data' serializations for this type /cannot/ be changed.
-}
data UpdateCommitteeHashMessage aggregatePubKeys = UpdateCommitteeHashMessage
  { sidechainParams :: SidechainParams
  , -- | 'newCommitteePubKeys' is the new aggregate committee public keys
    newAggregateCommitteePubKeys :: aggregatePubKeys
  , previousMerkleRoot :: Maybe LedgerBytes
  , sidechainEpoch :: Integer
  , validatorAddress :: Address
  }

-- | @since Unreleased
instance ToData aggregatePubKeys => ToData (UpdateCommitteeHashMessage aggregatePubKeys) where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (UpdateCommitteeHashMessage {..}) =
    productToData5 sidechainParams newAggregateCommitteePubKeys previousMerkleRoot sidechainEpoch validatorAddress

-- | @since Unreleased
instance FromData aggregatePubKeys => FromData (UpdateCommitteeHashMessage aggregatePubKeys) where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData5 UpdateCommitteeHashMessage

-- | @since Unreleased
instance UnsafeFromData aggregatePubKeys => UnsafeFromData (UpdateCommitteeHashMessage aggregatePubKeys) where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData5 UpdateCommitteeHashMessage

-- | @since Unreleased
instance HasField "sidechainParams" (UpdateCommitteeHashMessage aggregatePubKeys) SidechainParams where
  {-# INLINE get #-}
  get (UpdateCommitteeHashMessage x _ _ _ _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHashMessage sp nacpks pmr se va) =
    UpdateCommitteeHashMessage (f sp) nacpks pmr se va

-- | @since Unreleased
instance HasField "newAggregateCommitteePubKeys" (UpdateCommitteeHashMessage aggregatePubKeys) aggregatePubKeys where
  {-# INLINE get #-}
  get (UpdateCommitteeHashMessage _ x _ _ _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHashMessage sp nacpks pmr se va) =
    UpdateCommitteeHashMessage sp (f nacpks) pmr se va

-- | @since Unreleased
instance HasField "previousMerkleRoot" (UpdateCommitteeHashMessage aggregatePubKeys) (Maybe LedgerBytes) where
  {-# INLINE get #-}
  get (UpdateCommitteeHashMessage _ _ x _ _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHashMessage sp nacpks pmr se va) =
    UpdateCommitteeHashMessage sp nacpks (f pmr) se va

-- | @since Unreleased
instance HasField "sidechainEpoch" (UpdateCommitteeHashMessage aggregatePubKeys) Integer where
  {-# INLINE get #-}
  get (UpdateCommitteeHashMessage _ _ _ x _) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHashMessage sp nacpks pmr se va) =
    UpdateCommitteeHashMessage sp nacpks pmr (f se) va

-- | @since Unreleased
instance HasField "validatorAddress" (UpdateCommitteeHashMessage aggregatePubKeys) Address where
  {-# INLINE get #-}
  get (UpdateCommitteeHashMessage _ _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (UpdateCommitteeHashMessage sp nacpks pmr se va) =
    UpdateCommitteeHashMessage sp nacpks pmr se (f va)

newtype UpdateCommitteeHashRedeemer = UpdateCommitteeHashRedeemer
  { previousMerkleRoot :: Maybe LedgerBytes
  }
  deriving newtype
    ( ToData
    , FromData
    , UnsafeFromData
    )

-- | Datum for a checkpoint
data CheckpointDatum = CheckpointDatum
  { -- | @since Unreleased
    blockHash :: LedgerBytes
  , -- | @since Unreleased
    blockNumber :: Integer
  }

-- | @since Unreleased
instance ToData CheckpointDatum where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (CheckpointDatum {..}) =
    productToData2 blockHash blockNumber

-- | @since Unreleased
instance FromData CheckpointDatum where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData2 CheckpointDatum

-- | @since Unreleased
instance UnsafeFromData CheckpointDatum where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData2 CheckpointDatum

-- | @since Unreleased
instance HasField "blockHash" CheckpointDatum LedgerBytes where
  {-# INLINE get #-}
  get (CheckpointDatum x _) = x
  {-# INLINE modify #-}
  modify f (CheckpointDatum bh bn) =
    CheckpointDatum (f bh) bn

-- | @since Unreleased
instance HasField "blockNumber" CheckpointDatum Integer where
  {-# INLINE get #-}
  get (CheckpointDatum _ x) = x
  {-# INLINE modify #-}
  modify f (CheckpointDatum bh bn) =
    CheckpointDatum bh (f bn)

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
  { plainPublicKeys :: [LedgerBytes]
  , plainSignatures :: [LedgerBytes]
  }

PlutusTx.makeIsDataIndexed ''ATMSPlainMultisignature [('ATMSPlainMultisignature, 0)]

{- | The Redeemer that is passed to the on-chain validator to update the
 checkpoint
-}
data CheckpointRedeemer = CheckpointRedeemer
  { newCheckpointBlockHash :: LedgerBytes
  , newCheckpointBlockNumber :: Integer
  }

-- | @since Unreleased
instance ToData CheckpointRedeemer where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (CheckpointRedeemer {..}) =
    productToData2
      newCheckpointBlockHash
      newCheckpointBlockNumber

-- | @since Unreleased
instance FromData CheckpointRedeemer where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData2 CheckpointRedeemer

-- | @since Unreleased
instance UnsafeFromData CheckpointRedeemer where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData2 CheckpointRedeemer

-- | @since Unreleased
instance HasField "newCheckpointBlockHash" CheckpointRedeemer LedgerBytes where
  {-# INLINE get #-}
  get (CheckpointRedeemer x _) = x
  {-# INLINE modify #-}
  modify f (CheckpointRedeemer ncbh ncbn) =
    CheckpointRedeemer (f ncbh) ncbn

-- | @since Unreleased
instance HasField "newCheckpointBlockNumber" CheckpointRedeemer Integer where
  {-# INLINE get #-}
  get (CheckpointRedeemer _ x) = x
  {-# INLINE modify #-}
  modify f (CheckpointRedeemer ncbh ncbn) =
    CheckpointRedeemer ncbh (f ncbn)

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

-- | @since Unreleased
instance ToData CheckpointParameter where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData (CheckpointParameter {..}) =
    productToData4
      checkpointSidechainParams
      checkpointAssetClass
      checkpointCommitteeOracleCurrencySymbol
      checkpointCommitteeCertificateVerificationCurrencySymbol

-- | @since Unreleased
instance HasField "checkpointSidechainParams" CheckpointParameter SidechainParams where
  {-# INLINE get #-}
  get (CheckpointParameter x _ _ _) = x
  {-# INLINE modify #-}
  modify f (CheckpointParameter csp cac ccocs chac) =
    CheckpointParameter (f csp) cac ccocs chac

-- | @since Unreleased
instance HasField "checkpointAssetClass" CheckpointParameter AssetClass where
  {-# INLINE get #-}
  get (CheckpointParameter _ x _ _) = x
  {-# INLINE modify #-}
  modify f (CheckpointParameter csp cac ccocs chac) =
    CheckpointParameter csp (f cac) ccocs chac

-- | @since Unreleased
instance HasField "checkpointCommitteeOracleCurrencySymbol" CheckpointParameter CurrencySymbol where
  {-# INLINE get #-}
  get (CheckpointParameter _ _ x _) = x
  {-# INLINE modify #-}
  modify f (CheckpointParameter csp cac ccocs chac) =
    CheckpointParameter csp cac (f ccocs) chac

-- | @since Unreleased
instance HasField "checkpointCommitteeCertificationVerificationCurrencySymbol" CheckpointParameter CurrencySymbol where
  {-# INLINE get #-}
  get (CheckpointParameter _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (CheckpointParameter csp cac ccocs chac) =
    CheckpointParameter csp cac ccocs (f chac)

-- | @since Unreleased
instance FromData CheckpointParameter where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData = productFromData4 CheckpointParameter

-- | @since Unreleased
instance UnsafeFromData CheckpointParameter where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData = productUnsafeFromData4 CheckpointParameter

{- | = Important note

 The 'Data' serializations of this type /cannot/ be changed.
-}
data CheckpointMessage = CheckpointMessage
  { -- | @since Unreleased
    sidechainParams :: SidechainParams
  , -- | @since Unreleased
    blockHash :: LedgerBytes
  , -- | @since Unreleased
    blockNumber :: Integer
  , -- | @since Unreleased
    sidechainEpoch :: Integer
  }

PlutusTx.makeIsDataIndexed ''CheckpointMessage [('CheckpointMessage, 0)]

-- | @since Unreleased
instance HasField "sidechainParams" CheckpointMessage SidechainParams where
  {-# INLINE get #-}
  get (CheckpointMessage x _ _ _) = x
  {-# INLINE modify #-}
  modify f (CheckpointMessage sp bh bn se) =
    CheckpointMessage (f sp) bh bn se

-- | @since Unreleased
instance HasField "blockHash" CheckpointMessage LedgerBytes where
  {-# INLINE get #-}
  get (CheckpointMessage _ x _ _) = x
  {-# INLINE modify #-}
  modify f (CheckpointMessage sp bh bn se) =
    CheckpointMessage sp (f bh) bn se

-- | @since Unreleased
instance HasField "blockNumber" CheckpointMessage Integer where
  {-# INLINE get #-}
  get (CheckpointMessage _ _ x _) = x
  {-# INLINE modify #-}
  modify f (CheckpointMessage sp bh bn se) =
    CheckpointMessage sp bh (f bn) se

-- | @since Unreleased
instance HasField "sidechainEpoch" CheckpointMessage Integer where
  {-# INLINE get #-}
  get (CheckpointMessage _ _ _ x) = x
  {-# INLINE modify #-}
  modify f (CheckpointMessage sp bh bn se) =
    CheckpointMessage sp bh bn (f se)
