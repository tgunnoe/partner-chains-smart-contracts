module Options
  (
    -- * CLI parsing
    getOptions
  ,
    -- * Internal parsers
    parsePubKeyAndSignature
  ) where

import Contract.Prelude

import ConfigFile (decodeConfig, readJson)
import Contract.Config
  ( PrivateStakeKeySource(..)
  , ServerConfig
  , defaultDatumCacheWsConfig
  , defaultOgmiosWsConfig
  , defaultServerConfig
  , testnetConfig
  )
import Contract.Transaction (TransactionHash(..), TransactionInput(..))
import Contract.Wallet (PrivatePaymentKeySource(..), WalletSpec(..))
import Control.Bind as Bind
import Data.Array.NonEmpty as NonEmpty
import Data.Bifunctor (lmap)
import Data.BigInt (BigInt)
import Data.BigInt as BigInt
import Data.List (List)
import Data.String (Pattern(Pattern), split)
import Data.String.Regex (Regex)
import Data.String.Regex as Regex
import Data.String.Regex.Flags as Regex.Flags
import Data.String.Regex.Unsafe as Regex.Unsafe
import Data.UInt (UInt)
import Data.UInt as UInt
import Effect.Exception (error)
import Helpers (logWithLevel)
import Options.Applicative
  ( Parser
  , ParserInfo
  , ReadM
  , action
  , command
  , execParser
  , flag
  , fullDesc
  , header
  , help
  , helper
  , hsubparser
  , info
  , int
  , long
  , many
  , maybeReader
  , metavar
  , option
  , progDesc
  , short
  , showDefault
  , str
  , value
  )
import Options.Types (Config, Endpoint(..), Options)
import SidechainParams (SidechainParams(..))
import Types (PubKey, Signature)
import Types.ByteArray (ByteArray, hexToByteArray)
import Utils.Logging (environment, fileLogger)

