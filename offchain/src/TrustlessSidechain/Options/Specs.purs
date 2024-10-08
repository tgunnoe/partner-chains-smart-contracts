module TrustlessSidechain.Options.Specs (options) where

import Contract.Prelude

import Cardano.AsCbor (decodeCbor)
import Cardano.Types.Asset (Asset(..))
import Cardano.Types.BigNum (BigNum)
import Cardano.Types.NetworkId (NetworkId(MainnetId))
import Cardano.Types.TransactionInput (TransactionInput)
import Contract.Config
  ( PrivateStakeKeySource(PrivateStakeKeyFile)
  , ServerConfig
  , defaultOgmiosWsConfig
  , mainnetConfig
  , mkCtlBackendParams
  , testnetConfig
  )
import Contract.Prim.ByteArray (ByteArray)
import Contract.Scripts (ValidatorHash)
import Contract.Time (POSIXTime)
import Contract.Value (AssetName)
import Contract.Wallet
  ( PrivatePaymentKeySource(PrivatePaymentKeyFile)
  , WalletSpec(UseKeys)
  )
import Control.Alternative ((<|>))
import Ctl.Internal.Helpers (logWithLevel)
import Data.List (List)
import Data.List.Types (NonEmptyList)
import Data.UInt (UInt)
import Data.UInt as UInt
import JS.BigInt (BigInt)
import JS.BigInt as BigInt
import Options.Applicative
  ( Parser
  , ParserInfo
  , action
  , command
  , flag
  , flag'
  , fullDesc
  , header
  , help
  , helper
  , hsubparser
  , info
  , int
  , long
  , many
  , metavar
  , option
  , progDesc
  , short
  , showDefault
  , some
  , str
  , switch
  , value
  )
import TrustlessSidechain.CommitteeCandidateValidator
  ( BlockProducerRegistrationMsg(BlockProducerRegistrationMsg)
  , StakeOwnership(AdaBasedStaking, TokenBasedStaking)
  )
import TrustlessSidechain.FUELMintingPolicy.V1
  ( MerkleTreeEntry(MerkleTreeEntry)
  )
import TrustlessSidechain.Governance.Admin as Governance
import TrustlessSidechain.MerkleRoot.Types
  ( MerkleRootInsertionMessage(MerkleRootInsertionMessage)
  )
import TrustlessSidechain.MerkleTree (MerkleTree, RootHash)
import TrustlessSidechain.NativeTokenManagement.Types
  ( ImmutableReserveSettings(ImmutableReserveSettings)
  , MutableReserveSettings(MutableReserveSettings)
  )
import TrustlessSidechain.Options.Parsers
  ( bech32BytesParser
  , bech32ValidatorHashParser
  , bigInt
  , blockHash
  , byteArray
  , combinedMerkleProofParserWithPkh
  , denominator
  , ecdsaSecp256k1PrivateKey
  , governanceAuthority
  , networkId
  , numerator
  , permissionedCandidateKeys
  , plutusDataParser
  , pubKeyBytesAndSignatureBytes
  , registrationSidechainKeys
  , rootHash
  , schnorrSecp256k1PrivateKey
  , sidechainAddress
  , uint
  , validatorHashParser
  )
import TrustlessSidechain.Options.Parsers as Parsers
import TrustlessSidechain.Options.Types
  ( Config
  , InputArgOrFile(InputFromArg, InputFromFile)
  , Options(TxOptions, UtilsOptions, CLIVersion)
  , SidechainEndpointParams(SidechainEndpointParams)
  , TxEndpoint
      ( ClaimActV1
      , BurnActV1
      , ClaimActV2
      , BurnActV2
      , GetAddrs
      , CandidiatePermissionTokenAct
      , InitTokensMint
      , InitCheckpoint
      , InitFuel
      , InitReserveManagement
      , InitCandidatePermissionToken
      , CommitteeCandidateReg
      , CommitteeCandidateDereg
      , CommitteeHash
      , SaveRoot
      , CommitteeHandover
      , SaveCheckpoint
      , InsertVersion2
      , UpdateVersion
      , InvalidateVersion
      , InsertDParameter
      , UpdateDParameter
      , UpdatePermissionedCandidates
      , BurnNFTs
      , InitTokenStatus
      , ListVersionedScripts
      , CreateReserve
      , DepositReserve
      , ReleaseReserveFunds
      , HandoverReserve
      )
  , UtilsEndpoint
      ( EcdsaSecp256k1KeyGenAct
      , EcdsaSecp256k1SignAct
      , SchnorrSecp256k1KeyGenAct
      , SchnorrSecp256k1SignAct
      , CborUpdateCommitteeMessageAct
      , CborBlockProducerRegistrationMessageAct
      , CborMerkleTreeEntryAct
      , CborMerkleTreeAct
      , CborCombinedMerkleProofAct
      , CborMerkleRootInsertionMessageAct
      , CborPlainAggregatePublicKeysAct
      )
  )
import TrustlessSidechain.SidechainParams (SidechainParams(SidechainParams))
import TrustlessSidechain.UpdateCommitteeHash.Types
  ( UpdateCommitteeHashMessage(UpdateCommitteeHashMessage)
  )
import TrustlessSidechain.Utils.Logging (environment, fileLogger)

-- | Argument option parser for sidechain-main-cli
options ∷ Maybe Config → ParserInfo Options
options maybeConfig = info (helper <*> optSpec maybeConfig)
  ( fullDesc <> header
      "sidechain-main-cli - CLI application to execute TrustlessSidechain Cardano endpoints"
  )

