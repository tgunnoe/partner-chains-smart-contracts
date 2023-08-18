module TrustlessSidechain.Versioning.Types
  ( class Versionable
  , toScriptHash
  , toPlutusScript
  , ScriptId(..)
  , VersionOracle(..)
  , VersionOracleConfig(..)
  , VersionOraclePolicyRedeemer(..)
  , VersionOracleValidatorRedeemer(..)
  ) where

import Contract.Prelude

import Contract.Numeric.BigNum as BigNum
import Contract.PlutusData
  ( class FromData
  , class ToData
  , PlutusData(..)
  , fromData
  , toData
  )
import Contract.Scripts
  ( MintingPolicy(..)
  , PlutusScript
  , ScriptHash
  , Validator
  )
import Contract.Scripts as Scripts
import Contract.Value (CurrencySymbol)
import Data.BigInt (BigInt)
import Data.BigInt as BigInt
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)

-- | 'ScriptId' lists IDs of all scripts that are used by the sidechain, most of
-- | which are versioned using the versioning system.  Note that the list of
-- | versioned scripts can be extended during sidechain's lifetime.  It is
-- | therefore crucial that 'ScriptId' uses custom 'ToData'/'FromData' instances
-- | that represent constructors as integers.  Representing constructors as
-- | integers in the on-chain code allows adding new constructors without
-- | breaking compatibility with existing on-chain code.  When adding new
-- | constructors care should be taken not to reorder existing ones.  (More
-- | specifically, not to change integers assigned to already existing
-- | constructors.)
-- |
-- | 'ToData'/'FromData' instances below must align with identifiers assigned in
-- | on-chain code.  See Note [Versioned script identifiers].
data ScriptId
  = FUELMintingPolicy
  | MerkleRootTokenPolicy
  | MerkleRootTokenValidator
  | CommitteeCandidateValidator
  | CandidatePermissionPolicy
  | CommitteeNftPolicy
  | CommitteeHashPolicy
  | CommitteeHashValidator
  | DSKeyPolicy
  | DSConfPolicy
  | DSConfValidator
  | DSInsertValidator
  | CheckpointValidator
  | CheckpointPolicy
  | FUELBurningPolicy
  | VersionOraclePolicy -- not versioned
  | VersionOracleValidator -- not versioned
  | FUELProxyPolicy -- not versioned
  | CommitteeCertificateVerificationPolicy
  | CommitteeOraclePolicy -- (previously UpdateCommitteeHashPolicy)

derive instance Eq ScriptId
derive instance Ord ScriptId

instance Show ScriptId where
  show FUELMintingPolicy = "FUELMintingPolicy"
  show MerkleRootTokenPolicy = "MerkleRootTokenPolicy"
  show MerkleRootTokenValidator = "MerkleRootTokenValidator"
  show CommitteeCandidateValidator = "CommitteeCandidateValidator"
  show CandidatePermissionPolicy = "CandidatePermissionPolicy"
  show CommitteeNftPolicy = "CommitteeNftPolicy"
  show CommitteeHashPolicy = "CommitteeHashPolicy"
  show CommitteeHashValidator = "CommitteeHashValidator"
  show DSKeyPolicy = "DSKeyPolicy"
  show DSConfPolicy = "DSConfPolicy"
  show DSConfValidator = "DSConfValidator"
  show DSInsertValidator = "DSInsertValidator"
  show CheckpointValidator = "CheckpointValidator"
  show CheckpointPolicy = "CheckpointPolicy"
  show FUELBurningPolicy = "FUELBurningPolicy"
  show VersionOraclePolicy = "VersionOraclePolicy"
  show VersionOracleValidator = "VersionOracleValidator"
  show FUELProxyPolicy = "FUELProxyPolicy"
  show CommitteeCertificateVerificationPolicy =
    "CommitteeCertificateVerificationPolicy"
  show CommitteeOraclePolicy = "CommitteeOraclePolicy"

