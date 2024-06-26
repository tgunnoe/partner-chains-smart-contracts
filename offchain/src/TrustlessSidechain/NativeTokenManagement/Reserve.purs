module TrustlessSidechain.NativeTokenManagement.Reserve
  ( reserveValidator
  , reserveAuthPolicy
  , initialiseReserveUtxo
  , findReserveUtxos
  , depositToReserve
  , extractReserveDatum
  , updateReserveUtxo
  , transferToIlliquidCirculationSupply
  , handover
  ) where

import Contract.Prelude

import TrustlessSidechain.Utils.Asset (emptyAssetName, singletonFromAsset)
import Contract.Address (Address)
import Cardano.Types.Mint as Mint
import Cardano.Types.BigNum as BigNum
import Cardano.Types.BigNum (BigNum)
import Cardano.Types.Int as Int
import Cardano.Types.Asset (Asset(Asset))
import Cardano.Types.OutputDatum (outputDatumDatum)
import Cardano.Types.PlutusScript as PlutusScript
import Cardano.Types.PlutusScript (PlutusScript)
import Cardano.Types.ScriptHash (ScriptHash)
import Cardano.Types.AssetName (AssetName)
import Cardano.Types.Value (valueOf)
import Cardano.Types.TransactionUnspentOutput (TransactionUnspentOutput(TransactionUnspentOutput))
import Contract.PlutusData
  ( RedeemerDatum(RedeemerDatum)
  , fromData
  , toData
  , unitDatum
  )
import Contract.ScriptLookups as Lookups
import Contract.Transaction
  ( ScriptRef(..)
  , TransactionInput
  , TransactionOutput
  )
import Contract.TxConstraints (DatumPresence(..), InputWithScriptRef(..))
import Contract.TxConstraints as TxConstraints
import Contract.Utxos (UtxoMap)
import Contract.Value (add, getMultiAsset, minus, singleton) as Value
import JS.BigInt as BigInt
import Data.Map as Map
import Run (Run)
import Run.Except (EXCEPT, throw)
import TrustlessSidechain.Effects.Log (LOG)
import TrustlessSidechain.Effects.Transaction (TRANSACTION, utxosAt)
import TrustlessSidechain.Effects.Util (fromMaybeThrow)
import TrustlessSidechain.Effects.Wallet (WALLET)
import TrustlessSidechain.Error (OffchainError(..))
import TrustlessSidechain.NativeTokenManagement.Types
  ( ImmutableReserveSettings
  , MutableReserveSettings
  , ReserveDatum(..)
  , ReserveRedeemer(..)
  , ReserveStats(..)
  )
import TrustlessSidechain.SidechainParams (SidechainParams)
import TrustlessSidechain.Utils.Scripts
  ( mkMintingPolicyWithParams
  , mkValidatorWithParams
  )
import TrustlessSidechain.Utils.Transaction (balanceSignAndSubmit)
import TrustlessSidechain.Versioning.ScriptId (ScriptId(..))
import TrustlessSidechain.Versioning.Types
  ( VersionOracle(..)
  , VersionOracleConfig
  )
import TrustlessSidechain.Versioning.Utils as Versioning
import Type.Row (type (+))

reserveValidator ∷
  ∀ r.
  VersionOracleConfig →
  Run (EXCEPT OffchainError + r) PlutusScript
reserveValidator voc =
  mkValidatorWithParams ReserveValidator [ toData voc ]

reserveAuthPolicy ∷
  ∀ r.
  VersionOracleConfig →
  Run (EXCEPT OffchainError + r) PlutusScript
reserveAuthPolicy voc =
  mkMintingPolicyWithParams ReserveAuthPolicy [ toData voc ]

reserveAuthTokenName ∷ AssetName
reserveAuthTokenName = emptyAssetName

vFunctionTotalAccruedTokenName ∷ AssetName
vFunctionTotalAccruedTokenName = emptyAssetName

reserveVersionOracle ∷ VersionOracle
reserveVersionOracle = VersionOracle
  { version: BigNum.fromInt 1, scriptId: ReserveValidator }

