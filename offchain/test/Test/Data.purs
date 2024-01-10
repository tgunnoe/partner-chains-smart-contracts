module Test.Data (tests) where

import Contract.Prelude

import Contract.Address (PaymentPubKeyHash(PaymentPubKeyHash))
import Contract.Prim.ByteArray (ByteArray, byteArrayFromIntArrayUnsafe)
import Contract.Scripts (ValidatorHash(ValidatorHash))
import Control.Alt ((<|>))
import Data.Array.NonEmpty as NE
import Data.BigInt (BigInt)
import Data.BigInt as BigInt
import Data.String.CodeUnits (fromCharArray)
import Mote.Monad (test)
import Test.QuickCheck.Arbitrary (arbitrary)
import Test.QuickCheck.Gen (Gen, arrayOf, chooseInt, elements, vectorOf)
import Test.QuickCheck.Gen as QGen
import Test.Utils (WrappedTests, pureGroup)
import Test.Utils.Laws (toDataLaws)
import Test.Utils.QuickCheck
  ( ArbitraryAssetClass(ArbitraryAssetClass)
  , ArbitraryBigInt(ArbitraryBigInt)
  , ArbitraryCurrencySymbol(ArbitraryCurrencySymbol)
  , ArbitraryPaymentPubKeyHash(ArbitraryPaymentPubKeyHash)
  , ArbitraryPubKey(ArbitraryPubKey)
  , ArbitrarySignature(ArbitrarySignature)
  , ArbitraryTransactionInput(ArbitraryTransactionInput)
  , ArbitraryValidatorHash(ArbitraryValidatorHash)
  , DA
  , NonNegative(NonNegative)
  , Positive(Positive)
  , liftArbitrary
  , suchThatMap
  )
import TrustlessSidechain.CandidatePermissionToken
  ( CandidatePermissionMint(CandidatePermissionMint)
  )
import TrustlessSidechain.Checkpoint.Types
  ( CheckpointDatum(CheckpointDatum)
  , CheckpointMessage(CheckpointMessage)
  , CheckpointParameter(CheckpointParameter)
  , InitCheckpointMint(InitCheckpointMint)
  )
import TrustlessSidechain.CommitteeATMSSchemes.Types
  ( CommitteeCertificateMint(CommitteeCertificateMint)
  )
import TrustlessSidechain.CommitteeCandidateValidator
  ( BlockProducerRegistration(BlockProducerRegistration)
  , BlockProducerRegistrationMsg(BlockProducerRegistrationMsg)
  , StakeOwnership(AdaBasedStaking, TokenBasedStaking)
  )
import TrustlessSidechain.CommitteeOraclePolicy
  ( InitCommitteeHashMint(InitCommitteeHashMint)
  )
import TrustlessSidechain.CommitteePlainSchnorrSecp256k1ATMSPolicy
  ( ATMSPlainSchnorrSecp256k1Multisignature
      ( ATMSPlainSchnorrSecp256k1Multisignature
      )
  )
import TrustlessSidechain.CommitteePlainSchnorrSecp256k1ATMSPolicy as Schnorr
import TrustlessSidechain.DParameter.Types
  ( DParameterPolicyRedeemer(DParameterMint, DParameterBurn)
  , DParameterValidatorDatum(DParameterValidatorDatum)
  , DParameterValidatorRedeemer(UpdateDParameter, RemoveDParameter)
  )
import TrustlessSidechain.DistributedSet
  ( Ds(Ds)
  , DsConfDatum(DsConfDatum)
  , DsConfMint(DsConfMint)
  , DsDatum(DsDatum)
  , DsKeyMint(DsKeyMint)
  , Node(Node)
  )
import TrustlessSidechain.FUELMintingPolicy.V1
  ( CombinedMerkleProof(CombinedMerkleProof)
  , FUELMintingRedeemer(FUELMintingRedeemer, FUELBurningRedeemer)
  , MerkleTreeEntry(MerkleTreeEntry)
  )
import TrustlessSidechain.Governance (GovernanceAuthority(GovernanceAuthority))
import TrustlessSidechain.MerkleRoot.Types
  ( MerkleRootInsertionMessage(MerkleRootInsertionMessage)
  , SignedMerkleRootRedeemer(SignedMerkleRootRedeemer)
  )
