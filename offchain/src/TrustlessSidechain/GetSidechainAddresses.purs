-- | The module `GetSidechainAddresses` provides a way to get an array of strings
-- | identifying its associated hex encoded validator and currency symbol.
module TrustlessSidechain.GetSidechainAddresses
  ( SidechainAddresses
  , SidechainAddressesEndpointParams(SidechainAddressesEndpointParams)
  , SidechainAddressesExtra
  , getSidechainAddresses
  , currencySymbolToHex
  ) where

import Contract.Prelude

import Contract.Address (Address)
import Contract.Address as Address
import Contract.CborBytes as CborBytes
import Contract.Monad (Contract)
import Contract.Monad as Monad
import Contract.PlutusData as PlutusData
import Contract.Prim.ByteArray as ByteArray
import Contract.Scripts (MintingPolicy, Validator, validatorHash)
import Contract.Transaction (TransactionInput)
import Contract.Value (CurrencySymbol)
import Contract.Value as Value
import Data.Array as Array
import Data.BigInt as BigInt
import Data.Map as Map
import Data.TraversableWithIndex (traverseWithIndex)
import TrustlessSidechain.CandidatePermissionToken
  ( CandidatePermissionMint(CandidatePermissionMint)
  )
import TrustlessSidechain.CandidatePermissionToken as CandidatePermissionToken
import TrustlessSidechain.Checkpoint as Checkpoint
import TrustlessSidechain.Checkpoint.Types
  ( CheckpointParameter(CheckpointParameter)
  )
import TrustlessSidechain.CommitteeATMSSchemes
  ( ATMSKinds
  , CommitteeCertificateMint(CommitteeCertificateMint)
  )
import TrustlessSidechain.CommitteeATMSSchemes as CommitteeATMSSchemes
import TrustlessSidechain.CommitteeCandidateValidator as CommitteeCandidateValidator
import TrustlessSidechain.CommitteeOraclePolicy as CommitteeOraclePolicy
import TrustlessSidechain.DistributedSet as DistributedSet
import TrustlessSidechain.FUELProxyPolicy (getFuelProxyMintingPolicy)
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Types (assetClass)
import TrustlessSidechain.UpdateCommitteeHash.Types
  ( UpdateCommitteeHash(UpdateCommitteeHash)
  )
import TrustlessSidechain.UpdateCommitteeHash.Utils
  ( getUpdateCommitteeHashValidator
  )
import TrustlessSidechain.Utils.Logging
  ( InternalError(InvalidScript)
  , OffchainError(InternalError)
  )
import TrustlessSidechain.Versioning as Versioning
import TrustlessSidechain.Versioning.Types
  ( ScriptId
      ( DSConfPolicy
      , CandidatePermissionPolicy
      , MerkleRootTokenPolicy
      , CommitteeNftPolicy
      , CheckpointPolicy
      , FUELProxyPolicy
      , VersionOraclePolicy
      , CommitteeCandidateValidator
      , CommitteeHashValidator
      , DSConfValidator
      , DSInsertValidator
      , VersionOracleValidator
      , CheckpointValidator
      )
  , VersionOracle(VersionOracle)
  )
import TrustlessSidechain.Versioning.Utils
  ( getVersionOraclePolicy
  , getVersionedCurrencySymbol
  , versionOracleValidator
  )

-- | `SidechainAddresses` is an record of `Array`s which uniquely associates a `String`
-- | identifier with a hex encoded validator address / currency symbol of a
-- | sidechain validator / minting policy.
-- |
-- | See `getSidechainAddresses` for more details.
type SidechainAddresses =
  { -- bech32 addresses
    addresses ∷ Array (Tuple ScriptId String)
  , --  currency symbols
    mintingPolicies ∷ Array (Tuple ScriptId String)
  , -- cbor of the Plutus Address type.
    cborEncodedAddresses ∷ Array (Tuple ScriptId String)
  }

-- | `SidechainAddressesExtra` provides extra information for creating more
-- | addresses related to the sidechain.
-- | In particular, this allows us to optionally grab the minting policy of the
-- | candidate permission token.
type SidechainAddressesExtra =
  { mCandidatePermissionTokenUtxo ∷ Maybe TransactionInput
  , version ∷ Int
  }