reserveAuthVersionOracle ∷ VersionOracle
reserveAuthVersionOracle =
  VersionOracle
    { version: BigNum.fromInt 1, scriptId: ReserveAuthPolicy }

illiquidCirculationSupplyVersionOracle ∷ VersionOracle
illiquidCirculationSupplyVersionOracle =
  VersionOracle
    { version: BigNum.fromInt 1, scriptId: IlliquidCirculationSupplyValidator }

governanceVersionOracle ∷ VersionOracle
governanceVersionOracle = VersionOracle
  { version: BigNum.fromInt 1, scriptId: GovernancePolicy }

getReserveAuthCurrencySymbol ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    ScriptHash
getReserveAuthCurrencySymbol sidechainParams =
  Versioning.getVersionedCurrencySymbol
    sidechainParams
    reserveAuthVersionOracle

getReserveAddress ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    Address
getReserveAddress sidechainParams =
  Versioning.getVersionedValidatorAddress
    sidechainParams
    reserveVersionOracle

getGovernanceScriptRefUtxo ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    (TransactionInput /\ TransactionOutput)
getGovernanceScriptRefUtxo sidechainParams =
  Versioning.getVersionedScriptRefUtxo
    sidechainParams
    governanceVersionOracle

getReserveScriptRefUtxo ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    (TransactionInput /\ TransactionOutput)
getReserveScriptRefUtxo sidechainParams =
  Versioning.getVersionedScriptRefUtxo
    sidechainParams
    reserveVersionOracle

getReserveAuthScriptRefUtxo ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    (TransactionInput /\ TransactionOutput)
getReserveAuthScriptRefUtxo sidechainParams =
  Versioning.getVersionedScriptRefUtxo
    sidechainParams
    reserveAuthVersionOracle

getIlliquidCirculationSupplyScriptRefUtxo ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    (TransactionInput /\ TransactionOutput)
getIlliquidCirculationSupplyScriptRefUtxo sidechainParams =
  Versioning.getVersionedScriptRefUtxo
    sidechainParams
    illiquidCirculationSupplyVersionOracle

getGovernancePolicy ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    PlutusScript
getGovernancePolicy sidechainParams = do
  (_ /\ refTxOutput) ← getGovernanceScriptRefUtxo sidechainParams

  case (unwrap refTxOutput).scriptRef of
    Just (PlutusScriptRef s) → pure s
    _ → throw $ GenericInternalError
      "Versioning system utxo does not carry governance script"

getIlliquidCirculationSupplyValidator ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + TRANSACTION + r)
    PlutusScript
getIlliquidCirculationSupplyValidator sidechainParams = do
  (_ /\ refTxOutput) ← getIlliquidCirculationSupplyScriptRefUtxo sidechainParams

  case (unwrap refTxOutput).scriptRef of
    Just (PlutusScriptRef s) → pure s
    _ → throw $ GenericInternalError
      "Versioning system utxo does not carry ICS script"

findReserveUtxos ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    UtxoMap
findReserveUtxos sidechainParams = do
  reserveAuthCurrencySymbol ← getReserveAuthCurrencySymbol sidechainParams

  reserveAddress ← getReserveAddress sidechainParams

  utxos ← utxosAt reserveAddress

  pure $ flip Map.filter utxos $ \o → BigNum.one ==
    valueOf (Asset reserveAuthCurrencySymbol reserveAuthTokenName)
      (unwrap o).amount

reserveAuthLookupsAndConstraints ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    { reserveAuthLookups ∷ Lookups.ScriptLookups
    , reserveAuthConstraints ∷ TxConstraints.TxConstraints
    }
reserveAuthLookupsAndConstraints sp = do
  (reserveAuthRefTxInput /\ reserveAuthRefTxOutput) ←
    getReserveAuthScriptRefUtxo sp

  pure
    { reserveAuthLookups: Lookups.unspentOutputs
        (Map.singleton reserveAuthRefTxInput reserveAuthRefTxOutput)
    , reserveAuthConstraints: TxConstraints.mustReferenceOutput
        reserveAuthRefTxInput
    }

