{-# LANGUAGE TemplateHaskell #-}

module Compiled (
  newVerify,
  mkCPMPCode,
  mkCVCode,
  mkCCVCode,
  mkMPFuelCode,
  mkMPMerkleRootCode,
  mkUPCVCode,
  mkCommitteeHashPolicyCode,
  mkCPCode,
  mkInsertValidatorCode,
  mkDsConfPolicyCode,
  mkDsKeyPolicyCode,
  toDataGenerated,
  toDataHandwritten,
  fromDataGenerated,
  fromDataHandwritten,
  unsafeFromDataGenerated,
  unsafeFromDataHandwritten,
  pairToDataGenerated,
  pairToDataHandwritten,
  pairFromDataGenerated,
  pairFromDataHandwritten,
  pairUnsafeFromDataGenerated,
  pairUnsafeFromDataHandwritten,
  listToDataGenerated,
  listToDataHandwritten,
  listFromDataHandwritten,
  listFromDataGenerated,
  listUnsafeFromDataGenerated,
  listUnsafeFromDataHandwritten,
) where

import Data.Generated qualified as Generated
import Data.Handwritten qualified as Handwritten
import Plutus.V2.Ledger.Contexts (ScriptContext)
import PlutusTx (fromBuiltinData, toBuiltinData, unsafeFromBuiltinData)
import PlutusTx.Code (CompiledCode)
import PlutusTx.TH (compile)
import TrustlessSidechain.CandidatePermissionMintingPolicy (
  mkCandidatePermissionMintingPolicy,
 )
import TrustlessSidechain.CheckpointValidator (
  InitCheckpointMint,
  mkCheckpointPolicy,
  mkCheckpointValidator,
 )
import TrustlessSidechain.CommitteeCandidateValidator (
  mkCommitteeCandidateValidator,
 )
import TrustlessSidechain.DistributedSet (
  Ds,
  DsConfMint,
  DsDatum,
  DsKeyMint,
  mkDsConfPolicy,
  mkDsKeyPolicy,
  mkInsertValidator,
 )
import TrustlessSidechain.FUELMintingPolicy qualified as FUEL
import TrustlessSidechain.MerkleRootTokenMintingPolicy as MerkleRoot
import TrustlessSidechain.PlutusPrelude
import TrustlessSidechain.Types (
  BlockProducerRegistration,
  CandidatePermissionMint,
  CheckpointDatum,
  CheckpointParameter,
  CheckpointRedeemer,
  FUELMint,
  FUELRedeemer,
  SidechainParams,
  SignedMerkleRoot,
  SignedMerkleRootMint,
  UpdateCommitteeHash,
  UpdateCommitteeHashDatum,
  UpdateCommitteeHashRedeemer,
 )
import TrustlessSidechain.UpdateCommitteeHash (
  InitCommitteeHashMint,
  mkCommitteeHashPolicy,
  mkUpdateCommitteeHashValidator,
 )
import TrustlessSidechain.Utils (verifyMultisig)

listUnsafeFromDataGenerated :: CompiledCode (BuiltinData -> [Integer])
listUnsafeFromDataGenerated = $$(compile [||unsafeFromBuiltinData||])

listUnsafeFromDataHandwritten :: CompiledCode (BuiltinData -> [Integer])
listUnsafeFromDataHandwritten = $$(compile [||Handwritten.listUnsafeFromData||])

listFromDataGenerated :: CompiledCode (BuiltinData -> Maybe [Integer])
listFromDataGenerated = $$(compile [||fromBuiltinData||])

listFromDataHandwritten :: CompiledCode (BuiltinData -> Maybe [Integer])
listFromDataHandwritten = $$(compile [||Handwritten.listFromData||])

listToDataGenerated :: CompiledCode ([Integer] -> BuiltinData)
listToDataGenerated = $$(compile [||toBuiltinData||])

listToDataHandwritten :: CompiledCode ([Integer] -> BuiltinData)
listToDataHandwritten = $$(compile [||Handwritten.listToData||])

pairUnsafeFromDataGenerated :: CompiledCode (BuiltinData -> (Integer, Integer))
pairUnsafeFromDataGenerated = $$(compile [||unsafeFromBuiltinData||])

pairUnsafeFromDataHandwritten :: CompiledCode (BuiltinData -> (Integer, Integer))
pairUnsafeFromDataHandwritten = $$(compile [||Handwritten.pairUnsafeFromData||])

pairFromDataGenerated :: CompiledCode (BuiltinData -> Maybe (Integer, Integer))
pairFromDataGenerated = $$(compile [||fromBuiltinData||])

pairFromDataHandwritten :: CompiledCode (BuiltinData -> Maybe (Integer, Integer))
pairFromDataHandwritten = $$(compile [||Handwritten.pairFromData||])

pairToDataGenerated :: CompiledCode ((Integer, Integer) -> BuiltinData)
pairToDataGenerated = $$(compile [||toBuiltinData||])

pairToDataHandwritten :: CompiledCode ((Integer, Integer) -> BuiltinData)
pairToDataHandwritten = $$(compile [||Handwritten.pairToData||])

fromDataGenerated :: CompiledCode (BuiltinData -> Maybe Generated.Foo)
fromDataGenerated = $$(compile [||fromBuiltinData||])

fromDataHandwritten :: CompiledCode (BuiltinData -> Maybe Handwritten.Foo)
fromDataHandwritten = $$(compile [||fromBuiltinData||])

toDataGenerated :: CompiledCode (Generated.Foo -> BuiltinData)
toDataGenerated = $$(compile [||toBuiltinData||])

toDataHandwritten :: CompiledCode (Handwritten.Foo -> BuiltinData)
toDataHandwritten = $$(compile [||toBuiltinData||])

unsafeFromDataGenerated :: CompiledCode (BuiltinData -> Generated.Foo)
unsafeFromDataGenerated = $$(compile [||unsafeFromBuiltinData||])

unsafeFromDataHandwritten :: CompiledCode (BuiltinData -> Handwritten.Foo)
unsafeFromDataHandwritten = $$(compile [||unsafeFromBuiltinData||])

newVerify ::
  CompiledCode
    ( [BuiltinByteString] ->
      Integer ->
      BuiltinByteString ->
      [BuiltinByteString] ->
      Bool
    )
newVerify = $$(compile [||verifyMultisig||])

mkCPMPCode ::
  CompiledCode (CandidatePermissionMint -> () -> ScriptContext -> Bool)
mkCPMPCode = $$(compile [||mkCandidatePermissionMintingPolicy||])

mkCVCode ::
  CompiledCode
    ( CheckpointParameter ->
      CheckpointDatum ->
      CheckpointRedeemer ->
      ScriptContext ->
      Bool
    )
mkCVCode = $$(compile [||mkCheckpointValidator||])

mkCCVCode ::
  CompiledCode
    ( SidechainParams ->
      BlockProducerRegistration ->
      () ->
      ScriptContext ->
      Bool
    )
mkCCVCode = $$(compile [||mkCommitteeCandidateValidator||])

mkMPFuelCode ::
  CompiledCode
    ( FUELMint ->
      FUELRedeemer ->
      ScriptContext ->
      Bool
    )
mkMPFuelCode = $$(compile [||FUEL.mkMintingPolicy||])

mkMPMerkleRootCode ::
  CompiledCode
    ( SignedMerkleRootMint ->
      SignedMerkleRoot ->
      ScriptContext ->
      Bool
    )
mkMPMerkleRootCode = $$(compile [||MerkleRoot.mkMintingPolicy||])

mkUPCVCode ::
  CompiledCode
    ( UpdateCommitteeHash ->
      UpdateCommitteeHashDatum ->
      UpdateCommitteeHashRedeemer ->
      ScriptContext ->
      Bool
    )
mkUPCVCode = $$(compile [||mkUpdateCommitteeHashValidator||])

mkCommitteeHashPolicyCode ::
  CompiledCode
    ( InitCommitteeHashMint ->
      () ->
      ScriptContext ->
      Bool
    )
mkCommitteeHashPolicyCode = $$(compile [||mkCommitteeHashPolicy||])

mkCPCode ::
  CompiledCode
    ( InitCheckpointMint ->
      () ->
      ScriptContext ->
      Bool
    )
mkCPCode = $$(compile [||mkCheckpointPolicy||])

mkInsertValidatorCode ::
  CompiledCode (Ds -> DsDatum -> () -> ScriptContext -> Bool)
mkInsertValidatorCode = $$(compile [||mkInsertValidator||])

mkDsConfPolicyCode ::
  CompiledCode (DsConfMint -> () -> ScriptContext -> Bool)
mkDsConfPolicyCode = $$(compile [||mkDsConfPolicy||])

mkDsKeyPolicyCode ::
  CompiledCode (DsKeyMint -> () -> ScriptContext -> Bool)
mkDsKeyPolicyCode = $$(compile [||mkDsKeyPolicy||])
