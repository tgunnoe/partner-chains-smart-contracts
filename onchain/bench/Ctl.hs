{-# LANGUAGE RecordWildCards #-}

{- | "Ctl" defines a monad which allows one to conveniently call CLI ctl
 commands / generate required data.
-}
module Ctl (
  CtlRegistration (..),
  CtlDeregistration (..),
  CtlUpdateCommitteeHash (..),
  CtlSaveRoot (..),
  CtlInitSidechain (..),
  CtlClaim (..),
  CtlCommon (..),
  ctlCommonFlags,
  ctlInitSidechainFlags,
  ctlRegistrationFlags,
  ctlDeregistrationFlags,
  ctlUpdateCommitteeHash,
  ctlSaveRootFlags,
  ctlClaimFlags,
  generateFreshCommittee,
) where

import Cardano.Crypto.DSIGN (Ed25519DSIGN, VerKeyDSIGN)
import Cardano.Crypto.DSIGN.Class (SignKeyDSIGN)
import Control.Monad qualified as Monad
import Control.Monad.IO.Class qualified as IO.Class
import Crypto.Secp256k1 qualified as SECP
import Crypto.Secp256k1 qualified as Secp256k1
import Data.List qualified as List
import Data.String qualified as HString
import Plutus.V2.Ledger.Api (TxOutRef)
import System.IO (FilePath)
import TrustlessSidechain.HaskellPrelude
import TrustlessSidechain.MerkleTree (RootHash, unRootHash)
import TrustlessSidechain.OffChain qualified as OffChain
import TrustlessSidechain.Types (
  BlockProducerRegistrationMsg (
    BlockProducerRegistrationMsg,
    inputUtxo,
    sidechainParams,
    sidechainPubKey
  ),
  CombinedMerkleProof,
  MerkleRootInsertionMessage (
    MerkleRootInsertionMessage,
    merkleRoot,
    previousMerkleRoot,
    sidechainParams
  ),
  SidechainParams (SidechainParams),
  SidechainPubKey,
  UpdateCommitteeHashMessage (UpdateCommitteeHashMessage),
  chainId,
  genesisHash,
  genesisUtxo,
  thresholdDenominator,
  thresholdNumerator,
  uchmNewCommitteePubKeys,
  uchmPreviousMerkleRoot,
  uchmSidechainEpoch,
  uchmSidechainParams,
 )

-- * Various product types to represent the parameters needed for the corresponding ctl command

--  | 'CtlRegistration' provides a wrapper type for the parameters required
--  to register an spo
data CtlRegistration = CtlRegistration
  { crSpoPrivKey :: SignKeyDSIGN Ed25519DSIGN
  , crSidechainPrvKey :: Secp256k1.SecKey
  , crRegistrationUtxo :: TxOutRef
  }

--  | 'CtlDeregistration' provides a wrapper type for the parameters required
--  to deregister an spo
data CtlDeregistration = CtlDeregistration
  { cdrSpoPubKey :: VerKeyDSIGN Ed25519DSIGN
  }

--  | 'CtlUpdateCommitteeHash' provides a wrapper type for the parameters required
--  to update the committee hash
data CtlUpdateCommitteeHash = CtlUpdateCommitteeHash
  { cuchCurrentCommitteePrvKeys :: [Secp256k1.SecKey]
  , cuchNewCommitteePubKeys :: [SidechainPubKey]
  , cuchSidechainEpoch :: Integer
  , cuchPreviousMerkleRoot :: Maybe RootHash
  }

--  | 'CtlSaveRoot' provides a wrapper type for the parameters required
--  to save a merkle root
data CtlSaveRoot = CtlSaveRoot
  { csrMerkleRoot :: RootHash
  , csrCurrentCommitteePrivKeys :: [Secp256k1.SecKey]
  , csrPreviousMerkleRoot :: Maybe RootHash
  }

--  | 'CtlInitSidechain' provides a wrapper type for the parameters required
--  to inialise a sidechain
data CtlInitSidechain = CtlInitSidechain
  { cisInitCommitteePubKeys :: [SidechainPubKey]
  , cisSidechainEpoch :: Integer
  }

--  | 'CtlClaim' provides a wrapper type for the parameters required
--  to claim tokens
newtype CtlClaim = CtlClaim
  { ccCombinedMerkleProof :: CombinedMerkleProof
  }

--  | 'CtlBurn' provides a wrapper type for the parameters required
--  to burn tokens
-- TODO: put this in later.
-- @
-- data CtlBurn = CtlBurn
--   { cbAmount :: Integer
--   , cbRecipient :: BuiltinByteString
--   }
-- @

-- * Functions for generating ctl commands

--

{- $ctlFlags
 These functions provide a means to generate the flags for each CTL command.
 As an example use case, if we wanted to generate the complete CLI command
 for intializing the Sidechain, we'd type something like:
 @
 Data.List.intercalate " "
  $ concat
      [ [ "nix run .#sidechain-main-cli --" ]
      , ctlInitSidechainFlags (CtlInitSidechain{ {\- initalize this.. -\} })
      , ctlCommonFlags (CtlCommon{ {\- initalize this.. -\} })
      ]
 @
-}

--  | 'CtlCommon' provides the data of required flags for every CTL command.
data CtlCommon = CtlCommon
  { -- | 'ccSigningKeyFile' is the 'FilePath' to the signing key
    ccSigningKeyFile :: FilePath
  , -- | 'ccSidechainParams' are the sidechain parameters
    ccSidechainParams :: SidechainParams
  }

{- | 'ctlCommonFlags' generates the CLI flags that corresponds to sidechain
 parameters
-}
ctlCommonFlags :: CtlCommon -> [HString.String]
ctlCommonFlags CtlCommon {..} =
  let SidechainParams {..} = ccSidechainParams
   in fmap
        List.unwords
        [ ["--payment-signing-key-file", ccSigningKeyFile]
        , ["--genesis-committee-hash-utxo", OffChain.showTxOutRef genesisUtxo]
        , ["--sidechain-id", show chainId]
        , ["--sidechain-genesis-hash", OffChain.showGenesisHash genesisHash]
        , ["--threshold", OffChain.showThreshold thresholdNumerator thresholdDenominator]
        ]

{- | 'ctlInitSidechainFlags' generates the CLI flags that corresponds to init
 sidechain command
-}
ctlInitSidechainFlags :: CtlInitSidechain -> [HString.String]
ctlInitSidechainFlags CtlInitSidechain {..} =
  fmap List.unwords $
    (<>)
      [ ["init"]
      , ["--sidechain-epoch", show cisSidechainEpoch]
      ]
      $ flip fmap cisInitCommitteePubKeys $
        \pubKey ->
          ["--committee-pub-key", OffChain.showScPubKey pubKey]

{- | 'ctlRegistrationFlags' generates the CLI flags that corresponds to register
 command
-}
ctlRegistrationFlags :: SidechainParams -> CtlRegistration -> [HString.String]
ctlRegistrationFlags scParams CtlRegistration {..} =
  let msg =
        BlockProducerRegistrationMsg
          { sidechainParams = scParams
          , sidechainPubKey = OffChain.toSidechainPubKey crSidechainPrvKey
          , inputUtxo = crRegistrationUtxo
          }
   in fmap
        List.unwords
        [ ["register"]
        , ["--sidechain-public-key", OffChain.showScPubKey $ OffChain.toSidechainPubKey crSidechainPrvKey]
        , ["--spo-signature", OffChain.showSig $ OffChain.signWithSPOKey crSpoPrivKey msg]
        , ["--sidechain-signature", OffChain.showSig $ OffChain.signWithSidechainKey crSidechainPrvKey msg]
        , ["--registration-utxo", OffChain.showTxOutRef crRegistrationUtxo]
        ]

{- | 'ctlDeregistrationFlags' generates the CLI flags that corresponds to deregister
 command
-}
ctlDeregistrationFlags :: CtlDeregistration -> [HString.String]
ctlDeregistrationFlags CtlDeregistration {..} =
  fmap
    List.unwords
    [ ["deregister"]
    , ["--spo-public-key", OffChain.showPubKey $ OffChain.vKeyToSpoPubKey cdrSpoPubKey]
    ]

{- | 'ctlUpdateCommitteeHash' generates the CLI flags that corresponds to the
 update committee hash command
-}
ctlUpdateCommitteeHash :: SidechainParams -> CtlUpdateCommitteeHash -> [HString.String]
ctlUpdateCommitteeHash scParams CtlUpdateCommitteeHash {..} =
  let msg =
        UpdateCommitteeHashMessage
          { uchmSidechainParams = scParams
          , uchmNewCommitteePubKeys = List.sort cuchNewCommitteePubKeys
          , uchmPreviousMerkleRoot = unRootHash <$> cuchPreviousMerkleRoot
          , uchmSidechainEpoch = cuchSidechainEpoch
          }
      currentCommitteePubKeysAndSigsFlags =
        fmap
          ( \sidechainPrvKey ->
              [ "--committee-pub-key-and-signature"
              , OffChain.showScPubKeyAndSig
                  (OffChain.toSidechainPubKey sidechainPrvKey)
                  (OffChain.signWithSidechainKey sidechainPrvKey msg)
              ]
          )
          cuchCurrentCommitteePrvKeys
      newCommitteeFlags =
        fmap
          ( \pubKey ->
              [ "--new-committee-pub-key"
              , OffChain.showScPubKey pubKey
              ]
          )
          cuchNewCommitteePubKeys
   in fmap List.unwords $
        [["committee-hash"]]
          <> currentCommitteePubKeysAndSigsFlags
          <> newCommitteeFlags
          <> [["--sidechain-epoch", show cuchSidechainEpoch]]
          <> maybe
            []
            (\bs -> [["--previous-merkle-root", OffChain.showBuiltinBS $ unRootHash bs]])
            cuchPreviousMerkleRoot

{- | 'ctlSaveRootFlags' generates the CLI flags that corresponds to the
 save root command
-}
ctlSaveRootFlags :: SidechainParams -> CtlSaveRoot -> [HString.String]
ctlSaveRootFlags scParams CtlSaveRoot {..} =
  let msg =
        MerkleRootInsertionMessage
          { sidechainParams = scParams
          , merkleRoot = unRootHash csrMerkleRoot
          , previousMerkleRoot = fmap unRootHash csrPreviousMerkleRoot
          }
      currentCommitteePubKeysAndSigsFlags =
        fmap
          ( \sidechainPrvKey ->
              [ "--committee-pub-key-and-signature"
              , OffChain.showScPubKeyAndSig
                  (OffChain.toSidechainPubKey sidechainPrvKey)
                  (OffChain.signWithSidechainKey sidechainPrvKey msg)
              ]
          )
          csrCurrentCommitteePrivKeys
   in fmap List.unwords $
        [["save-root"]]
          <> currentCommitteePubKeysAndSigsFlags
          <> [["--merkle-root", OffChain.showBuiltinBS $ unRootHash csrMerkleRoot]]
          <> maybe [] (\bs -> [["--previous-merkle-root", OffChain.showBuiltinBS $ unRootHash bs]]) csrPreviousMerkleRoot

{- | 'ctlClaimFlags' generates the CLI flags that corresponds to the
 claim command (minting FUEL)
-}
ctlClaimFlags :: CtlClaim -> [HString.String]
ctlClaimFlags CtlClaim {..} =
  fmap
    List.unwords
    [ ["claim"]
    , ["--combined-proof", OffChain.showCombinedMerkleProof ccCombinedMerkleProof]
    ]

{- | 'ctlBurnFlags' generates the CLI flags that corresponds to the
 claim command (minting FUEL)
 TODO: Put this together later
 @
 ctlBurnFlags :: CtlBurn -> [String]
 ctlBurnFlags CtlBurn{..} =
     map List.unwords
         [ [ "burn" ]
         , [ "--combined-merkle-proof", OffChain.showCombinedMerkleProof ccCombinedMerkleProof]
         ]
 @
-}

-- * Some utility functions

-- | 'generateFreshCommittee' generates a fresh sidechain committee of the given size
generateFreshCommittee :: MonadIO m => Int -> m [(SECP.SecKey, SidechainPubKey)]
generateFreshCommittee n = IO.Class.liftIO $ do
  prvKeys <- Monad.replicateM n OffChain.generateRandomSecpPrivKey
  pure $ fmap (\prvKey -> (prvKey, OffChain.toSidechainPubKey prvKey)) prvKeys
