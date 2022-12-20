module Test.MPTRoot
  ( testScenario1
  , testScenario2
  , saveRoot
  , paymentPubKeyHashToBech32Bytes
  ) where

import Contract.Prelude

import Contract.Address (PaymentPubKeyHash)
import Contract.Address as Address
import Contract.Log as Log
import Contract.Monad (Contract, liftContractE, liftContractM, liftedM)
import Contract.Prim.ByteArray (ByteArray, hexToByteArrayUnsafe)
import Data.Array as Array
import Data.BigInt as BigInt
import FUELMintingPolicy
  ( Bech32Bytes
  , MerkleTreeEntry(MerkleTreeEntry)
  , bech32BytesFromAddress
  )
import InitSidechain as InitSidechain
import MPTRoot
  ( MerkleRootInsertionMessage(MerkleRootInsertionMessage)
  , SaveRootParams(SaveRootParams)
  )
import MPTRoot as MPTRoot
import MerkleTree as MerkleTree
import SidechainParams (InitSidechainParams(..), SidechainParams)
import SidechainParams as SidechainParams
import Test.Utils as Test.Utils
import Utils.Crypto (SidechainPrivateKey)
import Utils.Crypto as Crypto
import Utils.SerialiseData as SerialiseData

-- | `paymentPubKeyHashToBech32Bytes` converts a `PaymentPubKeyHash`
-- | to the `Bech32Bytes` required for the `recipient` field of
-- | `FUELMintingPolicy.MerkleTreeEntry`.
-- | Note this assumes no staking public key hash to simplify writing tests.
paymentPubKeyHashToBech32Bytes ∷ PaymentPubKeyHash → Contract () Bech32Bytes
paymentPubKeyHashToBech32Bytes pubKeyHash =
  bech32BytesFromAddress $ Address.pubKeyHashAddress pubKeyHash Nothing

-- | `saveRoot` is a wrapper around `MPTRoot.saveRoot` to make writing test
-- | cases a bit more terse (note that it makes all committee members sign the new root).
-- | It returns the saved merkle root.
saveRoot ∷
  { sidechainParams ∷ SidechainParams
  , -- merkle tree entries used to build the new merkle root
    merkleTreeEntries ∷ Array MerkleTreeEntry
  , -- the current committee's (expected to be stored on chain) private keys
    currentCommitteePrvKeys ∷ Array SidechainPrivateKey
  , -- the merkle root that was just saved
    previousMerkleRoot ∷ Maybe ByteArray
  } →
  Contract () ByteArray
saveRoot
  { sidechainParams
  , merkleTreeEntries
  , currentCommitteePrvKeys
  , previousMerkleRoot
  } = do
  serialisedEntries ←
    liftContractM "error 'testScenario': bad serialisation of merkle root" $
      traverse SerialiseData.serialiseToData merkleTreeEntries
  merkleTree ← liftContractE $ MerkleTree.fromArray serialisedEntries

  let
    merkleRoot = MerkleTree.unRootHash $ MerkleTree.rootHash merkleTree

  merkleRootInsertionMessage ←
    liftContractM
      "error 'Test.MPTRoot.testScenario': failed to create merkle root insertion message"
      $ MPTRoot.serialiseMrimHash
      $ MerkleRootInsertionMessage
          { sidechainParams: SidechainParams.convertSCParams sidechainParams
          , merkleRoot
          , previousMerkleRoot
          }
  let
    -- make every committee member sign the new root
    committeeSignatures = Array.zip
      (map Crypto.toPubKeyUnsafe currentCommitteePrvKeys)
      ( Just <$> Crypto.multiSign currentCommitteePrvKeys
          merkleRootInsertionMessage
      )

  void $ MPTRoot.saveRoot $ SaveRootParams
    { sidechainParams
    , merkleRoot
    , previousMerkleRoot
    , committeeSignatures
    }
  pure merkleRoot

