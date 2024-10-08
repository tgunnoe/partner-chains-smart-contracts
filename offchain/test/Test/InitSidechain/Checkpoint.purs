module Test.InitSidechain.Checkpoint
  ( tests
  ) where

import Contract.Prelude

import Cardano.Types.BigNum as BigNum
import Contract.Log as Log
import Contract.Prim.ByteArray as ByteArray
import Contract.Wallet as Wallet
import Data.List (head)
import JS.BigInt as BigInt
import Mote.Monad as Mote.Monad
import Test.InitSidechain.Utils (expectedInitTokens, failMsg, unorderedEq)
import Test.TestnetTest (TestnetTest)
import Test.TestnetTest as Test.TestnetTest
import Test.Unit.Assert (assert)
import Test.Utils (WrappedTests, testnetGroup)
import Test.Utils as Test.Utils
import TrustlessSidechain.CandidatePermissionToken as CandidatePermissionToken
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds(ATMSPlainEcdsaSecp256k1)
  )
import TrustlessSidechain.CommitteeOraclePolicy as CommitteeOraclePolicy
import TrustlessSidechain.DistributedSet as DistributedSet
import TrustlessSidechain.Effects.Contract (liftContract)
import TrustlessSidechain.Effects.Run (withUnliftApp)
import TrustlessSidechain.Effects.Util (fromMaybeThrow) as Effect
import TrustlessSidechain.Error (OffchainError(GenericInternalError))
import TrustlessSidechain.Governance.Admin as Governance
import TrustlessSidechain.InitSidechain.Checkpoint as InitCheckpoint
import TrustlessSidechain.InitSidechain.Init as Init
import TrustlessSidechain.InitSidechain.TokensMint as InitMint
import TrustlessSidechain.SidechainParams as SidechainParams
import TrustlessSidechain.Utils.Address (getOwnPaymentPubKeyHash)
import TrustlessSidechain.Versioning
  ( getActualVersionedPoliciesAndValidators
  , getExpectedVersionedPoliciesAndValidators
  ) as Versioning
import TrustlessSidechain.Versioning.ScriptId (ScriptId(..))

-- | `tests` aggregates all the tests together in one convenient function
tests ∷ WrappedTests
tests = testnetGroup "Initialising the checkpoint mechanism" $ do
  -- InitCheckpoint endpoint
  testInitCheckpointUninitialised
  testInitCheckpoint
  testInitCheckpointIdempotent

-- | Test `InitCheckpoint` without having run `initTokensMint`, expecting failure
testInitCheckpointUninitialised ∷ TestnetTest
testInitCheckpointUninitialised =
  Mote.Monad.test "Calling `InitCheckpoint` with no init token"
    $ Test.TestnetTest.mkTestnetConfigTest
        [ BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        ]
    $ \alice → do
        -- | Test succeeds if action fails.
        withUnliftApp (Test.Utils.fails <<< Wallet.withKeyWallet alice)
          do
            liftContract $ Log.logInfo'
              "InitSidechain 'testInitCheckpointUninitialised'"
            genesisUtxo ← Test.Utils.getOwnTransactionInput

            initGovernanceAuthority ← Governance.mkGovernanceAuthority
              <$> getOwnPaymentPubKeyHash
            let
              initGenesisHash = ByteArray.hexToByteArrayUnsafe "abababababa"
              initATMSKind = ATMSPlainEcdsaSecp256k1
              sidechainParams = SidechainParams.SidechainParams
                { chainId: BigInt.fromInt 9
                , genesisUtxo: genesisUtxo
                , thresholdNumerator: BigInt.fromInt 2
                , thresholdDenominator: BigInt.fromInt 3
                , governanceAuthority: initGovernanceAuthority
                }

            void $ InitCheckpoint.initCheckpoint sidechainParams
              initGenesisHash
              initATMSKind
              1

