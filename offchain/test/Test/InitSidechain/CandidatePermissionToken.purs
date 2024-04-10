module Test.InitSidechain.CandidatePermissionToken where

import Contract.Prelude

import Contract.Log as Log
import Contract.Wallet as Wallet
import Data.BigInt (fromInt)
import Data.BigInt as BigInt
import Mote.Monad as Mote.Monad
import Test.InitSidechain.Utils (failMsg)
import Test.PlutipTest (PlutipTest)
import Test.PlutipTest as Test.PlutipTest
import Test.Unit.Assert (assert)
import Test.Utils (WrappedTests, plutipGroup)
import Test.Utils as Test.Utils
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds(ATMSPlainEcdsaSecp256k1)
  )
import TrustlessSidechain.Effects.Contract (liftContract)
import TrustlessSidechain.Effects.Run (withUnliftApp)
import TrustlessSidechain.Effects.Util (fromMaybeThrow) as Effect
import TrustlessSidechain.Error (OffchainError(GenericInternalError))
import TrustlessSidechain.Governance as Governance
import TrustlessSidechain.InitSidechain.CandidatePermissionToken as InitCandidatePermission
import TrustlessSidechain.InitSidechain.TokensMint as InitMint
import TrustlessSidechain.SidechainParams as SidechainParams
import TrustlessSidechain.Utils.Address (getOwnPaymentPubKeyHash)

-- | `tests` aggregates all the tests together in one convenient function
tests ∷ WrappedTests
tests = plutipGroup "Initialising the checkpoint mechanism" $ do
  -- InitCandidatePermissionToken endpoint
  testInitCandidatePermissionToken
  testInitCandidatePermissionTokenIdempotent

-- | Test `initCandidatePermissionToken` having run `initTokensMint`, expecting
-- | no failure
-- Note that this test isn't great. If we want to keep the
-- `initCandidatePermissionToken` machinery, we should improve this test.
testInitCandidatePermissionToken ∷ PlutipTest
testInitCandidatePermissionToken =
  Mote.Monad.test "Calling `InitCandidatePermissionToken`"
    $ Test.PlutipTest.mkPlutipConfigTest
        [ BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        ]
    $ \alice → do
        withUnliftApp (Wallet.withKeyWallet alice)
          do
            liftContract $ Log.logInfo'
              "InitSidechain 'testInitCandidatePermissionToken'"
            genesisUtxo ← Test.Utils.getOwnTransactionInput
            initGovernanceAuthority ← (Governance.mkGovernanceAuthority <<< unwrap)
              <$> getOwnPaymentPubKeyHash
            let
              version = 1
              initCandidatePermissionTokenMintInfo = Just
                { candidatePermissionTokenAmount: fromInt 1 }
              initATMSKind = ATMSPlainEcdsaSecp256k1
              sidechainParams = SidechainParams.SidechainParams
                { chainId: BigInt.fromInt 9
                , genesisUtxo: genesisUtxo
                , thresholdNumerator: BigInt.fromInt 2
                , thresholdDenominator: BigInt.fromInt 3
                , governanceAuthority: initGovernanceAuthority
                }

            void $ InitCandidatePermission.initCandidatePermissionToken
              sidechainParams
              initCandidatePermissionTokenMintInfo
              initATMSKind
              version

-- | Test running `initCandidatePermissionToken` twice, having run
-- | `initTokensMint`, expecting idempotency
testInitCandidatePermissionTokenIdempotent ∷ PlutipTest
testInitCandidatePermissionTokenIdempotent =
  Mote.Monad.test
    "Calling `InitCandidatePermissionToken` twice, expecting idempotency"
    $ Test.PlutipTest.mkPlutipConfigTest
        [ BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        , BigInt.fromInt 50_000_000
        ]
    $ \alice → do
        withUnliftApp (Wallet.withKeyWallet alice)
          do
            liftContract $ Log.logInfo'
              "InitSidechain 'testInitCandidatePermissionTokenIdempotent'"
            genesisUtxo ← Test.Utils.getOwnTransactionInput
            initGovernanceAuthority ← (Governance.mkGovernanceAuthority <<< unwrap)
              <$> getOwnPaymentPubKeyHash
            let
              version = 1
              initCandidatePermissionTokenMintInfo = Just
                { candidatePermissionTokenAmount: fromInt 1 }
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
            void $ InitCandidatePermission.initCandidatePermissionToken
              sidechainParams
              initCandidatePermissionTokenMintInfo
              initATMSKind
              version

            -- Then do it again
            res ← InitCandidatePermission.initCandidatePermissionToken
              sidechainParams
              initCandidatePermissionTokenMintInfo
              initATMSKind
              version

            Effect.fromMaybeThrow (GenericInternalError "Unreachable")
              $ map Just
              $ liftAff
              $ assert (failMsg "Nothing" res) (isNothing res)
