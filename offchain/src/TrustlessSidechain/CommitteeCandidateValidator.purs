module TrustlessSidechain.CommitteeCandidateValidator
  ( RegisterParams(..)
  , DeregisterParams(..)
  , getCommitteeCandidateValidator
  , BlockProducerRegistration(..)
  , BlockProducerRegistrationMsg(..)
  , register
  , deregister
  ) where

import Contract.Prelude

import Contract.Address
  ( PaymentPubKeyHash
  , getNetworkId
  , getWalletAddress
  , ownPaymentPubKeyHash
  , validatorHashEnterpriseAddress
  )
import Contract.Monad
  ( Contract
  , liftContractE
  , liftContractM
  , liftedM
  , throwContractError
  )
import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class FromData
  , class ToData
  , Datum(Datum)
  , PlutusData(Constr)
  , fromData
  , toData
  , unitRedeemer
  )
import Contract.ScriptLookups as Lookups
import Contract.Scripts (Validator(Validator), applyArgs, validatorHash)
import Contract.TextEnvelope (decodeTextEnvelope, plutusScriptV2FromEnvelope)
import Contract.Transaction
  ( TransactionHash
  , TransactionInput
  , TransactionOutput(TransactionOutput)
  , TransactionOutputWithRefScript(TransactionOutputWithRefScript)
  , outputDatumDatum
  )
import Contract.TxConstraints as Constraints
import Contract.Utxos (UtxoMap, utxosAt)
import Contract.Value as Value
import Control.Alternative (guard)
import Control.Parallel (parTraverse)
import Data.Array (catMaybes)
import Data.BigInt as BigInt
import Data.Map as Map
import Record as Record
import TrustlessSidechain.CandidatePermissionToken
  ( CandidatePermissionMint(CandidatePermissionMint)
  , CandidatePermissionTokenInfo
  )
import TrustlessSidechain.CandidatePermissionToken as CandidatePermissionToken
import TrustlessSidechain.RawScripts (rawCommitteeCandidateValidator)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Types (PubKey, Signature)
import TrustlessSidechain.Utils.Crypto (SidechainPublicKey, SidechainSignature)
import TrustlessSidechain.Utils.Logging
  ( InternalError(NotFoundOwnPubKeyHash, NotFoundOwnAddress, InvalidScript)
  , OffchainError(InternalError, InvalidInputError)
  , mkReport
  )
import TrustlessSidechain.Utils.Transaction (balanceSignAndSubmit)

newtype RegisterParams = RegisterParams
  { sidechainParams ∷ SidechainParams
  , spoPubKey ∷ PubKey
  , sidechainPubKey ∷ SidechainPublicKey
  , spoSig ∷ Signature
  , sidechainSig ∷ SidechainSignature
  , inputUtxo ∷ TransactionInput
  , permissionToken ∷ Maybe CandidatePermissionTokenInfo
  }

newtype DeregisterParams = DeregisterParams
  { sidechainParams ∷ SidechainParams
  , spoPubKey ∷ PubKey
  }

getCommitteeCandidateValidator ∷ SidechainParams → Contract Validator
getCommitteeCandidateValidator sp = do
  let
    script = decodeTextEnvelope rawCommitteeCandidateValidator >>=
      plutusScriptV2FromEnvelope

  unapplied ← liftContractM "Decoding text envelope failed." script
  applied ← liftContractE $ applyArgs unapplied [ toData sp ]
  pure $ Validator applied

newtype BlockProducerRegistration = BlockProducerRegistration
  { bprSpoPubKey ∷ PubKey -- own cold verification key hash
  , bprSidechainPubKey ∷ SidechainPublicKey -- public key in the sidechain's desired format
  , bprSpoSignature ∷ Signature -- Signature of the SPO
  , bprSidechainSignature ∷ SidechainSignature -- Signature of the sidechain candidate
  , bprInputUtxo ∷ TransactionInput -- A UTxO that must be spent by the transaction
  , bprOwnPkh ∷ PaymentPubKeyHash -- Owner public key hash
  }

derive instance Generic BlockProducerRegistration _

derive instance Newtype BlockProducerRegistration _

instance ToData BlockProducerRegistration where
  toData
    ( BlockProducerRegistration
        { bprSpoPubKey
        , bprSidechainPubKey
        , bprSpoSignature
        , bprSidechainSignature
        , bprInputUtxo
        , bprOwnPkh
        }
    ) = Constr (BigNum.fromInt 0)
    [ toData bprSpoPubKey
    , toData bprSidechainPubKey
    , toData bprSpoSignature
    , toData bprSidechainSignature
    , toData bprInputUtxo
    , toData bprOwnPkh
    ]

instance FromData BlockProducerRegistration where
  fromData (Constr n [ a, b, c, d, e, f ]) | n == (BigNum.fromInt 0) =
    { bprSpoPubKey: _
    , bprSidechainPubKey: _
    , bprSpoSignature: _
    , bprSidechainSignature: _
    , bprInputUtxo: _
    , bprOwnPkh: _
    } <$> fromData a <*> fromData b <*> fromData c <*> fromData d <*> fromData e
      <*> fromData f
      <#> BlockProducerRegistration
  fromData _ = Nothing

data BlockProducerRegistrationMsg = BlockProducerRegistrationMsg
  { bprmSidechainParams ∷ SidechainParams
  , bprmSidechainPubKey ∷ SidechainPublicKey
  , bprmInputUtxo ∷ TransactionInput -- A UTxO that must be spent by the transaction
  }

