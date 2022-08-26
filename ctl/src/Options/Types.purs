module Options.Types (Options(..), Endpoint(..)) where

import Contract.Prelude

import CommitteCandidateValidator (PubKey, Signature)
import Contract.Transaction (TransactionInput)
import SidechainParams (SidechainParams)

type Options =
  { scParams :: SidechainParams
  , skey :: String
  , endpoint :: Endpoint
  }

data Endpoint
  = MintAct { amount :: Int }
  | BurnAct { amount :: Int, recipient :: String }
  | CommitteeCandidateReg
      { spoPubKey :: PubKey
      , sidechainPubKey :: PubKey
      , spoSig :: Signature
      , sidechainSig :: Signature
      , inputUtxo :: TransactionInput
      }
  | CommitteeCandidateDereg { spoPubKey :: PubKey }

derive instance Generic Endpoint _

instance Show Endpoint where
  show = genericShow