-- | `SidechainAddressesEndpointParams` is the offchain endpoint parameter for
-- | bundling the required data to grab all the sidechain addresses.
newtype SidechainAddressesEndpointParams = SidechainAddressesEndpointParams
  { sidechainParams ∷ SidechainParams
  , atmsKind ∷ ATMSKinds
  , -- Used to optionally grab the minting policy of candidate permission
    -- token.
    mCandidatePermissionTokenUtxo ∷ Maybe TransactionInput
  , version ∷ Int
  }

-- | `getSidechainAddresses` returns a `SidechainAddresses` corresponding to
-- | the given `SidechainAddressesEndpointParams` which contains related
-- | addresses and currency symbols. Moreover, it returns the currency symbol
-- | of the candidate permission token provided the `permissionTokenUtxo` is
-- | given.
getSidechainAddresses ∷
  SidechainAddressesEndpointParams → Contract SidechainAddresses
getSidechainAddresses
  ( SidechainAddressesEndpointParams
      { sidechainParams: scParams
      , atmsKind
      , mCandidatePermissionTokenUtxo
      , version
      }
  ) = do

  -- Minting policies
  let
    committeeCertificateMint =
      CommitteeCertificateMint
        { thresholdNumerator: (unwrap scParams).thresholdNumerator
        , thresholdDenominator: (unwrap scParams).thresholdDenominator
        }
  { committeeCertificateVerificationCurrencySymbol } ←
    CommitteeATMSSchemes.atmsCommitteeCertificateVerificationMintingPolicyFromATMSKind
      { committeeCertificateMint, sidechainParams: scParams }
      atmsKind

  { committeeOracleCurrencySymbol } ←
    CommitteeOraclePolicy.getCommitteeOraclePolicy scParams

  let committeeNftPolicyId = currencySymbolToHex committeeOracleCurrencySymbol

  ds ← DistributedSet.getDs (unwrap scParams).genesisUtxo

  dsConfPolicy ← DistributedSet.dsConfPolicy
    (wrap (unwrap scParams).genesisUtxo)
  dsConfPolicyId ← getCurrencySymbolHex DSConfPolicy dsConfPolicy

  mCandidatePermissionPolicyId ← case mCandidatePermissionTokenUtxo of
    Nothing → pure Nothing
    Just permissionTokenUtxo → do
      { candidatePermissionPolicy } ←
        CandidatePermissionToken.getCandidatePermissionMintingPolicy
          $ CandidatePermissionMint
              { sidechainParams: scParams
              , candidatePermissionTokenUtxo: permissionTokenUtxo
              }
      candidatePermissionPolicyId ← getCurrencySymbolHex
        CandidatePermissionPolicy
        candidatePermissionPolicy
      pure $ Just candidatePermissionPolicyId

  { checkpointCurrencySymbol } ← do
    Checkpoint.getCheckpointPolicy scParams
  let checkpointPolicyId = currencySymbolToHex checkpointCurrencySymbol

  { versionOracleCurrencySymbol } ← getVersionOraclePolicy scParams
  let versionOraclePolicyId = currencySymbolToHex versionOracleCurrencySymbol

  { fuelProxyCurrencySymbol } ← getFuelProxyMintingPolicy scParams
  let fuelProxyPolicyId = currencySymbolToHex fuelProxyCurrencySymbol

  -- Validators
  committeeCandidateValidatorAddr ← do
    validator ← CommitteeCandidateValidator.getCommitteeCandidateValidator
      scParams
    getAddr validator

  merkleRootTokenCurrencySymbol ←
    getVersionedCurrencySymbol scParams $ VersionOracle
      { version: BigInt.fromInt version, scriptId: MerkleRootTokenPolicy }

  { committeeHashValidatorAddr, committeeHashValidatorCborAddress } ←
    do
      let
        uch = UpdateCommitteeHash
          { sidechainParams: scParams
          , committeeOracleCurrencySymbol: committeeOracleCurrencySymbol
          , merkleRootTokenCurrencySymbol
          , committeeCertificateVerificationCurrencySymbol
          }
      { validator, address } ← getUpdateCommitteeHashValidator uch
      bech32Addr ← getAddr validator

      pure
        { committeeHashValidatorAddr: bech32Addr
        , committeeHashValidatorCborAddress: getCborEncodedAddress address
        }

  dsInsertValidatorAddr ← do
    validator ← DistributedSet.insertValidator ds
    getAddr validator
  dsConfValidatorAddr ← do
    validator ← DistributedSet.dsConfValidator ds
    getAddr validator

  checkpointValidatorAddr ← do
    let
      checkpointParam = CheckpointParameter
        { sidechainParams: scParams
        , checkpointAssetClass: assetClass checkpointCurrencySymbol
            Checkpoint.initCheckpointMintTn
        , committeeOracleCurrencySymbol
        , committeeCertificateVerificationCurrencySymbol
        }
    validator ← Checkpoint.checkpointValidator checkpointParam
    getAddr validator

  veresionOracleValidatorAddr ← do
    validator ← versionOracleValidator scParams versionOracleCurrencySymbol
    getAddr validator

  { versionedPolicies, versionedValidators } ←
    Versioning.getVersionedPoliciesAndValidators
      { sidechainParams: scParams, atmsKind }
      version
  versionedCurrencySymbols ← Map.toUnfoldable <$> traverseWithIndex
    getCurrencySymbolHex
    versionedPolicies
  versionedAddresses ← Map.toUnfoldable <$> traverse getAddr versionedValidators

  let
    mintingPolicies =
      [ CommitteeNftPolicy /\ committeeNftPolicyId
      , DSConfPolicy /\ dsConfPolicyId
      , CheckpointPolicy /\ checkpointPolicyId
      , FUELProxyPolicy /\ fuelProxyPolicyId
      , VersionOraclePolicy /\ versionOraclePolicyId
      ]
        <>
          Array.catMaybes
            [ map (CandidatePermissionPolicy /\ _)
                mCandidatePermissionPolicyId
            ]
        <> versionedCurrencySymbols

    addresses =
      [ CommitteeCandidateValidator /\ committeeCandidateValidatorAddr
      , CommitteeHashValidator /\ committeeHashValidatorAddr
      , DSConfValidator /\ dsConfValidatorAddr
      , DSInsertValidator /\ dsInsertValidatorAddr
      , VersionOracleValidator /\ veresionOracleValidatorAddr
      , CheckpointValidator /\ checkpointValidatorAddr
      ] <> versionedAddresses

    cborEncodedAddresses =
      [ CommitteeHashValidator /\ committeeHashValidatorCborAddress
      ]

  pure
    { addresses
    , mintingPolicies
    , cborEncodedAddresses
    }

-- | Print the bech32 serialised address of a given validator
getAddr ∷ Validator → Contract String
getAddr v = do
  netId ← Address.getNetworkId
  addr ← Monad.liftContractM ("Cannot get validator address") $
    Address.validatorHashEnterpriseAddress
      netId
      (validatorHash v)
  serialised ← Address.addressToBech32 addr
  pure serialised

-- | Gets the hex encoded string of the cbor representation of an Address
getCborEncodedAddress ∷ Address → String
getCborEncodedAddress =
  ByteArray.byteArrayToHex
    <<< CborBytes.cborBytesToByteArray
    <<< PlutusData.serializeData

-- | `getCurrencySymbolHex` converts a minting policy to its hex encoded
-- | currency symbol
getCurrencySymbolHex ∷ ScriptId → MintingPolicy → Contract String
getCurrencySymbolHex name mp = do
  cs ← Monad.liftContractM (show (InternalError (InvalidScript $ show name))) $
    Value.scriptCurrencySymbol mp
  pure $ currencySymbolToHex cs

-- | Convert a currency symbol to hex encoded string
currencySymbolToHex ∷ CurrencySymbol → String
currencySymbolToHex =
  ByteArray.byteArrayToHex <<< Value.getCurrencySymbol