-- | CLI parser of all commands
optSpec ∷ Maybe Config → Parser Options
optSpec maybeConfig =
  hsubparser $ fold
    [ command "init-tokens-mint"
        ( info (withCommonOpts maybeConfig initTokensMintSpec)
            (progDesc "Mint all sidechain initialisation tokens")
        )
    , command "init-reserve-management"
        ( info (withCommonOpts maybeConfig initReserveManagementSpec)
            (progDesc "Initialise native token reserve management system")
        )
    , command "init-checkpoint"
        ( info (withCommonOpts maybeConfig initCheckpointSpec)
            (progDesc "Initialise checkpoint")
        )
    , command "init-fuel"
        ( info (withCommonOpts maybeConfig initFuelSpec)
            (progDesc "Initialise the FUEL and committee selection mechanisms")
        )
    , command "init-candidate-permission-token"
        ( info (withCommonOpts maybeConfig initCandidatePermissionTokenSpec)
            (progDesc "Initialise candidate permission token")
        )
    , command "addresses"
        ( info (withCommonOpts maybeConfig getAddrSpec)
            (progDesc "Get the script addresses for a given sidechain")
        )
    , command "claim-v1"
        ( info (withCommonOpts maybeConfig claimSpecV1)
            (progDesc "Claim a FUEL tokens from a proof")
        )
    , command "burn-v1"
        ( info (withCommonOpts maybeConfig burnSpecV1)
            (progDesc "Burn a certain amount of FUEL tokens")
        )
    , command "claim-v2"
        ( info (withCommonOpts maybeConfig claimSpecV2)
            (progDesc "Claim FUEL tokens from thin air")
        )
    , command "burn-v2"
        ( info (withCommonOpts maybeConfig burnSpecV2)
            (progDesc "Burn a certain amount of FUEL tokens")
        )
    , command "register"
        ( info (withCommonOpts maybeConfig regSpec)
            (progDesc "Register a committee candidate")
        )
    , command "candidate-permission-token"
        ( info (withCommonOpts maybeConfig candidatePermissionTokenSpec)
            (progDesc "Mint candidate permission tokens")
        )
    , command "deregister"
        ( info (withCommonOpts maybeConfig deregSpec)
            (progDesc "Deregister a committee member")
        )
    , command "committee-hash"
        ( info (withCommonOpts maybeConfig committeeHashSpec)
            (progDesc "Update the committee hash")
        )
    , command "save-root"
        ( info (withCommonOpts maybeConfig saveRootSpec)
            (progDesc "Saving a new merkle root")
        )
    , command "committee-handover"
        ( info (withCommonOpts maybeConfig committeeHandoverSpec)
            ( progDesc
                "An alias for saving the merkle root, followed by updating the committee hash"
            )
        )
    , command "save-checkpoint"
        ( info (withCommonOpts maybeConfig saveCheckpointSpec)
            (progDesc "Saving a new checkpoint")
        )

    , command "reserve-create"
        ( info (withCommonOpts maybeConfig createReserveSpec)
            (progDesc "Create a new token reserve")
        )
    , command "reserve-handover"
        ( info (withCommonOpts maybeConfig handOverReserveSpec)
            (progDesc "Empty and remove an existing reserve")
        )
    , command "reserve-deposit"
        ( info (withCommonOpts maybeConfig depositReserveSpec)
            (progDesc "Deposit assets to existing reserve")
        )
    , command "reserve-release-funds"
        ( info (withCommonOpts maybeConfig releaseReserveFundsSpec)
            (progDesc "Release currently available funds from an existing reserve")
        )

    , command "insert-version-2"
        ( info (withCommonOpts maybeConfig insertVersionSpec)
            (progDesc "Initialize version 2 of a protocol")
        )
    , command "update-version"
        ( info (withCommonOpts maybeConfig updateVersionSpec)
            (progDesc "Update an existing protocol version")
        )
    , command "invalidate-version"
        ( info (withCommonOpts maybeConfig invalidateVersionSpec)
            (progDesc "Invalidate a protocol version")
        )
    , command "list-versioned-scripts"
        ( info (withCommonOpts maybeConfig listVersionedScriptsSpec)
            ( progDesc
                "Get scripts (validators and minting policies) that are currently being versioned"
            )
        )

    , command "insert-d-parameter"
        ( info (withCommonOpts maybeConfig insertDParameterSpec)
            (progDesc "Insert new D parameter")
        )
    , command "update-d-parameter"
        ( info (withCommonOpts maybeConfig updateDParameterSpec)
            (progDesc "Update a D parameter")
        )
    , command "update-permissioned-candidates"
        ( info (withCommonOpts maybeConfig updatePermissionedCandidatesSpec)
            (progDesc "Update a Permissioned Candidates list")
        )
    , command "collect-garbage"
        ( info (withCommonOpts maybeConfig burnNFTsSpec)
            (progDesc "Burn unneccessary NFTs")
        )
    , command "init-token-status"
        ( info (withCommonOpts maybeConfig initTokenStatusSpec)
            (progDesc "List the number of each init token the wallet still holds")
        )

    , command "cli-version"
        ( info (pure CLIVersion)
            ( progDesc
                "Display semantic version of the CLI and its git hash"
            )
        )

    , command "utils"
        ( info (utilsSpec maybeConfig)
            ( progDesc
                "Utility functions for cryptographic primitives and messages."
            )
        )

    ]

-- | `utilsSpec` provides CLI options for utilities in the sidechain that do
-- | not submit a tx to the blockchain
utilsSpec ∷ Maybe Config → Parser Options
utilsSpec maybeConfig =
  let
    keyGenSpecs ∷ Parser Options
    keyGenSpecs = hsubparser $ fold
      [ command "ecdsa-secp256k1"
          ( info ecdsaSecp256k1GenSpec
              (progDesc "Generate an ECDSA SECP256k1 public / private key pair")
          )
      , command "schnorr-secp256k1"
          ( info schnorrSecp256k1GenSpec
              (progDesc "Generate an Schnorr SECP256k1 public / private key pair")
          )
      ]

    signSpecs ∷ Parser Options
    signSpecs = hsubparser $ fold
      [ command "ecdsa-secp256k1"
          ( info ecdsaSecp256k1SignSpec
              (progDesc "Sign a message with an ECDSA SECP256k1 private key")
          )
      , command "schnorr-secp256k1"
          ( info schnorrSecp256k1SignSpec
              (progDesc "Sign a message with a Schnorr SECP256k1 private key")
          )
      ]

    encodeSpecs ∷ Parser Options
    encodeSpecs = hsubparser $ fold
      [ command "cbor-update-committee-message"
          ( info (cborUpdateCommitteeMessageSpec maybeConfig)
              (progDesc "Generate the CBOR of an update committee message")
          )

      , command "cbor-block-producer-registration-message"
          ( info (cborBlockProducerRegistrationMessageSpec maybeConfig)
              ( progDesc
                  "Generate the CBOR of a block producer registration message"
              )
          )

      , command "cbor-merkle-root-insertion-message"
          ( info (cborMerkleRootInsertionMessageSpec maybeConfig)
              ( progDesc
                  "Generate the CBOR of a Merkle root insertion message"
              )
          )

      , command "cbor-merkle-tree-entry"
          ( info cborMerkleTreeEntrySpec
              (progDesc "Generate the CBOR of a Merkle tree entry")
          )

      , command "cbor-merkle-tree"
          ( info cborMerkleTreeSpec
              ( progDesc
                  "Generate the CBOR of a Merkle tree and the Merkle root hash from the provided Merkle tree entries"
              )
          )

      , command "cbor-combined-merkle-proof"
          ( info cborCombinedMerkleProofSpec
              ( progDesc
                  "Generate the combined Merkle proof from the provided Merkle tree and Merkle tree entry"
              )
          )
      , command "cbor-plain-aggregate-public-keys"
          ( info cborPlainAggregatePublicKeys
              ( progDesc
                  "Aggregate the raw hex encoded public keys with the plain ATMS scheme which sorts, concatenates, and hashes"
              )
          )
      ]

  in
    hsubparser $ fold
      [ command "key-gen"
          ( info keyGenSpecs
              (progDesc "Generate a public / private key pair")
          )
      , command "sign"
          ( info signSpecs
              (progDesc "Sign a message")
          )
      , command "encode"
          ( info encodeSpecs
              (progDesc "Generate CBOR encoded data")
          )
      ]

