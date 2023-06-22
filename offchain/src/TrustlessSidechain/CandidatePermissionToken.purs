module TrustlessSidechain.CandidatePermissionToken
  ( CandidatePermissionMint(..)
  , getCandidatePermissionMintingPolicy
  , candidatePermissionMintingPolicy
  , CandidatePermissionMintParams(..)
  , CandidatePermissionTokenInfo
  , CandidatePermissionTokenMintInfo
  , candidatePermissionTokenLookupsAndConstraints
  , runCandidatePermissionToken
  ) where

import Contract.Prelude

import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData (class ToData, PlutusData(Constr))
import Contract.PlutusData as PlutusData
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (MintingPolicy(PlutusMintingPolicy))
import Contract.Scripts as Scripts
import Contract.TextEnvelope as TextEnvelope
import Contract.Transaction
  ( TransactionHash
  , TransactionInput
  , TransactionOutputWithRefScript(TransactionOutputWithRefScript)
  )
import Contract.TxConstraints (TxConstraints)
import Contract.TxConstraints as TxConstraints
import Contract.Utxos as Utxos
import Contract.Value (CurrencySymbol, TokenName)
import Contract.Value as Value
import Data.BigInt (BigInt)
import Data.Map as Map
import TrustlessSidechain.RawScripts as RawScripts
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Utils.Logging
  ( InternalError(NotFoundUtxo, InvalidScript)
  , OffchainError(InternalError)
  )
import TrustlessSidechain.Utils.Logging as Utils.Logging
import TrustlessSidechain.Utils.Transaction (balanceSignAndSubmit)

--------------------------------
-- Working with the onchain code
--------------------------------
-- | `CandidatePermissionMint` is the parameter for
-- | `candidatePermissionMintingPolicy`
newtype CandidatePermissionMint = CandidatePermissionMint
  { sidechainParams ∷ SidechainParams
  , candidatePermissionTokenUtxo ∷ TransactionInput
  }

derive instance Generic CandidatePermissionMint _
derive instance Newtype CandidatePermissionMint _

instance ToData CandidatePermissionMint where
  toData
    (CandidatePermissionMint { sidechainParams, candidatePermissionTokenUtxo }) =
    Constr
      (BigNum.fromInt 0)
      [ PlutusData.toData sidechainParams
      , PlutusData.toData candidatePermissionTokenUtxo
      ]

-- | `getCandidatePermissionMintingPolicy` grabs both the minting policy /
-- | currency symbol for the candidate permission minting policy.
getCandidatePermissionMintingPolicy ∷
  CandidatePermissionMint →
  Contract
    { candidatePermissionPolicy ∷ MintingPolicy
    , candidatePermissionCurrencySymbol ∷ CurrencySymbol
    }
getCandidatePermissionMintingPolicy cpm = do
  let
    mkErr = report "getCandidatePermissionMintingPolicy"

  candidatePermissionPolicy ← candidatePermissionMintingPolicy cpm
  candidatePermissionCurrencySymbol ← Monad.liftContractM
    (mkErr (InternalError (InvalidScript "CandidatePermissionToken")))
    (Value.scriptCurrencySymbol candidatePermissionPolicy)
  pure
    { candidatePermissionPolicy
    , candidatePermissionCurrencySymbol
    }

-- | `candidatePermissionMintingPolicy` gets the minting policy for the
-- | candidate permission minting policy
candidatePermissionMintingPolicy ∷
  CandidatePermissionMint → Contract MintingPolicy
candidatePermissionMintingPolicy cpm = do
  let
    script =
      TextEnvelope.decodeTextEnvelope
        RawScripts.rawCandidatePermissionMintingPolicy
        >>= TextEnvelope.plutusScriptV2FromEnvelope
  unapplied ← Monad.liftContractM "Decoding text envelope failed." script
  applied ← Monad.liftContractE $ Scripts.applyArgs unapplied
    [ PlutusData.toData cpm ]
  pure $ PlutusMintingPolicy applied

