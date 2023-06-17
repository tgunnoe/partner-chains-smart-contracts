module TrustlessSidechain.CommitteeOraclePolicy
  ( InitCommitteeHashMint(InitCommitteeHashMint)
  , committeeOraclePolicy
  , committeeOracleAssetClass
  , committeeOracleTn
  ) where

import Contract.Prelude

import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.PlutusData
  ( class ToData
  , toData
  )
import Contract.PlutusData as PlutusData
import Contract.Prim.ByteArray (ByteArray)
import Contract.Prim.ByteArray as ByteArray
import Contract.Scripts (MintingPolicy(PlutusMintingPolicy))
import Contract.Scripts as Scripts
import Contract.TextEnvelope
  ( decodeTextEnvelope
  , plutusScriptV2FromEnvelope
  )
import Contract.Transaction (TransactionInput)
import Contract.Value as Value
import Partial.Unsafe (unsafePartial)
import TrustlessSidechain.RawScripts as RawScripts
import TrustlessSidechain.Types (AssetClass, assetClass)

-- | `InitCommitteeHashMint` parameterizes the minting policy which identifies
-- | the utxo with the update committee hash validator script.
newtype InitCommitteeHashMint = InitCommitteeHashMint
  { icTxOutRef ∷ TransactionInput }

derive instance Generic InitCommitteeHashMint _

derive instance Newtype InitCommitteeHashMint _

instance ToData InitCommitteeHashMint where
  toData (InitCommitteeHashMint { icTxOutRef }) =
    toData icTxOutRef

committeeOraclePolicy ∷ InitCommitteeHashMint → Contract MintingPolicy
committeeOraclePolicy sp = do
  let
    script = decodeTextEnvelope RawScripts.rawCommitteeHashPolicy
      >>= plutusScriptV2FromEnvelope

  unapplied ← Monad.liftContractM "Decoding text envelope failed." script
  applied ← Monad.liftContractE $ Scripts.applyArgs unapplied
    [ PlutusData.toData sp ]
  pure $ PlutusMintingPolicy applied

-- | `committeeOracleAssetClass` is the asset class. See `committeeOracleTn`
-- | for details on the token name
{-# INLINEABLE committeeOracleAssetClass #-}
committeeOracleAssetClass ∷ InitCommitteeHashMint → Contract AssetClass
committeeOracleAssetClass ichm = do
  cp ← committeeOraclePolicy ichm
  curSym ← Monad.liftContractM "Couldn't get committeeHash currency symbol"
    (Value.scriptCurrencySymbol cp)

  pure $ assetClass curSym committeeOracleTn

-- | `committeeOracleTn` is the token name of the NFT which identifies
-- | the utxo which contains the committee hash. We use an empty bytestring for
-- | this because the name really doesn't matter, so we mighaswell save a few
-- | bytes by giving it the empty name.
committeeOracleTn ∷ Value.TokenName
committeeOracleTn = unsafePartial $ fromJust $ Value.mkTokenName $
  ByteArray.hexToByteArrayUnsafe ""