-- | Argument option parser for ctl-main
options ∷ Maybe Config → ParserInfo Options
options maybeConfig = info (helper <*> optSpec)
  ( fullDesc <> header
      "ctl-main - CLI application to execute TrustlessSidechain Cardano endpoints"
  )
  where
  optSpec =
    hsubparser $ fold
      [ command "addresses"
          ( info (withCommonOpts (pure GetAddrs))
              (progDesc "Get the script addresses for a given sidechain")
          )
      , command "mint"
          ( info (withCommonOpts mintSpec)
              (progDesc "Mint a certain amount of FUEL tokens")
          )
      , command "burn"
          ( info (withCommonOpts burnSpec)
              (progDesc "Burn a certain amount of FUEL tokens")
          )
      , command "register"
          ( info (withCommonOpts regSpec)
              (progDesc "Register a committee candidate")
          )
      , command "deregister"
          ( info (withCommonOpts deregSpec)
              (progDesc "Deregister a committee member")
          )
      , command "committee-hash"
          ( info (withCommonOpts committeeHashSpec)
              (progDesc "Update the committee hash")
          )
      , command "saveRoot"
          ( info (withCommonOpts saveRootSpec)
              (progDesc "Saving a new merkle root")
          )
      ]

  withCommonOpts endpointParser = ado
    pSkey ← pSkeySpec
    stSkey ← stSKeySpec
    scParams ← scParamsSpec
    endpoint ← endpointParser

    ogmiosConfig ← serverConfigSpec "ogmios" $
      fromMaybe defaultOgmiosWsConfig
        (maybeConfig >>= _.runtimeConfig >>= _.ogmios)

    datumCacheConfig ← serverConfigSpec "ogmios-datum-cache" $
      fromMaybe defaultDatumCacheWsConfig
        (maybeConfig >>= _.runtimeConfig >>= _.ogmiosDatumCache)

    ctlServerConfig ← serverConfigSpec "ctl-server" $
      fromMaybe defaultServerConfig
        (maybeConfig >>= _.runtimeConfig >>= _.ctlServer)
    in
      { scParams
      , endpoint
      , configParams: testnetConfig
          { logLevel = environment.logLevel
          , suppressLogs = not environment.isTTY
          , customLogger = Just
              \m → fileLogger m *> logWithLevel environment.logLevel m
          , walletSpec = Just $ UseKeys
              (PrivatePaymentKeyFile pSkey)
              (PrivateStakeKeyFile <$> stSkey)
          , ctlServerConfig = Just ctlServerConfig
          , datumCacheConfig = datumCacheConfig
          , ogmiosConfig = ogmiosConfig
          }
      }

  pSkeySpec =
    option str $ fold
      [ short 'k'
      , long "payment-signing-key-file"
      , metavar "/absolute/path/to/payment.skey"
      , help "Own payment signing key file path"
      , action "file"
      , maybe mempty value (maybeConfig >>= _.paymentSigningKeyFile)
      ]

  stSKeySpec =
    optional $ option str $ fold
      [ short 'K'
      , long "stake-signing-key-file"
      , metavar "/absolute/path/to/stake.skey"
      , help "Own stake signing key file path"
      , action "file"
      , maybe mempty value (maybeConfig >>= _.stakeSigningKeyFile)
      ]

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

  scParamsSpec = ado
    chainId ← option int $ fold
      [ short 'i'
      , long "sidechain-id"
      , metavar "1"
      , help "Sidechain ID"
      , maybe mempty value
          (maybeConfig >>= _.sidechainParameters >>= _.chainId)
      ]

    genesisHash ← option byteArray $ fold
      [ short 'h'
      , long "sidechain-genesis-hash"
      , metavar "GENESIS_HASH"
      , help "Sidechain genesis hash"
      , maybe mempty value
          (maybeConfig >>= _.sidechainParameters >>= _.genesisHash)
      ]

    genesisMint ← optional $ option transactionInput $ fold
      [ short 'm'
      , long "genesis-mint-utxo"
      , metavar "TX_ID#TX_IDX"
      , help "Input UTxO to be spend with the genesis mint"
      , maybe mempty value
          (maybeConfig >>= _.sidechainParameters >>= _.genesisMint)
      ]
    genesisUtxo ← option transactionInput $ fold
      [ short 'c'
      , long "genesis-committee-hash-utxo"
      , metavar "TX_ID#TX_IDX"
      , help "Input UTxO to be spent with the first committee hash setup"
      , maybe mempty value
          (maybeConfig >>= _.sidechainParameters >>= _.genesisUtxo)
      ]
    in
      SidechainParams
        { chainId: BigInt.fromInt chainId
        , genesisHash
        , genesisMint
        , genesisUtxo
        }

  mintSpec = MintAct <<< { amount: _ } <$> parseAmount

  burnSpec = ado
    amount ← parseAmount
    recipient ← option sidechainAddress $ fold
      [ long "recipient"
      , metavar "ADDRESS"
      , help "Address of the sidechain recipient"
      ]
    in BurnAct { amount, recipient }

  parseAmount = option bigInt $ fold
    [ short 'a'
    , long "amount"
    , metavar "1"
    , help "Amount of FUEL token to be burnt/minted"
    ]

  regSpec = ado
    spoPubKey ← parseSpoPubKey
    sidechainPubKey ← option byteArray $ fold
      [ long "sidechain-public-key"
      , metavar "PUBLIC_KEY"
      , help "Sidechain public key value"
      ]
    spoSig ← option byteArray $ fold
      [ long "spo-signature"
      , metavar "SIGNATURE"
      , help "SPO signature"
      ]
    sidechainSig ← option byteArray $ fold
      [ long "sidechain-signature"
      , metavar "SIGNATURE"
      , help "Sidechain signature"
      ]
    inputUtxo ← option transactionInput $ fold
      [ long "registration-utxo"
      , metavar "TX_ID#TX_IDX"
      , help "Input UTxO to be spend with the commitee candidate registration"
      ]
    in
      CommitteeCandidateReg
        { spoPubKey
        , sidechainPubKey
        , spoSig
        , sidechainSig
        , inputUtxo
        }

  deregSpec = CommitteeCandidateDereg <<< { spoPubKey: _ } <$> parseSpoPubKey

  parseSpoPubKey = option byteArray $ fold
    [ long "spo-public-key"
    , metavar "PUBLIC_KEY"
    , help "SPO cold verification key value"
    ]

  committeeHashSpec ∷ Parser Endpoint
  committeeHashSpec =
    CommitteeHash <$>
      ( { newCommitteePubKeys: _, committeeSignatures: _, previousMerkleRoot: _ }
          <$>
            many
              ( option
                  byteArray
                  ( fold
                      [ long "new-committee-pub-key"
                      , metavar "PUBLIC_KEY"
                      , help "Public key of a new committee member"
                      ]
                  )
              )
          <*>
            parseCommitteeSignatures
          <*>
            parsePreviousMerkleRoot
      )

  saveRootSpec ∷ Parser Endpoint
  saveRootSpec =
    SaveRoot <$>
      ( { merkleRoot: _, previousMerkleRoot: _, committeeSignatures: _ }
          <$>
            option
              byteArray
              ( fold
                  [ long "merkle-root"
                  , metavar "MERKLE_ROOT"
                  , help "Merkle root signed by the committee"
                  ]
              )
          <*>
            parsePreviousMerkleRoot
          <*>
            parseCommitteeSignatures
      )

  -- | 'parsePreviousMerkleRoot' gives the options for parsing a merkle root (this is
  -- used in both @saveRootSpec@ and @committeeHashSpec@).
  parsePreviousMerkleRoot ∷ Parser (Maybe ByteArray)
  parsePreviousMerkleRoot =
    optional
      ( option
          (byteArray)
          ( fold
              [ long "previous-merkle-root"
              , metavar "MERKLE_ROOT"
              , help "Hex encoded previous merkle root if it exists"
              ]
          )
      )

  -- | 'parseCommitteeSignatures' gives the options for parsing the current
  -- committees' signatures. This is used in both @saveRootSpec@ and
  -- @committeeHashSpec@).
  parseCommitteeSignatures ∷ Parser (List (PubKey /\ Maybe Signature))
  parseCommitteeSignatures =
    many
      ( option
          committeeSignature
          ( fold
              [ long "committee-pub-key-and-signature"
              , metavar "PUBLIC_KEY[:[SIGNATURE]]"
              , help
                  "Public key and (optionally) the signature of a committee member seperated by a colon ':'"
              ]
          )
      )

