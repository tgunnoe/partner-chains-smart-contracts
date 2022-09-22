-- | 'InitSidechain' implements the endpoint for intializing the sidechain.
module InitSidechain (initSidechain) where

import Contract.Prelude

import BalanceTx.Extra (reattachDatumsInline)
import Contract.Log (logInfo')
import Contract.Monad (Contract, liftedE, liftedM)
import Contract.Monad as Monad
import Contract.PlutusData (Datum(..))
import Contract.PlutusData as PlutusData
import Contract.ScriptLookups (ScriptLookups)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (validatorHash)
import Contract.Scripts as Scripts
import Contract.Transaction (awaitTxConfirmed, balanceAndSignTx, submit)
import Contract.TxConstraints (TxConstraints)
import Contract.TxConstraints as TxConstraints
import Contract.Utxos as Utxos
import Contract.Value as Value
import Data.Array as Array
import Data.Map as Map
import DistributedSet
  ( Ds(Ds)
  , DsConfDatum(DsConfDatum)
  , DsConfMint(DsConfMint)
  , DsDatum(DsDatum)
  , DsKeyMint(DsKeyMint)
  )
import DistributedSet as DistributedSet
import FUELMintingPolicy as FUELMintingPolicy
import SidechainParams
  ( InitSidechainParams(InitSidechainParams)
  , SidechainParams(SidechainParams)
  )
import Types (assetClassValue)
import UpdateCommitteeHash
  ( InitCommitteeHashMint(..)
  , UpdateCommitteeHash(..)
  , UpdateCommitteeHashDatum(..)
  , aggregateKeys
  , committeeHashAssetClass
  , committeeHashPolicy
  , updateCommitteeHashValidator
  )

{- | 'initSidechain' creates the 'SidechainParams' of a new sidechain which
 parameterize validators and minting policies in order to uniquely identify
 them. See the following notes for what 'initSidechain' must initialize.

 Note [Initializing the Committee Hash]
 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 The intialization step of the committee hash is done as follows.

  (1) Create an NFT which identifies the committee hash / spend the NFT to the
  script output which contains the committee hsah

 Note [Initializing the Distributed Set]
 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 The intialization step of the distributed set is done as follows.

  (1) Create an NFT and pay this to a script which holds 'DsConfDatum' which
  holds the minting policy of the scripts related to the distributed set.

  (2) Mint node which corresponds to the root of the distributed set
  i.e., 'DistributedSet.rootNode'

 Here, we create a transaction which executes both of these steps with a single
 transaction.
-}
initSidechain ∷ InitSidechainParams → Contract () SidechainParams
initSidechain (InitSidechainParams isp) = do
  let txIn = isp.initUtxo
  txOut ← liftedM "initSidechain: cannot find genesis UTxO" $ Utxos.getUtxo txIn

  -- Sidechain parameters
  -----------------------------------
  let
    sc = SidechainParams
      { chainId: isp.initChainId
      , genesisHash: isp.initGenesisHash
      , genesisUtxo: txIn
      , genesisMint: isp.initMint
      }

  -- Initializing the committee hash
  -----------------------------------
  let ichm = InitCommitteeHashMint { icTxOutRef: txIn }
  assetClassCommitteeHash ← committeeHashAssetClass ichm
  nftCommitteeHashPolicy ← committeeHashPolicy ichm
  aggregatedKeys ← aggregateKeys $ Array.sort isp.initCommittee
  let
    committeeHashParam = UpdateCommitteeHash
      { uchAssetClass: assetClassCommitteeHash }
    committeeHashDatum = Datum
      $ PlutusData.toData
      $ UpdateCommitteeHashDatum { committeeHash: aggregatedKeys }
    committeeHashValue = assetClassValue assetClassCommitteeHash one
  committeeHashValidator ← updateCommitteeHashValidator committeeHashParam
  let
    committeeHashValidatorHash = validatorHash committeeHashValidator

  -- Initializing the distributed set
  -----------------------------------

  -- Configuration policy of the distributed set
  dsConfPolicy ← DistributedSet.dsConfPolicy $ DsConfMint { dscmTxOutRef: txIn }
  dsConfPolicyCurrencySymbol ←
    Monad.liftContractM
      "error 'initSidechain': failed to get 'dsConfPolicy' CurrencySymbol."
      $ Value.scriptCurrencySymbol dsConfPolicy

  -- Validator for insertion of the distributed set / the associated datum and
  -- tokens that should be paid to this validator.
  let ds = Ds { dsConf: dsConfPolicyCurrencySymbol }
  insertValidator ← DistributedSet.insertValidator ds
  let
    insertValidatorHash = Scripts.validatorHash insertValidator
    dskm = DsKeyMint
      { dskmValidatorHash: insertValidatorHash
      , dskmConfCurrencySymbol: dsConfPolicyCurrencySymbol
      }

  dsKeyPolicy ← DistributedSet.dsKeyPolicy dskm
  dsKeyPolicyCurrencySymbol ←
    Monad.liftContractM
      "error 'initSidechain': failed to get 'dsKeyPolicy' CurrencySymbol."
      $ Value.scriptCurrencySymbol dsKeyPolicy
  dsKeyPolicyTokenName ←
    Monad.liftContractM
      "error 'initSidechain': failed to convert 'DistributedSet.rootNode.nKey' into a TokenName"
      $ Value.mkTokenName
      $ (unwrap DistributedSet.rootNode).nKey

  let
    insertValidatorValue = Value.singleton dsKeyPolicyCurrencySymbol
      dsKeyPolicyTokenName
      one
    insertValidatorDatum = Datum
      $ PlutusData.toData
      $ DsDatum
          { dsNext: (unwrap DistributedSet.rootNode).nNext
          }

  -- FUEL minting policy
  -- TODO: we need to update the fuel minting policy to actually integrate the
  -- distributed set in.
  fuelMintingPolicy ← FUELMintingPolicy.fuelMintingPolicy sc
  fuelMintingPolicyCurrencySymbol ←
    Monad.liftContractM
      "error 'initSidechain': failed to get 'fuelMintingPolicy' CurrencySymbol."
      $ Value.scriptCurrencySymbol fuelMintingPolicy

  -- Validator for the configuration of the distributed set / the associated
  -- datum and tokens that should be paid to this validator.
  dsConfValidator ← DistributedSet.dsConfValidator ds
  let
    dsConfValidatorHash = Scripts.validatorHash dsConfValidator
    dsConfValue = Value.singleton dsConfPolicyCurrencySymbol
      DistributedSet.dsConfTokenName
      one
    dsConfValidatorDatum = Datum
      $ PlutusData.toData
      $ DsConfDatum
          { dscKeyPolicy: dsKeyPolicyCurrencySymbol
          , dscFUELPolicy: fuelMintingPolicyCurrencySymbol
          }

  -- Building the transaction
  -----------------------------------
  let
    lookups ∷ ScriptLookups Void
    lookups =
      -- The distinguished transaction input to spend
      Lookups.unspentOutputs (Map.singleton txIn txOut)
        -- Lookups for update committee hash
        <> Lookups.mintingPolicy nftCommitteeHashPolicy
        <> Lookups.validator committeeHashValidator
        -- Lookups for the distributed set
        <> Lookups.validator insertValidator
        <> Lookups.mintingPolicy dsConfPolicy
        <> Lookups.mintingPolicy dsKeyPolicy

    constraints ∷ TxConstraints Void Void
    constraints =
      -- Spend the distinguished transaction input to spend
      TxConstraints.mustSpendPubKeyOutput txIn
        -- Constraints for updating the committee hash
        <> TxConstraints.mustMintValue committeeHashValue
        <> TxConstraints.mustPayToScript committeeHashValidatorHash
          committeeHashDatum
          committeeHashValue
        -- Constraints for initializing the distributed set
        <> TxConstraints.mustMintValue insertValidatorValue
        <> TxConstraints.mustPayToScript insertValidatorHash
          insertValidatorDatum
          insertValidatorValue
        <> TxConstraints.mustMintValue dsConfValue
        <> TxConstraints.mustPayToScript dsConfValidatorHash
          dsConfValidatorDatum
          dsConfValue

  ubTx ← liftedE (Lookups.mkUnbalancedTx lookups constraints)
  bsTx ← liftedM "Failed to balance/sign tx"
    (balanceAndSignTx (reattachDatumsInline ubTx))
  txId ← submit bsTx
  logInfo' "Submitted initial 'initSidechain' transaction."
  awaitTxConfirmed txId
  logInfo' "Initial 'initSidechain' transaction submitted successfully."

  pure sc
