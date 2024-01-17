-- | `MerkleRoot` contains the endpoint functionality for the `MerkleRoot` endpoint
module TrustlessSidechain.MerkleRoot
  ( module ExportTypes
  , module ExportUtils
  , saveRoot
  ) where

import Contract.Prelude

import Contract.Monad
  ( Contract
  , liftContractM
  , liftedM
  )
import Contract.PlutusData (toData, unitDatum)
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as Lookups
import Contract.Scripts as Scripts
import Contract.Transaction
  ( TransactionHash
  , mkTxUnspentOut
  )
import Contract.TxConstraints (InputWithScriptRef(RefInput), TxConstraints)
import Contract.TxConstraints as TxConstraints
import Contract.Value as Value
import Data.BigInt as BigInt
import Data.Map as Map
import TrustlessSidechain.CommitteeATMSSchemes
  ( CommitteeATMSParams(CommitteeATMSParams)
  , CommitteeCertificateMint(CommitteeCertificateMint)
  )
import TrustlessSidechain.CommitteeATMSSchemes as CommitteeATMSSchemes
import TrustlessSidechain.CommitteeOraclePolicy as CommitteeOraclePolicy
import TrustlessSidechain.Error
  ( OffchainError(InvalidData, NotFoundUtxo)
  )
import TrustlessSidechain.MerkleRoot.Types
  ( MerkleRootInsertionMessage(MerkleRootInsertionMessage)
  , SaveRootParams(SaveRootParams)
  )
import TrustlessSidechain.MerkleRoot.Types
  ( MerkleRootInsertionMessage(MerkleRootInsertionMessage)
  , SaveRootParams(SaveRootParams)
  , SignedMerkleRootRedeemer(SignedMerkleRootRedeemer)
  ) as ExportTypes
import TrustlessSidechain.MerkleRoot.Utils
  ( findMerkleRootTokenUtxo
  , getMerkleRootCurrencyInfo
  , merkleRootTokenValidator
  , serialiseMrimHash
  ) as ExportUtils
import TrustlessSidechain.MerkleRoot.Utils
  ( findPreviousMerkleRootTokenUtxo
  , getMerkleRootCurrencyInfo
  , merkleRootTokenValidator
  , serialiseMrimHash
  )
import TrustlessSidechain.MerkleTree (RootHash)
import TrustlessSidechain.MerkleTree as MerkleTree
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.UpdateCommitteeHash
  ( UpdateCommitteeHash(UpdateCommitteeHash)
  )
import TrustlessSidechain.UpdateCommitteeHash as UpdateCommitteeHash
import TrustlessSidechain.Utils.Crypto as Utils.Crypto
import TrustlessSidechain.Utils.Transaction (balanceSignAndSubmit)
import TrustlessSidechain.Versioning.Types
  ( ScriptId
      ( MerkleRootTokenPolicy
      , MerkleRootTokenValidator
      , CommitteeCertificateVerificationPolicy
      )
  , VersionOracle(VersionOracle)
  )
import TrustlessSidechain.Versioning.Utils as Versioning

-- | `saveRoot` is the endpoint.
saveRoot ∷ SaveRootParams → Contract TransactionHash
saveRoot
  ( SaveRootParams
      { sidechainParams
      , merkleRoot
      , previousMerkleRoot
      , aggregateSignature
      }
  ) = do
  -- Set up for the committee ATMS schemes
  ------------------------------------
  { currencySymbol: committeeOracleCurrencySymbol } ←
    CommitteeOraclePolicy.getCommitteeOraclePolicy sidechainParams

  let
    committeeCertificateMint =
      CommitteeCertificateMint
        { thresholdNumerator:
            (unwrap sidechainParams).thresholdNumerator
        , thresholdDenominator:
            (unwrap sidechainParams).thresholdDenominator
        }
  { currencySymbol: committeeCertificateVerificationCurrencySymbol } ←
    CommitteeATMSSchemes.atmsCommitteeCertificateVerificationMintingPolicy
      { committeeCertificateMint, sidechainParams }
      aggregateSignature

  -- Find the UTxO with the current committee.
  ------------------------------------
  { currencySymbol: merkleRootTokenCurrencySymbol } ← getMerkleRootCurrencyInfo
    sidechainParams
  currentCommitteeUtxo ←
    liftedM
      ( show $ NotFoundUtxo "failed to find current committee UTxO"
      )
      $ UpdateCommitteeHash.findUpdateCommitteeHashUtxo
      $ UpdateCommitteeHash
          { sidechainParams
          , committeeOracleCurrencySymbol
          , committeeCertificateVerificationCurrencySymbol
          , merkleRootTokenCurrencySymbol
          }

  -- Grab the lookups + constraints for saving a merkle root
  ------------------------------------
  { lookupsAndConstraints
  , merkleRootInsertionMessage
  } ← saveRootLookupsAndConstraints
    { sidechainParams
    , merkleRoot
    , previousMerkleRoot
    }

  -- Grab the lookups + constraints for the committee certificate
  -- verification
  ------------------------------------
  scMsg ← liftContractM "failed serializing the MerkleRootInsertionMessage"
    $
      serialiseMrimHash merkleRootInsertionMessage

  atmsLookupsAndConstraints ←
    CommitteeATMSSchemes.atmsSchemeLookupsAndConstraints sidechainParams
      $ CommitteeATMSParams
          { currentCommitteeUtxo
          , committeeCertificateMint
          , aggregateSignature
          , message: Utils.Crypto.ecdsaSecp256k1MessageToTokenName scMsg
          }

  -- Building the transaction / submitting it
  ------------------------------------
  let
    { lookups, constraints } =
      lookupsAndConstraints
        <> atmsLookupsAndConstraints
        <>
          -- include the current committee UTxO  in this transaction
          { lookups:
              Lookups.unspentOutputs
                ( Map.singleton currentCommitteeUtxo.index
                    currentCommitteeUtxo.value
                )
          , constraints:
              TxConstraints.mustReferenceOutput currentCommitteeUtxo.index
          }

  balanceSignAndSubmit "Save Merkle root" { lookups, constraints }

