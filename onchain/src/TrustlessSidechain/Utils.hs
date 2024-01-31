{-# OPTIONS_GHC -fno-specialise #-}

module TrustlessSidechain.Utils (
  fromSingleton,
  currencySymbolValueOf,
  oneTokenBurned,
  mkUntypedValidator,
  mkUntypedMintingPolicy,
  scriptToPlutusScript,
) where

import TrustlessSidechain.PlutusPrelude

import Cardano.Api (PlutusScriptV2)
import Cardano.Api.Shelley (PlutusScript (PlutusScriptSerialised))
import Codec.Serialise (serialise)
import Data.ByteString.Lazy (toStrict)
import Data.ByteString.Short (toShort)
import Data.Kind (Type)
import Plutonomy.UPLC qualified
import Plutus.V1.Ledger.Scripts (Script)
import Plutus.V2.Ledger.Api (
  CurrencySymbol,
  ScriptContext,
  TokenName,
  TxInfo (txInfoMint),
  Value,
  getValue,
 )
import PlutusTx.AssocMap qualified as AssocMap
import PlutusTx.AssocMap qualified as Map

-- | Unwrap a singleton list, or produce an error if not possible.
{-# INLINEABLE fromSingleton #-}
fromSingleton :: BuiltinString -> [a] -> a
fromSingleton _ [x] = x
fromSingleton msg _ = traceError msg

-- | Get amount of given currency in a value, ignoring token names.
{-# INLINEABLE currencySymbolValueOf #-}
currencySymbolValueOf :: Value -> CurrencySymbol -> Integer
currencySymbolValueOf v c = case Map.lookup c (getValue v) of
  Nothing -> 0
  Just x -> sum (Map.elems x)

-- | Check that exactly on specified asset was burned by a transaction.  Note
-- that transaction is also allowed to burn tokens of the same 'CurrencySymbol',
-- but with different 'TokenName's.  This is intended for use with 'InitToken's,
-- so that we permit multiple 'InitToken's with different names burned in the
-- same transaction.
{-# INLINEABLE oneTokenBurned #-}
oneTokenBurned :: TxInfo -> CurrencySymbol -> TokenName -> Bool
oneTokenBurned txInfo cs tn =
  case fmap AssocMap.toList $ AssocMap.lookup cs $ getValue $ txInfoMint txInfo of
    Just tns ->
      let go :: [(TokenName, Integer)] -> Bool
          go [] = False
          go ((tn', amt) : xs) = if tn' == tn && amt == -1 then True else go xs
       in go tns
    _ -> False

-- | Convert a validator to untyped
-- The output will accept BuiltinData instead of concrete types
{-# INLINE mkUntypedValidator #-}
mkUntypedValidator ::
  forall (d :: Type) (r :: Type).
  (UnsafeFromData d, UnsafeFromData r) =>
  (d -> r -> ScriptContext -> Bool) ->
  (BuiltinData -> BuiltinData -> BuiltinData -> ())
-- We can use unsafeFromBuiltinData here as we would fail immediately anyway if
-- parsing failed
mkUntypedValidator f d r p =
  check $ f (unsafeFromBuiltinData d) (unsafeFromBuiltinData r) (unsafeFromBuiltinData p)

-- | Convert a minting policy to untyped
-- The output will accept BuiltinData instead of concrete types
{-# INLINE mkUntypedMintingPolicy #-}
mkUntypedMintingPolicy ::
  forall (r :: Type).
  (UnsafeFromData r) =>
  (r -> ScriptContext -> Bool) ->
  (BuiltinData -> BuiltinData -> ())
-- We can use unsafeFromBuiltinData here as we would fail immediately anyway if
-- parsing failed
mkUntypedMintingPolicy f r p =
  check $ f (unsafeFromBuiltinData r) (unsafeFromBuiltinData p)

scriptToPlutusScript :: Script -> PlutusScript PlutusScriptV2
scriptToPlutusScript =
  PlutusScriptSerialised @PlutusScriptV2
    . toShort
    . toStrict
    . serialise
    . Plutonomy.UPLC.optimizeUPLC