import TrustlessSidechain.MerkleTree
  ( MerkleProof(MerkleProof)
  , RootHash
  , Side(L, R)
  , Up(Up)
  , byteArrayToRootHashUnsafe
  )
import TrustlessSidechain.PermissionedCandidates.Types
  ( PermissionedCandidateKeys(PermissionedCandidateKeys)
  , PermissionedCandidatesPolicyRedeemer
      ( PermissionedCandidatesMint
      , PermissionedCandidatesBurn
      )
  , PermissionedCandidatesValidatorDatum(PermissionedCandidatesValidatorDatum)
  , PermissionedCandidatesValidatorRedeemer
      ( UpdatePermissionedCandidates
      , RemovePermissionedCandidates
      )
  )
import TrustlessSidechain.SidechainParams (SidechainParams(SidechainParams))
import TrustlessSidechain.UpdateCommitteeHash.Types
  ( UpdateCommitteeDatum(UpdateCommitteeDatum)
  , UpdateCommitteeHash(UpdateCommitteeHash)
  , UpdateCommitteeHashMessage(UpdateCommitteeHashMessage)
  , UpdateCommitteeHashRedeemer(UpdateCommitteeHashRedeemer)
  )
import TrustlessSidechain.Utils.Address (byteArrayToBech32BytesUnsafe)
import TrustlessSidechain.Utils.Crypto
  ( EcdsaSecp256k1PubKey
  , ecdsaSecp256k1PubKey
  )
import TrustlessSidechain.Utils.SchnorrSecp256k1
  ( SchnorrSecp256k1PublicKey(SchnorrSecp256k1PublicKey)
  , SchnorrSecp256k1Signature(SchnorrSecp256k1Signature)
  )
import TrustlessSidechain.Versioning.Types
  ( ScriptId
      ( FUELMintingPolicy
      , MerkleRootTokenPolicy
      , MerkleRootTokenValidator
      , CommitteeCandidateValidator
      , CandidatePermissionPolicy
      , CommitteeHashValidator
      , DsKeyPolicy
      , DsConfPolicy
      , DsConfValidator
      , DsInsertValidator
      , CheckpointValidator
      , CheckpointPolicy
      , FUELBurningPolicy
      , VersionOraclePolicy
      , VersionOracleValidator
      , FUELProxyPolicy
      , CommitteeCertificateVerificationPolicy
      , CommitteeOraclePolicy
      , CommitteePlainEcdsaSecp256k1ATMSPolicy
      , CommitteePlainSchnorrSecp256k1ATMSPolicy
      , DParameterPolicy
      , DParameterValidator
      , PermissionedCandidatesPolicy
      , PermissionedCandidatesValidator
      , ScriptCache
      )
  , VersionOracle(VersionOracle)
  , VersionOracleConfig(VersionOracleConfig)
  , VersionOraclePolicyRedeemer
      ( InitializeVersionOracle
      , MintVersionOracle
      , BurnVersionOracle
      )
  , VersionOracleValidatorRedeemer(InvalidateVersionOracle, UpdateVersionOracle)
  )

