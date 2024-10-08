module Test.FUELMintingPolicy.V1 where

import Contract.Prelude

import Cardano.AsCbor (encodeCbor)
import Cardano.ToData (toData)
import Cardano.Types.AssetName as AssetName
import Cardano.Types.BigNum as BigNum
import Cardano.Types.NetworkId (NetworkId(TestnetId))
import Contract.PlutusData as PlutusData
import Contract.Wallet as Wallet
import Data.Array as Array
import JS.BigInt as BigInt
import Mote.Monad as Mote.Monad
import Partial.Unsafe (unsafePartial)
import Run (liftEffect) as Run
import Run.Except (note) as Run
import Test.MerkleRoot as Test.MerkleRoot
import Test.TestnetTest (TestnetTest)
import Test.TestnetTest as Test.TestnetTest
import Test.Utils
  ( WrappedTests
  , dummySidechainParams
  , fails
  , getOwnTransactionInput
  , testnetGroup
  )
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds(ATMSPlainEcdsaSecp256k1)
  )
import TrustlessSidechain.DistributedSet as DistributedSet
import TrustlessSidechain.Effects.Run (withUnliftApp)
import TrustlessSidechain.Effects.Util (mapError)
import TrustlessSidechain.Effects.Util as Effect
import TrustlessSidechain.Error (OffchainError(GenericInternalError))
import TrustlessSidechain.FUELMintingPolicy.V1
  ( FuelMintParams(FuelMintParams)
  , MerkleTreeEntry(MerkleTreeEntry)
  , combinedMerkleProofToFuelParams
  , mkMintFuelLookupAndConstraints
  )
import TrustlessSidechain.Governance.Admin as Governance
import TrustlessSidechain.InitSidechain.FUEL (initFuel)
import TrustlessSidechain.InitSidechain.TokensMint (initTokensMint)
import TrustlessSidechain.MerkleTree
  ( MerkleProof(MerkleProof)
  , fromList
  , lookupMp
  )
import TrustlessSidechain.MerkleTree as MerkleTree
import TrustlessSidechain.SidechainParams (SidechainParams(SidechainParams))
import TrustlessSidechain.Utils.Address
  ( fromPaymentPubKeyHash
  , getOwnPaymentPubKeyHash
  )
import TrustlessSidechain.Utils.Crypto
  ( aggregateKeys
  , blake2b256Hash
  , generatePrivKey
  , toPubKeyUnsafe
  )
import TrustlessSidechain.Utils.Transaction (balanceSignAndSubmit)

-- | `tests` aggregate all the FUELMintingPolicy tests in one convenient
-- | function
tests ∷ WrappedTests
tests = testnetGroup "Minting FUEL tokens using MerkleTree-based minting policy"
  $ do
      testScenarioSuccess
      testScenarioSuccess2
      testScenarioFailure
      testScenarioFailure2

-- | `testScenarioSuccess` tests minting some tokens
testScenarioSuccess ∷ TestnetTest
testScenarioSuccess = Mote.Monad.test "Claiming FUEL tokens"
  $ Test.TestnetTest.mkTestnetConfigTest
      [ BigNum.fromInt 100_000_000
      , BigNum.fromInt 100_000_000
      , BigNum.fromInt 100_000_000
      , BigNum.fromInt 100_000_000
      , BigNum.fromInt 100_000_000
      ]
  $ \alice → withUnliftApp (Wallet.withKeyWallet alice) do

      pkh ← getOwnPaymentPubKeyHash
      let ownRecipient = Test.MerkleRoot.paymentPubKeyHashToBech32Bytes pkh
      genesisUtxo ← getOwnTransactionInput
      let
        keyCount = 25
      initCommitteePrvKeys ← Run.liftEffect $ sequence $ Array.replicate keyCount
        generatePrivKey
      let
        initCommitteePubKeys = map toPubKeyUnsafe initCommitteePrvKeys
        aggregatedCommittee = PlutusData.toData
          $ aggregateKeys
          $ map unwrap
              initCommitteePubKeys
        sidechainParams =
          SidechainParams
            { chainId: BigInt.fromInt 69_420
            , genesisUtxo
            , thresholdNumerator: BigInt.fromInt 2
            , thresholdDenominator: BigInt.fromInt 3
            , governanceAuthority: Governance.mkGovernanceAuthority pkh
            }

      _ ← initTokensMint sidechainParams ATMSPlainEcdsaSecp256k1 1
      _ ←
        initFuel sidechainParams
          zero
          aggregatedCommittee
          ATMSPlainEcdsaSecp256k1
          1

      let
        amount = BigInt.fromInt 5
        recipient = fromPaymentPubKeyHash TestnetId pkh
        index = BigInt.fromInt 0
        previousMerkleRoot = Nothing
        ownEntry =
          MerkleTreeEntry
            { index
            , amount
            , previousMerkleRoot
            , recipient: ownRecipient
            }

        ownEntryBytes = unwrap $ encodeCbor $ toData ownEntry
        merkleTree =
          unsafePartial $ fromJust $ hush $ MerkleTree.fromArray
            [ ownEntryBytes ]

        merkleProof = unsafePartial $ fromJust $ MerkleTree.lookupMp ownEntryBytes
          merkleTree
      void $ Test.MerkleRoot.saveRoot
        { sidechainParams
        , merkleTreeEntries: [ ownEntry ]
        , currentCommitteePrvKeys: initCommitteePrvKeys
        , previousMerkleRoot: Nothing
        }

      void
        $
          ( mkMintFuelLookupAndConstraints sidechainParams $
              FuelMintParams
                { amount
                , recipient
                , sidechainParams
                , merkleProof
                , index
                , previousMerkleRoot
                , dsUtxo: Nothing
                }
          )
        >>= balanceSignAndSubmit "Test: mint v1 fuel"

