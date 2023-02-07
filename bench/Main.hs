{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Bench (BenchConfigPaths (..))
import Bench qualified
import Control.Monad qualified as Monad

import Cases.FUELMintingPolicy qualified as FUELMintingPolicy
import Cases.InitSidechain qualified as InitSidechain
import Cases.UpdateCommitteeHash qualified as UpdateCommitteeHash

{- | Assumptions:
    - `./payment.skey` is your secret key
    - `./payment.addr` is the address of your key (bech32 encoded -- needed
    for querying your utxos)
    - You have called `spago build` in `ctl/`
    - You have a symlink `ln -s ./ctl/output/ output/`

 Then, to use, run
 ```
 cabal bench
 ```
-}
defaultBenchConfigPaths :: BenchConfigPaths
defaultBenchConfigPaths =
  BenchConfigPaths
    { bcfgpBenchResults = "tmp.db"
    , bcfgpSigningKeyFilePath = "./payment.skey"
    , bcfgpTestNetMagic = 2
    , -- The command to call ctl:
      -- Note: this assumes that we have @./output/Main/index.js@ (i.e., the output
      -- of @spago build@) existing.
      bcfgpCtlCmd = "echo \"import('./output/Main/index.js').then(m => m.main())\"  | node -"
    , {- 'odcHost' is local host for ogmios-datum-cache i.e., when running @nix run
       .#ctl-runtime-preview@, this is the host name for ogmios-datum-cache.
      -}
      bcfgpOdcHost = "127.0.0.1"
    , {- 'odcPort' is port for ogmios-datum-cache i.e., when running @nix run
       .#ctl-runtime-preview@, this is the port for ogmios-datum-cache.
      -}
      bcfgpOdcPort = 9999
    , {- 'cardanoCli' is a string for using @cardano-cli@ through the docker image
       from @nix run .#ctl-runtime-preview@.
      -}
      bcfgpCardanoCliCmd =
        "docker exec -t -e CARDANO_NODE_SOCKET_PATH=\"/ipc/node.socket\" store_cardano-node_1  cardano-cli"
    , bcfgpOutputDir =
        "bench-output"
    }

-- main function!
main :: IO ()
main = do
  -- potentially override defaults via environment variables
  cfg <- Bench.overrideBenchConfigPathFromEnv defaultBenchConfigPaths
  -- Alternatively, one can cram the configuration in environment variables
  -- which are preferred over the default values i.e.,
  Monad.void $
    Bench.runBenchWith
      (cfg {bcfgpBenchResults = "FUELMintingBenchmarks.db"})
      FUELMintingPolicy.fuelMintingBench

  Monad.void $
    Bench.runBenchWith
      (cfg {bcfgpBenchResults = "UpdateCommitteeHashBenchmarks.db"})
      UpdateCommitteeHash.updateCommitteeHashBench

  Monad.void $
    Bench.runBenchWith
      (cfg {bcfgpBenchResults = "InitSidechain.db"})
      InitSidechain.initSidechainBench
