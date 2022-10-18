module Test.InitSidechain (testScenario1, testScenario2) where

import Contract.Prelude

import Contract.Log as Log
import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.Prim.ByteArray as ByteArray
import Contract.Utxos as Utxos
import Contract.Wallet (KeyWallet)
import Contract.Wallet as Wallet
import Control.Monad.Error.Class as MonadError
import Data.Array as Array
import Data.BigInt as BigInt
import Data.Map as Map
import Data.Set as Set
import Effect.Exception as Exception
import InitSidechain as InitSidechain
import SidechainParams (InitSidechainParams(..))
import Test.Utils as Test.Utils
import Utils.Crypto as Crypto

-- | 'testScenario1' just calls the init sidechain endpoint (which should
-- succeed!)
testScenario1 ∷ Contract () Unit
testScenario1 = do
  Log.logInfo' "InitSidechain 'testScenario1'"
  genesisUtxo ← Test.Utils.getOwnTransactionInput
  -- generate an initialize committee of @committeeSize@ committee members
  let committeeSize = 25
  committeePrvKeys ← sequence $ Array.replicate committeeSize
    Crypto.generatePrivKey
  let
    initCommittee = map Crypto.toPubKeyUnsafe committeePrvKeys
    initScParams = InitSidechainParams
      { initChainId: BigInt.fromInt 69
      , initGenesisHash: ByteArray.hexToByteArrayUnsafe "abababababa"
      , initMint: Nothing
      , initUtxo: genesisUtxo
      , initCommittee
      , initThresholdNumerator: BigInt.fromInt 2
      , initThresholdDenominator: BigInt.fromInt 3
      }

  void $ InitSidechain.initSidechain initScParams

-- | 'testScenario2' is a bit more complicated (but this should fail!). It
-- takes two distinct wallets, say Alice and Bob, grabs a utxo from Alice as
-- the 'initUtxo' ('genesisUtxo'); then Bob tries to initialize the sidechain
-- with Alice's utxo.
-- In short, this verifies that to initialize the sidechain, we need to spend
-- the initUtxo
testScenario2 ∷ KeyWallet → KeyWallet → Contract () Unit
testScenario2 alice bob = do
  aliceUtxos ← Wallet.withKeyWallet alice $ Monad.liftedM
    "Failed to query wallet utxos"
    Utxos.getWalletUtxos
  genesisUtxo ← Monad.liftContractM "No utxo found in wallet"
    $ Set.findMin
    $ Map.keys aliceUtxos

  result ← MonadError.try $ Wallet.withKeyWallet bob do

    -- generate an initialize committee of @committeeSize@ committee members
    let committeeSize = 1000
    committeePrvKeys ← sequence $ Array.replicate committeeSize
      Crypto.generatePrivKey
    let
      initCommittee = map Crypto.toPubKeyUnsafe committeePrvKeys
      initScParams = InitSidechainParams
        { initChainId: BigInt.fromInt 69
        , initGenesisHash: ByteArray.hexToByteArrayUnsafe "abababababa"
        , initMint: Nothing
        , initUtxo: genesisUtxo
        , initCommittee
        , initThresholdNumerator: BigInt.fromInt 2
        , initThresholdDenominator: BigInt.fromInt 3
        }

    void $ InitSidechain.initSidechain initScParams
  case result of
    Right _ →
      Monad.throwContractError $ Exception.error
        "Contract should have failed but it didn't."
    Left _err → pure unit