-- | `saveRootLookupsAndConstraints` creates the lookups and constraints (and
-- | the message to be signed) for saving a Merkle root
saveRootLookupsAndConstraints ∷
  { sidechainParams ∷ SidechainParams
  , merkleRoot ∷ RootHash
  , previousMerkleRoot ∷ Maybe RootHash
  } →
  Contract
    { lookupsAndConstraints ∷
        { constraints ∷ TxConstraints Void Void
        , lookups ∷ ScriptLookups Void
        }
    , merkleRootInsertionMessage ∷ MerkleRootInsertionMessage
    }
saveRootLookupsAndConstraints
  { sidechainParams
  , merkleRoot
  , previousMerkleRoot
  } = do

  -- Getting the required validators / minting policies...
  ---------------------------------------------------------
  { mintingPolicy: rootTokenMP
  , currencySymbol: rootTokenCS
  } ← getMerkleRootCurrencyInfo sidechainParams
  rootTokenVal ← merkleRootTokenValidator sidechainParams
  merkleRootTokenName ←
    liftContractM
      ( show
          ( InvalidData
              "Invalid Merkle root TokenName for merkleRootTokenMintingPolicy"
          )
      )
      $ Value.mkTokenName
      $ MerkleTree.unRootHash merkleRoot

  -- Grab the transaction holding the last merkle root
  ---------------------------------------------------------
  maybePreviousMerkleRootUtxo ← findPreviousMerkleRootTokenUtxo
    previousMerkleRoot
    sidechainParams

  -- Building the transaction
  ---------------------------------------------------------

  ( committeeCertificateVerificationVersioningInput /\
      committeeCertificateVerificationVersioningOutput
  ) ←
    Versioning.getVersionedScriptRefUtxo
      sidechainParams
      ( VersionOracle
          { version: BigInt.fromInt 1
          , scriptId: CommitteeCertificateVerificationPolicy
          }
      )

  (merkleRootValidatorVersioningInput /\ merkleRootValidatorVersioningOutput) ←
    Versioning.getVersionedScriptRefUtxo
      sidechainParams
      ( VersionOracle
          { version: BigInt.fromInt 1, scriptId: MerkleRootTokenValidator }
      )

  (merkleRootPolicyVersioningInput /\ merkleRootPolicyVersioningOutput) ←
    Versioning.getVersionedScriptRefUtxo
      sidechainParams
      ( VersionOracle
          { version: BigInt.fromInt 1, scriptId: MerkleRootTokenPolicy }
      )

  let
    value = Value.singleton rootTokenCS merkleRootTokenName one

    msg = MerkleRootInsertionMessage
      { sidechainParams
      , merkleRoot
      , previousMerkleRoot
      }

    redeemer = ExportTypes.SignedMerkleRootRedeemer
      { previousMerkleRoot
      }

    constraints ∷ TxConstraints Void Void
    constraints =
      TxConstraints.mustMintCurrencyWithRedeemerUsingScriptRef
        (Scripts.mintingPolicyHash rootTokenMP)
        (wrap (toData redeemer))
        merkleRootTokenName
        one
        ( RefInput $ mkTxUnspentOut merkleRootPolicyVersioningInput
            merkleRootPolicyVersioningOutput
        )
        <> TxConstraints.mustPayToScript (Scripts.validatorHash rootTokenVal)
          unitDatum
          TxConstraints.DatumWitness
          value
        <> TxConstraints.mustReferenceOutput merkleRootValidatorVersioningInput
        <> TxConstraints.mustReferenceOutput
          committeeCertificateVerificationVersioningInput
        <> case maybePreviousMerkleRootUtxo of
          Nothing → mempty
          Just { index: oref } → TxConstraints.mustReferenceOutput oref

    lookups ∷ Lookups.ScriptLookups Void
    lookups =
      Lookups.unspentOutputs
        ( Map.singleton merkleRootValidatorVersioningInput
            merkleRootValidatorVersioningOutput
        )
        <> Lookups.unspentOutputs
          ( Map.singleton committeeCertificateVerificationVersioningInput
              committeeCertificateVerificationVersioningOutput
          )
        <> Lookups.unspentOutputs
          ( Map.singleton merkleRootPolicyVersioningInput
              merkleRootPolicyVersioningOutput
          )
        <> case maybePreviousMerkleRootUtxo of
          Nothing → mempty
          Just { index: txORef, value: txOut } → Lookups.unspentOutputs
            (Map.singleton txORef txOut)

  pure
    { lookupsAndConstraints: { lookups, constraints }
    , merkleRootInsertionMessage: msg
    }