instance FromData ScriptId where
  fromData (Integer i) | i == BigInt.fromInt 0 =
    Just FUELMintingPolicy
  fromData (Integer i) | i == BigInt.fromInt 1 =
    Just MerkleRootTokenPolicy
  fromData (Integer i) | i == BigInt.fromInt 2 =
    Just MerkleRootTokenValidator
  fromData (Integer i) | i == BigInt.fromInt 3 =
    Just CommitteeCandidateValidator
  fromData (Integer i) | i == BigInt.fromInt 4 =
    Just CandidatePermissionPolicy
  fromData (Integer i) | i == BigInt.fromInt 5 =
    Just CommitteeNftPolicy
  fromData (Integer i) | i == BigInt.fromInt 6 =
    Just CommitteeHashPolicy
  fromData (Integer i) | i == BigInt.fromInt 7 =
    Just CommitteeHashValidator
  fromData (Integer i) | i == BigInt.fromInt 8 =
    Just DSKeyPolicy
  fromData (Integer i) | i == BigInt.fromInt 9 =
    Just DSConfPolicy
  fromData (Integer i) | i == BigInt.fromInt 10 =
    Just DSConfValidator
  fromData (Integer i) | i == BigInt.fromInt 11 =
    Just DSInsertValidator
  fromData (Integer i) | i == BigInt.fromInt 12 =
    Just CheckpointValidator
  fromData (Integer i) | i == BigInt.fromInt 13 =
    Just CheckpointPolicy
  fromData (Integer i) | i == BigInt.fromInt 14 =
    Just FUELBurningPolicy
  fromData (Integer i) | i == BigInt.fromInt 15 =
    Just VersionOraclePolicy
  fromData (Integer i) | i == BigInt.fromInt 16 =
    Just VersionOracleValidator
  fromData (Integer i) | i == BigInt.fromInt 17 =
    Just FUELProxyPolicy
  fromData (Integer i) | i == BigInt.fromInt 18 =
    Just CommitteeCertificateVerificationPolicy
  fromData (Integer i) | i == BigInt.fromInt 19 =
    Just CommitteeOraclePolicy

  fromData _ = Nothing

instance ToData ScriptId where
  toData FUELMintingPolicy = Integer (BigInt.fromInt 0)
  toData MerkleRootTokenPolicy = Integer (BigInt.fromInt 1)
  toData MerkleRootTokenValidator = Integer (BigInt.fromInt 2)
  toData CommitteeCandidateValidator = Integer (BigInt.fromInt 3)
  toData CandidatePermissionPolicy = Integer (BigInt.fromInt 4)
  toData CommitteeNftPolicy = Integer (BigInt.fromInt 5)
  toData CommitteeHashPolicy = Integer (BigInt.fromInt 6)
  toData CommitteeHashValidator = Integer (BigInt.fromInt 7)
  toData DSKeyPolicy = Integer (BigInt.fromInt 8)
  toData DSConfPolicy = Integer (BigInt.fromInt 9)
  toData DSConfValidator = Integer (BigInt.fromInt 10)
  toData DSInsertValidator = Integer (BigInt.fromInt 11)
  toData CheckpointValidator = Integer (BigInt.fromInt 12)
  toData CheckpointPolicy = Integer (BigInt.fromInt 13)
  toData FUELBurningPolicy = Integer (BigInt.fromInt 14)
  toData VersionOraclePolicy = Integer (BigInt.fromInt 15)
  toData VersionOracleValidator = Integer (BigInt.fromInt 16)
  toData FUELProxyPolicy = Integer (BigInt.fromInt 17)
  toData CommitteeCertificateVerificationPolicy = Integer (BigInt.fromInt 18)
  toData CommitteeOraclePolicy = Integer (BigInt.fromInt 19)

-- | Datum attached to 'VersionOraclePolicy' tokens stored on the
-- | 'VersionOracleValidator' script.
newtype VersionOracle = VersionOracle
  { version ∷ BigInt -- ^ version of the protocol
  , scriptId ∷ ScriptId -- ^ unique identifier of the validator
  }

derive instance Eq VersionOracle
derive instance Generic VersionOracle _
instance Show VersionOracle where
  show = genericShow

instance FromData VersionOracle where
  fromData (Constr n [ v, sId ]) | n == (BigNum.fromInt 0) =
    VersionOracle <$>
      ({ version: _, scriptId: _ } <$> fromData v <*> fromData sId)
  fromData _ = Nothing