tests ∷ WrappedTests
tests = pureGroup "Data roundtrip tests" $ do
  test "SidechainParams" $ liftEffect $ toDataLaws testCount genSP
  test "EcdsaSecp256k1PubKey" $ liftEffect $ toDataLaws smallTestCount genPK
  test "CandidatePermissionMint" $ liftEffect $ toDataLaws testCount genCPM
  test "BlockProducerRegistration" $ liftEffect $ toDataLaws testCount genBPR
  test "BlockProducerRegistrationMsg" $ liftEffect $ toDataLaws testCount
    genBPRM
  -- BlockProducerRegistrationMsg?
  test "MerkleTreeEntry" $ liftEffect $ toDataLaws testCount genMTE
  test "MerkleRootInsertionMessage" $ liftEffect $ toDataLaws testCount genMRIM
  test "SignedMerkleRootRedeemer" $ liftEffect $ toDataLaws testCount genSMRR
  test "RootHash" $ liftEffect $ toDataLaws testCount genRH
  test "Side" $ liftEffect $ toDataLaws smallTestCount genSide
  test "Up" $ liftEffect $ toDataLaws testCount genUp
  test "MerkleProof" $ liftEffect $ toDataLaws testCount genMP
  test "CombinedMerkleProof" $ liftEffect $ toDataLaws smallTestCount genCMP
  -- FUELRedeemer not exported
  test "UpdateCommitteeDatum" $ liftEffect $ toDataLaws testCount genUCD
  test "UpdateCommitteeHash" $ liftEffect $ toDataLaws smallTestCount genUCH
  test "UpdateCommitteeHashMessage" $ liftEffect $ toDataLaws smallTestCount
    genUCHM
  test "UpdateCommitteeHashRedeemer" $ liftEffect $ toDataLaws testCount genUCHR
  test "CommitteeCertificateMint" $ liftEffect $ toDataLaws testCount genCCM
  test "CheckpointParameter" $ liftEffect $ toDataLaws smallTestCount genCP
  test "Ds" $ liftEffect $ toDataLaws testCount genDs
  test "DsDatum" $ liftEffect $ toDataLaws testCount genDsDatum
  test "DsConfDatum" $ liftEffect $ toDataLaws smallTestCount genDsConfDatum
  -- Ib not exported
  test "DsConfMint" $ liftEffect $ toDataLaws testCount genDsConfMint
  test "DsKeyMint" $ liftEffect $ toDataLaws testCount genDsKeyMint
  test "Node" $ liftEffect $ toDataLaws testCount genNode
  test "CheckpointDatum" $ liftEffect $ toDataLaws testCount genCheckpointDatum
  test "CheckpointParameter" $ liftEffect $ toDataLaws testCount
    genCheckpointParameter
  test "InitCheckpointMint" $ liftEffect $ toDataLaws testCount
    genInitCheckpointMint
  test "CheckpointMessage" $ liftEffect $ toDataLaws testCount
    genCheckpointMessage
  test "DParameterValidatorRedeemer" $ liftEffect $ toDataLaws testCount
    genDParameterValidatorRedeemer
  test "DParameterValidatorDatum" $ liftEffect $ toDataLaws testCount
    genDParameterValidatorDatum
  test "DParameterPolicyRedeemer" $ liftEffect $ toDataLaws testCount
    genDParameterPolicyRedeemer
  test "FUELMintingRedeemer" $ liftEffect $ toDataLaws testCount
    genFUELMintingRedeemer
  test "PermissionedCandidatesValidatorRedeemer" $ liftEffect $ toDataLaws
    testCount
    genPermissionedCandidatesValidatorRedeemer
  test "PermissionedCandidatesValidatorDatum" $ liftEffect $ toDataLaws testCount
    genPermissionedCandidatesValidatorDatum
  test "PermissionedCandidatesPolicyRedeemer" $ liftEffect $ toDataLaws testCount
    genPermissionedCandidatesPolicyRedeemer
  test "PermissionedCandidateKeys" $ liftEffect $ toDataLaws testCount
    genPermissionedCandidateKeys
  test "ScriptId" $ liftEffect $ toDataLaws testCount genScriptId
  test "VersionOracle" $ liftEffect $ toDataLaws testCount genVersionOracle
  test "VersionOracleConfig" $ liftEffect $ toDataLaws testCount
    genVersionOracleConfig
  test "VersionOraclePolicyRedeemer" $ liftEffect $ toDataLaws testCount
    genVersionOraclePolicyRedeemer
  test "VersionOracleValidatorRedeemer" $ liftEffect $ toDataLaws testCount
    genVersionOracleValidatorRedeemer
  test "InitCommitteeHashMint" $ liftEffect $ toDataLaws testCount
    genInitCommitteeHashMint
  test "ATMSPlainSchnorrSecp256k1Multisignature" $ liftEffect $ toDataLaws
    testCount
    genATMSPlainSchnorrSecp256k1Multisignature
  test "ATMSRedeemerSchnorr" $ liftEffect $ toDataLaws testCount
    genATMSRedeemerSchnorr
  where
  testCount ∷ Int
  testCount = 10_000

  smallTestCount ∷ Int
  smallTestCount = 1_000