--------------------------------
-- Endpoint code
--------------------------------

-- | `CandidatePermissionMintParams` is the endpoint parameters for the
-- | candidate permission token.
newtype CandidatePermissionMintParams = CandidatePermissionMintParams
  { candidateMintPermissionMint ∷ CandidatePermissionMint
  , candidatePermissionTokenName ∷ TokenName
  , amount ∷ BigInt
  }

-- | `CandidatePermissionTokenInfo` wraps up some of the required information for
-- | referring to a candidate permission token. This isn't used onchain, but used
-- | offchain for wrapping up this data consistently
type CandidatePermissionTokenInfo =
  { candidatePermissionTokenUtxo ∷ TransactionInput
  , candidatePermissionTokenName ∷ TokenName
  }

-- | `CandidatePermissionTokenMintInfo` wraps up some of the required information for
-- | minting a candidate permission token. This isn't used onchain, but used
-- | offchain for wrapping up this data consistently
type CandidatePermissionTokenMintInfo =
  { amount ∷ BigInt
  , permissionToken ∷ CandidatePermissionTokenInfo
  }

-- | `candidatePermissionTokenLookupsAndConstraints` creates the required
-- | lookups and constraints to build the transaction to mint the tokens.
candidatePermissionTokenLookupsAndConstraints ∷
  CandidatePermissionMintParams →
  Contract
    { lookups ∷ ScriptLookups Void
    , constraints ∷ TxConstraints Void Void
    }
candidatePermissionTokenLookupsAndConstraints
  ( CandidatePermissionMintParams
      { candidateMintPermissionMint, candidatePermissionTokenName, amount }
  ) = do
  let
    mkErr = report "candidatePermissionTokenLookupsAndConstraints"
  { candidatePermissionPolicy
  , candidatePermissionCurrencySymbol
  } ← getCandidatePermissionMintingPolicy
    candidateMintPermissionMint

  let txIn = (unwrap candidateMintPermissionMint).candidatePermissionTokenUtxo
  txOut ← Monad.liftedM (mkErr (InternalError (NotFoundUtxo "Genesis UTxO"))) $
    Utxos.getUtxo
      txIn

  let
    value = Value.singleton
      candidatePermissionCurrencySymbol
      candidatePermissionTokenName
      amount

    lookups ∷ ScriptLookups Void
    lookups =
      Lookups.mintingPolicy candidatePermissionPolicy
        <>
          Lookups.unspentOutputs
            ( Map.singleton txIn
                ( TransactionOutputWithRefScript
                    { output: txOut, scriptRef: Nothing }
                )
            )

    constraints ∷ TxConstraints Void Void
    constraints =
      TxConstraints.mustMintValueWithRedeemer
        PlutusData.unitRedeemer
        value
        <> TxConstraints.mustSpendPubKeyOutput txIn
  pure { lookups, constraints }

-- | `runCandidatePermissionToken` is the endpoint for minting candidate
-- | permission tokens.
runCandidatePermissionToken ∷
  CandidatePermissionMintParams →
  Contract
    { transactionId ∷ TransactionHash
    , candidatePermissionCurrencySymbol ∷ CurrencySymbol
    }
runCandidatePermissionToken
  cpmp@
    ( CandidatePermissionMintParams
        { candidateMintPermissionMint }
    ) = do
  { candidatePermissionCurrencySymbol } ← getCandidatePermissionMintingPolicy
    candidateMintPermissionMint

  { lookups, constraints } ← candidatePermissionTokenLookupsAndConstraints cpmp
  txId ← balanceSignAndSubmit "Mint CandidatePermissionToken" lookups
    constraints

  pure { transactionId: txId, candidatePermissionCurrencySymbol }

-- | `report` is an internal function used for helping writing log messages.
report ∷ String → OffchainError → String
report = Utils.Logging.mkReport "CandidatePermissionToken"