-- | Helper function, adding parsers of common fields (private key, staking key,
-- | sidechain parameters and runtime configuration)
withCommonOpts ∷ Maybe Config → Parser TxEndpoint → Parser Options
withCommonOpts maybeConfig endpointParser = ado
  pSkey ← pSkeySpec maybeConfig
  stSkey ← stSKeySpec maybeConfig
  sidechainEndpointParams ← sidechainEndpointParamsSpec maybeConfig
  endpoint ← endpointParser

  ogmiosConfig ← serverConfigSpec "ogmios" $
    fromMaybe defaultOgmiosWsConfig
      (maybeConfig >>= _.runtimeConfig >>= _.ogmios)

  kupoConfig ← serverConfigSpec "kupo" $
    fromMaybe defaultKupoServerConfig
      (maybeConfig >>= _.runtimeConfig >>= _.kupo)

  network ← option networkId $ fold
    [ long "network"
    , metavar "NETWORK"
    , help "Network ID of the sidechain"
    , maybe mempty value
        (maybeConfig >>= _.runtimeConfig >>= _.network)
    ]

  let
    config = case network of
      MainnetId → mainnetConfig
      _ → testnetConfig

  in
    TxOptions
      { sidechainEndpointParams
      , endpoint
      , contractParams: config
          { logLevel = environment.logLevel
          , suppressLogs = not environment.isTTY
          , customLogger = Just
              \_ m → fileLogger m *> logWithLevel environment.logLevel m
          , walletSpec = Just $ UseKeys
              (PrivatePaymentKeyFile pSkey)
              (PrivateStakeKeyFile <$> stSkey)
          , backendParams = mkCtlBackendParams { kupoConfig, ogmiosConfig }
          }
      }
  where
  -- the default server config upstream is different than Kupo's defaults
  defaultKupoServerConfig ∷
    { host ∷ String
    , path ∷ Maybe String
    , port ∷ UInt
    , secure ∷ Boolean
    }
  defaultKupoServerConfig =
    { port: UInt.fromInt 1442
    , host: "localhost"
    , secure: false
    , path: Nothing
    }

-- | Payment signing key file CLI parser
pSkeySpec ∷ Maybe Config → Parser String
pSkeySpec maybeConfig =
  option str $ fold
    [ short 'k'
    , long "payment-signing-key-file"
    , metavar "/absolute/path/to/payment.skey"
    , help "Own payment signing key file path"
    , action "file"
    , maybe mempty value (maybeConfig >>= _.paymentSigningKeyFile)
    ]

-- | Stake signing key file CLI parser
stSKeySpec ∷ Maybe Config → Parser (Maybe String)
stSKeySpec maybeConfig =
  optional $ option str $ fold
    [ short 'K'
    , long "stake-signing-key-file"
    , metavar "/absolute/path/to/stake.skey"
    , help "Own stake signing key file path"
    , action "file"
    , maybe mempty value (maybeConfig >>= _.stakeSigningKeyFile)
    ]

-- | Generic server config CLI parser.
-- | This can be used to parse the configuration of a CTL-runtime service.
-- | A default configuration is used as fallback
serverConfigSpec ∷ String → ServerConfig → Parser ServerConfig
serverConfigSpec
  name
  { host: defHost, path: defPath, port: defPort, secure: defSecure } = ado
  host ← option str $ fold
    [ long $ name <> "-host"
    , metavar "localhost"
    , help $ "Address host of " <> name
    , value defHost
    , showDefault
    ]
  path ← optional $ option str $ fold
    [ long $ name <> "-path"
    , metavar "some/path"
    , help $ "Address path of " <> name
    , maybe mempty value defPath
    , showDefault
    ]
  port ← option uint $ fold
    [ long $ name <> "-port"
    , metavar "1234"
    , help $ "Port of " <> name
    , value defPort
    , showDefault
    ]
  secure ← flag false true $ fold
    [ long $ name <> "-secure"
    , help $ "Whether " <> name <> " is using an HTTPS connection"
    ]
  in { host, path, port, secure: secure || defSecure }

sidechainParamsSpec ∷ Maybe Config → Parser SidechainParams
sidechainParamsSpec maybeConfig = ado
  chainId ← option int $ fold
    [ short 'i'
    , long "sidechain-id"
    , metavar "1"
    , help "Sidechain ID"
    , maybe mempty value
        (maybeConfig >>= _.sidechainParameters >>= _.chainId)
    ]

  genesisUtxo ← option Parsers.transactionInput $ fold
    [ short 'c'
    , long "genesis-committee-hash-utxo"
    , metavar "TX_ID#TX_IDX"
    , help "Input UTxO to be spent with the first committee hash setup"
    , maybe mempty value
        (maybeConfig >>= _.sidechainParameters >>= _.genesisUtxo)
    ]

  governanceAuthority ← option governanceAuthority $ fold
    [ short 'g'
    , long "governance-authority"
    , metavar "PUB_KEY_HASH"
    , help "Public key hash of governance authority"
    , maybe mempty value
        ( maybeConfig >>= _.sidechainParameters >>= _.governanceAuthority >>=
            -- parse ByteArray stored in Config into a PubKeyHash
            ( wrap >>> decodeCbor >=> wrap
                >>> Governance.mkGovernanceAuthority
                >>> pure
            )
        )
    ]

  { thresholdNumerator, thresholdDenominator } ←
    let
      thresholdNumeratorDenominatorOption = ado
        thresholdNumerator ← option numerator $ fold
          [ long "threshold-numerator"
          , metavar "INT"
          , help "The numerator for the ratio of the threshold"
          , maybe mempty value
              $ map (BigInt.fromInt <<< _.numerator)
                  ( maybeConfig >>= _.sidechainParameters >>=
                      _.threshold
                  )
          ]
        thresholdDenominator ← option denominator $ fold
          [ long "threshold-denominator"
          , metavar "INT"
          , help "The denominator for the ratio of the threshold"
          , maybe mempty value
              $ map (BigInt.fromInt <<< _.denominator)
                  ( maybeConfig >>= _.sidechainParameters >>=
                      _.threshold
                  )
          ]
        in { thresholdNumerator, thresholdDenominator }
    in
      thresholdNumeratorDenominatorOption
  in
    SidechainParams
      { chainId: BigInt.fromInt chainId
      , genesisUtxo
      , governanceAuthority
      , thresholdNumerator
      , thresholdDenominator
      }