illiquidCirculationSupplyLookupsAndConstraints ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    { icsLookups ∷ Lookups.ScriptLookups
    , icsConstraints ∷ TxConstraints.TxConstraints
    }
illiquidCirculationSupplyLookupsAndConstraints sp = do
  (icsRefTxInput /\ icsRefTxOutput) ←
    getIlliquidCirculationSupplyScriptRefUtxo sp

  pure
    { icsLookups: Lookups.unspentOutputs
        (Map.singleton icsRefTxInput icsRefTxOutput)
    , icsConstraints: TxConstraints.mustReferenceOutput
        icsRefTxInput
    }

reserveLookupsAndConstraints ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    { reserveLookups ∷ Lookups.ScriptLookups
    , reserveConstraints ∷ TxConstraints.TxConstraints
    }
reserveLookupsAndConstraints sp = do
  (reserveRefTxInput /\ reserveRefTxOutput) ←
    getReserveScriptRefUtxo sp

  pure
    { reserveLookups: Lookups.unspentOutputs
        (Map.singleton reserveRefTxInput reserveRefTxOutput)
    , reserveConstraints: TxConstraints.mustReferenceOutput
        reserveRefTxInput
    }

governanceLookupsAndConstraints ∷
  ∀ r.
  SidechainParams →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    { governanceLookups ∷ Lookups.ScriptLookups
    , governanceConstraints ∷ TxConstraints.TxConstraints
    }
governanceLookupsAndConstraints sp = do
  (governanceRefTxInput /\ governanceRefTxOutput) ←
    getGovernanceScriptRefUtxo sp

  governancePolicy ← getGovernancePolicy sp

  pure
    { governanceLookups: Lookups.unspentOutputs
        (Map.singleton governanceRefTxInput governanceRefTxOutput)
    , governanceConstraints:
        TxConstraints.mustReferenceOutput governanceRefTxInput
          <> TxConstraints.mustMintCurrencyUsingScriptRef
            (PlutusScript.hash governancePolicy)
            emptyAssetName
            (Int.fromInt 1)
            ( RefInput $ TransactionUnspentOutput
                { input: governanceRefTxInput
                , output: governanceRefTxOutput
                }
            )
    }

initialiseReserveUtxo ∷
  ∀ r.
  SidechainParams →
  ImmutableReserveSettings →
  MutableReserveSettings →
  BigNum →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    Unit
initialiseReserveUtxo
  sidechainParams
  immutableSettings
  mutableSettings
  numOfTokens =
  do
    { governanceLookups
    , governanceConstraints
    } ← governanceLookupsAndConstraints sidechainParams

    { reserveLookups
    , reserveConstraints
    } ← reserveLookupsAndConstraints sidechainParams

    reserveAuthCurrencySymbol ← getReserveAuthCurrencySymbol sidechainParams

    versionOracleConfig ← Versioning.getVersionOracleConfig sidechainParams

    reserveValidator' ← PlutusScript.hash <$> reserveValidator
      versionOracleConfig
    reserveAuthPolicy' ← reserveAuthPolicy versionOracleConfig

    let
      valueToPay = singletonFromAsset (unwrap immutableSettings).tokenKind numOfTokens

      reserveAuthTokenValue =
        Value.singleton
          reserveAuthCurrencySymbol
          reserveAuthTokenName
          (BigNum.fromInt 1)

    totalValueToPay <- fromMaybeThrow
      (GenericInternalError "Could not calculate total value to pay")
      (pure (valueToPay `Value.add` reserveAuthTokenValue))

    let
      lookups ∷ Lookups.ScriptLookups
      lookups =
        governanceLookups
          <> reserveLookups
          <> Lookups.plutusMintingPolicy reserveAuthPolicy'

      constraints =
        governanceConstraints
          <> reserveConstraints
          <> TxConstraints.mustMintValue (Mint.fromMultiAsset $ Value.getMultiAsset reserveAuthTokenValue)
          <> TxConstraints.mustPayToScript
            reserveValidator'
            (toData initialReserveDatum)
            DatumInline
            totalValueToPay

    void $ balanceSignAndSubmit
      "Reserve initialization transaction"
      { constraints, lookups }

  where
  initialReserveDatum ∷ ReserveDatum
  initialReserveDatum = ReserveDatum
    { immutableSettings
    , mutableSettings
    , stats: ReserveStats { tokenTotalAmountTransferred: BigInt.fromInt 0 }
    }