-- Generators

genBPRM ∷ Gen BlockProducerRegistrationMsg
genBPRM = do
  bprmSidechainParams ← genSP
  bprmSidechainPubKey ← genGH
  ArbitraryTransactionInput bprmInputUtxo ← arbitrary
  pure $ BlockProducerRegistrationMsg
    { bprmSidechainParams
    , bprmSidechainPubKey
    , bprmInputUtxo
    }

genNode ∷ Gen Node
genNode = do
  nKey ← genGH
  nNext ← genGH
  pure $ Node
    { nKey
    , nNext
    }

genCheckpointDatum ∷ Gen CheckpointDatum
genCheckpointDatum = do
  blockHash ← arbitrary
  blockNumber ← BigInt.fromInt <$> arbitrary
  pure $ CheckpointDatum
    { blockHash
    , blockNumber
    }

genCheckpointParameter ∷ Gen CheckpointParameter
genCheckpointParameter = do
  sidechainParams ← genSP
  ArbitraryAssetClass checkpointAssetClass ← arbitrary
  ArbitraryCurrencySymbol committeeOracleCurrencySymbol ← arbitrary
  ArbitraryCurrencySymbol committeeCertificateVerificationCurrencySymbol ←
    arbitrary

  pure $ CheckpointParameter
    { sidechainParams
    , checkpointAssetClass
    , committeeOracleCurrencySymbol
    , committeeCertificateVerificationCurrencySymbol
    }

genInitCheckpointMint ∷ Gen InitCheckpointMint
genInitCheckpointMint = InitCheckpointMint <<< { icTxOutRef: _ } <$> do
  ArbitraryTransactionInput input ← arbitrary
  pure input

genCheckpointMessage ∷ Gen CheckpointMessage
genCheckpointMessage = do
  sidechainParams ← genSP
  checkpointBlockHash ← arbitrary
  checkpointBlockNumber ← BigInt.fromInt <$> arbitrary
  sidechainEpoch ← BigInt.fromInt <$> arbitrary

  pure $ CheckpointMessage
    { sidechainParams
    , checkpointBlockHash
    , checkpointBlockNumber
    , sidechainEpoch
    }

genDParameterValidatorRedeemer ∷ Gen DParameterValidatorRedeemer
genDParameterValidatorRedeemer = QGen.oneOf $ NE.cons' (pure UpdateDParameter)
  [ pure RemoveDParameter ]

genDParameterValidatorDatum ∷ Gen DParameterValidatorDatum
genDParameterValidatorDatum = do
  permissionedCandidatesCount ← BigInt.fromInt <$> arbitrary
  registeredCandidatesCount ← BigInt.fromInt <$> arbitrary

  pure $ DParameterValidatorDatum
    { permissionedCandidatesCount
    , registeredCandidatesCount
    }

genDParameterPolicyRedeemer ∷ Gen DParameterPolicyRedeemer
genDParameterPolicyRedeemer = QGen.oneOf $ NE.cons' (pure DParameterMint)
  [ pure DParameterBurn ]

genFUELMintingRedeemer ∷ Gen FUELMintingRedeemer
genFUELMintingRedeemer = QGen.oneOf $ NE.cons' (pure FUELBurningRedeemer)
  [ FUELMintingRedeemer <$> genMTE <*> genMP
  ]

genPermissionedCandidatesValidatorRedeemer ∷
  Gen PermissionedCandidatesValidatorRedeemer
genPermissionedCandidatesValidatorRedeemer = QGen.oneOf $ NE.cons'
  (pure UpdatePermissionedCandidates)
  [ pure RemovePermissionedCandidates ]

genPermissionedCandidatesValidatorDatum ∷
  Gen PermissionedCandidatesValidatorDatum
genPermissionedCandidatesValidatorDatum = do
  PermissionedCandidatesValidatorDatum <<< { candidates: _ } <$> QGen.arrayOf
    genPermissionedCandidateKeys

genPermissionedCandidatesPolicyRedeemer ∷
  Gen PermissionedCandidatesPolicyRedeemer
genPermissionedCandidatesPolicyRedeemer = QGen.oneOf $ NE.cons'
  (pure PermissionedCandidatesMint)
  [ pure PermissionedCandidatesBurn ]

