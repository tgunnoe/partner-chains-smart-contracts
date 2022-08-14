{-# LANGUAGE NamedFieldPuns #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

module Test.TrustlessSidechain.Integration (test) where

import Cardano.Crypto.Wallet qualified as Wallet
import Control.Arrow qualified as Arrow
import Control.Monad qualified as Monad
import Data.ByteString qualified as ByteString
import Data.Functor (void)
import Data.Maybe qualified as Maybe
import Data.Text (Text)
import Ledger (getCardanoTxId)
import Ledger.Address (PaymentPubKeyHash (PaymentPubKeyHash, unPaymentPubKeyHash))
import Ledger.Address qualified as Address
import Ledger.Crypto (PubKey, PubKeyHash (PubKeyHash, getPubKeyHash), Signature (getSignature))
import Ledger.Crypto qualified as Crypto
import Plutus.Contract (Contract, awaitTxConfirmed, ownPaymentPubKeyHash, utxosAt)
import PlutusTx.Prelude
import Test.Plutip.Contract (assertExecution, initAda, withContract, withContractAs)
import Test.Plutip.Internal.Types qualified as PlutipInternal
import Test.Plutip.LocalCluster (withCluster)
import Test.Plutip.Predicate (shouldFail, shouldSucceed)
import Test.Tasty (TestTree)
import TrustlessSidechain.MerkleTree (RootHash (unRootHash))
import TrustlessSidechain.MerkleTree qualified as MerkleTree
import TrustlessSidechain.OffChain.CommitteeCandidateValidator qualified as CommitteeCandidateValidator
import TrustlessSidechain.OffChain.FUELMintingPolicy qualified as FUELMintingPolicy
import TrustlessSidechain.OffChain.MPTRootTokenMintingPolicy qualified as MPTRootTokenMintingPolicy
import TrustlessSidechain.OffChain.Schema (TrustlessSidechainSchema)
import TrustlessSidechain.OffChain.Types (
  BurnParams (BurnParams),
  DeregisterParams (DeregisterParams),
  GenesisCommitteeHashParams (GenesisCommitteeHashParams),
  MintParams (MintParams, amount, index, merkleProof, recipient, sidechainEpoch),
  RegisterParams (RegisterParams),
  SaveRootParams (SaveRootParams, committeePubKeys, merkleRoot, signatures, threshold),
  SidechainParams (SidechainParams, chainId, genesisHash, genesisMint),
  UpdateCommitteeHashParams (UpdateCommitteeHashParams),
 )
import TrustlessSidechain.OffChain.Types qualified as OffChainTypes
import TrustlessSidechain.OffChain.UpdateCommitteeHash qualified as UpdateCommitteeHash
import TrustlessSidechain.OnChain.CommitteeCandidateValidator (
  BlockProducerRegistrationMsg (BlockProducerRegistrationMsg),
  serialiseBprm,
 )
import TrustlessSidechain.OnChain.MPTRootTokenMintingPolicy qualified as MPTRootTokenMintingPolicy
import TrustlessSidechain.OnChain.Types (
  MerkleTreeEntry (MerkleTreeEntry, mteAmount, mteIndex, mteRecipient, mteSidechainEpoch),
 )
import TrustlessSidechain.OnChain.UpdateCommitteeHash qualified as UpdateCommitteeHash
import Prelude qualified

sidechainParams :: SidechainParams
sidechainParams =
  SidechainParams
    { chainId = ""
    , genesisHash = ""
    , genesisMint = Nothing
    }

spoPrivKey :: Wallet.XPrv
spoPrivKey = Crypto.generateFromSeed' $ ByteString.replicate 32 123

sidechainPrivKey :: Wallet.XPrv
sidechainPrivKey = Crypto.generateFromSeed' $ ByteString.replicate 32 111

spoPubKey :: PubKey
spoPubKey = Crypto.toPublicKey spoPrivKey

{- | 'saveMerkleRootEntries' is a thin wrapper around
 'MPTRootTokenMintingPolicy.saveRoot' to reduce boilerplate when making tests
 regarding the FUELMintingPolicy.

 To use this, you need to apply the generate the committee first. The
 committee can be generated by the following code:
 > cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. cmtLen]
 > cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys
 > cmt = zip cmtPrvKeys cmtPubKeys
 or as a one liner
 > cmt =  map (id Prelude.&&& Crypto.toPublicKey Prelude.<<< Crypto.generateFromSeed' Prelude.<<< ByteString.replicate 32) [1 .. cmtLen]
-}
saveMerkleRootEntries :: SidechainParams -> [(Wallet.XPrv, PubKey)] -> [MerkleTreeEntry] -> Contract () TrustlessSidechainSchema Text [MintParams]
saveMerkleRootEntries sc cmt entries = do
  -- Create a committee:
  let cmtPrvKeys :: [Wallet.XPrv]
      cmtPubKeys :: [PubKey]

      (cmtPrvKeys, cmtPubKeys) = Prelude.unzip cmt

      cmtLen = Prelude.length cmt

      mt = MerkleTree.fromList $ map MPTRootTokenMintingPolicy.serialiseMte entries
      rh = unRootHash $ MerkleTree.rootHash mt

      mintparams =
        map
          ( \mte ->
              MintParams
                { amount = mteAmount mte
                , recipient = PaymentPubKeyHash $ PubKeyHash $ mteRecipient mte
                , merkleProof = Maybe.fromJust $ MerkleTree.lookupMp (MPTRootTokenMintingPolicy.serialiseMte mte) mt
                , sidechainParams = sc
                , index = mteIndex mte
                , sidechainEpoch = mteSidechainEpoch mte
                }
          )
          entries

  MPTRootTokenMintingPolicy.saveRoot
    SaveRootParams
      { sidechainParams = sc
      , merkleRoot = rh
      , signatures = sort $ map (getSignature . Crypto.sign' rh) cmtPrvKeys
      , threshold = (2 * Prelude.fromIntegral cmtLen - 1) `Prelude.div` 3 + 1
      , committeePubKeys = cmtPubKeys
      }
    >>= awaitTxConfirmed . getCardanoTxId

  return mintparams

-- | 'test' is the suite of tests.
test :: TestTree
test =
  withCluster
    "Plutip integration test"
    [ assertExecution
        "CommitteeCandidateValidator.register"
        (initAda [100] Prelude.<> initAda [1])
        ( withContract $
            const
              ( do
                  oref <- CommitteeCandidateValidator.getInputUtxo
                  let sidechainPubKey = ""
                      msg =
                        serialiseBprm $
                          BlockProducerRegistrationMsg sidechainParams sidechainPubKey oref
                      spoSig = Crypto.sign' msg spoPrivKey
                      sidechainSig = Crypto.sign' msg sidechainPrivKey
                  CommitteeCandidateValidator.register
                    (RegisterParams sidechainParams spoPubKey sidechainPubKey spoSig sidechainSig oref)
              )
        )
        [shouldSucceed]
    , assertExecution
        "CommitteeCandidateValidator.deregister"
        (initAda [100])
        ( withContract $
            const
              ( do
                  oref <- CommitteeCandidateValidator.getInputUtxo
                  let sidechainPubKey = ""
                      msg =
                        serialiseBprm $
                          BlockProducerRegistrationMsg sidechainParams sidechainPubKey oref
                      spoSig = Crypto.sign' msg spoPrivKey
                      sidechainSig = Crypto.sign' msg sidechainPrivKey
                  regTx <-
                    CommitteeCandidateValidator.register
                      (RegisterParams sidechainParams spoPubKey sidechainPubKey spoSig sidechainSig oref)

                  awaitTxConfirmed (getCardanoTxId regTx)

                  deregTx <-
                    CommitteeCandidateValidator.deregister
                      (DeregisterParams sidechainParams spoPubKey)

                  awaitTxConfirmed (getCardanoTxId deregTx)
              )
        )
        [shouldSucceed]
    , assertExecution
        "FUELMintingPolicy.burn"
        (initAda [100, 100, 100, 100])
        ( withContract $
            const $ do
              h <- ownPaymentPubKeyHash

              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 2
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash h
                      , mteSidechainEpoch = 1
                      }

                  mte1 =
                    MerkleTreeEntry
                      { mteIndex = 1
                      , mteAmount = 2
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash h
                      , mteSidechainEpoch = 1
                      }
              mintparams <- saveMerkleRootEntries sidechainParams cmt [mte0, mte1]

              traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mint) mintparams

              FUELMintingPolicy.burn
                BurnParams {amount = -4, recipient = "", sidechainParams}
                >>= awaitTxConfirmed . getCardanoTxId
        )
        [shouldSucceed]
    , assertExecution
        "FUELMintingPolicy.burnOneshotMint"
        -- making this test case work is a bit convuluated because sometimes
        -- the constraint solver for building the transaction would spend the
        -- distinguished utxo when saving the root parameters.
        (initAda [100, 100, 100] Prelude.<> initAda [200, 200, 200]) -- mint, fee, collateral
        ( do
            PlutipInternal.ExecutionResult (Right ((_utxo, utxos, scpOS), _)) _ _ <- withContractAs 0 $
              const $ do
                h <- ownPaymentPubKeyHash

                utxo <- CommitteeCandidateValidator.getInputUtxo
                utxos <- utxosAt (Address.pubKeyHashAddress h Nothing)

                let scpOS = sidechainParams {genesisMint = Just utxo}

                return (utxo, utxos, scpOS)

            PlutipInternal.ExecutionResult (Right (mintparams, _)) _ _ <- withContractAs 1 $ \[pkh0] -> do
              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 2
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash pkh0
                      , mteSidechainEpoch = 1
                      }
              saveMerkleRootEntries scpOS cmt [mte0]

            withContractAs 0 $
              const $ do
                traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mintWithUtxo (Just utxos)) mintparams

                FUELMintingPolicy.burn $ BurnParams (-2) "" scpOS
        )
        [shouldSucceed]
    , assertExecution
        "FUELMintingPolicy.burnOneshot double Mint"
        (initAda [100, 100, 100] Prelude.<> initAda [200, 200, 200]) -- mint, fee, collateral
        ( do
            PlutipInternal.ExecutionResult (Right ((_utxo, utxos, scpOS), _)) _ _ <- withContractAs 0 $
              const $ do
                h <- ownPaymentPubKeyHash

                utxo <- CommitteeCandidateValidator.getInputUtxo
                utxos <- utxosAt (Address.pubKeyHashAddress h Nothing)

                let scpOS = sidechainParams {genesisMint = Just utxo}

                return (utxo, utxos, scpOS)

            PlutipInternal.ExecutionResult (Right (mintparams, _)) _ _ <- withContractAs 1 $ \[pkh0] -> do
              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 2
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash pkh0
                      , mteSidechainEpoch = 1
                      }
              saveMerkleRootEntries scpOS cmt [mte0]

            withContractAs 0 $
              const $ do
                traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mintWithUtxo (Just utxos)) mintparams
                traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mintWithUtxo (Just utxos)) mintparams
        )
        [shouldFail]
    , assertExecution
        "FUELMintingPolicy.mint"
        (initAda [10, 10, 10]) -- mint, fee
        ( withContract $
            const $ do
              h <- ownPaymentPubKeyHash

              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 1
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash h
                      , mteSidechainEpoch = 1
                      }

                  mte1 =
                    MerkleTreeEntry
                      { mteIndex = 1
                      , mteAmount = 1
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash h
                      , mteSidechainEpoch = 1
                      }
              mintparams <- saveMerkleRootEntries sidechainParams cmt [mte0, mte1]

              traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mint) mintparams
        )
        [shouldSucceed]
    , assertExecution
        "FUELMintingPolicy.mint FUEL to other"
        (initAda [3, 3, 3] Prelude.<> initAda [2, 2, 2]) -- mint, fee, ??? <> collateral
        ( do
            -- let the first wallet @[3,3,3]@ save the root entries, which mints
            -- to someone the second wallet @[2,2,2]@
            PlutipInternal.ExecutionResult (Right (mintparams, _)) _ _ <- withContract $ \[pkh1] -> do
              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 1
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash pkh1
                      , mteSidechainEpoch = 1
                      }
              saveMerkleRootEntries sidechainParams cmt [mte0]

            -- Then, let the second wallet @[2,2,2]@ claim the mint; and burn it immediately
            withContractAs 1 $
              const $ do
                traverse_ (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mint) mintparams
                FUELMintingPolicy.burn
                  BurnParams {amount = -1, recipient = "", sidechainParams}
                  >>= awaitTxConfirmed . getCardanoTxId
        )
        [shouldSucceed]
    , assertExecution
        "FUELMintingPolicy.burn unowned FUEL"
        (initAda [3, 3, 3] Prelude.<> initAda [2, 2, 2])
        ( do
            -- let the first wallet @[3,3,3]@ save the root entries, which mints
            -- to someone the second wallet @[2,2,2]@
            PlutipInternal.ExecutionResult (Right (mintparams, _)) _ _ <- withContract $ \[pkh1] -> do
              -- Create a committee:
              let cmt :: [(Wallet.XPrv, PubKey)]
                  cmt = map (id Arrow.&&& Crypto.toPublicKey Arrow.<<< Crypto.generateFromSeed' Arrow.<<< ByteString.replicate 32) [1 .. 10]

              -- Create the merkle tree / proof
              let mte0 =
                    MerkleTreeEntry
                      { mteIndex = 0
                      , mteAmount = 1
                      , mteRecipient = getPubKeyHash $ unPaymentPubKeyHash pkh1
                      , mteSidechainEpoch = 1
                      }
              saveMerkleRootEntries sidechainParams cmt [mte0]

            -- Then, let the second wallet @[2,2,2]@ claim the mint
            void $
              withContractAs 1 $
                const $ do
                  traverse (awaitTxConfirmed . getCardanoTxId Monad.<=< FUELMintingPolicy.mint) mintparams

            -- Then, let the first wallet try to burn the second wallet's FUEL
            withContractAs 0 $
              const $ do
                FUELMintingPolicy.burn
                  BurnParams {amount = -1, recipient = "", sidechainParams}
                  >>= awaitTxConfirmed . getCardanoTxId
        )
        [shouldFail]
    , assertExecution
        "UpdateCommitteeHash.genesisCommitteeHash"
        (initAda [2, 2])
        ( withContract $ \[] -> do
            -- create a committee:
            let cmtPrvKeys :: [Wallet.XPrv]
                cmtPubKeys :: [PubKey]

                cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. 10]
                cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys

            -- Executingthe endpoint:
            h <- ownPaymentPubKeyHash
            let addr = Address.pubKeyHashAddress h Nothing
                tokenName = "Update committee hash test"
                gch =
                  GenesisCommitteeHashParams
                    { genesisCommitteePubKeys = cmtPubKeys
                    , genesisAddress = addr
                    , genesisToken = tokenName
                    }

            UpdateCommitteeHash.genesisCommitteeHash gch
        )
        [shouldSucceed]
    , assertExecution
        "UpdateCommitteeHash.genesisCommitteeHash followed by UpdateCommitteeHash.updateCommitteeHash on same wallet"
        (initAda [3, 2])
        ( do
            -- Creating the committees:
            let cmtPrvKeys :: [Wallet.XPrv]
                cmtPubKeys :: [PubKey]

                cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. 100]
                cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys

            let nCmtPrvKeys :: [Wallet.XPrv]
                nCmtPubKeys :: [PubKey]

                nCmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [101 .. 200]
                nCmtPubKeys = map Crypto.toPublicKey nCmtPrvKeys

            withContract $ \_ -> do
              -- Executing the genesis transaction endpoint [more or less
              -- duplicated code from the previous test case]
              h <- ownPaymentPubKeyHash
              let addr = Address.pubKeyHashAddress h Nothing
                  tokenName = "Update committee hash test"
                  gch =
                    GenesisCommitteeHashParams
                      { genesisCommitteePubKeys = cmtPubKeys
                      , genesisAddress = addr
                      , genesisToken = tokenName
                      }

              nft <- UpdateCommitteeHash.genesisCommitteeHash gch

              -- updating the committee hash
              let nCommitteeHash = UpdateCommitteeHash.aggregateKeys nCmtPubKeys
                  sig = UpdateCommitteeHash.multiSign nCommitteeHash cmtPrvKeys

                  uchp =
                    UpdateCommitteeHashParams
                      { OffChainTypes.newCommitteePubKeys = nCmtPubKeys
                      , OffChainTypes.token = nft
                      , OffChainTypes.committeePubKeys = cmtPubKeys
                      , OffChainTypes.committeeSignatures = [sig]
                      }
              UpdateCommitteeHash.updateCommitteeHash uchp
        )
        [shouldSucceed]
    , assertExecution
        "UpdateCommitteeHash.genesisCommitteeHash followed by UpdateCommitteeHash.updateCommitteeHash on different wallet"
        (initAda [3, 2] Prelude.<> initAda [3, 2])
        ( do
            -- Creating the committees:
            let cmtPrvKeys :: [Wallet.XPrv]
                cmtPubKeys :: [PubKey]

                cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. 100]
                cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys

            let nCmtPrvKeys :: [Wallet.XPrv]
                nCmtPubKeys :: [PubKey]

                nCmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [101 .. 200]
                nCmtPubKeys = map Crypto.toPublicKey nCmtPrvKeys

            -- Executing the genesis transaction endpoint [more or less
            -- duplicated code from the previous test case]
            PlutipInternal.ExecutionResult (Right (nft, _)) _ _ <- withContract $ \_ -> do
              h <- ownPaymentPubKeyHash
              let addr = Address.pubKeyHashAddress h Nothing
                  tokenName = "Update committee hash test"
                  gch =
                    GenesisCommitteeHashParams
                      { genesisCommitteePubKeys = cmtPubKeys
                      , genesisAddress = addr
                      , genesisToken = tokenName
                      }

              UpdateCommitteeHash.genesisCommitteeHash gch

            -- Let another wallet update the committee hash.
            withContractAs 1 $ \_ -> do
              let nCommitteeHash = UpdateCommitteeHash.aggregateKeys nCmtPubKeys
                  sig = UpdateCommitteeHash.multiSign nCommitteeHash cmtPrvKeys

                  uchp =
                    UpdateCommitteeHashParams
                      { OffChainTypes.newCommitteePubKeys = nCmtPubKeys
                      , OffChainTypes.token = nft
                      , OffChainTypes.committeePubKeys = cmtPubKeys
                      , OffChainTypes.committeeSignatures = [sig]
                      }
              UpdateCommitteeHash.updateCommitteeHash uchp
        )
        [shouldSucceed]
    , assertExecution
        "UpdateCommitteeHash.genesisCommitteeHash followed by UpdateCommitteeHash.updateCommitteeHash on same wallet with the wrong committee"
        (initAda [3, 2])
        ( do
            -- Creating the committees:
            let cmtPrvKeys :: [Wallet.XPrv]
                cmtPubKeys :: [PubKey]

                cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. 100]
                cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys

            let nCmtPrvKeys :: [Wallet.XPrv]
                nCmtPubKeys :: [PubKey]

                nCmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [101 .. 200]
                nCmtPubKeys = map Crypto.toPublicKey nCmtPrvKeys

            withContract $ \_ -> do
              -- Executing the genesis transaction endpoint [more or less
              -- duplicated code from the previous test case]
              h <- ownPaymentPubKeyHash
              let addr = Address.pubKeyHashAddress h Nothing
                  tokenName = "Update committee hash test"
                  gch =
                    GenesisCommitteeHashParams
                      { genesisCommitteePubKeys = cmtPubKeys
                      , genesisAddress = addr
                      , genesisToken = tokenName
                      }

              nft <- UpdateCommitteeHash.genesisCommitteeHash gch

              -- updating the committee hash
              let nCommitteeHash = UpdateCommitteeHash.aggregateKeys nCmtPubKeys
                  sig = UpdateCommitteeHash.multiSign nCommitteeHash cmtPrvKeys

                  uchp =
                    UpdateCommitteeHashParams
                      { OffChainTypes.newCommitteePubKeys = nCmtPubKeys
                      , OffChainTypes.token = nft
                      , OffChainTypes.committeePubKeys = nCmtPubKeys
                      , OffChainTypes.committeeSignatures = [sig]
                      }
              UpdateCommitteeHash.updateCommitteeHash uchp
        )
        [shouldFail]
    , assertExecution
        "UpdateCommitteeHash.genesisCommitteeHash followed by UpdateCommitteeHash.updateCommitteeHash on different wallet with the wrong committee"
        (initAda [3, 2] Prelude.<> initAda [3, 2])
        ( do
            -- Creating the committees:
            let cmtPrvKeys :: [Wallet.XPrv]
                cmtPubKeys :: [PubKey]

                cmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [1 .. 100]
                cmtPubKeys = map Crypto.toPublicKey cmtPrvKeys

            let nCmtPrvKeys :: [Wallet.XPrv]
                nCmtPubKeys :: [PubKey]

                nCmtPrvKeys = map (Crypto.generateFromSeed' . ByteString.replicate 32) [101 .. 200]
                nCmtPubKeys = map Crypto.toPublicKey nCmtPrvKeys

            -- Executing the genesis transaction endpoint [more or less
            -- duplicated code from the previous test case]
            PlutipInternal.ExecutionResult (Right (nft, _)) _ _ <- withContract $ \_ -> do
              h <- ownPaymentPubKeyHash
              let addr = Address.pubKeyHashAddress h Nothing
                  tokenName = "Update committee hash test"
                  gch =
                    GenesisCommitteeHashParams
                      { genesisCommitteePubKeys = cmtPubKeys
                      , genesisAddress = addr
                      , genesisToken = tokenName
                      }

              UpdateCommitteeHash.genesisCommitteeHash gch

            -- Let another wallet update the committee hash.
            withContractAs 1 $ \_ -> do
              let nCommitteeHash = UpdateCommitteeHash.aggregateKeys nCmtPubKeys
                  sig = UpdateCommitteeHash.multiSign nCommitteeHash cmtPrvKeys

                  uchp =
                    UpdateCommitteeHashParams
                      { newCommitteePubKeys = nCmtPubKeys
                      , token = nft
                      , committeePubKeys = nCmtPubKeys
                      , committeeSignatures = [sig]
                      }
              UpdateCommitteeHash.updateCommitteeHash uchp
        )
        [shouldFail]
    ]