-- | `testScenario1` does
-- |    1. Sets up the sidechain using the `InitSidechain.initSidechain` endpoint
-- |
-- |    2. Creates a merkle root to sign
-- |
-- |    3. Saves that merkle root with the current committee (everyone but one
-- |    person) using the `MPTRoot.saveRoot` endpoint.
testScenario1 ∷ Contract () Unit
testScenario1 = do
  Log.logInfo' "MPTRoot testScenario1"

  -- 1. Setting up the sidechain
  ---------------------------
  let
    committeeSize = 25
  -- It fails with ~50 (nondeterministically) with budget overspent
  -- I would really like to get this up to 101 as with the update
  -- committee hash endpoint! Some room for optimization is certainly
  -- a possibility..
  genesisUtxo ← Test.Utils.getOwnTransactionInput

  initCommitteePrvKeys ← sequence $ Array.replicate committeeSize
    Crypto.generatePrivKey
  let
    initCommitteePubKeys = map Crypto.toPubKeyUnsafe initCommitteePrvKeys
    initSidechainParams = InitSidechainParams
      { initChainId: BigInt.fromInt 69
      , initGenesisHash: hexToByteArrayUnsafe "aabbcc"
      , initMint: Nothing
      , initUtxo: genesisUtxo
      , initCommittee: initCommitteePubKeys
      , initSidechainEpoch: zero
      , initThresholdNumerator: BigInt.fromInt 2
      , initThresholdDenominator: BigInt.fromInt 3
      }

  { sidechainParams } ← InitSidechain.initSidechain initSidechainParams

  -- Building / saving the root that pays lots of FUEL to this wallet :)
  ----------------------------------------------------------------------
  ownPaymentPubKeyHash ← liftedM
    "error 'testScenario1': 'Contract.Address.ownPaymentPubKeyHash' failed"
    Address.ownPaymentPubKeyHash

  ownRecipient ← paymentPubKeyHashToBech32Bytes ownPaymentPubKeyHash
  serialisedEntries ←
    liftContractM "error 'testScenario1': bad serialisation of merkle root" $
      traverse SerialiseData.serialiseToData
        [ MerkleTreeEntry
            { index: BigInt.fromInt 0
            , amount: BigInt.fromInt 69
            , previousMerkleRoot: Nothing
            , recipient: ownRecipient
            }
        ]
  merkleTree ← liftContractE $ MerkleTree.fromArray serialisedEntries

  let
    merkleRoot = MerkleTree.unRootHash $ MerkleTree.rootHash merkleTree

  merkleRootInsertionMessage ←
    liftContractM
      "error 'Test.MPTRoot.testScenario1': failed to create merkle root insertion message"
      $ MPTRoot.serialiseMrimHash
      $ MerkleRootInsertionMessage
          { sidechainParams: SidechainParams.convertSCParams sidechainParams
          , merkleRoot
          , previousMerkleRoot: Nothing
          }
  let
    -- We create signatures for every committee member BUT the first key...
    -- if you wanted to create keys for every committee member, we would write
    -- ```
    -- committeeSignatures = Array.zip
    --     initCommitteePubKeys
    --     (Just <$> Crypto.multiSign initCommitteePrvKeys merkleRootInsertionMessage)
    -- ```
    committeeSignatures =
      case
        Array.uncons $ Array.zip
          initCommitteePubKeys
          ( Just <$> Crypto.multiSign initCommitteePrvKeys
              merkleRootInsertionMessage
          )
        of
        Just { head, tail } →
          Array.cons ((fst head) /\ Nothing) tail
        _ → [] -- should never happen

  void $ MPTRoot.saveRoot $ SaveRootParams
    { sidechainParams
    , merkleRoot
    , previousMerkleRoot: Nothing
    , committeeSignatures
    }

  pure unit

-- | `testScenario2` does the following
-- |    1. initializes the sidechain
-- |
-- |    2. saves a merkle root
-- |
-- |    3. saves another merkle root (this references the last merkle root).
-- |
-- | Note: the initialize sidechain part is duplicated code from above.
testScenario2 ∷ Contract () Unit
testScenario2 = do
  Log.logInfo' "MPTRoot testScenario2"

  -- 1. Setting up the sidechain
  ---------------------------
  let
    committeeSize = 25
  -- It fails with ~50 (nondeterministically) with budget overspent
  -- I would really like to get this up to 101 as with the update
  -- committee hash endpoint! Some room for optimization is certainly
  -- a possibility..
  genesisUtxo ← Test.Utils.getOwnTransactionInput

  initCommitteePrvKeys ← sequence $ Array.replicate committeeSize
    Crypto.generatePrivKey
  let
    initCommitteePubKeys = map Crypto.toPubKeyUnsafe initCommitteePrvKeys
    initSidechainParams = InitSidechainParams
      { initChainId: BigInt.fromInt 69
      , initGenesisHash: hexToByteArrayUnsafe "aabbcc"
      , initMint: Nothing
      , initUtxo: genesisUtxo
      , initCommittee: initCommitteePubKeys
      , initSidechainEpoch: zero
      , initThresholdNumerator: BigInt.fromInt 2
      , initThresholdDenominator: BigInt.fromInt 3
      }

  { sidechainParams } ← InitSidechain.initSidechain initSidechainParams

  -- Building / saving the root that pays lots of FUEL to this wallet :)
  ----------------------------------------------------------------------
  ownPaymentPubKeyHash ← liftedM
    "error 'testScenario1': 'Contract.Address.ownPaymentPubKeyHash' failed"
    Address.ownPaymentPubKeyHash

  ownRecipient ← paymentPubKeyHashToBech32Bytes ownPaymentPubKeyHash

  merkleRoot1 ←
    saveRoot
      { sidechainParams
      , merkleTreeEntries:
          [ MerkleTreeEntry
              { index: BigInt.fromInt 0
              , amount: BigInt.fromInt 69
              , previousMerkleRoot: Nothing
              , recipient: ownRecipient
              }
          ]
      , currentCommitteePrvKeys: initCommitteePrvKeys
      , previousMerkleRoot: Nothing
      }
  _ ←
    saveRoot
      { sidechainParams
      , merkleTreeEntries:
          [ MerkleTreeEntry
              { index: BigInt.fromInt 0
              , amount: BigInt.fromInt 69
              , previousMerkleRoot: Just merkleRoot1
              , recipient: ownRecipient
              }
          , MerkleTreeEntry
              { index: BigInt.fromInt 1
              , amount: BigInt.fromInt 69
              , previousMerkleRoot: Just merkleRoot1
              , recipient: ownRecipient
              }
          ]
      , currentCommitteePrvKeys: initCommitteePrvKeys
      , previousMerkleRoot: Nothing
      }
  pure unit