-- | SidechainParams CLI parser
sidechainEndpointParamsSpec ∷ Maybe Config → Parser SidechainEndpointParams
sidechainEndpointParamsSpec maybeConfig = ado
  sidechainParams ← sidechainParamsSpec maybeConfig

  atmsKind ← option Parsers.atmsKind $ fold
    [ short 'm'
    , long "atms-kind"
    , metavar "ATMS_KIND"
    , help
        "ATMS kind for the sidechain -- either 'plain-ecdsa-secp256k1', 'multisignature', 'pok', or 'dummy'"
    , maybe mempty value
        (maybeConfig >>= _.sidechainParameters >>= _.atmsKind)
    ]
  in
    SidechainEndpointParams
      { sidechainParams
      , atmsKind
      }

-- | Parse all parameters for the `claim` endpoint
claimSpecV1 ∷ Parser TxEndpoint
claimSpecV1 = ado
  (combinedMerkleProof /\ recipient) ← option combinedMerkleProofParserWithPkh
    $ fold
        [ short 'p'
        , long "combined-proof"
        , metavar "CBOR"
        , help "CBOR-encoded Combined Merkle Proof"
        ]
  dsUtxo ← optional $ option Parsers.transactionInput $ fold
    [ long "distributed-set-utxo"
    , metavar "TX_ID#TX_IDX"
    , help
        "UTxO to use for the distributed set to ensure uniqueness of claiming the transaction"
    ]

  let
    { transaction, merkleProof } = unwrap combinedMerkleProof
    { amount, index, previousMerkleRoot } = unwrap transaction
  in
    ClaimActV1
      { amount
      , recipient
      , merkleProof
      , index
      , previousMerkleRoot
      , dsUtxo
      }

-- | Parse all parameters for the `burn` endpoint
burnSpecV1 ∷ Parser TxEndpoint
burnSpecV1 = ado
  amount ← parseAmount
  recipient ← option sidechainAddress $ fold
    [ long "recipient"
    , metavar "ADDRESS"
    , help "Address of the sidechain recipient"
    ]
  in BurnActV1 { amount, recipient }

-- | Parse all parameters for the `claim-v2` endpoint
claimSpecV2 ∷ Parser TxEndpoint
claimSpecV2 = ado
  amount ← parseAmount
  in
    ClaimActV2
      { amount }

-- | Parse all parameters for the `burn-v2` endpoint
burnSpecV2 ∷ Parser TxEndpoint
burnSpecV2 = ado
  amount ← parseAmount
  recipient ← option sidechainAddress $ fold
    [ long "recipient"
    , metavar "ADDRESS"
    , help "Address of the sidechain recipient"
    ]
  in BurnActV2 { amount, recipient }

-- | Token amount parser
parseAmount ∷ Parser BigInt
parseAmount = option bigInt $ fold
  [ short 'a'
  , long "amount"
  , metavar "1"
  , help "Amount of FUEL token to be burnt/minted"
  ]

-- | Parse required data for a stake ownership variant
stakeOwnershipSpec ∷ Parser StakeOwnership
stakeOwnershipSpec = parseAdaBasedStaking <|> parseTokenBasedStaking

  where
  parseAdaBasedStaking = ado
    parseAdaBasedStakingFlag
    pk ← parseSpoPubKey
    sig ← option byteArray $ fold
      [ long "spo-signature"
      , metavar "SIGNATURE"
      , help "SPO signature"
      ]
    in AdaBasedStaking pk sig
  parseTokenBasedStaking = ado
    parseTokenBasedStakingFlag
    in TokenBasedStaking

parseAdaBasedStakingFlag ∷ Parser Unit
parseAdaBasedStakingFlag =
  flag' unit $ fold
    [ long "ada-based-staking"
    , help "Using Ada based staking model"
    ]

parseTokenBasedStakingFlag ∷ Parser Unit
parseTokenBasedStakingFlag =
  flag' unit $ fold
    [ long "native-token-based-staking"
    , help "Using native token based staking model"
    ]

-- | Parse all parameters for the `register` endpoint
regSpec ∷ Parser TxEndpoint
regSpec = ado
  { sidechainKey, auraKey, grandpaKey } ←
    parseRegistrationSidechainKeys
  sidechainSig ← option byteArray $ fold
    [ long "sidechain-signature"
    , metavar "SIGNATURE"
    , help "Sidechain signature"
    ]
  inputUtxo ← option Parsers.transactionInput $ fold
    [ long "registration-utxo"
    , metavar "TX_ID#TX_IDX"
    , help "Input UTxO to be spend with the commitee candidate registration"
    ]
  stakeOwnership ← stakeOwnershipSpec
  usePermissionToken ← switch $ fold
    -- `switch` is
    --  No flag given ==> false
    --  Flag given ==> true
    [ long "use-candidate-permission-token"
    , help
        "Use candidate permission tokens during committee candidate registration"
    ]
  in
    CommitteeCandidateReg
      { stakeOwnership
      , sidechainPubKey: sidechainKey
      , sidechainSig
      , inputUtxo
      , usePermissionToken
      , auraKey
      , grandpaKey
      }

-- | Parse all parameters for the `deregister` endpoint
deregSpec ∷ Parser TxEndpoint
deregSpec = CommitteeCandidateDereg <<< { spoPubKey: _ } <$>
  (parseAdaBasedStaking <|> parseTokenBasedStaking)

  where
  parseAdaBasedStaking = ado
    parseAdaBasedStakingFlag
    pk ← parseSpoPubKey
    in Just pk
  parseTokenBasedStaking = ado
    parseTokenBasedStakingFlag
    in Nothing

-- | SPO public key CLI parser
parseSpoPubKey ∷ Parser ByteArray
parseSpoPubKey = option byteArray $ fold
  [ long "spo-public-key"
  , metavar "PUBLIC_KEY"
  , help "SPO cold verification key value"
  ]

-- | Parse all parameters for the `committee-hash` endpoint
committeeHashSpec ∷ Parser TxEndpoint
committeeHashSpec = ado
  newCommitteePubKeysInput ← parseNewCommitteePubKeys
  committeeSignaturesInput ←
    ( parseCommitteeSignatures
        "committee-pub-key-and-signature"
        "Public key and (optionally) the signature of the new committee hash separated by a colon"
        "committee-pub-key-and-signature-file-path"
        "Filepath of a JSON file containing public keys and associated\
        \ signatures e.g. `[{\"public-key\":\"aabb...\", \"signature\":null}, ...]`"
    )
  previousMerkleRoot ← parsePreviousMerkleRoot
  sidechainEpoch ← parseSidechainEpoch
  mNewCommitteeValidatorHash ← optional parseNewCommitteeValidatorHash
  in
    CommitteeHash
      { newCommitteePubKeysInput
      , committeeSignaturesInput
      , previousMerkleRoot
      , sidechainEpoch
      , mNewCommitteeValidatorHash
      }

