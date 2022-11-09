module SidechainParams where

import Contract.Prelude

import Contract.PlutusData (class ToData, PlutusData(Constr), toData)
import Contract.Prim.ByteArray (ByteArray)
import Data.BigInt (BigInt)
import Data.BigInt as BigInt
import Data.Codec.Argonaut as CA
import Data.Codec.Argonaut.Compat as CAC
import Data.Codec.Argonaut.Record as CAR
import Data.Profunctor (wrapIso)
import Partial.Unsafe (unsafePartial)
import Types (PubKey)
import Types.Transaction (TransactionInput)
import Utils.Codecs (byteArrayCodec, transactionInputCodec)

newtype SidechainParams = SidechainParams
  { chainId ∷ BigInt
  , genesisHash ∷ ByteArray
  , genesisMint ∷ Maybe TransactionInput
  , genesisUtxo ∷ TransactionInput
  ,
    -- 'thresholdNumerator' is the numerator of the ratio required for the
    -- committee to verify that committee has signed something (e.g. updating the
    -- committee hash, or saving a new merkle root).
    thresholdNumerator ∷ BigInt
  ,
    -- 'thresholdDenominator' is the denominator of the ratio required for the
    -- committee to verify that committee has signed something (e.g. updating the
    -- committee hash, or saving a new merkle root).
    thresholdDenominator ∷ BigInt
  }

derive instance Generic SidechainParams _
derive instance Newtype SidechainParams _
instance ToData SidechainParams where
  toData
    ( SidechainParams
        { chainId
        , genesisHash
        , genesisMint
        , genesisUtxo
        , thresholdNumerator
        , thresholdDenominator
        }
    ) =
    Constr zero
      [ toData chainId
      , toData genesisHash
      , toData genesisMint
      , toData genesisUtxo
      , toData thresholdNumerator
      , toData thresholdDenominator
      ]

instance Show SidechainParams where
  show = genericShow

-- | Parameters to initialize a sidechain
newtype InitSidechainParams = InitSidechainParams
  { initChainId ∷ BigInt
  , initGenesisHash ∷ ByteArray
  , -- | 'initUtxo ' is a 'TxOutRef' used for creating 'AssetClass's for the
    -- internal function of the side chain (e.g. InitCommitteeHashMint TODO: hyperlink this documentation)
    initUtxo ∷ TransactionInput
  , -- | 'initCommittee' is the initial committee of the sidechain
    initCommittee ∷ Array PubKey
  , -- | 'initSidechainEpoch' is the initial sidechain epoch of the sidechain
    initSidechainEpoch ∷ BigInt
  , initMint ∷ Maybe TransactionInput
  , initThresholdNumerator ∷ BigInt
  , initThresholdDenominator ∷ BigInt
  }

derive instance Generic InitSidechainParams _
derive instance Newtype InitSidechainParams _
instance ToData InitSidechainParams where
  toData
    ( InitSidechainParams
        { initChainId
        , initGenesisHash
        , initUtxo
        , initCommittee
        , initMint
        , initThresholdNumerator
        , initThresholdDenominator
        }
    ) =
    Constr zero
      [ toData initChainId
      , toData initGenesisHash
      , toData initUtxo
      , toData initCommittee
      , toData initMint
      , toData initThresholdNumerator
      , toData initThresholdDenominator
      ]

instance Show InitSidechainParams where
  show = genericShow

scParamsCodec ∷ CA.JsonCodec SidechainParams
scParamsCodec =
  wrapIso SidechainParams $
    ( CAR.object "sidechainParameters"
        { chainId: chainIdCodec
        , genesisHash: byteArrayCodec
        , genesisMint: CAC.maybe transactionInputCodec
        , genesisUtxo: transactionInputCodec
        , thresholdNumerator:
            CA.prismaticCodec "thresholdNumerator"
              (Just <<< BigInt.fromInt)
              unsafeToInt
              CA.int
        , thresholdDenominator:
            CA.prismaticCodec "thresholdDenominator"
              (Just <<< BigInt.fromInt)
              unsafeToInt
              CA.int
        }
    )
  where
  chainIdCodec ∷ CA.JsonCodec BigInt
  chainIdCodec = CA.prismaticCodec "chainId"
    (Just <<< BigInt.fromInt)
    unsafeToInt
    CA.int

  unsafeToInt ∷ BigInt → Int
  unsafeToInt x = unsafePartial $ fromJust $ BigInt.toInt x
