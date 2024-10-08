module TrustlessSidechain.Versioning.V1
  ( getCommitteeSelectionPoliciesAndValidators
  , getCheckpointPoliciesAndValidators
  , getVersionedPoliciesAndValidators
  , getFuelPoliciesAndValidators
  , getDsPoliciesAndValidators
  , getMerkleRootPoliciesAndValidators
  , getNativeTokenManagementPoliciesAndValidators
  ) where

import Contract.Prelude

import Cardano.Types.PlutusScript (PlutusScript)
import Data.List (List)
import Data.List as List
import Run (Run)
import Run.Except (EXCEPT)
import TrustlessSidechain.Checkpoint as Checkpoint
import TrustlessSidechain.Checkpoint.Types
  ( CheckpointParameter(CheckpointParameter)
  )
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds
  , CommitteeCertificateMint(CommitteeCertificateMint)
  )
import TrustlessSidechain.CommitteeATMSSchemes as CommitteeATMSSchemes
import TrustlessSidechain.CommitteeCandidateValidator
  ( getCommitteeCandidateValidator
  )
import TrustlessSidechain.CommitteeOraclePolicy as CommitteeOraclePolicy
import TrustlessSidechain.DistributedSet as DistributedSet
import TrustlessSidechain.Effects.Env (Env, READER, ask)
import TrustlessSidechain.Effects.Wallet (WALLET)
import TrustlessSidechain.Error (OffchainError)
import TrustlessSidechain.FUELBurningPolicy.V1 as FUELBurningPolicy.V1
import TrustlessSidechain.FUELMintingPolicy.V1 as FUELMintingPolicy.V1
import TrustlessSidechain.Governance (Governance(MultiSig))
import TrustlessSidechain.Governance.MultiSig
  ( multisigGovPolicy
  )
import TrustlessSidechain.MerkleRoot as MerkleRoot
import TrustlessSidechain.NativeTokenManagement.IlliquidCirculationSupply
  ( illiquidCirculationSupplyValidator
  )
import TrustlessSidechain.NativeTokenManagement.Reserve
  ( reserveAuthPolicy
  , reserveValidator
  )
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.UpdateCommitteeHash.Utils
  ( getUpdateCommitteeHashValidator
  )
import TrustlessSidechain.Versioning.Types
  ( ScriptId
      ( CheckpointValidator
      , CommitteeCandidateValidator
      , CommitteeCertificateVerificationPolicy
      , CommitteeHashValidator
      , CommitteeOraclePolicy
      , DsKeyPolicy
      , FUELBurningPolicy
      , FUELMintingPolicy
      , GovernancePolicy
      , IlliquidCirculationSupplyValidator
      , MerkleRootTokenPolicy
      , MerkleRootTokenValidator
      , ReserveAuthPolicy
      , ReserveValidator
      )
  )
import TrustlessSidechain.Versioning.Utils as Versioning
import Type.Row (type (+))