parseNewCommitteeValidatorHash ∷ Parser ValidatorHash
parseNewCommitteeValidatorHash =
  ( option
      validatorHashParser
      ( fold
          [ long "new-committee-validator-hash"
          , metavar "VALIDATOR_HASH"
          , help
              "Hex encoded validator hash to send the committee oracle to"
          ]
      )
  )
    <|>
      ( option
          bech32ValidatorHashParser
          ( fold
              [ long "new-committee-validator-bech32-address"
              , metavar "BECH32_ADDRESS"
              , help
                  "bech32 of a validator address to send the committee oracle to"
              ]
          )
      )

-- | Parse all parameters for the `save-root` endpoint
saveRootSpec ∷ Parser TxEndpoint
saveRootSpec = ado
  merkleRoot ← parseMerkleRoot
  previousMerkleRoot ← parsePreviousMerkleRoot
  committeeSignaturesInput ←
    parseCommitteeSignatures
      "committee-pub-key-and-signature"
      "Public key and (optionally) the signature of the new merkle root separated by a colon"
      "committee-pub-key-and-signature-file-path"
      "Filepath of a JSON file containing public keys and associated\
      \ signatures e.g. `[{\"public-key\":\"aabb...\", \"signature\":null}, ...]`"
  in SaveRoot { merkleRoot, previousMerkleRoot, committeeSignaturesInput }

-- | Parse all parameters for the `committee-handover` endpoint
committeeHandoverSpec ∷ Parser TxEndpoint
committeeHandoverSpec = ado
  merkleRoot ← parseMerkleRoot
  previousMerkleRoot ← parsePreviousMerkleRoot
  newCommitteePubKeysInput ← parseNewCommitteePubKeys
  newCommitteeSignaturesInput ← parseCommitteeSignatures
    "committee-pub-key-and-new-committee-signature"
    "Public key and (optionally) the signature of the new committee hash separated by a colon"
    "committee-pub-key-and-new-committee-file-path"
    "Filepath of a JSON file containing public keys and associated\
    \ signatures e.g. `[{\"public-key\":\"aabb...\", \"signature\":null}, ...]`"
  newMerkleRootSignaturesInput ← parseCommitteeSignatures
    "committee-pub-key-and-new-merkle-root-signature"
    "Public key and (optionally) the signature of the merkle root separated by a colon"
    "committee-pub-key-and-new-merkle-root-file-path"
    "Filepath of a JSON file containing public keys and associated\
    \ signatures e.g. `[{\"public-key\":\"aabb...\", \"signature\":null}, ...]`"
  sidechainEpoch ← parseSidechainEpoch
  mNewCommitteeValidatorHash ← optional parseNewCommitteeValidatorHash
  in
    CommitteeHandover
      { merkleRoot
      , previousMerkleRoot
      , newCommitteePubKeysInput
      , newCommitteeSignaturesInput
      , newMerkleRootSignaturesInput
      , sidechainEpoch
      , mNewCommitteeValidatorHash
      }

-- | Parse all parameters for the `save-checkpoint` endpoint
saveCheckpointSpec ∷ Parser TxEndpoint
saveCheckpointSpec = ado
  committeeSignaturesInput ←
    ( parseCommitteeSignatures
        "committee-pub-key-and-signature"
        "Public key and (optionally) the signature of the new checkpoint separated by a colon"
        "committee-pub-key-and-signature-file-path"
        "Filepath of a JSON file containing public keys and associated\
        \ signatures e.g. `[{\"public-key\":\"aabb...\", \"signature\":null}, ...]`"
    )
  newCheckpointBlockHash ← parseNewCheckpointBlockHash
  newCheckpointBlockNumber ← parseNewCheckpointBlockNumber
  sidechainEpoch ← parseSidechainEpoch
  in
    SaveCheckpoint
      { committeeSignaturesInput
      , newCheckpointBlockHash
      , newCheckpointBlockNumber
      , sidechainEpoch

      }

-- `parseCommittee` parses the committee public keys and takes the long
-- flag / help message as parameters
parseCommittee ∷
  String →
  String →
  String →
  String →
  Parser (InputArgOrFile (NonEmptyList ByteArray))
parseCommittee longflag hdesc filelongflag filehdesc =
  map InputFromArg
    ( some
        ( option byteArray
            ( fold
                [ long longflag
                , metavar "PUBLIC_KEY"
                , help hdesc
                ]
            )
        )
    )
    <|>
      map InputFromFile
        ( option
            str
            ( fold
                [ long filelongflag
                , metavar "FILEPATH"
                , help filehdesc
                ]
            )
        )

-- `parseNewCommitteePubKeys` wraps `parseCommittee` with sensible defaults.
parseNewCommitteePubKeys ∷ Parser (InputArgOrFile (NonEmptyList ByteArray))
parseNewCommitteePubKeys =
  parseCommittee
    "new-committee-pub-key"
    "Public key of a new committee member"
    "new-committee-pub-key-file-path"
    "Filepath of a JSON file containing public keys of the new committee\
    \ e.g. `[{\"public-key\":\"aabb...\", }, ...]`"

-- `parseCommitteeSignatures` gives the options for parsing the current
-- committees' signatures.
parseCommitteeSignatures ∷
  String →
  String →
  String →
  String →
  Parser (InputArgOrFile (NonEmptyList (ByteArray /\ Maybe ByteArray)))
parseCommitteeSignatures longflag hdesc filelongflag filehdesc =
  map InputFromArg
    ( some
        ( option pubKeyBytesAndSignatureBytes
            ( fold
                [ long longflag
                , metavar "PUBLIC_KEY[:[SIGNATURE]]"
                , help hdesc
                ]
            )
        )
    )
    <|>
      map InputFromFile
        ( option
            str
            ( fold
                [ long filelongflag
                , metavar "FILEPATH"
                , help filehdesc
                ]
            )
        )

-- `parseMerkleRoot` parses the option of a new merkle root. This is used
-- in `saveRootSpec` and `committeeHashSpec`
parseMerkleRoot ∷ Parser RootHash
parseMerkleRoot = option
  rootHash
  ( fold
      [ long "merkle-root"
      , metavar "MERKLE_ROOT"
      , help "Raw hex encoded Merkle root signed by the committee"
      ]
  )

-- `parsePreviousMerkleRoot` gives the options for parsing a merkle root (this is
-- used in both `saveRootSpec` and `committeeHashSpec`).
parsePreviousMerkleRoot ∷ Parser (Maybe RootHash)
parsePreviousMerkleRoot =
  optional
    ( option
        rootHash
        ( fold
            [ long "previous-merkle-root"
            , metavar "MERKLE_ROOT"
            , help "Raw hex encoded previous merkle root if it exists"
            ]
        )
    )

-- | Sidechain epoch CLI parser
parseSidechainEpoch ∷ Parser BigInt
parseSidechainEpoch =
  option
    bigInt
    ( fold
        [ long "sidechain-epoch"
        , metavar "INT"
        , help "Sidechain epoch"
        ]
    )

parseNewCheckpointBlockNumber ∷ Parser BigInt
parseNewCheckpointBlockNumber =
  option
    bigInt
    ( fold
        [ long "new-checkpoint-block-number"
        , metavar "INT"
        , help "Block number of the new checkpoint"
        ]
    )

