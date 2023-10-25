module Test.PermissionedCandidates (tests) where

import Contract.Prelude

import Contract.PlutusData (toData)
import Contract.Prim.ByteArray (hexToByteArrayUnsafe)
import Contract.Wallet as Wallet
import Data.Array as Array
import Data.BigInt as BigInt
import Mote.Monad as Mote.Monad
import Test.PlutipTest (PlutipTest)
import Test.PlutipTest as Test.PlutipTest
import Test.Utils
  ( WrappedTests
  , fails
  , getOwnTransactionInput
  , plutipGroup
  )
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds(ATMSPlainEcdsaSecp256k1)
  )
import TrustlessSidechain.Governance as Governance
import TrustlessSidechain.InitSidechain
  ( InitSidechainParams(InitSidechainParams)
  , initSidechain
  )
import TrustlessSidechain.PermissionedCandidates as PermissionedCandidates
import TrustlessSidechain.Utils.Address (getOwnPaymentPubKeyHash)
import TrustlessSidechain.Utils.Crypto
  ( aggregateKeys
  , generatePrivKey
  , toPubKeyUnsafe
  )
import TrustlessSidechain.Utils.Tx (submitAndAwaitTx)

-- | `tests` aggregate all the PermissionedCandidatesPolicy tests in one convenient
-- | function
tests ∷ WrappedTests
tests = plutipGroup "Minting, and burning a PermissionedCandidates Token" $
  do
    testScenarioSuccess
    testScenarioFailure

testScenarioSuccess ∷ PlutipTest
testScenarioSuccess =
  Mote.Monad.test "Minting, updating and removing a PermissionedCandidates Token"
    $ Test.PlutipTest.mkPlutipConfigTest
        [ BigInt.fromInt 150_000_000
        , BigInt.fromInt 150_000_000
        , BigInt.fromInt 50_000_000
        ]
    $ \alice → Wallet.withKeyWallet alice do

        pkh ← getOwnPaymentPubKeyHash
        genesisUtxo ← getOwnTransactionInput
        let
          keyCount = 25
        initCommitteePrvKeys ← sequence $ Array.replicate keyCount generatePrivKey
        let
          initCommitteePubKeys = map toPubKeyUnsafe initCommitteePrvKeys
          initScParams = InitSidechainParams
            { initChainId: BigInt.fromInt 1
            , initGenesisHash: hexToByteArrayUnsafe "aabbcc"
            , initUtxo: genesisUtxo
            , initAggregatedCommittee: toData $ aggregateKeys
                $ map unwrap initCommitteePubKeys
            , initSidechainEpoch: zero
            , initThresholdNumerator: BigInt.fromInt 2
            , initThresholdDenominator: BigInt.fromInt 3
            , initCandidatePermissionTokenMintInfo: Nothing
            , initGovernanceAuthority: Governance.mkGovernanceAuthority $ unwrap
                pkh
            , initATMSKind: ATMSPlainEcdsaSecp256k1
            }

        { sidechainParams } ← initSidechain initScParams 1

        void
          $
            ( PermissionedCandidates.mkInsertPermissionedCandidatesLookupsAndConstraints
                sidechainParams
                { candidates:
                    [ { mainchainKey: hexToByteArrayUnsafe "aa11"
                      , sidechainKey: hexToByteArrayUnsafe "bb11"
                      , authorityDiscoveryKey: hexToByteArrayUnsafe "cc11"
                      , grandpaKey: hexToByteArrayUnsafe "dd11"
                      }
                    , { mainchainKey: hexToByteArrayUnsafe "aa22"
                      , sidechainKey: hexToByteArrayUnsafe "bb22"
                      , authorityDiscoveryKey: hexToByteArrayUnsafe "cc22"
                      , grandpaKey: hexToByteArrayUnsafe "dd22"
                      }
                    ]
                }
                >>=
                  submitAndAwaitTx
            )

        void
          $
            ( PermissionedCandidates.mkUpdatePermissionedCandidatesLookupsAndConstraints
                sidechainParams
                { candidates:
                    [ { mainchainKey: hexToByteArrayUnsafe "aa33"
                      , sidechainKey: hexToByteArrayUnsafe "bb33"
                      , authorityDiscoveryKey: hexToByteArrayUnsafe "cc33"
                      , grandpaKey: hexToByteArrayUnsafe "dd33"
                      }
                    ]
                }
                >>=
                  submitAndAwaitTx
            )

        void
          $
            ( PermissionedCandidates.mkRemovePermissionedCandidatesLookupsAndConstraints
                sidechainParams
                >>=
                  submitAndAwaitTx
            )

testScenarioFailure ∷ PlutipTest
testScenarioFailure =
  Mote.Monad.test
    "Minting and removing twice a PermissionedCandidates Token. (this should fail)"
    $ Test.PlutipTest.mkPlutipConfigTest
        [ BigInt.fromInt 150_000_000
        , BigInt.fromInt 150_000_000
        , BigInt.fromInt 50_000_000
        ]
    $ \alice → Wallet.withKeyWallet alice do

        pkh ← getOwnPaymentPubKeyHash
        genesisUtxo ← getOwnTransactionInput
        let
          keyCount = 25
        initCommitteePrvKeys ← sequence $ Array.replicate keyCount generatePrivKey
        let
          initCommitteePubKeys = map toPubKeyUnsafe initCommitteePrvKeys
          initScParams = InitSidechainParams
            { initChainId: BigInt.fromInt 1
            , initGenesisHash: hexToByteArrayUnsafe "aabbcc"
            , initUtxo: genesisUtxo
            , initAggregatedCommittee: toData $ aggregateKeys
                $ map unwrap initCommitteePubKeys
            , initSidechainEpoch: zero
            , initThresholdNumerator: BigInt.fromInt 2
            , initThresholdDenominator: BigInt.fromInt 3
            , initCandidatePermissionTokenMintInfo: Nothing
            , initGovernanceAuthority: Governance.mkGovernanceAuthority $ unwrap
                pkh
            , initATMSKind: ATMSPlainEcdsaSecp256k1
            }

        { sidechainParams } ← initSidechain initScParams 1

        void
          $
            ( PermissionedCandidates.mkInsertPermissionedCandidatesLookupsAndConstraints
                sidechainParams
                { candidates:
                    [ { mainchainKey: hexToByteArrayUnsafe "aa11"
                      , sidechainKey: hexToByteArrayUnsafe "bb11"
                      , authorityDiscoveryKey: hexToByteArrayUnsafe "cc11"
                      , grandpaKey: hexToByteArrayUnsafe "dd11"
                      }
                    , { mainchainKey: hexToByteArrayUnsafe "aa22"
                      , sidechainKey: hexToByteArrayUnsafe "bb22"
                      , authorityDiscoveryKey: hexToByteArrayUnsafe "cc22"
                      , grandpaKey: hexToByteArrayUnsafe "dd22"
                      }
                    ]
                }
                >>=
                  submitAndAwaitTx
            )

        void
          $
            ( PermissionedCandidates.mkRemovePermissionedCandidatesLookupsAndConstraints
                sidechainParams
                >>=
                  submitAndAwaitTx
            )

        ( void
            $
              ( PermissionedCandidates.mkRemovePermissionedCandidatesLookupsAndConstraints
                  sidechainParams
                  >>=
                    submitAndAwaitTx
              )
        ) # fails
