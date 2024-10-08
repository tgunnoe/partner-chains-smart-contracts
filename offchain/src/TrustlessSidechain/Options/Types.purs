module TrustlessSidechain.Options.Types
  ( InputArgOrFile(..)
  , Config(..)
  , Options(..)
  , RuntimeConfig(..)
  , SidechainEndpointParams(..)
  , TxEndpoint(..)
  , UtilsEndpoint(..)
  ) where

import Contract.Prelude

import Cardano.Types.Asset (Asset)
import Cardano.Types.BigNum (BigNum)
import Cardano.Types.NetworkId (NetworkId)
import Contract.Address (Address)
import Contract.Config (ContractParams, ServerConfig)
import Contract.PlutusData (PlutusData)
import Contract.Prim.ByteArray (ByteArray)
import Contract.Scripts (ValidatorHash)
import Contract.Transaction (TransactionInput)
import Data.List (List)
import Data.List.NonEmpty (NonEmptyList)
import JS.BigInt (BigInt)
import Node.Path (FilePath)
import TrustlessSidechain.CommitteeATMSSchemes.Types (ATMSKinds)
import TrustlessSidechain.CommitteeCandidateValidator
  ( BlockProducerRegistrationMsg
  , StakeOwnership
  )
import TrustlessSidechain.FUELMintingPolicy.V1 (MerkleTreeEntry)
import TrustlessSidechain.GetSidechainAddresses (SidechainAddressesExtra)
import TrustlessSidechain.MerkleRoot.Types (MerkleRootInsertionMessage)
import TrustlessSidechain.MerkleTree (MerkleProof, MerkleTree, RootHash)
import TrustlessSidechain.NativeTokenManagement.Types
  ( ImmutableReserveSettings
  , MutableReserveSettings
  )
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Types (PubKey)
import TrustlessSidechain.UpdateCommitteeHash.Types (UpdateCommitteeHashMessage)
import TrustlessSidechain.Utils.Crypto (EcdsaSecp256k1PrivateKey)
import TrustlessSidechain.Utils.SchnorrSecp256k1 (SchnorrSecp256k1PrivateKey)

-- | `SidechainEndpointParams` is an offchain type for grabbing information
-- | related to the sidechain.
-- | This is essentially `SidechainParams` with a little bit more information.
newtype SidechainEndpointParams = SidechainEndpointParams
  { sidechainParams ∷ SidechainParams
  , atmsKind ∷ ATMSKinds
  }

derive instance Newtype SidechainEndpointParams _

-- | CLI arguments providing an interface to contract endpoints
data Options
  =
    -- | `TxOptions` are the options for endpoints which build / submit a
    -- | transaction to the blockchain.
    -- | In particular, these endpoints need to be in the `Contract` monad
    TxOptions
      { sidechainEndpointParams ∷ SidechainEndpointParams
      , endpoint ∷ TxEndpoint
      , contractParams ∷ ContractParams
      }
  |
    -- | `UtilsOptions` are the options for endpoints for functionality
    -- | related to signing messages such as: creating key pairs, creating
    -- | messages to sign, signing messages, aggregating keys, etc.
    -- | In particular, these endpoints do _not_ need to be in the `Contract`
    -- | monad
    UtilsOptions
      { utilsOptions ∷ UtilsEndpoint
      }
  | CLIVersion

-- | Sidechain configuration file including common parameters.
-- Any parameter can be set `null` requiring a CLI argument instead
type Config =
  { -- | Sidechain parameters (defining the sidechain which we will interact with)
    sidechainParameters ∷
      Maybe
        { chainId ∷ Maybe Int
        , genesisUtxo ∷ Maybe TransactionInput
        , threshold ∷
            Maybe
              { numerator ∷ Int
              , denominator ∷ Int
              }
        , atmsKind ∷ Maybe ATMSKinds
        -- governanceAuthority should really be a PubKeyHash but there's no
        -- (easy) way of pulling a dummy PubKeyHash value out of thin air in
        -- TrustlessSidechain.ConfigFile.optExample
        , governanceAuthority ∷ Maybe ByteArray
        }
  , -- | Filepath of the payment signing key of the wallet owner
    paymentSigningKeyFile ∷ Maybe FilePath
  , -- | Filepath of the stake signing key of the wallet owner
    stakeSigningKeyFile ∷ Maybe FilePath
  , -- | Network configuration of the runtime dependencies (kupo, ogmios)
    runtimeConfig ∷ Maybe RuntimeConfig
  }