parseNewCheckpointBlockHash ∷ Parser ByteArray
parseNewCheckpointBlockHash =
  option
    blockHash
    ( fold
        [ long "new-checkpoint-block-hash"
        , metavar "BLOCK_HASH"
        , help "Hex encoded block hash of the new checkpoint"
        ]
    )

parseGenesisHash ∷ Parser ByteArray
parseGenesisHash =
  option
    byteArray
    ( fold
        [ long "sidechain-genesis-hash"
        , metavar "GENESIS_HASH"
        , help "Sidechain genesis hash"
        ]
    )

-- | `initCandidatePermissionTokenMintHelper` helps mint candidate permission
-- | tokens from initializing the sidechain
initCandidatePermissionTokenMintHelper ∷
  Parser BigInt
initCandidatePermissionTokenMintHelper =
  option bigInt $ fold
    [ long "candidate-permission-token-amount"
    , metavar "INT"
    , help "Amount of the candidate permission token to be minted"
    ]

parseVersion ∷ Parser Int
parseVersion =
  option
    int
    ( fold
        [ long "version"
        , metavar "INT"
        , help "Protocol version"
        ]
    )

-- | Parser for the `init-tokens-mint` endpoint.
initTokensMintSpec ∷ Parser TxEndpoint
initTokensMintSpec = ado
  version ← parseVersion
  in
    InitTokensMint { version }

initCandidatePermissionTokenSpec ∷ Parser TxEndpoint
initCandidatePermissionTokenSpec = ado
  initCandidatePermissionTokenMintInfo ←
    optional initCandidatePermissionTokenMintHelper
  in
    InitCandidatePermissionToken
      { initCandidatePermissionTokenMintInfo
      }

-- `initSpec` includes the sub parser from `initTokensSpec` (to optionally mint
-- candidate permission tokens), and parsers for the initial committee
initCheckpointSpec ∷ Parser TxEndpoint
initCheckpointSpec = ado
  genesisHash ← parseGenesisHash
  version ← parseVersion
  in
    InitCheckpoint
      { genesisHash
      , version
      }

initReserveManagementSpec ∷ Parser TxEndpoint
initReserveManagementSpec = ado
  version ← parseVersion
  in
    InitReserveManagement
      { version
      }

initFuelSpec ∷ Parser TxEndpoint
initFuelSpec = ado
  committeePubKeysInput ← parseCommittee
    "committee-pub-key"
    "Public key for a committee member at sidechain initialisation"
    "committee-pub-key-file-path"
    "Filepath of a JSON file containing public keys of the new committee\
    \ e.g. `[{\"public-key\":\"aabb...\", }, ...]`"
  initSidechainEpoch ← parseSidechainEpoch
  version ← parseVersion
  in
    InitFuel
      { committeePubKeysInput
      , initSidechainEpoch
      , version
      }

insertVersionSpec ∷ Parser TxEndpoint
insertVersionSpec = pure InsertVersion2

parseOldVersion ∷ Parser Int
parseOldVersion =
  option
    int
    ( fold
        [ long "old-version"
        , metavar "INT"
        , help "Old protocol version"
        ]
    )

parseNewVersion ∷ Parser Int
parseNewVersion =
  option
    int
    ( fold
        [ long "new-version"
        , metavar "INT"
        , help "New protocol version"
        ]
    )

updateVersionSpec ∷ Parser TxEndpoint
updateVersionSpec = ado
  newVersion ← parseNewVersion
  oldVersion ← parseOldVersion
  in UpdateVersion { newVersion, oldVersion }

invalidateVersionSpec ∷ Parser TxEndpoint
invalidateVersionSpec = ado
  version ← parseVersion
  in InvalidateVersion { version }

listVersionedScriptsSpec ∷ Parser TxEndpoint
listVersionedScriptsSpec = ado
  version ← parseVersion
  in ListVersionedScripts { version }

parseDParameterPermissionedCandidatesCount ∷ Parser BigInt
parseDParameterPermissionedCandidatesCount =
  option
    Parsers.permissionedCandidatesCount
    ( fold
        [ long "d-parameter-permissioned-candidates-count"
        , metavar "INT"
        , help "D Parameter permissioned-candidates-count"
        ]
    )

parseDParameterRegisteredCandidatesCount ∷ Parser BigInt
parseDParameterRegisteredCandidatesCount =
  option
    Parsers.registeredCandidatesCount
    ( fold
        [ long "d-parameter-registered-candidates-count"
        , metavar "INT"
        , help "D Parameter registered candidates count"
        ]
    )

insertDParameterSpec ∷ Parser TxEndpoint
insertDParameterSpec = ado
  permissionedCandidatesCount ← parseDParameterPermissionedCandidatesCount
  registeredCandidatesCount ← parseDParameterRegisteredCandidatesCount
  in InsertDParameter { permissionedCandidatesCount, registeredCandidatesCount }

updateDParameterSpec ∷ Parser TxEndpoint
updateDParameterSpec = ado
  permissionedCandidatesCount ← parseDParameterPermissionedCandidatesCount
  registeredCandidatesCount ← parseDParameterRegisteredCandidatesCount
  in UpdateDParameter { permissionedCandidatesCount, registeredCandidatesCount }

parseRegistrationSidechainKeys ∷
  Parser
    { sidechainKey ∷ ByteArray
    , auraKey ∷ ByteArray
    , grandpaKey ∷ ByteArray
    }
parseRegistrationSidechainKeys =
  option registrationSidechainKeys
    ( fold
        [ long "sidechain-public-keys"
        , metavar "SIDECHAIN_KEY:AURA_KEY:GRANDPA_KEY"
        , help "Sidechain keys of a block producer"
        ]
    )

parseAddPermissionedCandidates ∷
  Parser
    ( List
        { sidechainKey ∷ ByteArray
        , auraKey ∷ ByteArray
        , grandpaKey ∷ ByteArray
        }
    )
parseAddPermissionedCandidates =
  ( many
      ( option permissionedCandidateKeys
          ( fold
              [ long "add-candidate"
              , metavar
                  "SIDECHAIN_KEY:AURA_KEY:GRANDPA_KEY"
              , help
                  "A list of tuples of 3 keys used to describe a permissioned candidate, separated by a colon"
              ]
          )
      )
  )

parseRemovePermissionedCandidates ∷
  Parser
    ( Maybe
        ( List
            { sidechainKey ∷ ByteArray
            , auraKey ∷ ByteArray
            , grandpaKey ∷ ByteArray
            }
        )
    )
parseRemovePermissionedCandidates = Just <$>
  ( many
      ( option permissionedCandidateKeys
          ( fold
              [ long "remove-candidate"
              , metavar
                  "SIDECHAIN_KEY:AURA_KEY:GRANDPA_KEY"
              , help
                  "A list of tuples of 3 keys used to describe a permissioned candidate, separated by a colon"
              ]
          )
      )
  )

