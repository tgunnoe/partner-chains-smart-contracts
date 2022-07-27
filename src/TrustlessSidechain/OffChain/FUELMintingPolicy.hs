{-# LANGUAGE NamedFieldPuns #-}

module TrustlessSidechain.OffChain.FUELMintingPolicy where

import Control.Monad (when)
import Data.Map (Map)
import Data.Text (Text)
import Ledger (CardanoTx, ChainIndexTxOut, Redeemer (Redeemer), TxOutRef, scriptCurrencySymbol)
import Ledger.Constraints qualified as Constraint
import Ledger.Value qualified as Value
import Plutus.Contract (Contract)
import Plutus.Contract qualified as Contract
import PlutusTx (ToData (toBuiltinData))
import PlutusTx.Prelude
import TrustlessSidechain.OffChain.Schema (TrustlessSidechainSchema)
import TrustlessSidechain.OffChain.Types (
  BurnParams (BurnParams, amount, recipient, sidechainParams),
  MintParams (MintParams, amount, recipient, sidechainParams),
 )
import TrustlessSidechain.OnChain.FUELMintingPolicy qualified as FUELMintingPolicy
import TrustlessSidechain.OnChain.Types (FUELRedeemer (MainToSide, SideToMain))
import Prelude qualified

burn :: BurnParams -> Contract () TrustlessSidechainSchema Text CardanoTx
burn BurnParams {amount, sidechainParams, recipient} = do
  let policy = FUELMintingPolicy.mintingPolicy sidechainParams
      value = Value.singleton (scriptCurrencySymbol policy) "FUEL" amount
      redeemer = Redeemer $ toBuiltinData (MainToSide recipient)
  when (amount > 0) $ Contract.throwError "Can't burn a positive amount"
  Contract.submitTxConstraintsWith @FUELRedeemer
    (Constraint.mintingPolicy policy)
    (Constraint.mustMintValueWithRedeemer redeemer value)

mintWithUtxo :: Maybe (Map TxOutRef ChainIndexTxOut) -> MintParams -> Contract () TrustlessSidechainSchema Text CardanoTx
mintWithUtxo utxo MintParams {amount, sidechainParams, recipient} = do
  let policy = FUELMintingPolicy.mintingPolicy sidechainParams
      value = Value.singleton (scriptCurrencySymbol policy) "FUEL" amount
      redeemer = Redeemer $ toBuiltinData SideToMain
      lookups =
        Constraint.mintingPolicy policy
          Prelude.<> maybe Prelude.mempty Constraint.unspentOutputs utxo
      tx =
        ( Constraint.mustMintValueWithRedeemer redeemer value
            <> Constraint.mustPayToPubKey recipient value
        )
  when (amount < 0) $ Contract.throwError "Can't mint a negative amount"
  Contract.submitTxConstraintsWith @FUELRedeemer lookups tx

mint :: MintParams -> Contract () TrustlessSidechainSchema Text CardanoTx
mint = mintWithUtxo Nothing