-- | Data for CLI endpoints which provide supporting utilities for the
-- | sidechain
data UtilsEndpoint
  = EcdsaSecp256k1KeyGenAct
  | EcdsaSecp256k1SignAct
      { message ∷ ByteArray
      , privateKey ∷ EcdsaSecp256k1PrivateKey
      , noHashMessage ∷ Boolean
      -- whether to hash the message or not before signing.
      -- true ===> do NOT hash the message
      -- false ===> hash the message
      }
  | SchnorrSecp256k1KeyGenAct
  | SchnorrSecp256k1SignAct
      { message ∷ ByteArray
      , privateKey ∷ SchnorrSecp256k1PrivateKey
      , noHashMessage ∷ Boolean
      -- whether to hash the message or not before signing.
      -- true ===> do NOT hash the message
      -- false ===> hash the message
      }

  | CborUpdateCommitteeMessageAct
      { updateCommitteeHashMessage ∷ UpdateCommitteeHashMessage PlutusData }
  | CborBlockProducerRegistrationMessageAct
      { blockProducerRegistrationMsg ∷ BlockProducerRegistrationMsg
      }
  | CborMerkleTreeEntryAct { merkleTreeEntry ∷ MerkleTreeEntry }
  | CborMerkleTreeAct
      { merkleTreeEntries ∷ NonEmptyList MerkleTreeEntry
      }
  | CborMerkleRootInsertionMessageAct
      { merkleRootInsertionMessage ∷ MerkleRootInsertionMessage
      }
  | CborCombinedMerkleProofAct
      { merkleTreeEntry ∷ MerkleTreeEntry
      , merkleTree ∷ MerkleTree
      }
  | CborPlainAggregatePublicKeysAct
      { publicKeys ∷ NonEmptyList ByteArray
      }