extractReserveDatum ∷ TransactionOutput → Maybe ReserveDatum
extractReserveDatum txOut =
  (unwrap txOut).datum >>= outputDatumDatum >>= fromData

findReserveUtxoForAssetClass ∷
  ∀ r.
  SidechainParams →
  Asset →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    UtxoMap
findReserveUtxoForAssetClass sp ac = do
  utxos ← findReserveUtxos sp

  let
    extractTokenKind =
      unwrap >>> _.immutableSettings >>> unwrap >>> _.tokenKind

  pure $ flip Map.filter utxos $ \txOut →
    flip (maybe false) (extractReserveDatum txOut)
      $ extractTokenKind
      >>> (_ == ac)

depositToReserve ∷
  ∀ r.
  SidechainParams →
  Asset →
  BigNum →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    Unit
depositToReserve sp asset amount = do
  utxo ← fromMaybeThrow (NotFoundUtxo "Reserve UTxO for asset class not found")
    $ (Map.toUnfoldable <$> findReserveUtxoForAssetClass sp asset)

  { governanceLookups
  , governanceConstraints
  } ← governanceLookupsAndConstraints sp

  { reserveAuthLookups
  , reserveAuthConstraints
  } ← reserveAuthLookupsAndConstraints sp

  { icsLookups
  , icsConstraints
  } ← illiquidCirculationSupplyLookupsAndConstraints sp

  versionOracleConfig ← Versioning.getVersionOracleConfig sp
  reserveValidator' ← reserveValidator versionOracleConfig

  datum ← fromMaybeThrow (InvalidData "Reserve does not carry inline datum")
    $ pure ((unwrap $ snd utxo).datum >>= (outputDatumDatum))

  let
    value = unwrap >>> _.amount $ snd utxo

  newValue <- fromMaybeThrow
      (GenericInternalError "Could not calculate new reserve value")
      $ pure (value `Value.add` singletonFromAsset asset amount)

  let
    lookups ∷ Lookups.ScriptLookups
    lookups =
      reserveAuthLookups
        <> icsLookups
        <> governanceLookups
        <> Lookups.unspentOutputs (uncurry Map.singleton utxo)
        <> Lookups.validator reserveValidator'

    constraints =
      governanceConstraints
        <> icsConstraints
        <> reserveAuthConstraints
        <> TxConstraints.mustPayToScript
          (PlutusScript.hash reserveValidator')
          datum
          DatumInline
          newValue
        <> TxConstraints.mustSpendScriptOutput (fst utxo)
          (RedeemerDatum $ toData DepositToReserve)

  void $ balanceSignAndSubmit
    "Deposit to a reserve utxo"
    { constraints, lookups }

-- utxo passed to this function must be a reserve utxo
-- use `findReserveUtxos` and `extractReserveDatum` to find utxos of interest
updateReserveUtxo ∷
  ∀ r.
  SidechainParams →
  MutableReserveSettings →
  (TransactionInput /\ TransactionOutput) →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    Unit
updateReserveUtxo sp updatedMutableSettings utxo = do
  { governanceLookups
  , governanceConstraints
  } ← governanceLookupsAndConstraints sp

  { reserveAuthLookups
  , reserveAuthConstraints
  } ← reserveAuthLookupsAndConstraints sp

  { icsLookups
  , icsConstraints
  } ← illiquidCirculationSupplyLookupsAndConstraints sp

  versionOracleConfig ← Versioning.getVersionOracleConfig sp
  reserveValidator' ← reserveValidator versionOracleConfig

  datum ← fromMaybeThrow (InvalidData "Reserve does not carry inline datum")
    $ pure
    $ extractReserveDatum
    $ snd
    $ utxo

  let
    updatedDatum = ReserveDatum $ (unwrap datum)
      { mutableSettings = updatedMutableSettings }
    value = unwrap >>> _.amount $ snd utxo

    lookups ∷ Lookups.ScriptLookups
    lookups =
      reserveAuthLookups
        <> icsLookups
        <> governanceLookups
        <> Lookups.unspentOutputs (uncurry Map.singleton utxo)
        <> Lookups.validator reserveValidator'

    constraints =
      governanceConstraints
        <> icsConstraints
        <> reserveAuthConstraints
        <> TxConstraints.mustPayToScript
          (PlutusScript.hash reserveValidator')
          (toData updatedDatum)
          DatumInline
          value
        <> TxConstraints.mustSpendScriptOutput (fst utxo)
          (RedeemerDatum $ toData UpdateReserve)

  void $ balanceSignAndSubmit
    "Update reserve mutable settings"
    { constraints, lookups }

transferToIlliquidCirculationSupply ∷
  ∀ r.
  SidechainParams →
  Int → -- total amount of assets paid out until now
  PlutusScript →
  (TransactionInput /\ TransactionOutput) →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    Unit
transferToIlliquidCirculationSupply
  sp
  totalAccruedTillNow
  vFunctionTotalAccruedMintingPolicy
  utxo = do
  { reserveAuthLookups
  , reserveAuthConstraints
  } ← reserveAuthLookupsAndConstraints sp

  { icsLookups
  , icsConstraints
  } ← illiquidCirculationSupplyLookupsAndConstraints sp

  versionOracleConfig ← Versioning.getVersionOracleConfig sp
  reserveValidator' ← reserveValidator versionOracleConfig

  illiquidCirculationSupplyValidator ← getIlliquidCirculationSupplyValidator sp

  datum ← fromMaybeThrow (InvalidData "Reserve does not carry inline datum")
    $ pure
    $ extractReserveDatum
    $ snd
    $ utxo

  let
    tokenKindAsset =
      unwrap
        >>> _.immutableSettings
        >>> unwrap
        >>> _.tokenKind
        $ datum

  tokenTotalAmountTransferred <- fromMaybeThrow
    (GenericInternalError "Could not calculate total amount transferred")
    (unwrap
        >>> _.stats
        >>> unwrap
        >>> _.tokenTotalAmountTransferred
        >>> BigInt.toInt
        >>> pure
        $ datum)
  let
    vFunctionTotalAccruedCurrencySymbol =
      unwrap
        >>> _.mutableSettings
        >>> unwrap
        >>> _.vFunctionTotalAccrued
        $ datum

  incentiveAmount <- fromMaybeThrow
    (GenericInternalError "Could not calculate incentive amount")
    $ pure
      (unwrap
        >>> _.mutableSettings
        >>> unwrap
        >>> _.incentiveAmount
        >>> BigInt.toString
        >>> BigNum.fromString
        $ datum)

  unless
    ( (PlutusScript.hash vFunctionTotalAccruedMintingPolicy) ==
        vFunctionTotalAccruedCurrencySymbol
    ) $ throw (InvalidData "Passed ICS minting policy is not correct")

  let
    toTransferAsInt =
      totalAccruedTillNow - tokenTotalAmountTransferred

    incentiveAsValue =
      singletonFromAsset tokenKindAsset incentiveAmount

    toTransferAsValue =
      singletonFromAsset tokenKindAsset (BigNum.fromInt toTransferAsInt)

    vtTokensAsValue = Value.singleton
      vFunctionTotalAccruedCurrencySymbol
      vFunctionTotalAccruedTokenName
      (BigNum.fromInt toTransferAsInt)

  let
    updatedDatum = ReserveDatum $ (unwrap datum)
      { stats = ReserveStats { tokenTotalAmountTransferred: BigInt.fromInt totalAccruedTillNow }
      }
    value = unwrap >>> _.amount $ snd utxo

  newValue ← fromMaybeThrow (GenericInternalError "Could not calculate new reserve value")
    (pure (value `Value.minus` toTransferAsValue))

  illiquidCirculationNewValue <- fromMaybeThrow
    (GenericInternalError "Could not calculate new ICS value")
    (pure (toTransferAsValue `Value.minus` incentiveAsValue))

  let
    lookups ∷ Lookups.ScriptLookups
    lookups =
      reserveAuthLookups
        <> icsLookups
        <> Lookups.unspentOutputs (uncurry Map.singleton utxo)
        <> Lookups.validator reserveValidator'
        <> Lookups.plutusMintingPolicy vFunctionTotalAccruedMintingPolicy

    constraints =
      reserveAuthConstraints
        <> icsConstraints
        <> TxConstraints.mustPayToScript
          (PlutusScript.hash reserveValidator')
          (toData updatedDatum)
          DatumInline
          newValue
        <> TxConstraints.mustSpendScriptOutput (fst utxo)
          (RedeemerDatum $ toData TransferToIlliquidCirculationSupply)
        <> TxConstraints.mustMintValue
              (Mint.fromMultiAsset $ Value.getMultiAsset vtTokensAsValue)
        <> TxConstraints.mustPayToScript
          (PlutusScript.hash illiquidCirculationSupplyValidator)
          unitDatum
          DatumInline
          illiquidCirculationNewValue

  void $ balanceSignAndSubmit
    "Transfer to illiquid circulation supply"
    { constraints, lookups }

handover ∷
  ∀ r.
  SidechainParams →
  (TransactionInput /\ TransactionOutput) →
  Run
    (EXCEPT OffchainError + WALLET + LOG + TRANSACTION + r)
    Unit
handover
  sp
  utxo = do
  { reserveAuthLookups
  , reserveAuthConstraints
  } ← reserveAuthLookupsAndConstraints sp

  { icsLookups
  , icsConstraints
  } ← illiquidCirculationSupplyLookupsAndConstraints sp

  { governanceLookups
  , governanceConstraints
  } ← governanceLookupsAndConstraints sp

  { reserveLookups
  , reserveConstraints
  } ← reserveLookupsAndConstraints sp

  versionOracleConfig ← Versioning.getVersionOracleConfig sp
  reserveAuthPolicy' ← reserveAuthPolicy versionOracleConfig

  illiquidCirculationSupplyValidator ← getIlliquidCirculationSupplyValidator sp

  datum ← fromMaybeThrow (InvalidData "Reserve does not carry inline datum")
    $ pure
    $ extractReserveDatum
    $ snd
    $ utxo

  (reserveAuthRefTxInput /\ reserveAuthRefTxOutput) ← getReserveAuthScriptRefUtxo
    sp

  (reserveRefTxInput /\ reserveRefTxOutput) ← getReserveScriptRefUtxo sp

  let
    tokenKindAsset =
      unwrap
        >>> _.immutableSettings
        >>> unwrap
        >>> _.tokenKind
        $ datum

    value = unwrap >>> _.amount $ snd utxo
    tokenValue = valueOf tokenKindAsset value
    toHandover = singletonFromAsset tokenKindAsset tokenValue

    lookups ∷ Lookups.ScriptLookups
    lookups =
      reserveAuthLookups
        <> icsLookups
        <> governanceLookups
        <> reserveLookups
        <> Lookups.unspentOutputs (uncurry Map.singleton utxo)

    constraints =
      reserveAuthConstraints
        <> icsConstraints
        <> governanceConstraints
        <> reserveConstraints
        <> TxConstraints.mustPayToScript
          (PlutusScript.hash illiquidCirculationSupplyValidator)
          unitDatum
          DatumInline
          toHandover
        <> TxConstraints.mustSpendScriptOutputUsingScriptRef
          (fst utxo)
          (RedeemerDatum $ toData Handover)
          ( RefInput $ TransactionUnspentOutput
              { input: reserveRefTxInput
              , output: reserveRefTxOutput
              }
          )
        <> TxConstraints.mustMintCurrencyUsingScriptRef
          (PlutusScript.hash reserveAuthPolicy')
          emptyAssetName
          (Int.fromInt (-1))
          ( RefInput $ TransactionUnspentOutput
              { input: reserveAuthRefTxInput
              , output: reserveAuthRefTxOutput
              }
          )

  void $ balanceSignAndSubmit
    "Handover to illiquid circulation supply"
    { constraints, lookups }