parseRemoveAllCandidates ∷ ∀ a. Parser (Maybe a)
parseRemoveAllCandidates = flag' Nothing $ fold
  [ long "remove-all-candidates"
  , help "When used, all current permissioned candidates will be removed."
  ]

updatePermissionedCandidatesSpec ∷ Parser TxEndpoint
updatePermissionedCandidatesSpec = ado
  permissionedCandidatesToAdd ← parseAddPermissionedCandidates
  permissionedCandidatesToRemove ←
    (parseRemoveAllCandidates <|> parseRemovePermissionedCandidates)
  in
    UpdatePermissionedCandidates
      { permissionedCandidatesToAdd, permissionedCandidatesToRemove }

burnNFTsSpec ∷ Parser TxEndpoint
burnNFTsSpec = pure BurnNFTs

initTokenStatusSpec ∷ Parser TxEndpoint
initTokenStatusSpec = pure InitTokenStatus

-- | Parse all parameters for the `candidiate-permission-token` endpoint
candidatePermissionTokenSpec ∷ Parser TxEndpoint
candidatePermissionTokenSpec = ado
  candidatePermissionTokenAmount ← option bigInt $ fold
    [ long "candidate-permission-token-amount"
    , metavar "INT"
    , help "Amount of the candidate permission token to be minted"
    ]
  in CandidiatePermissionTokenAct { candidatePermissionTokenAmount }

-- | `getAddrSpec` provides a parser for getting the required information for
-- | the `addresses` endpoint
getAddrSpec ∷ Parser TxEndpoint
getAddrSpec = ado
  usePermissionToken ← switch $ fold
    -- `switch` is
    --  No flag given ==> false
    --  Flag given ==> true
    [ long "use-candidate-permission-token"
    , help
        "Use candidate permission tokens during committee candidate registration"
    ]
  version ← parseVersion
  in
    GetAddrs
      { usePermissionToken
      , version
      }

ecdsaSecp256k1GenSpec ∷ Parser Options
ecdsaSecp256k1GenSpec = pure $
  UtilsOptions
    { utilsOptions: EcdsaSecp256k1KeyGenAct
    }

schnorrSecp256k1GenSpec ∷ Parser Options
schnorrSecp256k1GenSpec = pure $
  UtilsOptions
    { utilsOptions: SchnorrSecp256k1KeyGenAct
    }

ecdsaSecp256k1SignSpec ∷ Parser Options
ecdsaSecp256k1SignSpec = ado
  privateKey ←
    option ecdsaSecp256k1PrivateKey $ fold
      [ long "private-key"
      , metavar "SIDECHAIN_PRIVATE_KEY"
      , help "Hex encoded raw bytes of an ECDSA SECP256k1 private key"
      ]
  message ← option byteArray $ fold
    [ long "message"
    , metavar "MESSAGE"
    , help "Hex encoded raw bytes of a message to sign"
    ]
  noHashMessage ← switch $ fold
    -- `switch` is
    --  No flag given ==> false
    --  Flag given ==> true
    [ long "no-hash-message"
    , help "Do not hash the message with blake2b256 before signing"
    ]
  in
    UtilsOptions
      { utilsOptions:
          EcdsaSecp256k1SignAct
            { message
            , privateKey
            , noHashMessage
            }
      }

schnorrSecp256k1SignSpec ∷ Parser Options
schnorrSecp256k1SignSpec = ado
  privateKey ←
    option schnorrSecp256k1PrivateKey $ fold
      [ long "private-key"
      , metavar "SIDECHAIN_PRIVATE_KEY"
      , help "Hex encoded raw bytes of an Schnorr SECP256k1 private key"
      ]
  message ← option byteArray $ fold
    [ long "message"
    , metavar "MESSAGE"
    , help "Hex encoded raw bytes of a message to sign"
    ]
  noHashMessage ← switch $ fold
    -- `switch` is
    --  No flag given ==> false
    --  Flag given ==> true
    [ long "no-hash-message"
    , help "Do not hash the message with blake2b256 before signing"
    ]
  in
    UtilsOptions
      { utilsOptions:
          SchnorrSecp256k1SignAct
            { message
            , privateKey
            , noHashMessage
            }
      }

cborUpdateCommitteeMessageSpec ∷ Maybe Config → Parser Options
cborUpdateCommitteeMessageSpec mConfig = ado
  scParams ← sidechainParamsSpec mConfig
  sidechainEpoch ← parseSidechainEpoch
  previousMerkleRoot ← parsePreviousMerkleRoot
  newAggregatePubKeys ←
    option plutusDataParser $ fold
      [ long "cbor-aggregated-public-keys"
      , metavar "AGGREGATED_SIDECHAIN_PUBLIC_KEYS"
      , help "A CBOR encoded aggregated public key of the sidechain committee"
      ]
  validatorHash ← parseNewCommitteeValidatorHash
  in
    UtilsOptions
      { utilsOptions: CborUpdateCommitteeMessageAct
          { updateCommitteeHashMessage:
              UpdateCommitteeHashMessage
                { sidechainParams: scParams
                , newAggregatePubKeys
                , validatorHash
                , previousMerkleRoot
                , sidechainEpoch
                }
          }
      }

cborBlockProducerRegistrationMessageSpec ∷ Maybe Config → Parser Options
cborBlockProducerRegistrationMessageSpec mConfig = ado
  scParams ← sidechainParamsSpec mConfig
  scPublicKey ←
    option byteArray $ fold
      [ long "sidechain-public-key"
      , metavar "SIDECHAIN_PUB_KEY"
      , help "Sidechain public key"
      ]
  inputUtxo ← option Parsers.transactionInput $ fold
    [ long "input-utxo"
    , metavar "TX_ID#TX_IDX"
    , help "Input UTxO which must be spent by the transaction"
    ]

  in
    UtilsOptions
      { utilsOptions: CborBlockProducerRegistrationMessageAct
          { blockProducerRegistrationMsg:
              BlockProducerRegistrationMsg
                { bprmSidechainParams: scParams
                , bprmSidechainPubKey: scPublicKey
                , bprmInputUtxo: inputUtxo
                }
          }
      }

cborMerkleRootInsertionMessageSpec ∷ Maybe Config → Parser Options
cborMerkleRootInsertionMessageSpec mConfig = ado
  scParams ← sidechainParamsSpec mConfig
  merkleRoot ← parseMerkleRoot
  previousMerkleRoot ← parsePreviousMerkleRoot
  in
    UtilsOptions
      { utilsOptions: CborMerkleRootInsertionMessageAct
          { merkleRootInsertionMessage:
              MerkleRootInsertionMessage
                { sidechainParams: scParams
                , merkleRoot
                , previousMerkleRoot
                }
          }
      }

