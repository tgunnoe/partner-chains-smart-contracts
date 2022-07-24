{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TemplateHaskell #-}

module TrustlessSidechain.OnChain.FUELMintingPolicy where

import Ledger (
  MintingPolicy,
  ScriptContext (ScriptContext),
  ScriptPurpose (Minting),
  TxInfo (TxInfo),
 )
import Ledger qualified
import Ledger.Typed.Scripts qualified as Script
import Ledger.Value qualified as Value
import PlutusTx (applyCode, compile, liftCode) -- , unsafeFromBuiltinData , toBuiltinData)
import PlutusTx.Prelude
import TrustlessSidechain.OffChain.Types (SidechainParams (..))
import TrustlessSidechain.OnChain.Types (FUELRedeemer (MainToSide, SideToMain))

{-# INLINEABLE mkMintingPolicy #-}
mkMintingPolicy :: SidechainParams -> FUELRedeemer -> ScriptContext -> Bool
mkMintingPolicy
  SidechainParams {genesisMint}
  mode
  ScriptContext
    { scriptContextPurpose = Minting ownSymbol
    , scriptContextTxInfo = TxInfo {txInfoMint, txInfoInputs}
    } =
    let hasUTxO utxo = any (\i -> Ledger.txInInfoOutRef i == utxo) txInfoInputs
        oneshotMintAndUTxOPresent = maybe True hasUTxO genesisMint
        verifyTokenAmount verify = case Value.flattenValue txInfoMint of
          [(sym, name, amount)] ->
            verify amount
              && traceIfFalse "Token Symbol is incorrect" (sym == ownSymbol)
              && traceIfFalse "Token Name is incorrect" (name == ownTokenName)
          _ -> False
        ownTokenName = Value.TokenName "FUEL"
     in case mode of
          MainToSide _ _ ->
            verifyTokenAmount (traceIfFalse "Can't burn a positive amount" . (< 0))
          SideToMain ->
            verifyTokenAmount (traceIfFalse "Can't mint a negative amount" . (> 0))
              && traceIfFalse "Oneshot Mintingpolicy utxo not present" oneshotMintAndUTxOPresent
mkMintingPolicy _ _ _ = False

mintingPolicy :: SidechainParams -> MintingPolicy
mintingPolicy param =
  Ledger.mkMintingPolicyScript
    ( $$(compile [||Script.wrapMintingPolicy . mkMintingPolicy||])
        `applyCode` liftCode (param)
    )

-- CTL hacks
--mkMintingPolicyUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
--mkMintingPolicyUntyped a = mkMintingPolicy (unsafeFromBuiltinData a)