-- | Test `InitCheckpoint` having run `initTokensMint`, expecting success and for the
-- | `checkpointInitToken` to be spent
testInitCheckpoint ∷ TestnetTest
testInitCheckpoint =
  Mote.Monad.test "Calling `InitCheckpoint`"
    $ Test.TestnetTest.mkTestnetConfigTest
        [ BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        ]
    $ \alice → do
        withUnliftApp (Wallet.withKeyWallet alice)
          do
            liftContract $ Log.logInfo'
              "InitSidechain 'testInitCheckpoint'"
            genesisUtxo ← Test.Utils.getOwnTransactionInput

            initGovernanceAuthority ← Governance.mkGovernanceAuthority
              <$> getOwnPaymentPubKeyHash
            let
              version = 1
              initGenesisHash = ByteArray.hexToByteArrayUnsafe "abababababa"
              initATMSKind = ATMSPlainEcdsaSecp256k1
              sidechainParams = SidechainParams.SidechainParams
                { chainId: BigInt.fromInt 9
                , genesisUtxo: genesisUtxo
                , thresholdNumerator: BigInt.fromInt 2
                , thresholdDenominator: BigInt.fromInt 3
                , governanceAuthority: initGovernanceAuthority
                }

            void $ InitMint.initTokensMint sidechainParams
              initATMSKind
              version

            void $ InitCheckpoint.initCheckpoint sidechainParams
              initGenesisHash
              initATMSKind
              version

            -- For computing the number of versionOracle init tokens
            { versionedPolicies, versionedValidators } ←
              Versioning.getExpectedVersionedPoliciesAndValidators
                { atmsKind: initATMSKind
                , sidechainParams
                }
                version

            let
              expectedTokens = expectedInitTokens 1 versionedPolicies
                versionedValidators
                [ DistributedSet.dsInitTokenName
                , CommitteeOraclePolicy.committeeOracleInitTokenName
                , CandidatePermissionToken.candidatePermissionInitTokenName
                ]

            -- Get the tokens just created
            { initTokenStatusData: resTokens } ← Init.getInitTokenStatus
              sidechainParams

            { versionedValidators: validatorsRes } ←
              Versioning.getActualVersionedPoliciesAndValidators
                { atmsKind: initATMSKind
                , sidechainParams
                }
                version

            let
              expectedExistingValidator = Just CheckpointValidator
              actualExistingValidator = head $ map fst validatorsRes

            Effect.fromMaybeThrow (GenericInternalError "Unreachable")
              $ map Just
              $ liftAff
              $
                assert (failMsg expectedTokens resTokens)
                  (unorderedEq expectedTokens resTokens)
              <* assert
                ( failMsg expectedExistingValidator
                    actualExistingValidator
                )
                ( expectedExistingValidator ==
                    actualExistingValidator
                )

-- | Test running `initCheckpoint` twice, having run `initTokensMint`, expecting idempotency
-- | and for the `checkpointInitToken` to be spent
testInitCheckpointIdempotent ∷ TestnetTest
testInitCheckpointIdempotent =
  Mote.Monad.test "Calling `InitCheckpoint` twice, expecting idempotency"
    $ Test.TestnetTest.mkTestnetConfigTest
        [ BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        , BigNum.fromInt 50_000_000
        ]
    $ \alice → do
        withUnliftApp (Wallet.withKeyWallet alice)
          do
            liftContract $ Log.logInfo'
              "InitSidechain 'testInitCheckpointIdempotent'"
            genesisUtxo ← Test.Utils.getOwnTransactionInput

            initGovernanceAuthority ← Governance.mkGovernanceAuthority
              <$> getOwnPaymentPubKeyHash
            let
              version = 1
              initGenesisHash = ByteArray.hexToByteArrayUnsafe "abababababa"
              initATMSKind = ATMSPlainEcdsaSecp256k1
              sidechainParams = SidechainParams.SidechainParams
                { chainId: BigInt.fromInt 9
                , genesisUtxo: genesisUtxo
                , thresholdNumerator: BigInt.fromInt 2
                , thresholdDenominator: BigInt.fromInt 3
                , governanceAuthority: initGovernanceAuthority
                }

            -- Initialise tokens
            void $ InitMint.initTokensMint sidechainParams
              initATMSKind
              version

            -- Initialise checkpoint
            void $ InitCheckpoint.initCheckpoint sidechainParams
              initGenesisHash
              initATMSKind
              version

            -- Then do it again
            { scriptsInitTxIds, tokensInitTxId } ←
              InitCheckpoint.initCheckpoint sidechainParams
                initGenesisHash
                initATMSKind
                version

            -- For computing the number of versionOracle init tokens
            { versionedPolicies, versionedValidators } ←
              Versioning.getExpectedVersionedPoliciesAndValidators
                { atmsKind: initATMSKind
                , sidechainParams
                }
                version

            let
              expectedTokens = expectedInitTokens 1 versionedPolicies
                versionedValidators
                [ DistributedSet.dsInitTokenName
                , CommitteeOraclePolicy.committeeOracleInitTokenName
                , CandidatePermissionToken.candidatePermissionInitTokenName
                ]

            -- Get the tokens just created
            { initTokenStatusData: resTokens } ← Init.getInitTokenStatus
              sidechainParams

            { versionedValidators: validatorsRes } ←
              Versioning.getActualVersionedPoliciesAndValidators
                { atmsKind: initATMSKind
                , sidechainParams
                }
                version

            let
              expectedExistingValidator = Just CheckpointValidator
              actualExistingValidator = head $ map fst validatorsRes

            Effect.fromMaybeThrow (GenericInternalError "Unreachable")
              $ map Just
              $ liftAff
              $
                assert (failMsg expectedTokens resTokens)
                  (unorderedEq expectedTokens resTokens)
              <* assert
                ( failMsg "{ scriptsInitTxIds: [], tokensInitTxId: Nothing }"
                    { scriptsInitTxIds, tokensInitTxId }
                )
                (null scriptsInitTxIds && isNothing tokensInitTxId)
              <* assert
                ( failMsg expectedExistingValidator
                    actualExistingValidator
                )
                ( expectedExistingValidator ==
                    actualExistingValidator
                )