instance ToData VersionOracle where
  toData (VersionOracle { version, scriptId }) = Constr (BigNum.fromInt 0)
    [ toData version, toData scriptId ]

-- | Redeemer for the version oracle minting policy that instructs the script
-- | whether to mint or burn version tokens.
data VersionOraclePolicyRedeemer
  = -- | Mint initial version tokens.  Used during sidechain initialization.
    InitializeVersionOracle
  | -- | Mint a new version token ensuring it contains correct datum and
    -- | reference script.
    MintVersionOracle VersionOracle ScriptHash
  | -- | Burn existing version token.
    BurnVersionOracle VersionOracle

instance FromData VersionOraclePolicyRedeemer where
  fromData (Constr n []) | n == (BigNum.fromInt 0) =
    pure InitializeVersionOracle
  fromData (Constr n [ vo, sh ]) | n == (BigNum.fromInt 1) =
    MintVersionOracle <$> fromData vo <*> fromData sh
  fromData (Constr n [ vo ]) | n == (BigNum.fromInt 2) =
    BurnVersionOracle <$> fromData vo
  fromData _ = Nothing

instance ToData VersionOraclePolicyRedeemer where
  toData InitializeVersionOracle =
    Constr (BigNum.fromInt 0) []
  toData (MintVersionOracle vo sh) =
    Constr (BigNum.fromInt 1) [ toData vo, toData sh ]
  toData (BurnVersionOracle vo) =
    Constr (BigNum.fromInt 2) [ toData vo ]

-- | Redeemer for version oracle validator script.  Used when existing
-- | version tokens are spent from the script, either to be burned or updated
-- | with a new script and datum.
data VersionOracleValidatorRedeemer
  = -- | Invalidate existing version token.
    InvalidateVersionOracle VersionOracle
  | -- | Update existing version token.
    UpdateVersionOracle VersionOracle ScriptHash

instance FromData VersionOracleValidatorRedeemer where
  fromData (Constr n [ vo ]) | n == (BigNum.fromInt 0) =
    InvalidateVersionOracle <$> fromData vo
  fromData (Constr n [ vo, sh ]) | n == (BigNum.fromInt 1) =
    UpdateVersionOracle <$> fromData vo <*> fromData sh
  fromData _ = Nothing

instance ToData VersionOracleValidatorRedeemer where
  toData (InvalidateVersionOracle vo) = Constr (BigNum.fromInt 0) [ toData vo ]
  toData (UpdateVersionOracle vo sh) = Constr (BigNum.fromInt 1)
    [ toData vo
    , toData sh
    ]

-- | Configuration of the versioning system.  Contains currency symbol of
-- | VersionOraclePolicy tokens.  Required to identify version tokens that can
-- | be trusted.
newtype VersionOracleConfig = VersionOracleConfig
  { versionOracleCurrencySymbol ∷ CurrencySymbol -- ^ VersionOraclePolicy
  }

derive instance Generic VersionOracleConfig _
derive instance Newtype VersionOracleConfig _

instance FromData VersionOracleConfig where
  fromData (Constr n [ currencySymbol ]) | n == (BigNum.fromInt 0) = do
    versionOracleCurrencySymbol ← fromData currencySymbol
    pure $ VersionOracleConfig { versionOracleCurrencySymbol }

  fromData _ = Nothing

instance ToData VersionOracleConfig where
  toData
    ( VersionOracleConfig { versionOracleCurrencySymbol }
    ) =
    Constr (BigNum.fromInt 0)
      [ toData versionOracleCurrencySymbol ]

-- | Class of types that can be versioned.  Allows uniform handling of
-- | validators and minting policies when building lookups and constraints for
-- | versioning purposes.
class Versionable a where
  toPlutusScript ∷ a → Maybe PlutusScript
  toScriptHash ∷ a → ScriptHash

instance Versionable Validator where
  toPlutusScript = Just <<< unwrap
  toScriptHash = unwrap <<< Scripts.validatorHash

instance Versionable MintingPolicy where
  toPlutusScript (PlutusMintingPolicy script) = Just script
  toPlutusScript _ = Nothing
  toScriptHash = unwrap <<< Scripts.mintingPolicyHash
