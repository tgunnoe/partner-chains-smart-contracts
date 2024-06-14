module TrustlessSidechain.NativeTokenManagement.Types
  ( ImmutableReserveSettings(..)
  , MutableReserveSettings(..)
  , ReserveStats(..)
  , ReserveDatum(..)
  , ReserveRedeemer(..)
  , IlliquidCirculationSupplyRedeemer(..)
  ) where

import Contract.Prelude

import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class FromData
  , class ToData
  , PlutusData(..)
  , fromData
  , toData
  )
import Contract.Value (CurrencySymbol)
import Ctl.Internal.Types.Interval (POSIXTime)
import Data.BigInt as BigInt
import TrustlessSidechain.Types (AssetClass)
import TrustlessSidechain.Utils.Data
  ( productFromData2
  , productFromData3
  , productToData2
  , productToData3
  )

newtype ImmutableReserveSettings = ImmutableReserveSettings
  { t0 ∷ POSIXTime
  , tokenKind ∷ AssetClass
  }

derive instance Generic ImmutableReserveSettings _
derive instance Newtype ImmutableReserveSettings _
derive newtype instance Eq ImmutableReserveSettings
derive newtype instance Show ImmutableReserveSettings

instance ToData ImmutableReserveSettings where
  toData (ImmutableReserveSettings { t0, tokenKind }) =
    productToData2 t0 tokenKind

instance FromData ImmutableReserveSettings where
  fromData = productFromData2
    ( \x y →
        ImmutableReserveSettings { t0: x, tokenKind: y }
    )

newtype MutableReserveSettings = MutableReserveSettings
  { vFunctionTotalAccrued ∷ CurrencySymbol
  }

derive newtype instance Eq MutableReserveSettings

derive instance Generic MutableReserveSettings _

derive instance Newtype MutableReserveSettings _

instance Show MutableReserveSettings where
  show = genericShow

instance ToData MutableReserveSettings where
  toData (MutableReserveSettings { vFunctionTotalAccrued }) = toData
    vFunctionTotalAccrued

instance FromData MutableReserveSettings where
  fromData dat = do
    vFunctionTotalAccrued ← fromData dat
    pure $ MutableReserveSettings { vFunctionTotalAccrued }

newtype ReserveStats = ReserveStats
  { tokenTotalAmountTransferred ∷ BigInt.BigInt
  }

derive newtype instance Eq ReserveStats

derive instance Generic ReserveStats _

derive instance Newtype ReserveStats _

instance Show ReserveStats where
  show = genericShow

instance ToData ReserveStats where
  toData (ReserveStats { tokenTotalAmountTransferred }) = toData
    tokenTotalAmountTransferred

instance FromData ReserveStats where
  fromData dat = do
    tokenTotalAmountTransferred ← fromData dat
    pure $ ReserveStats { tokenTotalAmountTransferred }

newtype ReserveDatum = ReserveDatum
  { immutableSettings ∷ ImmutableReserveSettings
  , mutableSettings ∷ MutableReserveSettings
  , stats ∷ ReserveStats
  }

derive instance Generic ReserveDatum _
derive instance Newtype ReserveDatum _
derive newtype instance Eq ReserveDatum
derive newtype instance Show ReserveDatum

instance ToData ReserveDatum where
  toData (ReserveDatum { immutableSettings, mutableSettings, stats }) =
    productToData3 immutableSettings mutableSettings stats

instance FromData ReserveDatum where
  fromData = productFromData3
    ( \x y z →
        ReserveDatum { immutableSettings: x, mutableSettings: y, stats: z }
    )

data ReserveRedeemer
  = DepositToReserve
  | TransferToIlliquidCirculationSupply
  | UpdateReserve
  | Handover

derive instance Eq ReserveRedeemer

derive instance Generic ReserveRedeemer _

instance Show ReserveRedeemer where
  show = genericShow

instance ToData ReserveRedeemer where
  toData DepositToReserve = Integer (BigInt.fromInt 0)
  toData TransferToIlliquidCirculationSupply = Integer (BigInt.fromInt 1)
  toData UpdateReserve = Integer (BigInt.fromInt 2)
  toData Handover = Integer (BigInt.fromInt 3)

instance FromData ReserveRedeemer where
  fromData = case _ of
    Integer tag | tag == BigInt.fromInt 0 → pure DepositToReserve
    Integer tag | tag == BigInt.fromInt 1 → pure
      TransferToIlliquidCirculationSupply
    Integer tag | tag == BigInt.fromInt 2 → pure UpdateReserve
    Integer tag | tag == BigInt.fromInt 3 → pure Handover
    _ → Nothing

data IlliquidCirculationSupplyRedeemer
  = DepositMoreToSupply
  | WithdrawFromSupply

derive instance Eq IlliquidCirculationSupplyRedeemer

derive instance Generic IlliquidCirculationSupplyRedeemer _

instance Show IlliquidCirculationSupplyRedeemer where
  show = genericShow

instance ToData IlliquidCirculationSupplyRedeemer where
  toData DepositMoreToSupply = Constr (BigNum.fromInt 0) []
  toData WithdrawFromSupply = Constr (BigNum.fromInt 1) []

instance FromData IlliquidCirculationSupplyRedeemer where
  fromData = case _ of
    Constr tag [] | tag == BigNum.fromInt 0 → pure DepositMoreToSupply
    Constr tag [] | tag == BigNum.fromInt 1 → pure WithdrawFromSupply
    _ → Nothing