cborMerkleTreeEntrySpec ∷ Parser Options
cborMerkleTreeEntrySpec = ado
  index ← option bigInt $ fold
    [ long "index"
    , metavar "INDEX"
    , help "Integer to ensure uniqueness amongst Merkle tree entries"
    ]
  amount ← parseAmount
  recipient ← option bech32BytesParser $ fold
    [ long "recipient"
    , metavar "BECH32_ADDRESS"
    , help "Human readable bech32 address of the recipient."
    ]
  previousMerkleRoot ← parsePreviousMerkleRoot

  in
    UtilsOptions
      { utilsOptions:
          CborMerkleTreeEntryAct
            { merkleTreeEntry:
                MerkleTreeEntry
                  { index
                  , amount
                  , recipient
                  , previousMerkleRoot
                  }
            }
      }

parseCborMerkleTreeEntry ∷ Parser MerkleTreeEntry
parseCborMerkleTreeEntry = option plutusDataParser $ fold
  [ long "cbor-merkle-tree-entry"
  , metavar "CBOR_MERKLE_TREE_ENTRY"
  , help "Cbor encoded Merkle tree entry"
  ]

parseCborMerkleTree ∷ Parser MerkleTree
parseCborMerkleTree = option plutusDataParser $ fold
  [ long "cbor-merkle-tree"
  , metavar "CBOR_MERKLE_TREE"
  , help "Cbor encoded Merkle tree"
  ]

cborMerkleTreeSpec ∷ Parser Options
cborMerkleTreeSpec = ado
  merkleTreeEntries ← some parseCborMerkleTreeEntry
  in
    UtilsOptions
      { utilsOptions: CborMerkleTreeAct { merkleTreeEntries } }

cborPlainAggregatePublicKeys ∷ Parser Options
cborPlainAggregatePublicKeys = ado
  publicKeys ← some
    $ option byteArray
    $ fold
        [ long "public-key"
        , metavar "PUBLIC_KEY"
        , help "Hex encoded raw bytes of a sidechain public key"
        ]
  in
    UtilsOptions
      { utilsOptions: CborPlainAggregatePublicKeysAct { publicKeys } }

cborCombinedMerkleProofSpec ∷ Parser Options
cborCombinedMerkleProofSpec = ado
  merkleTreeEntry ← parseCborMerkleTreeEntry
  merkleTree ← parseCborMerkleTree
  in
    UtilsOptions
      { utilsOptions: CborCombinedMerkleProofAct { merkleTree, merkleTreeEntry } }

parseDepositAmount ∷ Parser BigNum
parseDepositAmount = option Parsers.tokenAmount
  ( fold
      [ long "reserve-initial-deposit-amount"
      , metavar "RESERVE-DEPOSIT-AMOUNT"
      , help "Inital amount of tokens to deposit"
      ]
  )

parseIncentiveAmount ∷ Parser BigInt
parseIncentiveAmount =
  let
    fparser =
      Parsers.positiveAmount
        "failed to parse incentive-amount"
        "incentive-amount amount must be non-negative"
  in
    option fparser
      ( fold
          [ long "reserve-initial-incentive-amount"
          , metavar "RESERVE-INCENTIVE-AMOUNT"
          , help "Incentive amount of tokens"
          , (value (BigInt.fromInt 0))
          , showDefault
          ]
      )

-- `parsePOSIXTime`
parserT0 ∷ Parser POSIXTime
parserT0 = option Parsers.posixTime
  ( fold
      [ long "reserve-posixtime-t0"
      , metavar "POSIXTIME"
      , help
          "Partner chain POSIX timestamp of the moment the reserve is launched"
      ]
  )

parseAssetName ∷ Parser AssetName
parseAssetName =
  ( option
      Parsers.assetNameParser
      ( fold
          [ long "reserve-asset-name"
          , metavar "RESERVE_ASSET_NAME"
          , help
              "Reserve native token assetName"
          ]
      )
  )

handOverReserveSpec ∷ Parser TxEndpoint
handOverReserveSpec = flag' HandoverReserve $ fold
  [ long "hand-over"
  , help "Hand Over Reserve Tokens"
  ]

parseAdaAsset ∷ Parser Asset
parseAdaAsset = flag' AdaAsset $ fold
  [ long "reserve-ada-asset"
  , help "Use Ada for reserve asset"
  ]

parseAsset ∷ String → String → Parser Asset
parseAsset long' metavar' =
  ( Asset
      <$>
        ( option validatorHashParser
            ( fold
                [ long long'
                , metavar metavar'
                , help "Hex encoded hash string"
                ]
            )
        )
      <*> parseAssetName
  )
    <|>
      parseAdaAsset

parseImmutableReserveSettings ∷ Parser ImmutableReserveSettings
parseImmutableReserveSettings = ado
  t0 ← parserT0
  tokenKind ← parseAsset "reserve-asset-script-hash" "ASSET-SCRIPT-HASH"
  in ImmutableReserveSettings { t0, tokenKind }

parseMutableReserveSettings ∷ Parser MutableReserveSettings
parseMutableReserveSettings = ado
  vFunctionTotalAccrued ←
    ( option validatorHashParser
        ( fold
            [ long "total-accrued-function-script-hash"
            , metavar "SCRIPT-HASH"
            , help "Hex encoded hash string"
            ]
        )
    )

  incentiveAmount ← parseIncentiveAmount
  in MutableReserveSettings { vFunctionTotalAccrued, incentiveAmount }

createReserveSpec ∷ Parser TxEndpoint
createReserveSpec = ado
  mutableReserveSettings ← parseMutableReserveSettings
  immutableReserveSettings ← parseImmutableReserveSettings
  depositAmount ← parseDepositAmount
  in
    CreateReserve
      { mutableReserveSettings
      , immutableReserveSettings
      , depositAmount
      }

depositReserveSpec ∷ Parser TxEndpoint
depositReserveSpec = ado
  asset ← parseAsset "deposit-reserve-asset" "ASSET-SCRIPT-HASH"
  depositAmount ← parseDepositAmount
  in
    DepositReserve { asset, depositAmount }

parseUnit ∷ Parser UInt
parseUnit = option uint $ fold
  [ long "total-accrued-till-now"
  , metavar "INT"
  , help "Computerd integer for the v(t)"
  ]

releaseReserveFundsSpec ∷ Parser TxEndpoint
releaseReserveFundsSpec = ado
  totalAccruedTillNow ← UInt.toInt <$> parseUnit
  transactionInput ← parseTransactionInput
  in
    ReleaseReserveFunds
      { totalAccruedTillNow
      , transactionInput
      }

parseTransactionInput ∷ Parser TransactionInput
parseTransactionInput =
  option Parsers.transactionInput $ fold
    [ long "reserve-transaction-input"
    , metavar "RESERVE-TRANSACTION-INPUT"
    , help
        "Transaction input of the policy script for to transfer illiquid circulation"
    ]
