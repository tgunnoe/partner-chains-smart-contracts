module TrustlessSidechain.Error
  ( OffchainError(..)
  ) where

import Contract.Prelude

import Contract.Address (Address)
import Contract.ScriptLookups as ScriptLookups
import Contract.Scripts (ApplyArgsError, MintingPolicy)
import Contract.Transaction as Transaction
import TrustlessSidechain.Versioning.ScriptId (ScriptId)

-- | Error raised from the off-chain code of the application
data OffchainError
  -- | A UTxO that should exist (not given as user input) could not be found
  = NotFoundUtxo String
  -- | Own payment public key hashes cannot be found
  | NotFoundOwnPubKeyHash
  -- | Own address cannot be found
  | NotFoundOwnAddress
  -- | Reference script not found in UTXO
  | NotFoundReferenceScript String
  -- | Invalid script address
  | InvalidAddress String Address
  -- | ScriptId not found in rawScriptsMap
  | InvalidScriptId ScriptId
  -- | Cannot apply arguments to a script
  | InvalidScriptArgs ApplyArgsError
  -- | Invalid policy or validator script, conversion to currency symbol /
  -- | validator hash failed
  | InvalidScript String
  -- | Invalid datum or redeemer, decoding errors
  | InvalidData String
  -- | Conversion of any data type (excluding datums and redeemers, use
  -- | InvalidData for those)
  | ConversionError String
  -- | Error while building a transaction from lookups and constraints
  | BuildTxError ScriptLookups.MkUnbalancedTxError
  -- | Error while attempting to balance a transaction
  | BalanceTxError Transaction.BalanceTxError
  -- | Distributed set insertion error.  TODO: this should ultimately take three
  -- | token names and the error message should be generated by error handler.
  | DsInsertError String
  -- | Error verifying a signature or a hash
  | VerificationError String
  -- | Parameters passed on the command line are invalid in some way.
  | InvalidCLIParams String
  -- | A UTxO that should exist (given as user input) could not be found
  | NotFoundInputUtxo String
  -- | A special case of not finding an input UTxO, used when genesis UTxO
  -- | cannot be found.
  | NoGenesisUTxO String
  -- | Anything that involves complicated internal logic, happens only once or
  -- | twice in the code, and isn't worth having a dedicated constructor
  | GenericInternalError String

  -- Below are the impossible errors, i.e. things that should never happen, but
  -- CTL forces us to handle these cases anyway.

  -- | Given minting policy cannot be converted to a currency symbol.  This
  -- | should never really happen, but CTL forces us to handle this case
  | InvalidCurrencySymbol ScriptId MintingPolicy
  -- | Feature that has not yet been implemented
  | NotImplemented String

derive instance Generic OffchainError _

instance Show OffchainError where
  show = genericShow
