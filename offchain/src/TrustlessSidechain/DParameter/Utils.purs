module TrustlessSidechain.DParameter.Utils
  ( getDParameterMintingPolicyAndCurrencySymbol
  , getDParameterValidatorAndAddress
  ) where

import Contract.Prelude

import Contract.Address
  ( Address
  )
import Contract.Monad (Contract)
import Contract.PlutusData
  ( toData
  )
import Contract.Scripts
  ( MintingPolicy
  , Validator
  , validatorHash
  )
import Contract.Value (CurrencySymbol)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Utils.Address (getCurrencySymbol, toAddress)
import TrustlessSidechain.Utils.Scripts
  ( mkMintingPolicyWithParams
  , mkValidatorWithParams
  )
import TrustlessSidechain.Versioning.ScriptId
  ( ScriptId
      ( DParameterValidator
      , DParameterPolicy
      )
  )

-- | Get the PoCMintingPolicy by applying `SidechainParams` to the dummy
-- | minting policy.
decodeDParameterMintingPolicy ∷ SidechainParams → Contract MintingPolicy
decodeDParameterMintingPolicy sidechainParams = do
  { dParameterValidatorAddress } ← getDParameterValidatorAndAddress
    sidechainParams
  mkMintingPolicyWithParams DParameterPolicy $
    [ toData sidechainParams, toData dParameterValidatorAddress ]

decodeDParameterValidator ∷ SidechainParams → Contract Validator
decodeDParameterValidator sidechainParams = do
  mkValidatorWithParams DParameterValidator [ toData sidechainParams ]

getDParameterValidatorAndAddress ∷
  SidechainParams →
  Contract
    { dParameterValidator ∷ Validator
    , dParameterValidatorAddress ∷ Address
    }
getDParameterValidatorAndAddress sidechainParams = do
  dParameterValidator ← decodeDParameterValidator sidechainParams
  dParameterValidatorAddress ←
    toAddress (validatorHash dParameterValidator)

  pure { dParameterValidator, dParameterValidatorAddress }

getDParameterMintingPolicyAndCurrencySymbol ∷
  SidechainParams →
  Contract
    { dParameterMintingPolicy ∷ MintingPolicy
    , dParameterCurrencySymbol ∷ CurrencySymbol
    }
getDParameterMintingPolicyAndCurrencySymbol sidechainParams = do
  dParameterMintingPolicy ← decodeDParameterMintingPolicy sidechainParams
  dParameterCurrencySymbol ←
    getCurrencySymbol DParameterPolicy dParameterMintingPolicy
  pure { dParameterMintingPolicy, dParameterCurrencySymbol }
