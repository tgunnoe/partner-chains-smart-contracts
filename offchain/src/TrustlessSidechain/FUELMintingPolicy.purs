module TrustlessSidechain.FUELMintingPolicy
  ( CombinedMerkleProof(..)
  , FUELMint(..)
  , FuelParams(..)
  , MerkleTreeEntry(..)
  , fuelMintingPolicy
  , getFuelMintingPolicy
  , runFuelMP
  , Bech32Bytes
  , getBech32BytesByteArray
  , byteArrayToBech32BytesUnsafe
  , addressFromCborBytes
  , bech32BytesFromAddress
  , combinedMerkleProofToFuelParams
  ) where

import Contract.Prelude

import Contract.Address
  ( Address
  , PaymentPubKeyHash(..)
  , StakePubKeyHash(..)
  , getNetworkId
  , ownPaymentPubKeyHash
  , toPubKeyHash
  , toStakingCredential
  )
import Contract.CborBytes (CborBytes, cborBytesFromByteArray)
import Contract.Credential (Credential(..), StakingCredential(..))
import Contract.Hashing (blake2b256Hash)
import Contract.Log (logInfo')
import Contract.Monad (Contract, liftContractE, liftContractM, liftedE, liftedM)
import Contract.PlutusData
  ( class FromData
  , class ToData
  , Datum(..)
  , PlutusData(Constr)
  , fromData
  , toData
  , unitRedeemer
  )
import Contract.Prim.ByteArray (ByteArray, byteArrayFromAscii)
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (MintingPolicy(PlutusMintingPolicy))
import Contract.Scripts as Scripts
import Contract.TextEnvelope
  ( decodeTextEnvelope
  , plutusScriptV2FromEnvelope
  )
import Contract.Transaction
  ( TransactionHash
  , TransactionInput
  , TransactionOutputWithRefScript
  , awaitTxConfirmed
  , balanceTx
  , signTransaction
  , submit
  )
import Contract.TxConstraints
  ( DatumPresence(..)
  , TxConstraints
  )
import Contract.TxConstraints as Constraints
import Contract.Value
  ( CurrencySymbol
  , TokenName
  , Value
  , getTokenName
  , mkTokenName
  )
import Contract.Value as Value
import Ctl.Internal.Plutus.Conversion (fromPlutusAddress, toPlutusAddress)
import Ctl.Internal.Serialization.Address (addressBytes, addressFromBytes)
import Data.Bifunctor (lmap)
import Data.BigInt (BigInt)
import Data.BigInt as BigInt
import Data.Map as Map
import TrustlessSidechain.DistributedSet as DistributedSet
import TrustlessSidechain.MerkleRoot
  ( SignedMerkleRootMint(..)
  , findMerkleRootTokenUtxo
  )
import TrustlessSidechain.MerkleRoot as MerkleRoot
import TrustlessSidechain.MerkleTree (MerkleProof, RootHash, rootMp, unRootHash)
import TrustlessSidechain.RawScripts (rawFUELMintingPolicy)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.UpdateCommitteeHash (getCommitteeHashPolicy)
import TrustlessSidechain.Utils.Logging (class Display)
import TrustlessSidechain.Utils.Logging as Logging
import TrustlessSidechain.Utils.SerialiseData (serialiseData)

-- | `FUELMint` is the data type to parameterize the minting policy.
-- | Note: this matches the haskell onchain data type.
newtype FUELMint = FUELMint
  { merkleRootTokenCurrencySymbol ∷ CurrencySymbol
  , sidechainParams ∷ SidechainParams
  , dsKeyCurrencySymbol ∷ CurrencySymbol
  }

derive instance Generic FUELMint _
derive instance Newtype FUELMint _
instance ToData FUELMint where
  toData
    ( FUELMint
        { merkleRootTokenCurrencySymbol, sidechainParams, dsKeyCurrencySymbol }
    ) =
    Constr zero
      [ toData merkleRootTokenCurrencySymbol
      , toData sidechainParams
      , toData dsKeyCurrencySymbol
      ]

-- | `Bech32Bytes` is a newtype wrapper for bech32 encoded bytestrings. In
-- | particular, this is used in the `recipient` field of `MerkleTreeEntry`
-- | which should be a decoded bech32 cardano address.
-- | See [here](https://cips.cardano.org/cips/cip19/) for details.
newtype Bech32Bytes = Bech32Bytes ByteArray

-- | `getBech32BytesByteArray` gets the underlying `ByteArray` of `Bech32Bytes`
getBech32BytesByteArray ∷ Bech32Bytes → ByteArray
getBech32BytesByteArray (Bech32Bytes byteArray) = byteArray

derive newtype instance ordBech32Bytes ∷ Ord Bech32Bytes
derive newtype instance eqBech32Bytes ∷ Eq Bech32Bytes
derive newtype instance toDataBech32Bytes ∷ ToData Bech32Bytes
derive newtype instance fromDataBech32Bytes ∷ FromData Bech32Bytes

instance Show Bech32Bytes where
  show (Bech32Bytes byteArray) = "(byteArrayToBech32BytesUnsafe "
    <> show byteArray
    <> ")"

-- | `byteArrayToBech32BytesUnsafe` converts a `ByteArray` to `Bech32Bytes`
-- | without checking the data format.
byteArrayToBech32BytesUnsafe ∷ ByteArray → Bech32Bytes
byteArrayToBech32BytesUnsafe = Bech32Bytes

-- | `bech32BytesFromAddress` serialises an `Address` to `Bech32Bytes` using
-- | the network id in the `Contract`
bech32BytesFromAddress ∷ ∀ r. Address → Contract r Bech32Bytes
bech32BytesFromAddress address =
  ( \netId → byteArrayToBech32BytesUnsafe $ unwrap $ addressBytes $
      fromPlutusAddress netId address
  )
    <$> getNetworkId

-- | `addressFromCborBytes` is a convenient wrapper to convert cbor bytes
-- | into an `Address.`
-- | It is useful to use this with `Contract.CborBytes.cborBytesFromByteArray`
-- | to create an address from a `ByteArray` i.e.,
-- | ```
-- | addressFromCborBytes <<< Contract.CborBytes.cborBytesFromByteArray
-- | ```
-- | Then, you can use `bech32BytesFromAddress` to get the `recipient`.
addressFromCborBytes ∷ CborBytes → Maybe Address
addressFromCborBytes = toPlutusAddress <=< addressFromBytes

-- | `MerkleTreeEntry` (abbr. mte and pl. mtes) is the data which are the elements in the merkle tree
-- | for the MerkleRootToken. It contains:
-- | - `index`: 32 bit unsigned integer, used to provide uniqueness among
-- | transactions within the tree
-- | - `amount`: 256 bit unsigned integer that represents amount of tokens
-- | being sent out of the bridge
-- | - `recipient`: arbitrary length bytestring that represents decoded bech32
-- | cardano address. See [here](https://cips.cardano.org/cips/cip19/) for more
-- | details of bech32.
-- | - `previousMerkleRoot`: if a previous merkle root exists, used to ensure
-- | uniqueness of entries.
newtype MerkleTreeEntry = MerkleTreeEntry
  { index ∷ BigInt
  , amount ∷ BigInt
  , recipient ∷ Bech32Bytes
  , previousMerkleRoot ∷ Maybe RootHash
  }

instance FromData MerkleTreeEntry where
  fromData (Constr n [ a, b, c, d ]) | n == zero = ado
    index ← fromData a
    amount ← fromData b
    recipient ← fromData c
    previousMerkleRoot ← fromData d
    in MerkleTreeEntry { index, amount, recipient, previousMerkleRoot }
  fromData _ = Nothing

derive instance Generic MerkleTreeEntry _
derive instance Newtype MerkleTreeEntry _
instance ToData MerkleTreeEntry where
  toData
    ( MerkleTreeEntry
        { index, amount, recipient, previousMerkleRoot }
    ) =
    Constr zero
      [ toData index
      , toData amount
      , toData recipient
      , toData previousMerkleRoot
      ]

instance Show MerkleTreeEntry where
  show = genericShow

-- | `CombinedMerkleProof` contains both the `MerkleTreeEntry` and its
-- | corresponding `MerkleProof`. See #249 for details.
newtype CombinedMerkleProof = CombinedMerkleProof
  { transaction ∷ MerkleTreeEntry
  , merkleProof ∷ MerkleProof
  }

-- | `combinedMerkleProofToFuelParams` converts `SidechainParams` and
-- | `CombinedMerkleProof` to a `Mint` of `FuelParams`.
-- | This is a modestly convenient wrapper to help call the `runFuelMP `
-- | endpoint for internal tests.
combinedMerkleProofToFuelParams ∷
  SidechainParams → CombinedMerkleProof → Maybe FuelParams
combinedMerkleProofToFuelParams
  sidechainParams
  (CombinedMerkleProof { transaction, merkleProof }) =
  let
    transaction' = unwrap transaction
  in

    addressFromBytes
      (cborBytesFromByteArray $ getBech32BytesByteArray $ transaction'.recipient)
      >>= toPlutusAddress
      >>=
        \recipient → pure $ Mint
          { amount: transaction'.amount
          , recipient
          , merkleProof
          , sidechainParams
          , index: transaction'.index
          , previousMerkleRoot: transaction'.previousMerkleRoot
          , dsOutput: Nothing
          }

instance Show CombinedMerkleProof where
  show = genericShow

derive instance Generic CombinedMerkleProof _
derive instance Newtype CombinedMerkleProof _
instance ToData CombinedMerkleProof where
  toData
    ( CombinedMerkleProof
        { transaction, merkleProof }
    ) =
    Constr zero
      [ toData transaction
      , toData merkleProof
      ]

instance FromData CombinedMerkleProof where
  fromData (Constr n [ a, b ]) | n == zero = ado
    transaction ← fromData a
    merkleProof ← fromData b
    in CombinedMerkleProof { transaction, merkleProof }
  fromData _ = Nothing

data FUELRedeemer
  = MainToSide ByteArray -- recipient sidechain (addr , signature)
  | SideToMain MerkleTreeEntry MerkleProof

derive instance Generic FUELRedeemer _
instance ToData FUELRedeemer where
  toData (MainToSide s1) = Constr zero [ toData s1 ]
  toData (SideToMain s1 s2) = Constr one
    [ toData s1
    , toData s2
    ]

-- | Gets the FUELMintingPolicy by applying `FUELMint` to the FUEL minting
-- | policy
fuelMintingPolicy ∷ FUELMint → Contract () MintingPolicy
fuelMintingPolicy fm = do
  let
    script = decodeTextEnvelope rawFUELMintingPolicy >>=
      plutusScriptV2FromEnvelope

  unapplied ← liftContractM "Decoding text envelope failed." script
  applied ← liftContractE $ Scripts.applyArgs unapplied [ toData fm ]
  pure $ PlutusMintingPolicy applied

-- | `getFuelMintingPolicy` creates the parameter `FUELMint`
-- | (as required by the onchain mintng policy) via the given
-- | `SidechainParams`, and calls `fuelMintingPolicy` to give us the minting
-- | policy
getFuelMintingPolicy ∷
  SidechainParams →
  Contract ()
    { fuelMintingPolicy ∷ MintingPolicy
    , fuelMintingPolicyCurrencySymbol ∷ CurrencySymbol
    }
getFuelMintingPolicy sidechainParams = do
  let msg = report "getFuelMintingPolicy"
  { merkleRootTokenCurrencySymbol } ← MerkleRoot.getMerkleRootTokenMintingPolicy
    sidechainParams
  { dsKeyPolicyCurrencySymbol } ← DistributedSet.getDsKeyPolicy sidechainParams

  policy ← fuelMintingPolicy $
    FUELMint
      { sidechainParams
      , merkleRootTokenCurrencySymbol
      , dsKeyCurrencySymbol: dsKeyPolicyCurrencySymbol
      }
  fuelMintingPolicyCurrencySymbol ←
    liftContractM (msg "Cannot get currency symbol") $
      Value.scriptCurrencySymbol policy
  pure
    { fuelMintingPolicy: policy
    , fuelMintingPolicyCurrencySymbol
    }

-- | `FuelParams` is the data for the FUEL mint / burn endpoint.
data FuelParams
  = Mint
      { amount ∷ BigInt
      , recipient ∷ Address
      , merkleProof ∷ MerkleProof
      , sidechainParams ∷ SidechainParams
      , index ∷ BigInt
      , previousMerkleRoot ∷ Maybe RootHash
      , dsOutput ∷ Maybe TransactionInput
      }
  | Burn { amount ∷ BigInt, recipient ∷ ByteArray }

-- | `runFuelMP` executes the FUEL mint / burn endpoint.
runFuelMP ∷ SidechainParams → FuelParams → Contract () TransactionHash
runFuelMP sp fp = do
  let msg = Logging.mkReport { mod: "FUELMintingPolicy", fun: "runFuelMP" }

  { fuelMintingPolicy: fuelMP } ← getFuelMintingPolicy sp

  { lookups, constraints } ← case fp of
    Burn params →
      burnFUEL fuelMP params
    Mint params → claimFUEL fuelMP params

  ubTx ← liftedE (lmap msg <$> Lookups.mkUnbalancedTx lookups constraints)
  bsTx ← liftedE (lmap msg <$> balanceTx ubTx)
  signedTx ← signTransaction bsTx
  txId ← submit signedTx
  logInfo' $ msg ("Submitted Tx: " <> show txId)
  awaitTxConfirmed txId
  logInfo' $ msg "Tx submitted successfully!"

  pure txId

-- | Mint FUEL tokens using the Active Bridge configuration, verifying the
-- | Merkle proof
claimFUEL ∷
  MintingPolicy →
  { amount ∷ BigInt
  , recipient ∷ Address
  , merkleProof ∷ MerkleProof
  , sidechainParams ∷ SidechainParams
  , index ∷ BigInt
  , previousMerkleRoot ∷ Maybe RootHash
  , dsOutput ∷ Maybe TransactionInput
  } →
  Contract ()
    { lookups ∷ ScriptLookups Void, constraints ∷ TxConstraints Void Void }
claimFUEL
  fuelMP
  { amount
  , recipient
  , merkleProof
  , sidechainParams
  , index
  , previousMerkleRoot
  , dsOutput
  } =
  do
    let msg = Logging.mkReport { mod: "FUELMintingPolicy", fun: "mintFUEL" }
    ownPkh ← liftedM (msg "Cannot get own pubkey") ownPaymentPubKeyHash

    cs /\ tn ← getFuelAssetClass fuelMP

    ds ← DistributedSet.getDs sidechainParams

    bech32BytesRecipient ← bech32BytesFromAddress recipient
    let
      merkleTreeEntry =
        MerkleTreeEntry
          { index
          , amount
          , previousMerkleRoot
          , recipient: bech32BytesRecipient
          }

    entryBytes ← liftContractM (msg "Cannot serialise merkle tree entry")
      $ serialiseData
      $ toData
          merkleTreeEntry

    let rootHash = rootMp entryBytes merkleProof

    cborMteHashedTn ← liftContractM (msg "Token name exceeds size limet")
      $ mkTokenName
      $ blake2b256Hash entryBytes

    { index: mptUtxo, value: mptTxOut } ←
      liftContractM
        (msg "Couldn't find the parent Merkle tree root hash of the transaction")
        =<< findMerkleRootTokenUtxoByRootHash sidechainParams rootHash

    { inUtxo:
        { nodeRef
        , oNode
        , datNode
        , tnNode
        }
    , nodes: DistributedSet.Ib { unIb: nodeA /\ nodeB }
    } ← liftedM (msg "Couldn't find distributed set nodes") $
      DistributedSet.findDsOutput ds cborMteHashedTn

    { confRef, confO } ← DistributedSet.findDsConfOutput ds

    insertValidator ← DistributedSet.insertValidator ds
    let insertValidatorHash = Scripts.validatorHash insertValidator
    { dsKeyPolicy, dsKeyPolicyCurrencySymbol } ← DistributedSet.getDsKeyPolicy
      sidechainParams

    recipientPkh ←
      liftContractM (msg "Couldn't derive payment public key hash from address")
        $ PaymentPubKeyHash
        <$> toPubKeyHash recipient

    let recipientSt = toStakePubKeyHash recipient

    let
      node = DistributedSet.mkNode (getTokenName tnNode) datNode
      value = Value.singleton cs tn amount
      redeemer = wrap (toData (SideToMain merkleTreeEntry merkleProof))
      -- silence missing stake key warning

      mkNodeConstraints n = do
        nTn ← liftContractM "Couldn't convert node token name"
          $ mkTokenName
          $ (unwrap n).nKey

        let val = Value.singleton dsKeyPolicyCurrencySymbol nTn (BigInt.fromInt 1)
        if getTokenName nTn == (unwrap node).nKey then
          pure $ Constraints.mustPayToScript
            insertValidatorHash
            (Datum (toData (DistributedSet.nodeToDatum n)))
            DatumInline
            val
        else
          pure
            $ Constraints.mustPayToScript
                insertValidatorHash
                (Datum (toData (DistributedSet.nodeToDatum n)))
                DatumInline
                val
            <> Constraints.mustMintValue val

    mustAddDSNodeA ← mkNodeConstraints nodeA
    mustAddDSNodeB ← mkNodeConstraints nodeB

    pure
      { lookups:
          Lookups.mintingPolicy fuelMP
            <> Lookups.mintingPolicy dsKeyPolicy
            <> Lookups.validator insertValidator
            <> Lookups.unspentOutputs (Map.singleton mptUtxo mptTxOut)
            <> Lookups.unspentOutputs (Map.singleton confRef confO)
            <> Lookups.unspentOutputs (Map.singleton nodeRef oNode)

      , constraints:
          -- Minting the FUEL tokens
          Constraints.mustMintValueWithRedeemer redeemer value
            <> mustPayToPubKeyAddress' recipientPkh recipientSt value
            <> Constraints.mustBeSignedBy ownPkh

            -- Referencing Merkle root
            <> Constraints.mustReferenceOutput mptUtxo

            -- Updating the distributed set
            <> Constraints.mustReferenceOutput confRef
            <> Constraints.mustSpendScriptOutput nodeRef unitRedeemer
            <> mustAddDSNodeA
            <> mustAddDSNodeB
      }

-- | `burnFUEL` burns the given FUEL amount.
burnFUEL ∷
  MintingPolicy →
  { amount ∷ BigInt, recipient ∷ ByteArray } →
  Contract ()
    { lookups ∷ ScriptLookups Void, constraints ∷ TxConstraints Void Void }
burnFUEL fuelMP { amount, recipient } = do
  cs /\ tn ← getFuelAssetClass fuelMP

  let
    value = Value.singleton cs tn (-amount)
    redeemer = wrap (toData (MainToSide recipient))
  pure
    { lookups: Lookups.mintingPolicy fuelMP
    , constraints: Constraints.mustMintValueWithRedeemer redeemer value
    }

-- | `findMerkleRootTokenUtxoByRootHash` attempts to find a UTxO with MerkleRootToken
-- | as given by the `RootHash`
-- TODO: refactor to utility module
findMerkleRootTokenUtxoByRootHash ∷
  SidechainParams →
  RootHash →
  Contract ()
    (Maybe { index ∷ TransactionInput, value ∷ TransactionOutputWithRefScript })
findMerkleRootTokenUtxoByRootHash sidechainParams rootHash = do
  { committeeHashCurrencySymbol } ← getCommitteeHashPolicy sidechainParams

  -- Then, we get the merkle root token validator hash / minting policy..
  merkleRootValidatorHash ← map Scripts.validatorHash $
    MerkleRoot.merkleRootTokenValidator sidechainParams
  let
    msg = Logging.mkReport
      { mod: "FUELMintingPolicy", fun: "findMerkleRootTokenUtxoByRootHash" }
    smrm = SignedMerkleRootMint
      { sidechainParams
      , updateCommitteeHashCurrencySymbol: committeeHashCurrencySymbol
      , merkleRootValidatorHash
      }
  merkleRootTokenName ←
    liftContractM
      (msg "Invalid merkle root TokenName for merkleRootTokenMintingPolicy")
      $ Value.mkTokenName
      $ unRootHash rootHash
  findMerkleRootTokenUtxo merkleRootTokenName smrm

-- | Derive the stake key hash from a public key address
toStakePubKeyHash ∷ Address → Maybe StakePubKeyHash
toStakePubKeyHash addr =
  case toStakingCredential addr of
    Just (StakingHash (PubKeyCredential pkh)) → Just (StakePubKeyHash pkh)
    _ → Nothing

-- | Pay values to a public key address (with optional staking key)
mustPayToPubKeyAddress' ∷
  PaymentPubKeyHash → Maybe StakePubKeyHash → Value → TxConstraints Void Void
mustPayToPubKeyAddress' pkh = case _ of
  Just skh → Constraints.mustPayToPubKeyAddress pkh skh
  Nothing → Constraints.mustPayToPubKey pkh

-- | Return the currency symbol and token name of the FUEL token
getFuelAssetClass ∷ MintingPolicy → Contract () (CurrencySymbol /\ TokenName)
getFuelAssetClass fuelMP = do
  cs ← liftContractM "Cannot get FUEL currency symbol" $
    Value.scriptCurrencySymbol fuelMP
  tn ← liftContractM "Cannot get FUEL token name"
    (Value.mkTokenName =<< byteArrayFromAscii "FUEL")

  pure (cs /\ tn)

-- | `report` is an internal function used for helping writing log messages.
report ∷ String → ∀ e. Display e ⇒ e → String
report = Logging.mkReport <<< { mod: "FUELMintingPolicy", fun: _ }