genPermissionedCandidateKeys ∷ Gen PermissionedCandidateKeys
genPermissionedCandidateKeys = do
  sidechainKey ← arbitrary
  auraKey ← arbitrary
  grandpaKey ← arbitrary

  pure $ PermissionedCandidateKeys
    { sidechainKey
    , auraKey
    , grandpaKey
    }

genScriptId ∷ Gen ScriptId
genScriptId = QGen.oneOf $ NE.cons' (pure FUELMintingPolicy) $ pure <$>
  [ MerkleRootTokenPolicy
  , MerkleRootTokenValidator
  , CommitteeCandidateValidator
  , CandidatePermissionPolicy
  , CommitteeHashValidator
  , DsKeyPolicy
  , DsConfPolicy
  , DsConfValidator
  , DsInsertValidator
  , CheckpointValidator
  , CheckpointPolicy
  , FUELBurningPolicy
  , VersionOraclePolicy
  , VersionOracleValidator
  , FUELProxyPolicy
  , CommitteeCertificateVerificationPolicy
  , CommitteeOraclePolicy
  , CommitteePlainEcdsaSecp256k1ATMSPolicy
  , CommitteePlainSchnorrSecp256k1ATMSPolicy
  , DParameterPolicy
  , DParameterValidator
  , PermissionedCandidatesPolicy
  , PermissionedCandidatesValidator
  , ScriptCache
  ]

genVersionOracle ∷ Gen VersionOracle
genVersionOracle = do
  version ← BigInt.fromInt <$> arbitrary
  scriptId ← genScriptId
  pure $ VersionOracle
    { version
    , scriptId
    }

genVersionOracleConfig ∷ Gen VersionOracleConfig
genVersionOracleConfig = do
  ArbitraryCurrencySymbol versionOracleCurrencySymbol ← arbitrary
  pure $ VersionOracleConfig
    { versionOracleCurrencySymbol
    }

genVersionOraclePolicyRedeemer ∷ Gen VersionOraclePolicyRedeemer
genVersionOraclePolicyRedeemer = QGen.oneOf $ NE.cons'
  (pure InitializeVersionOracle)
  [ do
      versionOracle ← genVersionOracle
      ArbitraryValidatorHash (ValidatorHash scriptHash) ← arbitrary
      pure $ MintVersionOracle versionOracle scriptHash
  , BurnVersionOracle <$> genVersionOracle
  ]

genVersionOracleValidatorRedeemer ∷ Gen VersionOracleValidatorRedeemer
genVersionOracleValidatorRedeemer = QGen.oneOf $ NE.cons'
  ( do
      versionOracle ← genVersionOracle
      pure $ InvalidateVersionOracle versionOracle
  )
  [ do
      versionOracle ← genVersionOracle
      ArbitraryValidatorHash (ValidatorHash scriptHash) ← arbitrary
      pure $ UpdateVersionOracle versionOracle scriptHash
  ]

genInitCommitteeHashMint ∷ Gen InitCommitteeHashMint
genInitCommitteeHashMint = do
  ArbitraryTransactionInput icTxOutRef ← arbitrary
  pure $ InitCommitteeHashMint
    { icTxOutRef }

genATMSPlainSchnorrSecp256k1Multisignature ∷
  Gen Schnorr.ATMSPlainSchnorrSecp256k1Multisignature
genATMSPlainSchnorrSecp256k1Multisignature = do
  currentCommittee ← map SchnorrSecp256k1PublicKey <$> QGen.arrayOf arbitrary
  currentCommitteeSignatures ← map SchnorrSecp256k1Signature <$> QGen.arrayOf
    arbitrary
  pure $ ATMSPlainSchnorrSecp256k1Multisignature
    { currentCommittee
    , currentCommitteeSignatures
    }

genATMSRedeemerSchnorr ∷ Gen Schnorr.ATMSRedeemer
genATMSRedeemerSchnorr = QGen.oneOf $ NE.cons'
  ( pure Schnorr.ATMSBurn
  )
  [ Schnorr.ATMSMint <$> genATMSPlainSchnorrSecp256k1Multisignature
  ]

