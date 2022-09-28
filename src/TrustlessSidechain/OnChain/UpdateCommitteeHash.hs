{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module TrustlessSidechain.OnChain.UpdateCommitteeHash where

import Cardano.Crypto.Wallet (XPrv)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Ledger (PubKey)
import Ledger qualified
import Ledger.Crypto qualified as Crypto
import Ledger.Value (AssetClass)
import Ledger.Value qualified as Value
import Plutus.Script.Utils.V2.Scripts (scriptCurrencySymbol)
import Plutus.Script.Utils.V2.Typed.Scripts qualified as ScriptUtils
import Plutus.V2.Ledger.Api (
  CurrencySymbol,
  Datum (getDatum),
  LedgerBytes (getLedgerBytes),
  MintingPolicy,
  TokenName (TokenName),
  Value (getValue),
 )
import Plutus.V2.Ledger.Contexts (
  ScriptContext (scriptContextTxInfo),
  TxInInfo (txInInfoOutRef),
  TxInfo (txInfoInputs, txInfoMint),
  TxOut (txOutDatum, txOutValue),
  TxOutRef,
 )
import Plutus.V2.Ledger.Contexts qualified as Contexts
import Plutus.V2.Ledger.Tx (OutputDatum (..))
import PlutusTx qualified
import PlutusTx.AssocMap qualified as AssocMap
import PlutusTx.Builtins qualified as Builtins
import PlutusTx.IsData.Class qualified as IsData
import PlutusTx.Prelude as PlutusTx
import TrustlessSidechain.MerkleTree qualified as MT
import TrustlessSidechain.OnChain.Types (
  UpdateCommitteeHash (cToken),
  UpdateCommitteeHashDatum (UpdateCommitteeHashDatum, committeeHash),
  UpdateCommitteeHashRedeemer (committeePubKeys, committeeSignatures, newCommitteeHash),
 )
import TrustlessSidechain.OnChain.Utils (verifyMultisig)
import Prelude qualified

-- * Updating the committee hash

{- | 'aggregateKeys' aggregates a list of public keys into a single
 committee hash by essentially computing the merkle root of all public keys
 together.
 We call the output of this function an /aggregate public key/.
-}
{-# INLINEABLE aggregateKeys #-}
aggregateKeys :: [PubKey] -> BuiltinByteString
aggregateKeys [] = traceError "Empty committee"
aggregateKeys lst = MT.unRootHash $ MT.rootHash $ MT.fromList $ map (getLedgerBytes . Crypto.getPubKey) lst

{- Note [Aggregate Keys Append Scheme]
 In early versions, we used a "simple append scheme" i.e., we implemented this function with
  > aggregateKeys = Builtins.blake2b_256 . mconcat . map (Bytes.getLedgerBytes . Crypto.getPubKey)
  but this didn't work in the Plutip integration tests (budget exceeded errors), so we jumped straight
  to the merkle root solution instead.
 -}

{- | 'aggregateCheck' takes a sequence of public keys and an aggregate public
 key, and returns true or false to determinig whether the public keys were
 used to produce the aggregate public key
-}
{-# INLINEABLE aggregateCheck #-}
aggregateCheck :: [PubKey] -> BuiltinByteString -> Bool
aggregateCheck pubKeys avk = aggregateKeys pubKeys == avk

{- | 'multiSign'' is a wrapper for how multiple private keys can sign a message.
Warning: there should be a non-empty number of private keys.
We put this function here (even though it isn't used in the on chain code)
because it corresponds to the 'verifyMultiSignature'
TODO: For now, to simplify things we just make the first person sign the message.
TODO: do a proper multisign later.
-}
multiSign :: BuiltinByteString -> [XPrv] -> BuiltinByteString
multiSign msg (prvKey : _) = Crypto.getSignature (Crypto.sign' msg prvKey)
multiSign _ _ = traceError "Empty multisign"

{- | 'mkUpdateCommitteeHashValidator' is the on-chain validator. We test for the following conditions
  1. The native token is in both the input and output.
  2. The new committee hash is signed by the current committee
  3. The committee provided really is the current committee
  4. The new output transaction contains the new committee hash
TODO an optimization. Instead of putting the new committee hash in the
redeemer, we could just:
    1. check if the committee hash is included in the datum (we already do
    this)
    2. check if what is in the datum is signed by the current committee
Note [Committee hash in output datum]:
Normally, the producer of a utxo is only required to include the datum hash,
and not the datum itself (but can optionally do so). In this case, we rely on
the fact that the producer actually does include the datum; and enforce this
with 'outputDatum'.
Note [Input has Token and Output has Token]:
In an older iteration, we used to check if the tx's input has the token, but
this is implicitly covered when checking if the output spends the token. Hence,
we don't need to check if the input tx's spends the token which is a nice
little optimization.
-}
{-# INLINEABLE mkUpdateCommitteeHashValidator #-}
mkUpdateCommitteeHashValidator ::
  UpdateCommitteeHash ->
  UpdateCommitteeHashDatum ->
  UpdateCommitteeHashRedeemer ->
  ScriptContext ->
  Bool
mkUpdateCommitteeHashValidator uch dat red ctx =
  traceIfFalse "Token missing from output" outputHasToken
    && traceIfFalse "Committee signature missing" signedByCurrentCommittee
    && traceIfFalse "Wrong committee" isCurrentCommittee
    && traceIfFalse "Wrong output datum" (outputDatum == UpdateCommitteeHashDatum (newCommitteeHash red))
  where
    ownOutput :: TxOut
    ownOutput = case Contexts.getContinuingOutputs ctx of
      [o] -> o
      _ -> traceError "Expected exactly one committee output"

    outputDatum :: UpdateCommitteeHashDatum
    outputDatum = case txOutDatum ownOutput of
      -- Note [Committee Hash Inline Datum]
      -- We only accept the committtee has to be given as inline datum, so
      -- all other scripts which rely on this script can safely assume that
      -- the datum is given inline.
      OutputDatum d -> IsData.unsafeFromBuiltinData (getDatum d)
      _ -> traceError "error 'mkUpdateCommitteeHashValidator': no output inline datum missing"

    outputHasToken :: Bool
    outputHasToken = hasNft (txOutValue ownOutput)

    hasNft :: Value -> Bool
    hasNft val = Value.assetClassValueOf val (cToken uch) == 1

    threshold :: Integer
    threshold = length (committeePubKeys red) `Builtins.multiplyInteger` 2 `Builtins.divideInteger` 3

    signedByCurrentCommittee :: Bool
    signedByCurrentCommittee =
      verifyMultisig
        (getLedgerBytes . Crypto.getPubKey <$> committeePubKeys red)
        threshold -- TODO: this should be the threshold?
        (newCommitteeHash red)
        (committeeSignatures red)

    isCurrentCommittee :: Bool
    isCurrentCommittee = aggregateCheck (committeePubKeys red) $ committeeHash dat

-- * Initializing the committee hash

-- | 'InitCommitteeHashMint' is used as the parameter for the minting policy
newtype InitCommitteeHashMint = InitCommitteeHashMint
  { -- | 'TxOutRef' is the output reference to mint the NFT initially.
    icTxOutRef :: TxOutRef
  }
  deriving newtype (Prelude.Show, Prelude.Eq, Prelude.Ord, Generic, PlutusTx.UnsafeFromData)
  deriving anyclass (FromJSON, ToJSON)

PlutusTx.makeLift ''InitCommitteeHashMint

{- | 'initCommitteeHashMintTn'  is the token name of the NFT which identifies
 the utxo which contains the committee hash. We use an empty bytestring for
 this because the name really doesn't matter, so we mighaswell save a few
 bytes by giving it the empty name.
-}
{-# INLINEABLE initCommitteeHashMintTn #-}
initCommitteeHashMintTn :: TokenName
initCommitteeHashMintTn = TokenName Builtins.emptyByteString

{- | 'initCommitteeHashMintAmount' is the amount of the currency to mint which
 is 1.
-}
{-# INLINEABLE initCommitteeHashMintAmount #-}
initCommitteeHashMintAmount :: Integer
initCommitteeHashMintAmount = 1

{- | 'mkCommitteeHashPolicy' is the minting policy for the NFT which identifies
 the committee hash.
-}
{-# INLINEABLE mkCommitteeHashPolicy #-}
mkCommitteeHashPolicy :: InitCommitteeHashMint -> () -> ScriptContext -> Bool
mkCommitteeHashPolicy ichm _red ctx =
  traceIfFalse "error 'mkCommitteeHashPolicy' UTxO not consumed" hasUtxo
    && traceIfFalse "error 'mkCommitteeHashPolicy' wrong amount minted" checkMintedAmount
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    oref :: TxOutRef
    oref = icTxOutRef ichm

    hasUtxo :: Bool
    hasUtxo = any ((oref ==) . txInInfoOutRef) $ txInfoInputs info

    -- assert that we have minted exactly one of this currency symbol
    checkMintedAmount :: Bool
    checkMintedAmount = case fmap AssocMap.toList $ AssocMap.lookup (Contexts.ownCurrencySymbol ctx) $ getValue $ txInfoMint info of
      Just [(tn', amt)] -> tn' == initCommitteeHashMintTn && amt == initCommitteeHashMintAmount
      _ -> False

-- | 'committeeHashPolicy' is the minting policy
{-# INLINEABLE committeeHashPolicy #-}
committeeHashPolicy :: InitCommitteeHashMint -> MintingPolicy
committeeHashPolicy gch =
  Ledger.mkMintingPolicyScript $
    $$(PlutusTx.compile [||ScriptUtils.mkUntypedMintingPolicy . mkCommitteeHashPolicy||])
      `PlutusTx.applyCode` PlutusTx.liftCode gch

-- | 'committeeHashCurSymbol' is the currency symbol
{-# INLINEABLE committeeHashCurSymbol #-}
committeeHashCurSymbol :: InitCommitteeHashMint -> CurrencySymbol
committeeHashCurSymbol ichm = scriptCurrencySymbol $ committeeHashPolicy ichm

{- | 'committeeHashAssetClass' is the asset class. See 'initCommitteeHashMintTn'
 for details on the token name
-}
{-# INLINEABLE committeeHashAssetClass #-}
committeeHashAssetClass :: InitCommitteeHashMint -> AssetClass
committeeHashAssetClass ichm = Value.assetClass (committeeHashCurSymbol ichm) initCommitteeHashMintTn

-- CTL hack
mkCommitteeHashPolicyUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkCommitteeHashPolicyUntyped = ScriptUtils.mkUntypedMintingPolicy . mkCommitteeHashPolicy . PlutusTx.unsafeFromBuiltinData

serialisableCommitteeHashPolicy :: Ledger.Script
serialisableCommitteeHashPolicy = Ledger.fromCompiledCode $$(PlutusTx.compile [||mkCommitteeHashPolicyUntyped||])

mkCommitteeHashValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> BuiltinData -> ()
mkCommitteeHashValidatorUntyped = ScriptUtils.mkUntypedValidator . mkUpdateCommitteeHashValidator . PlutusTx.unsafeFromBuiltinData

serialisableCommitteeHashValidator :: Ledger.Script
serialisableCommitteeHashValidator = Ledger.fromCompiledCode $$(PlutusTx.compile [||mkCommitteeHashValidatorUntyped||])