getVersionedPoliciesAndValidators ∷
  ∀ r.
  { sidechainParams ∷ SidechainParams
  , atmsKind ∷ ATMSKinds
  } →
  Run (READER Env + EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getVersionedPoliciesAndValidators { sidechainParams: sp, atmsKind } = do
  committeeScripts ← getCommitteeSelectionPoliciesAndValidators atmsKind sp
  checkpointScripts ← getCheckpointPoliciesAndValidators sp
  fuelScripts ← getFuelPoliciesAndValidators sp
  dsScripts ← getDsPoliciesAndValidators sp
  merkleRootScripts ← getMerkleRootPoliciesAndValidators sp
  nativeTokenManagementScripts ← getNativeTokenManagementPoliciesAndValidators sp

  pure $ committeeScripts
    <> checkpointScripts
    <> fuelScripts
    <> dsScripts
    <> merkleRootScripts
    <> nativeTokenManagementScripts

getMerkleRootPoliciesAndValidators ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getMerkleRootPoliciesAndValidators sp = do
  { mintingPolicy: merkleRootTokenMintingPolicy } ←
    MerkleRoot.merkleRootCurrencyInfo sp

  merkleRootTokenValidator ← MerkleRoot.merkleRootTokenValidator sp

  let
    versionedPolicies = List.fromFoldable
      [ MerkleRootTokenPolicy /\ merkleRootTokenMintingPolicy ]
    versionedValidators = List.fromFoldable
      [ MerkleRootTokenValidator /\ merkleRootTokenValidator ]

  pure { versionedPolicies, versionedValidators }

getCommitteeSelectionPoliciesAndValidators ∷
  ∀ r.
  ATMSKinds →
  SidechainParams →
  Run (EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getCommitteeSelectionPoliciesAndValidators atmsKind sp =
  do
    -- Getting policies to version
    -----------------------------------
    -- some awkwardness that we need the committee hash policy first.
    { mintingPolicy: committeeOraclePolicy
    } ←
      CommitteeOraclePolicy.committeeOracleCurrencyInfo sp

    let
      committeeCertificateMint =
        CommitteeCertificateMint
          { thresholdNumerator: (unwrap sp).thresholdNumerator
          , thresholdDenominator: (unwrap sp).thresholdDenominator
          }

    { mintingPolicy: committeeCertificateVerificationMintingPolicy } ←
      CommitteeATMSSchemes.atmsCommitteeCertificateVerificationMintingPolicyFromATMSKind
        { committeeCertificateMint, sidechainParams: sp }
        atmsKind

    let
      versionedPolicies = List.fromFoldable
        [ CommitteeCertificateVerificationPolicy /\
            committeeCertificateVerificationMintingPolicy
        , CommitteeOraclePolicy /\ committeeOraclePolicy
        ]

    -- Getting validators to version
    -----------------------------------
    { validator: committeeHashValidator } ←
      do
        getUpdateCommitteeHashValidator sp
    committeeCandidateValidator ← getCommitteeCandidateValidator sp

    let
      versionedValidators = List.fromFoldable
        [ CommitteeHashValidator /\ committeeHashValidator
        , CommitteeCandidateValidator /\ committeeCandidateValidator
        ]

    pure $ { versionedPolicies, versionedValidators }

getCheckpointPoliciesAndValidators ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getCheckpointPoliciesAndValidators sp = do
  checkpointAssetClass ← Checkpoint.checkpointAssetClass sp

  versionOracleConfig ← Versioning.getVersionOracleConfig sp
  checkpointValidator ← do
    let
      checkpointParam = CheckpointParameter
        { sidechainParams: sp
        , checkpointAssetClass
        }
    Checkpoint.checkpointValidator checkpointParam versionOracleConfig

  let
    versionedValidators = List.fromFoldable
      [ CheckpointValidator /\ checkpointValidator
      ]

  pure $ { versionedPolicies: mempty, versionedValidators }

getNativeTokenManagementPoliciesAndValidators ∷
  ∀ r.
  SidechainParams →
  Run (READER Env + EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getNativeTokenManagementPoliciesAndValidators sp = do
  governance ← (_.governance) <$> ask
  case governance of
    -- The native token management system can only be used if the user specified
    -- parameters for the governance (currently only multisignature governance)
    Just (MultiSig msgp) → do
      versionOracleConfig ← Versioning.getVersionOracleConfig sp
      reserveAuthPolicy' ← reserveAuthPolicy versionOracleConfig
      reserveValidator' ← reserveValidator versionOracleConfig
      illiquidCirculationSupplyValidator' ←
        illiquidCirculationSupplyValidator versionOracleConfig
      governancePolicy ← multisigGovPolicy msgp

      let
        versionedPolicies = List.fromFoldable
          [ ReserveAuthPolicy /\ reserveAuthPolicy'
          , GovernancePolicy /\ governancePolicy
          ]
        versionedValidators = List.fromFoldable
          [ ReserveValidator /\ reserveValidator'
          , IlliquidCirculationSupplyValidator /\
              illiquidCirculationSupplyValidator'
          ]

      pure $ { versionedPolicies, versionedValidators }
    _ → pure { versionedPolicies: mempty, versionedValidators: mempty }

-- | Return policies and validators needed for FUEL minting
-- | and burning.
getFuelPoliciesAndValidators ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + WALLET + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getFuelPoliciesAndValidators sp = do
  { fuelMintingPolicy } ← FUELMintingPolicy.V1.getFuelMintingPolicy sp
  { fuelBurningPolicy } ← FUELBurningPolicy.V1.getFuelBurningPolicy sp

  let
    versionedPolicies = List.fromFoldable
      [ FUELMintingPolicy /\ fuelMintingPolicy
      , FUELBurningPolicy /\ fuelBurningPolicy
      ]
    versionedValidators = List.fromFoldable []

  pure { versionedPolicies, versionedValidators }

-- | Get V1 policies and validators for the
-- | Ds* types.
getDsPoliciesAndValidators ∷
  ∀ r.
  SidechainParams →
  Run (EXCEPT OffchainError + r)
    { versionedPolicies ∷ List (Tuple ScriptId PlutusScript)
    , versionedValidators ∷ List (Tuple ScriptId PlutusScript)
    }
getDsPoliciesAndValidators sp = do
  ds ← DistributedSet.getDs sp
  { mintingPolicy: dsKeyPolicy } ← DistributedSet.getDsKeyPolicy ds

  let
    versionedPolicies = List.fromFoldable [ DsKeyPolicy /\ dsKeyPolicy ]
    versionedValidators = List.fromFoldable []

  pure { versionedPolicies, versionedValidators }
