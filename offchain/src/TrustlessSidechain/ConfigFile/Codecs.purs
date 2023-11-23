module TrustlessSidechain.ConfigFile.Codecs
  ( committeeSignaturesCodec
  , committeeCodec
  , configCodec
  , sidechainSignatureCodec
  , sidechainPubKeyCodec
  ) where

import Contract.Prelude

import Contract.Address (NetworkId(MainnetId, TestnetId))
import Contract.Config (ServerConfig)
import Contract.Prim.ByteArray (ByteArray)
import Contract.Transaction (TransactionInput)
import Data.Codec.Argonaut as CA
import Data.Codec.Argonaut.Common as CAM
import Data.Codec.Argonaut.Compat as CAC
import Data.Codec.Argonaut.Record as CAR
import Data.List (List)
import Data.UInt as UInt
import TrustlessSidechain.CommitteeATMSSchemes.Types (ATMSKinds)
import TrustlessSidechain.Options.Types (Config)
import TrustlessSidechain.Utils.Codecs
  ( atmsKindCodec
  , byteArrayCodec
  , thresholdCodec
  , transactionInputCodec
  )
import TrustlessSidechain.Utils.Crypto
  ( EcdsaSecp256k1PubKey
  , EcdsaSecp256k1Signature
  , getEcdsaSecp256k1PubKeyByteArray
  , getEcdsaSecp256k1SignatureByteArray
  )
import TrustlessSidechain.Utils.Crypto as Utils.Crypto

configCodec ∷ CA.JsonCodec Config
configCodec =
  CA.object "Config file"
    ( CAR.record
        { sidechainParameters: CAC.maybe scParamsCodec
        , paymentSigningKeyFile: CAC.maybe CA.string
        , stakeSigningKeyFile: CAC.maybe CA.string
        , runtimeConfig: CAC.maybe runtimeConfigCodec
        }
    )
  where
  scParamsCodec ∷
    CA.JsonCodec
      { chainId ∷ Maybe Int
      , genesisUtxo ∷ Maybe TransactionInput
      , threshold ∷
          Maybe
            { denominator ∷ Int
            , numerator ∷ Int
            }
      , atmsKind ∷ Maybe ATMSKinds
      , governanceAuthority ∷ Maybe ByteArray
      }
  scParamsCodec =
    ( CAR.object "sidechainParameters"
        { chainId: CAC.maybe CA.int
        , genesisUtxo: CAC.maybe transactionInputCodec
        , threshold: CAC.maybe thresholdCodec
        , atmsKind: CAC.maybe atmsKindCodec
        , governanceAuthority: CAC.maybe byteArrayCodec
        }
    )

  runtimeConfigCodec ∷
    CA.JsonCodec
      { kupo ∷ Maybe ServerConfig
      , network ∷ Maybe NetworkId
      , ogmios ∷ Maybe ServerConfig
      }
  runtimeConfigCodec =
    ( CAR.object "runtimeConfig"
        { ogmios: CAC.maybe serverConfigCodec
        , kupo: CAC.maybe serverConfigCodec
        , network: CAC.maybe networkIdCodec
        }
    )

-- | Accepts the format: `[ {"public-key":"aabb...", "signature":null}, ... ]`
committeeSignaturesCodec ∷
  CA.JsonCodec (List (ByteArray /\ Maybe ByteArray))
committeeSignaturesCodec = CAM.list memberCodec
  where
  memberRecord ∷
    CA.JsonCodec
      { "public-key" ∷ ByteArray
      , signature ∷ Maybe ByteArray
      }
  memberRecord = CAR.object "member"
    { "public-key": byteArrayCodec
    , "signature": CAC.maybe byteArrayCodec
    }

  memberCodec ∷
    CA.JsonCodec (Tuple ByteArray (Maybe ByteArray))
  memberCodec = CA.prismaticCodec "member" dec enc memberRecord

  dec ∷
    { "public-key" ∷ ByteArray
    , signature ∷ Maybe ByteArray
    } →
    Maybe (Tuple ByteArray (Maybe ByteArray))
  dec { "public-key": p, signature } = Just (p /\ signature)

  enc ∷
    Tuple ByteArray (Maybe ByteArray) →
    { "public-key" ∷ ByteArray
    , signature ∷ Maybe ByteArray
    }
  enc (p /\ signature) = { "public-key": p, signature }

-- | Accepts the format `[ {"public-key":"aabb..."}, ... ]`
committeeCodec ∷ CA.JsonCodec (List ByteArray)
committeeCodec = CAM.list memberCodec
  where
  memberCodec ∷ CA.JsonCodec ByteArray
  memberCodec = CA.prismaticCodec "member" dec enc $ CAR.object "member"
    { "public-key": byteArrayCodec }

  dec ∷
    { "public-key" ∷ ByteArray
    } →
    Maybe ByteArray
  dec { "public-key": p } = Just p

  enc ∷
    ByteArray →
    { "public-key" ∷ ByteArray
    }
  enc p = { "public-key": p }

sidechainPubKeyCodec ∷ CA.JsonCodec EcdsaSecp256k1PubKey
sidechainPubKeyCodec = CA.prismaticCodec "EcdsaSecp256k1PubKey" dec enc
  byteArrayCodec
  where
  dec ∷ ByteArray → Maybe EcdsaSecp256k1PubKey
  dec = Utils.Crypto.ecdsaSecp256k1PubKey

  enc ∷ EcdsaSecp256k1PubKey → ByteArray
  enc = getEcdsaSecp256k1PubKeyByteArray

sidechainSignatureCodec ∷ CA.JsonCodec EcdsaSecp256k1Signature
sidechainSignatureCodec = CA.prismaticCodec "EcdsaSecp256k1Signature" dec enc
  byteArrayCodec
  where
  dec ∷ ByteArray → Maybe EcdsaSecp256k1Signature
  dec = Utils.Crypto.ecdsaSecp256k1Signature

  enc ∷ EcdsaSecp256k1Signature → ByteArray
  enc = getEcdsaSecp256k1SignatureByteArray

serverConfigCodec ∷ CA.JsonCodec ServerConfig
serverConfigCodec = CAR.object "serverConfig"
  { host: CA.string
  , port: CA.prismaticCodec "UInt" UInt.fromInt' UInt.toInt CA.int
  , secure: CA.boolean
  , path: CAC.maybe CA.string
  }

networkIdCodec ∷ CA.JsonCodec NetworkId
networkIdCodec = CA.prismaticCodec "Network" dec enc CA.string
  where
  dec ∷ String → Maybe NetworkId
  dec = case _ of
    "mainnet" → Just MainnetId
    "testnet" → Just TestnetId
    _ → Nothing

  enc ∷ NetworkId → String
  enc = case _ of
    MainnetId → "mainnet"
    TestnetId → "testnet"