genDsKeyMint ∷ Gen DsKeyMint
genDsKeyMint = do
  ArbitraryValidatorHash dskmValidatorHash ← arbitrary
  ArbitraryCurrencySymbol dskmConfCurrencySymbol ← arbitrary
  pure $ DsKeyMint
    { dskmValidatorHash
    , dskmConfCurrencySymbol
    }

genDsConfMint ∷ Gen DsConfMint
genDsConfMint = DsConfMint <$> do
  ArbitraryTransactionInput ti ← arbitrary
  pure ti

genDsConfDatum ∷ Gen DsConfDatum
genDsConfDatum = do
  ArbitraryCurrencySymbol dscKeyPolicy ← arbitrary
  ArbitraryCurrencySymbol dscFUELPolicy ← arbitrary
  pure $ DsConfDatum
    { dscKeyPolicy
    , dscFUELPolicy
    }

genDsDatum ∷ Gen DsDatum
genDsDatum = DsDatum <$> genGH

genDs ∷ Gen Ds
genDs = Ds <$> do
  ArbitraryCurrencySymbol cs ← arbitrary
  pure cs

genCP ∷ Gen CheckpointParameter
genCP = do
  sidechainParams ← genSP
  ArbitraryAssetClass checkpointAssetClass ← arbitrary
  ArbitraryCurrencySymbol committeeOracleCurrencySymbol ← arbitrary
  ArbitraryCurrencySymbol committeeCertificateVerificationCurrencySymbol ←
    arbitrary
  pure $ CheckpointParameter
    { sidechainParams
    , checkpointAssetClass
    , committeeOracleCurrencySymbol
    , committeeCertificateVerificationCurrencySymbol
    }

genCCM ∷ Gen CommitteeCertificateMint
genCCM = do
  Positive (ArbitraryBigInt thresholdNumerator) ← arbitrary
  Positive (ArbitraryBigInt thresholdDenominator) ← arbitrary
  pure $ CommitteeCertificateMint
    { thresholdNumerator
    , thresholdDenominator
    }

genUCHR ∷ Gen UpdateCommitteeHashRedeemer
genUCHR =
  UpdateCommitteeHashRedeemer <<< { previousMerkleRoot: _ } <$> liftArbitrary
    genRH

genUCHM ∷ Gen (UpdateCommitteeHashMessage DA)
genUCHM = do
  sidechainParams ← genSP
  newAggregatePubKeys ← arbitrary
  previousMerkleRoot ← liftArbitrary genRH
  Positive (ArbitraryBigInt sidechainEpoch) ← arbitrary
  ArbitraryValidatorHash validatorHash ← arbitrary
  pure $ UpdateCommitteeHashMessage
    { sidechainParams
    , newAggregatePubKeys
    , previousMerkleRoot
    , sidechainEpoch
    , validatorHash
    }

genUCH ∷ Gen UpdateCommitteeHash
genUCH = do
  sidechainParams ← genSP
  ArbitraryCurrencySymbol committeeOracleCurrencySymbol ← arbitrary
  ArbitraryCurrencySymbol committeeCertificateVerificationCurrencySymbol ←
    arbitrary
  ArbitraryCurrencySymbol merkleRootTokenCurrencySymbol ← arbitrary
  pure $ UpdateCommitteeHash
    { sidechainParams
    , committeeOracleCurrencySymbol
    , committeeCertificateVerificationCurrencySymbol
    , merkleRootTokenCurrencySymbol
    }

genUCD ∷ Gen (UpdateCommitteeDatum DA)
genUCD = do
  aggregatePubKeys ← arbitrary
  Positive (ArbitraryBigInt sidechainEpoch) ← arbitrary
  pure $ UpdateCommitteeDatum
    { aggregatePubKeys
    , sidechainEpoch
    }

genCMP ∷ Gen CombinedMerkleProof
genCMP = do
  transaction ← genMTE
  merkleProof ← genMP
  pure $ CombinedMerkleProof
    { transaction
    , merkleProof
    }

genMP ∷ Gen MerkleProof
genMP = MerkleProof <$> arrayOf genUp

genUp ∷ Gen Up
genUp = do
  siblingSide ← genSide
  sibling ← genRH
  pure $ Up
    { siblingSide
    , sibling
    }