-- | Reading configuration file from `./config.json`, and parsing CLI arguments. CLI argmuents override the config file.
getOptions ∷ Effect Options
getOptions = do
  config ← readAndParseJsonFrom "./config.json"
  execParser (options config)

  where
  readAndParseJsonFrom loc = do
    json' ← hush <$> readJson loc
    traverse decodeConfigUnsafe json'

  decodeConfigUnsafe json =
    liftEither $ lmap (error <<< show) $ decodeConfig json

-- * Custom Parsers

-- | Parse a transaction input from a CLI format (e.g. aabbcc#0)
transactionInput ∷ ReadM TransactionInput
transactionInput = maybeReader \txIn →
  case split (Pattern "#") txIn of
    [ txId, txIdx ] → ado
      index ← UInt.fromString txIdx
      transactionId ← TransactionHash <$> hexToByteArray txId
      in
        TransactionInput
          { transactionId
          , index
          }
    _ → Nothing

-- | Parse ByteArray from hexadecimal representation
byteArray ∷ ReadM ByteArray
byteArray = maybeReader hexToByteArray

-- | Parse BigInt
bigInt ∷ ReadM BigInt
bigInt = maybeReader BigInt.fromString

-- | Parse UInt
uint ∷ ReadM UInt
uint = maybeReader UInt.fromString

-- | 'sidechainAddress' parses
--    >  sidechainAddress
--    >         -> 0x hexStr
--    >         -> hexStr
-- where @hexStr@ is a sequence of hex digits.
sidechainAddress ∷ ReadM ByteArray
sidechainAddress = maybeReader $ \str →
  case split (Pattern "0x") str of
    [ "", hex ] → hexToByteArray hex
    [ hex ] → hexToByteArray hex
    _ → Nothing

-- | 'committeeSignature' is a wrapper around 'parsePubKeyAndSignature'.
committeeSignature ∷ ReadM (ByteArray /\ Maybe ByteArray)
committeeSignature = maybeReader $ \str → do
  { pubKey, signature } ← parsePubKeyAndSignature str
  -- For performance, I suppose we could actually use the unsafe version of
  -- 'hexToByteArray'
  pubKey' ← hexToByteArray pubKey
  signature' ← case signature of
    Nothing → pure Nothing
    Just sig → do
      sig' ← hexToByteArray sig
      pure $ Just sig'
  pure $ pubKey' /\ signature'

-- | 'parsePubKeyAndSignature' parses (in EBNF)
--    >  sidechainAddress
--    >         -> hexStr[:[hexStr]]
-- where @hexStr@ is a sequence of non empty hex digits i.e, it parses a @hexStr@
-- public key, followed by an equal sign, followed by an optional signature
-- @hexStr@.
parsePubKeyAndSignature ∷
  String →
  Maybe
    { -- hex encoded pub key
      pubKey ∷ String
    , -- hex encoded signature (if it exists)
      signature ∷ Maybe String
    }
parsePubKeyAndSignature input = do
  matches ← Regex.match pubKeyAndSignatureRegex input
  pubKey ← Bind.join $ NonEmpty.index matches 1
  signature ← NonEmpty.index matches 2
  pure $ { pubKey, signature }

-- Regexes tend to be a bit unreadable.. As a EBNF grammar, we're matching:
--   > pubKeyAndSig
--   >      -> hexStr [ ':' [hexStr]]
-- where `hexStr` is a a sequence of non empty hex digits of even length (the even
-- length requirement is imposed by 'Contract.Prim.ByteArray.hexToByteArray').
-- i.e., we are parsing a `hexStr` followed optionally by a colon ':', and
-- followed optionally by another non empty `hexStr`.
pubKeyAndSignatureRegex ∷ Regex
pubKeyAndSignatureRegex =
  Regex.Unsafe.unsafeRegex
    """^((?:[0-9a-f]{2})+)(?::((?:[0-9a-f]{2})+)?)?$"""
    Regex.Flags.ignoreCase