-- | Data for CLI endpoints which submit a transaction to the blockchain.
data TxEndpoint
  = ClaimActV1
      { amount ∷ BigInt
      , recipient ∷ Address
      , merkleProof ∷ MerkleProof
      , index ∷ BigInt
      , previousMerkleRoot ∷ Maybe RootHash
      , dsUtxo ∷ Maybe TransactionInput
      }
  | BurnActV1 { amount ∷ BigInt, recipient ∷ ByteArray }
  | ClaimActV2
      { amount ∷ BigInt
      }
  | BurnActV2 { amount ∷ BigInt, recipient ∷ ByteArray }
  | CommitteeCandidateReg
      { stakeOwnership ∷ StakeOwnership
      , sidechainPubKey ∷ ByteArray
      , sidechainSig ∷ ByteArray
      , inputUtxo ∷ TransactionInput
      , usePermissionToken ∷ Boolean
      , auraKey ∷ ByteArray
      , grandpaKey ∷ ByteArray
      }
  | CandidiatePermissionTokenAct
      { candidatePermissionTokenAmount ∷ BigInt }
  | CommitteeCandidateDereg { spoPubKey ∷ Maybe PubKey }
  | CommitteeHash
      { newCommitteePubKeysInput ∷ InputArgOrFile (NonEmptyList ByteArray)
      , committeeSignaturesInput ∷
          InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray))
      , previousMerkleRoot ∷ Maybe RootHash
      , sidechainEpoch ∷ BigInt
      , mNewCommitteeValidatorHash ∷ Maybe ValidatorHash
      }
  | SaveRoot
      { merkleRoot ∷ RootHash
      , previousMerkleRoot ∷ Maybe RootHash
      , committeeSignaturesInput ∷
          InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray))
      }
  |
    -- `CommitteeHandover` is a convenient alias for saving the root,
    -- followed by updating the committee hash.
    CommitteeHandover
      { merkleRoot ∷ RootHash
      , previousMerkleRoot ∷ Maybe RootHash
      , newCommitteePubKeysInput ∷ InputArgOrFile (NonEmptyList ByteArray)
      , newCommitteeSignaturesInput ∷
          InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray))
      , newMerkleRootSignaturesInput ∷
          InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray))
      , sidechainEpoch ∷ BigInt
      , mNewCommitteeValidatorHash ∷ Maybe ValidatorHash
      }
  | GetAddrs
      SidechainAddressesExtra
  | InitTokensMint
      { version ∷ Int }
  | InitCheckpoint
      { genesisHash ∷ ByteArray
      , version ∷ Int
      }
  | InitFuel
      { committeePubKeysInput ∷ InputArgOrFile (NonEmptyList ByteArray)
      , initSidechainEpoch ∷ BigInt
      , version ∷ Int
      }
  | InitReserveManagement
      { version ∷ Int
      }
  | InitCandidatePermissionToken
      { initCandidatePermissionTokenMintInfo ∷ Maybe BigInt
      }
  | SaveCheckpoint
      { committeeSignaturesInput ∷
          InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray))
      , newCheckpointBlockHash ∷ ByteArray
      , newCheckpointBlockNumber ∷ BigInt
      , sidechainEpoch ∷ BigInt
      }

  -- See Note [Supporting version insertion beyond version 2]
  | InsertVersion2
  | UpdateVersion
      { oldVersion ∷ Int
      , newVersion ∷ Int
      }
  | InvalidateVersion
      { version ∷ Int
      }
  | ListVersionedScripts
      { version ∷ Int
      }
  | InsertDParameter
      { permissionedCandidatesCount ∷ BigInt
      , registeredCandidatesCount ∷ BigInt
      }
  | UpdateDParameter
      { permissionedCandidatesCount ∷ BigInt
      , registeredCandidatesCount ∷ BigInt
      }
  | UpdatePermissionedCandidates
      { permissionedCandidatesToAdd ∷
          List
            { sidechainKey ∷ ByteArray
            , auraKey ∷ ByteArray
            , grandpaKey ∷ ByteArray
            }
      , permissionedCandidatesToRemove ∷
          Maybe
            ( List
                { sidechainKey ∷ ByteArray
                , auraKey ∷ ByteArray
                , grandpaKey ∷ ByteArray
                }
            )
      }
  | BurnNFTs

  -- | reserve initialization for an asset class
  | InitTokenStatus

  -- | CLI entpoints for reserve initialization for an asset class
  | CreateReserve
      { mutableReserveSettings ∷ MutableReserveSettings
      , immutableReserveSettings ∷ ImmutableReserveSettings
      , depositAmount ∷ BigNum
      }

  -- | update of a reserve
  | UpdateReserveSettings
      { mutableReserveSettings ∷ MutableReserveSettings }

  -- | deposit to a reserve
  | DepositReserve
      { asset ∷ Asset
      , depositAmount ∷ BigNum
      }

  -- | transfer from a reserve to illiquid circulation supply
  | ReleaseReserveFunds
      { totalAccruedTillNow ∷ Int
      , transactionInput ∷ TransactionInput
      }

  -- | handover of a reserve
  | HandoverReserve

-- | `InputArgOrFile` represents that we may either allow an option as input
-- | via a CLI argument or a filepath of a JSON file
data InputArgOrFile (a ∷ Type)
  = InputFromArg a
  | InputFromFile FilePath

-- | Network configuration of the runtime dependencies
-- Any parameter can be set `null` falling back to its default value
type RuntimeConfig =
  { ogmios ∷ Maybe ServerConfig
  , kupo ∷ Maybe ServerConfig
  , network ∷ Maybe NetworkId
  }
