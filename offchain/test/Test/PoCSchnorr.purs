module Test.PoCSchnorr (tests) where

import Contract.Prelude

import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class ToData
  , PlutusData(Constr)
  )
import Contract.PlutusData as PlutusData
import Contract.Prim.ByteArray (ByteArray)
import Contract.Prim.ByteArray as ByteArray
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as ScriptLookups
import Contract.Scripts (MintingPolicy)
import Contract.TxConstraints (TxConstraints)
import Contract.TxConstraints as TxConstraints
import Contract.Value (CurrencySymbol)
import Contract.Value as Value
import Contract.Wallet as Wallet
import Data.BigInt as BigInt
import Data.Semiring as Semiring
import Effect.Class as Effect.Class
import Mote.Monad as Mote.Monad
import Test.PlutipTest (PlutipTest)
import Test.PlutipTest as Test.PlutipTest
import Test.Utils as Test.Utils
import TrustlessSidechain.RawScripts as RawScripts
import TrustlessSidechain.Utils.Schnorr as Utils.Schnorr
import TrustlessSidechain.Utils.Scripts as Utils.Scripts
import TrustlessSidechain.Utils.Transaction as Utils.Transaction

-- | `SchnorrRedeemer` corresponds to the onchain type.
newtype SchnorrRedeemer = SchnorrRedeemer
  { message ∷ ByteArray
  , signature ∷ ByteArray
  , publicKey ∷ ByteArray
  }

instance ToData SchnorrRedeemer where
  toData (SchnorrRedeemer { message, signature, publicKey }) = Constr
    (BigNum.fromInt 0)
    [ PlutusData.toData message
    , PlutusData.toData signature
    , PlutusData.toData publicKey
    ]

-- | Grabs the minting policy / currency symbol of the schnorr proof of concept
-- | test minting policy.
getPoCSchnorrMintingPolicy ∷
  Contract { currencySymbol ∷ CurrencySymbol, mintingPolicy ∷ MintingPolicy }
getPoCSchnorrMintingPolicy = do
  mintingPolicy ← Utils.Scripts.mkMintingPolicyWithParams
    RawScripts.rawPoCSchnorr
    (mempty ∷ Array Unit)
  currencySymbol ← Monad.liftContractM "minting policy to currency symbol failed"
    $ Value.scriptCurrencySymbol mintingPolicy
  pure { mintingPolicy, currencySymbol }

mustMintPocSchnorr ∷
  SchnorrRedeemer →
  Contract
    { lookups ∷ ScriptLookups Void
    , constraints ∷ TxConstraints Void Void
    }
mustMintPocSchnorr schnorrRedeemer = do
  { currencySymbol, mintingPolicy } ← getPoCSchnorrMintingPolicy
  let
    redeemer = wrap $ PlutusData.toData schnorrRedeemer
    value = Value.singleton
      currencySymbol
      Value.adaToken
      -- the token name doesn't matter for this test, so we just set
      -- it to be the empty token name i.e., ada's token name
      Semiring.one

    lookups = ScriptLookups.mintingPolicy mintingPolicy
    constraints =
      TxConstraints.mustMintValueWithRedeemer
        redeemer
        value
  pure { lookups, constraints }

-- | `tests` aggregates all the PoCInlineDatums together conveniently
tests ∷ PlutipTest
tests = Mote.Monad.group "PoCSchnorr tests" do
  testScenario1
  testScenario2

testScenario1 ∷ PlutipTest
testScenario1 = Mote.Monad.test "PoCSchnorr: valid test scenario"
  $ Test.PlutipTest.mkPlutipConfigTest
      [ BigInt.fromInt 10_000_000, BigInt.fromInt 10_000_000 ]
  $ \alice → Wallet.withKeyWallet alice do
      privateKey ← Effect.Class.liftEffect $
        Utils.Schnorr.generateRandomPrivateKey

      let
        message = ByteArray.hexToByteArrayUnsafe "706F6D6572616E69616E"
        signature = Utils.Schnorr.sign message privateKey
        publicKey = Utils.Schnorr.toPubKey privateKey

        redeemer = SchnorrRedeemer
          { message
          , signature: unwrap signature
          , publicKey: unwrap publicKey
          }
      { lookups, constraints } ← mustMintPocSchnorr redeemer

      void $ Utils.Transaction.balanceSignAndSubmit "PoCSchnorr" lookups
        constraints
      pure unit

testScenario2 ∷ PlutipTest
testScenario2 = Mote.Monad.test "PoCSchnorr: invalid test scenario"
  $ Test.PlutipTest.mkPlutipConfigTest
      [ BigInt.fromInt 10_000_000, BigInt.fromInt 10_000_000 ]
  $ \alice → Wallet.withKeyWallet alice do
      privateKey ← Effect.Class.liftEffect $
        Utils.Schnorr.generateRandomPrivateKey

      let
        message = ByteArray.hexToByteArrayUnsafe "4D61792033312C2031383332"
        signature = Utils.Schnorr.sign message privateKey
        publicKey = Utils.Schnorr.toPubKey privateKey

        wrongMessage = ByteArray.hexToByteArrayUnsafe
          "4F63746F6265722032352C2031383131"

        redeemer = SchnorrRedeemer
          { message: wrongMessage
          , signature: unwrap signature
          , publicKey: unwrap publicKey
          }
      { lookups, constraints } ← mustMintPocSchnorr redeemer

      Test.Utils.fails $ void $ Utils.Transaction.balanceSignAndSubmit
        "PoCSchnorr"
        lookups
        constraints
      pure unit