register ∷ RegisterParams → Contract TransactionHash
register
  ( RegisterParams
      { sidechainParams
      , spoPubKey
      , sidechainPubKey
      , spoSig
      , sidechainSig
      , inputUtxo
      , permissionToken
      }
  ) = do
  let mkErr = report "register"
  netId ← getNetworkId

  ownPkh ← liftedM (mkErr (InternalError NotFoundOwnPubKeyHash))
    ownPaymentPubKeyHash
  ownAddr ← liftedM (mkErr (InternalError NotFoundOwnAddress)) getWalletAddress

  validator ← getCommitteeCandidateValidator sidechainParams
  let valHash = validatorHash validator
  valAddr ← liftContractM
    ( mkErr
        ( InternalError
            (InvalidScript "Couldn't convert validator hash to address")
        )
    )
    (validatorHashEnterpriseAddress netId valHash)

  ownUtxos ← utxosAt ownAddr
  valUtxos ← utxosAt valAddr

  ownRegistrations ← findOwnRegistrations ownPkh spoPubKey valUtxos

  maybeCandidatePermissionMintingPolicy ← case permissionToken of
    Just
      { candidatePermissionTokenUtxo: pUtxo
      , candidatePermissionTokenName: pTokenName
      } →
      map
        ( \rec → Just $ Record.union rec
            { candidatePermissionTokenName: pTokenName }
        )
        $ CandidatePermissionToken.getCandidatePermissionMintingPolicy
        $ CandidatePermissionMint
            { sidechainParams
            , candidatePermissionTokenUtxo: pUtxo
            }
    Nothing → pure Nothing

  let
    val = Value.lovelaceValueOf (BigInt.fromInt 1)
      <> case maybeCandidatePermissionMintingPolicy of
        Nothing → mempty
        Just { candidatePermissionTokenName, candidatePermissionCurrencySymbol } →
          Value.singleton
            candidatePermissionCurrencySymbol
            candidatePermissionTokenName
            one
    datum = BlockProducerRegistration
      { bprSpoPubKey: spoPubKey
      , bprSidechainPubKey: sidechainPubKey
      , bprSpoSignature: spoSig
      , bprSidechainSignature: sidechainSig
      , bprInputUtxo: inputUtxo
      , bprOwnPkh: ownPkh
      }

    lookups ∷ Lookups.ScriptLookups Void
    lookups = Lookups.unspentOutputs ownUtxos
      <> Lookups.validator validator
      <> Lookups.unspentOutputs valUtxos
      <> case maybeCandidatePermissionMintingPolicy of
        Nothing → mempty
        Just { candidatePermissionPolicy } →
          Lookups.mintingPolicy candidatePermissionPolicy

    constraints ∷ Constraints.TxConstraints Void Void
    constraints =
      -- Sending new registration to validator address
      Constraints.mustSpendPubKeyOutput inputUtxo
        <> Constraints.mustPayToScript valHash (Datum (toData datum))
          Constraints.DatumInline
          val

        -- Consuming old registration UTxOs
        <> Constraints.mustBeSignedBy ownPkh
        <> mconcat
          ( flip Constraints.mustSpendScriptOutput unitRedeemer <$>
              ownRegistrations
          )

  balanceSignAndSubmit "Registers Committee Candidate" lookups constraints

deregister ∷ DeregisterParams → Contract TransactionHash
deregister (DeregisterParams { sidechainParams, spoPubKey }) = do
  let mkErr = report "deregister"

  netId ← getNetworkId

  ownPkh ← liftedM (mkErr (InternalError NotFoundOwnPubKeyHash))
    ownPaymentPubKeyHash
  ownAddr ← liftedM (mkErr (InternalError NotFoundOwnAddress)) getWalletAddress

  validator ← getCommitteeCandidateValidator sidechainParams
  let valHash = validatorHash validator
  valAddr ← liftContractM
    ( mkErr
        ( InternalError
            (InvalidScript "Couldn't convert validator hash to address")
        )
    )
    (validatorHashEnterpriseAddress netId valHash)
  ownUtxos ← utxosAt ownAddr
  valUtxos ← utxosAt valAddr

  ownRegistrations ← findOwnRegistrations ownPkh spoPubKey valUtxos

  when (null ownRegistrations)
    $ throwContractError
        (mkErr (InvalidInputError "Couldn't find registration UTxO"))

  let
    lookups ∷ Lookups.ScriptLookups Void
    lookups = Lookups.validator validator
      <> Lookups.unspentOutputs ownUtxos
      <> Lookups.unspentOutputs valUtxos

    constraints ∷ Constraints.TxConstraints Void Void
    constraints = Constraints.mustBeSignedBy ownPkh
      <> mconcat
        (flip Constraints.mustSpendScriptOutput unitRedeemer <$> ownRegistrations)

  balanceSignAndSubmit "Deregister Committee Candidate" lookups constraints

report ∷ String → OffchainError → String
report = mkReport "CommitteeCandidateValidator"

-- | Based on the wallet public key hash and the SPO public key, it finds the
-- | the registration UTxOs of the committee member/candidate
findOwnRegistrations ∷
  PaymentPubKeyHash →
  PubKey →
  UtxoMap →
  Contract (Array TransactionInput)
findOwnRegistrations ownPkh spoPubKey validatorUtxos = do
  mayTxIns ← Map.toUnfoldable validatorUtxos #
    parTraverse
      \(input /\ TransactionOutputWithRefScript { output: TransactionOutput out }) →
        pure do
          Datum d ← outputDatumDatum out.datum
          BlockProducerRegistration r ← fromData d
          guard (r.bprSpoPubKey == spoPubKey && r.bprOwnPkh == ownPkh)
          pure input
  pure $ catMaybes mayTxIns