genSide ∷ Gen Side
genSide = elements $ NE.cons' L [ R ]

genSMRR ∷ Gen SignedMerkleRootRedeemer
genSMRR =
  SignedMerkleRootRedeemer <<< { previousMerkleRoot: _ } <$> liftArbitrary genRH

genMRIM ∷ Gen MerkleRootInsertionMessage
genMRIM = do
  sidechainParams ← genSP
  merkleRoot ← genRH
  previousMerkleRoot ← liftArbitrary genRH
  pure $ MerkleRootInsertionMessage
    { sidechainParams
    , merkleRoot
    , previousMerkleRoot
    }

genGA ∷ Gen GovernanceAuthority
genGA = do
  ArbitraryPaymentPubKeyHash (PaymentPubKeyHash pkh) ← arbitrary
  pure $ GovernanceAuthority pkh

genMTE ∷ Gen MerkleTreeEntry
genMTE = do
  index ← genBigIntBits 32
  amount ← genBigIntBits 256
  recipient ← byteArrayToBech32BytesUnsafe <$> genGH
  previousMerkleRoot ← liftArbitrary genRH
  pure $ MerkleTreeEntry
    { index
    , amount
    , recipient
    , previousMerkleRoot
    }

genSO ∷ Gen StakeOwnership
genSO =
  ( ado
      ArbitraryPubKey pk ← arbitrary
      ArbitrarySignature sig ← arbitrary
      in AdaBasedStaking pk sig
  )
    <|> pure TokenBasedStaking

genBPR ∷ Gen BlockProducerRegistration
genBPR = do
  stakeOwnership ← genSO
  sidechainPubKey ← genGH
  auraKey ← genGH
  grandpaKey ← genGH
  sidechainSignature ← genGH
  ArbitraryTransactionInput inputUtxo ← arbitrary
  ArbitraryPaymentPubKeyHash ownPkh ← arbitrary
  pure $ BlockProducerRegistration
    { stakeOwnership
    , sidechainPubKey
    , sidechainSignature
    , inputUtxo
    , ownPkh
    , auraKey
    , grandpaKey
    }

genCPM ∷ Gen CandidatePermissionMint
genCPM = do
  sidechainParams ← genSP
  ArbitraryTransactionInput candidatePermissionTokenUtxo ← arbitrary
  pure $ CandidatePermissionMint
    { sidechainParams
    , candidatePermissionTokenUtxo
    }

genPK ∷ Gen EcdsaSecp256k1PubKey
genPK = suchThatMap (genByteArrayLen 33) ecdsaSecp256k1PubKey

genSP ∷ Gen SidechainParams
genSP = do
  NonNegative (ArbitraryBigInt chainId) ← arbitrary
  ArbitraryTransactionInput genesisUtxo ← arbitrary
  Positive (ArbitraryBigInt thresholdNumerator) ← arbitrary
  Positive (ArbitraryBigInt thresholdDenominator) ← arbitrary
  governanceAuthority ← genGA
  pure $ SidechainParams
    { chainId
    , genesisUtxo
    , thresholdNumerator
    , thresholdDenominator
    , governanceAuthority
    }

genRH ∷ Gen RootHash
genRH = byteArrayToRootHashUnsafe <$> genByteArrayLen 32

genGH ∷ Gen ByteArray
genGH = byteArrayFromIntArrayUnsafe <$> arrayOf (chooseInt 0 255)

genByteArrayLen ∷ Int → Gen ByteArray
genByteArrayLen len =
  byteArrayFromIntArrayUnsafe <$> vectorOf len (chooseInt 0 255)

-- Doing this is a bit tricky, as you can easily overflow if you use the naive
-- method, as Purescript limits Int to 32 bits (4 bytes), and the number is
-- signed.
--
-- Instead, we generate a binary string of required size, then convert it.
genBigIntBits ∷ Int → Gen BigInt
genBigIntBits bitSize = suchThatMap mkChars
  (fromCharArray >>> BigInt.fromBase 2)
  where
  mkChars ∷ Gen (Array Char)
  mkChars = vectorOf bitSize (elements (NE.cons' '0' [ '1' ]))
