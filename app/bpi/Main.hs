{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import BotPlutusInterface qualified
import BotPlutusInterface.Types (
  HasDefinitions (..),
  LogLevel (Debug),
  PABConfig (..),
  SomeBuiltin (..),
  endpointsToSchemas,
 )
import Cardano.Api (NetworkId (Testnet), NetworkMagic (..))
import Data.Aeson qualified as JSON
import Data.Aeson.TH (defaultOptions, deriveJSON)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Default (def)
import Data.Maybe (fromMaybe)
import Playground.Types (FunctionSchema)
import Schema (FormSchema)
import TrustlessSidechain.OffChain.CommitteeCandidateValidator (deregister, registerWithMock)
import TrustlessSidechain.OffChain.FUELMintingPolicy (burn, mint)
import TrustlessSidechain.OffChain.Schema (TrustlessSidechainSchema)
import TrustlessSidechain.OffChain.Types (
  BurnParams,
  DeregisterParams,
  MintParams,
  RegisterParams,
 )

import Prelude

instance HasDefinitions TrustlessSidechainContracts where
  getDefinitions :: [TrustlessSidechainContracts]
  getDefinitions = []

  getSchema :: TrustlessSidechainContracts -> [FunctionSchema FormSchema]
  getSchema _ = endpointsToSchemas @TrustlessSidechainSchema

  getContract :: (TrustlessSidechainContracts -> SomeBuiltin)
  getContract = \case
    RegisterCommitteeCandidate params -> SomeBuiltin $ registerWithMock params
    DeregisterCommitteeCandidate params -> SomeBuiltin $ deregister params
    MintFUELToken params -> SomeBuiltin $ mint params
    BurnFUELToken params -> SomeBuiltin $ burn params

data TrustlessSidechainContracts
  = RegisterCommitteeCandidate RegisterParams
  | DeregisterCommitteeCandidate DeregisterParams
  | MintFUELToken MintParams
  | BurnFUELToken BurnParams
  deriving stock (Show)

$(deriveJSON defaultOptions ''TrustlessSidechainContracts)

main :: IO ()
main = do
  protocolParams <-
    fromMaybe (error "protocol.json file not found") . JSON.decode
      <$> LazyByteString.readFile "protocol.json"
  let pabConf =
        (def @PABConfig)
          { pcNetwork = Testnet (NetworkMagic 1097911063)
          , pcProtocolParams = Just protocolParams
          , pcOwnPubKeyHash = "0f45aaf1b2959db6e5ff94dbb1f823bf257680c3c723ac2d49f97546"
          , pcScriptFileDir = "./data"
          , pcMetadataDir = "./metadata"
          , pcSigningKeyFileDir = "./signing-keys"
          , pcTxFileDir = "./txs"
          , pcDryRun = False
          , pcLogLevel = Debug
          , pcProtocolParamsFile = "./protocol.json"
          , pcEnableTxEndpoint = True
          , pcCollectLogs = True
          }
  BotPlutusInterface.runPAB @TrustlessSidechainContracts pabConf
