{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TemplateHaskell #-}

module TrustlessSidechain.OffChain.Types where

import Control.DeepSeq (NFData)
import Data.Aeson.TH (defaultOptions, deriveJSON)
import Data.Bifunctor (bimap)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as Char8
import Data.Either (fromRight)
import Data.String (IsString (fromString))
import GHC.Generics (Generic)
import Ledger (PaymentPubKeyHash)
import Ledger.Crypto (PubKey, Signature)
import Ledger.Tx (TxOutRef)
import Plutus.V1.Ledger.Bytes (LedgerBytes (LedgerBytes))
import PlutusTx (FromData, ToData, UnsafeFromData)
import PlutusTx qualified
import PlutusTx.Lift (makeLift)
import PlutusTx.Prelude hiding (Semigroup ((<>)))
import PlutusTx.Prelude qualified as PlutusTx
import Schema (ToSchema)
import Prelude qualified

newtype GenesisHash = GenesisHash {getGenesisHash :: PlutusTx.BuiltinByteString}
  deriving (IsString, Prelude.Show) via LedgerBytes
  deriving stock (Generic)
  deriving newtype (Prelude.Eq, Prelude.Ord, Eq, Ord, ToData, FromData, UnsafeFromData)
  deriving anyclass (NFData, ToSchema)

makeLift ''GenesisHash

$(deriveJSON defaultOptions ''GenesisHash)

newtype SidechainPubKey = SidechainPubKey {getSidechainPubKey :: (PlutusTx.BuiltinByteString, PlutusTx.BuiltinByteString)}
  deriving stock (Generic)
  deriving newtype (Prelude.Eq, Prelude.Ord, Eq, Ord, ToData, FromData, UnsafeFromData)
  deriving anyclass (NFData, ToSchema)

instance IsString SidechainPubKey where
  fromString =
    mkSidechainPubKey
      . fromRight (error ())
      . Base16.decode
      . fromString

instance Prelude.Show SidechainPubKey where
  show =
    Char8.unpack
      . Base16.encode
      . PlutusTx.fromBuiltin
      . uncurry PlutusTx.appendByteString
      . getSidechainPubKey

mkSidechainPubKey :: ByteString -> SidechainPubKey
mkSidechainPubKey =
  SidechainPubKey
    . bimap PlutusTx.toBuiltin PlutusTx.toBuiltin
    . ByteString.splitAt 32

makeLift ''SidechainPubKey

$(deriveJSON defaultOptions ''SidechainPubKey)

-- | Parameters uniquely identifying a sidechain
data SidechainParams = SidechainParams
  { chainId :: Integer
  , genesisHash :: GenesisHash
  }
  deriving stock (Prelude.Show, Generic)
  deriving anyclass (ToSchema)

$(deriveJSON defaultOptions ''SidechainParams)
PlutusTx.makeLift ''SidechainParams

PlutusTx.makeIsDataIndexed ''SidechainParams [('SidechainParams, 0)]

-- | Endpoint parameters for committee candidate registration
data RegisterParams = RegisterParams
  { sidechainParams :: !SidechainParams
  , spoPubKey :: !PubKey
  , sidechainPubKey :: !SidechainPubKey
  , spoSig :: !Signature
  , sidechainSig :: !Signature
  , inputUtxo :: !TxOutRef
  }
  deriving stock (Generic, Prelude.Show)
  deriving anyclass (ToSchema)

$(deriveJSON defaultOptions ''RegisterParams)

-- | Endpoint parameters for committee candidate deregistration
data DeregisterParams = DeregisterParams
  { sidechainParams :: !SidechainParams
  , spoPubKey :: !PubKey
  }
  deriving stock (Generic, Prelude.Show)
  deriving anyclass (ToSchema)

$(deriveJSON defaultOptions ''DeregisterParams)

data BurnParams = BurnParams
  { -- | Burnt amount in FUEL (Negative)
    amount :: Integer
  , -- | SideChain address
    recipient :: BuiltinByteString
  , -- | passed for parametrization
    sidechainParams :: SidechainParams
  }
  deriving stock (Generic, Prelude.Show)
  deriving anyclass (ToSchema)

$(deriveJSON defaultOptions ''BurnParams)

data MintParams = MintParams
  { -- | Minted amount in FUEL (Positive)
    amount :: Integer
  , -- | MainChain address
    recipient :: PaymentPubKeyHash
  , -- | passed for parametrization
    sidechainParams :: SidechainParams
    -- , proof :: MerkleProof
  }
  deriving stock (Generic, Prelude.Show)
  deriving anyclass (ToSchema)

$(deriveJSON defaultOptions ''MintParams)