-- | `testScenarioSuccess2` tests minting some tokens with the fast distributed
-- | set lookup. Note: this is mostly duplicated from `testScenarioSuccess`
testScenarioSuccess2 ∷ TestnetTest
testScenarioSuccess2 =
  Mote.Monad.test "Claiming FUEL tokens with fast distributed set lookup"
    $ Test.TestnetTest.mkTestnetConfigTest
        [ BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 40_000_000
        ]
    $ \alice → withUnliftApp (Wallet.withKeyWallet alice) do

        pkh ← getOwnPaymentPubKeyHash
        let ownRecipient = Test.MerkleRoot.paymentPubKeyHashToBech32Bytes pkh
        genesisUtxo ← getOwnTransactionInput
        let
          keyCount = 25
        initCommitteePrvKeys ← Run.liftEffect $ sequence $ Array.replicate
          keyCount
          generatePrivKey
        let
          initCommitteePubKeys = map toPubKeyUnsafe initCommitteePrvKeys
          aggregatedCommittee = PlutusData.toData
            $ aggregateKeys
            $ map unwrap initCommitteePubKeys
          sidechainParams =
            SidechainParams
              { chainId: BigInt.fromInt 1
              , genesisUtxo
              , thresholdNumerator: BigInt.fromInt 2
              , thresholdDenominator: BigInt.fromInt 3
              , governanceAuthority: Governance.mkGovernanceAuthority pkh
              }

        _ ← initTokensMint sidechainParams ATMSPlainEcdsaSecp256k1 1
        _ ←
          initFuel sidechainParams
            zero
            aggregatedCommittee
            ATMSPlainEcdsaSecp256k1
            1

        let
          amount = BigInt.fromInt 5
          recipient = fromPaymentPubKeyHash TestnetId pkh
          index = BigInt.fromInt 0
          previousMerkleRoot = Nothing
          ownEntry =
            MerkleTreeEntry
              { index
              , amount
              , previousMerkleRoot
              , recipient: ownRecipient
              }

          ownEntryBytes = unwrap $ encodeCbor $ toData ownEntry
          ownEntryHash = blake2b256Hash $ ownEntryBytes

          ownEntryHashTn = unsafePartial $ fromJust $ AssetName.mkAssetName
            ownEntryHash
          merkleTree =
            unsafePartial $ fromJust $ hush $ MerkleTree.fromArray
              [ ownEntryBytes ]

          merkleProof = unsafePartial $ fromJust $ MerkleTree.lookupMp
            ownEntryBytes
            merkleTree

        void $ Test.MerkleRoot.saveRoot
          { sidechainParams
          , merkleTreeEntries: [ ownEntry ]
          , currentCommitteePrvKeys: initCommitteePrvKeys
          , previousMerkleRoot: Nothing
          }

        void do
          ds ← DistributedSet.getDs sidechainParams

          -- we first grab the distributed set UTxO (the slow way as we have no
          -- other mechanism for doing this with ctl)
          { inUtxo: { nodeRef } } ←
            Effect.fromMaybeThrow
              (GenericInternalError "error no distributed set node found")
              $ DistributedSet.slowFindDsOutput ds ownEntryHashTn

          void
            $
              ( mkMintFuelLookupAndConstraints sidechainParams $
                  FuelMintParams
                    { amount
                    , recipient
                    , sidechainParams
                    , merkleProof
                    , index
                    , previousMerkleRoot
                    , dsUtxo: Just nodeRef -- note that we use the distributed set UTxO in the endpoint here.
                    }
              )
            >>=
              balanceSignAndSubmit "Test: mint v1 fuel"

testScenarioFailure ∷ TestnetTest
testScenarioFailure =
  Mote.Monad.test "Attempt to claim with invalid merkle proof (should fail)"
    $ Test.TestnetTest.mkTestnetConfigTest
        [ BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 40_000_000
        ]
    $ \alice →
        withUnliftApp (Wallet.withKeyWallet alice) do

          pkh ← getOwnPaymentPubKeyHash
          let
            recipient = fromPaymentPubKeyHash TestnetId pkh

          -- This is not how you create a working merkleproof that passes onchain validator.
          let mp' = unwrap $ encodeCbor $ toData (MerkleProof [])
          mt ← mapError GenericInternalError $ Effect.fromEitherThrow $ pure
            (fromList (pure mp'))
          mp ←
            Effect.fromMaybeThrow
              (GenericInternalError "couldn't lookup merkleproof") $
              pure (lookupMp mp' mt)

          void
            $ mkMintFuelLookupAndConstraints dummySidechainParams
                ( FuelMintParams
                    { merkleProof: mp
                    , recipient
                    , sidechainParams: dummySidechainParams
                    , amount: BigInt.fromInt 1
                    , index: BigInt.fromInt 0
                    , previousMerkleRoot: Nothing
                    , dsUtxo: Nothing
                    }
                )
            >>= balanceSignAndSubmit "Test: mint v1 fuel"
          # withUnliftApp fails

-- | `testScenarioFailure2` tries to mint something twice (which should
-- | fail!)
testScenarioFailure2 ∷ TestnetTest
testScenarioFailure2 = Mote.Monad.test "Attempt to double claim (should fail)"
  $ Test.TestnetTest.mkTestnetConfigTest
      [ BigNum.fromInt 50_000_000
      , BigNum.fromInt 50_000_000
      , BigNum.fromInt 50_000_000
      , BigNum.fromInt 40_000_000
      ]
  $ \alice →
      withUnliftApp (Wallet.withKeyWallet alice) do
        -- start of mostly duplicated code from `testScenarioSuccess2`

        pkh ← getOwnPaymentPubKeyHash
        let ownRecipient = Test.MerkleRoot.paymentPubKeyHashToBech32Bytes pkh
        genesisUtxo ← getOwnTransactionInput
        let
          keyCount = 25
        initCommitteePrvKeys ← liftEffect $ sequence $ Array.replicate keyCount
          generatePrivKey
        let
          initCommitteePubKeys = map toPubKeyUnsafe initCommitteePrvKeys
          aggregatedCommittee = PlutusData.toData
            $ aggregateKeys
            $ map unwrap initCommitteePubKeys
          sidechainParams =
            SidechainParams
              { chainId: BigInt.fromInt 1
              , genesisUtxo
              , thresholdNumerator: BigInt.fromInt 2
              , thresholdDenominator: BigInt.fromInt 3
              , governanceAuthority: Governance.mkGovernanceAuthority pkh
              }

        _ ← initTokensMint sidechainParams ATMSPlainEcdsaSecp256k1 1
        _ ←
          initFuel sidechainParams
            zero
            aggregatedCommittee
            ATMSPlainEcdsaSecp256k1
            1

        { combinedMerkleProofs } ← Test.MerkleRoot.saveRoot
          { sidechainParams
          , merkleTreeEntries:
              let
                previousMerkleRoot = Nothing
                entry0 =
                  MerkleTreeEntry
                    { index: BigInt.fromInt 0
                    , amount: BigInt.fromInt 5
                    , previousMerkleRoot
                    , recipient: ownRecipient
                    }
                entry1 =
                  MerkleTreeEntry
                    { index: BigInt.fromInt 1
                    , amount: BigInt.fromInt 7
                    , previousMerkleRoot
                    , recipient: ownRecipient
                    }
              in
                [ entry0, entry1 ]
          , currentCommitteePrvKeys: initCommitteePrvKeys
          , previousMerkleRoot: Nothing
          }
        -- end of mostly duplicated code from `testScenarioSuccess2`

        (combinedMerkleProof0 /\ _combinedMerkleProof1) ←
          Run.note
            (GenericInternalError "bad test case for `testScenarioSuccess2`")
            $ case combinedMerkleProofs of
                [ combinedMerkleProof0, combinedMerkleProof1 ] → pure
                  $ combinedMerkleProof0
                  /\ combinedMerkleProof1
                _ → Nothing

        fp0 ← Run.note (GenericInternalError "Could not build FuelParams") $
          combinedMerkleProofToFuelParams
            { sidechainParams
            , combinedMerkleProof: combinedMerkleProof0
            }

        -- the very bad double mint attempt...
        void $ mkMintFuelLookupAndConstraints sidechainParams fp0 >>=
          balanceSignAndSubmit "Test: mint v1 fuel"
        void $ mkMintFuelLookupAndConstraints sidechainParams fp0 >>=
          balanceSignAndSubmit "Test: mint v1 fuel again"

        pure unit
        # withUnliftApp fails
