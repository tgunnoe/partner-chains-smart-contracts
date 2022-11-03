module Main (main) where

import Contract.Prelude

import CommitteCandidateValidator as CommitteCandidateValidator
import Contract.Address (ownPaymentPubKeyHash)
import Contract.Monad
  ( Contract
  , launchAff_
  , liftedM
  , runContract
  )
import Data.List as List
import EndpointResp (EndpointResp(..), stringifyEndpointResp)
import FUELMintingPolicy
  ( FuelParams(Burn)
  , passiveBridgeMintParams
  , runFuelMP
  )
import GetSidechainAddresses as GetSidechainAddresses
import InitSidechain (initSidechain)
import MPTRoot (SaveRootParams(SaveRootParams))
import MPTRoot as MPTRoot
import Options (getOptions)
import Options.Types (Endpoint(..))
import UpdateCommitteeHash
  ( UpdateCommitteeHashParams(UpdateCommitteeHashParams)
  )
import UpdateCommitteeHash as UpdateCommitteeHash

-- | Main entrypoint for the CTL CLI
main ∷ Effect Unit
main = do
  opts ← getOptions

  launchAff_ $ runContract opts.configParams do
    pkh ← liftedM "Couldn't find own PKH" ownPaymentPubKeyHash
    endpointResp ← case opts.endpoint of
      MintAct { amount } →
        runFuelMP opts.scParams
          (passiveBridgeMintParams opts.scParams { amount, recipient: pkh })
          <#> unwrap
          >>> { transactionId: _ }
          >>> MintActResp

      BurnAct { amount, recipient } →
        runFuelMP opts.scParams
          (Burn { amount, recipient }) <#> unwrap >>> { transactionId: _ } >>>
          BurnActResp

      CommitteeCandidateReg
        { spoPubKey
        , sidechainPubKey
        , spoSig
        , sidechainSig
        , inputUtxo
        } →
        let
          params = CommitteCandidateValidator.RegisterParams
            { sidechainParams: opts.scParams
            , spoPubKey
            , sidechainPubKey
            , spoSig
            , sidechainSig
            , inputUtxo
            }
        in
          CommitteCandidateValidator.register params
            <#> unwrap
            >>> { transactionId: _ }
            >>> CommitteeCandidateRegResp

      CommitteeCandidateDereg { spoPubKey } →
        let
          params = CommitteCandidateValidator.DeregisterParams
            { sidechainParams: opts.scParams
            , spoPubKey
            }
        in
          CommitteCandidateValidator.deregister params
            <#> unwrap
            >>> { transactionId: _ }
            >>> CommitteeCandidateDeregResp
      GetAddrs → do
        addresses ← GetSidechainAddresses.getSidechainAddresses opts.scParams
        pure $ GetAddrsResp { addresses }

      CommitteeHash
        { newCommitteePubKeys, committeeSignatures, previousMerkleRoot } →
        let
          params = UpdateCommitteeHashParams
            { sidechainParams: opts.scParams
            , newCommitteePubKeys: List.toUnfoldable newCommitteePubKeys
            , committeeSignatures: List.toUnfoldable committeeSignatures
            , previousMerkleRoot
            }
        in
          UpdateCommitteeHash.updateCommitteeHash params
            <#> unwrap
            >>> { transactionId: _ }
            >>> CommitteeHashResp

      SaveRoot { merkleRoot, previousMerkleRoot, committeeSignatures } →
        let
          params = SaveRootParams
            { sidechainParams: opts.scParams
            , merkleRoot
            , previousMerkleRoot
            , committeeSignatures: List.toUnfoldable committeeSignatures
            }
        in
          MPTRoot.saveRoot params
            <#> unwrap
            >>> { transactionId: _ }
            >>> SaveRootResp
      Init { committeePubKeys } → do
        let
          sc = unwrap opts.scParams
          isc = wrap
            { initChainId: sc.chainId
            , initGenesisHash: sc.genesisHash
            , initUtxo: sc.genesisUtxo
            -- v only difference between sidechain and initsidechain
            , initCommittee: List.toUnfoldable committeePubKeys
            , initMint: sc.genesisMint
            }
        { transactionId, sidechainParams, addresses } ← initSidechain isc

        pure $ InitResp
          { transactionId: unwrap transactionId, sidechainParams, addresses }

      CommitteeHandover
        { merkleRoot
        , previousMerkleRoot
        , newCommitteePubKeys
        , newCommitteeSignatures
        , newMerkleRootSignatures
        } → do
        let
          saveRootParams = SaveRootParams
            { sidechainParams: opts.scParams
            , merkleRoot
            , previousMerkleRoot
            , committeeSignatures: List.toUnfoldable newMerkleRootSignatures
            }
          uchParams = UpdateCommitteeHashParams
            { sidechainParams: opts.scParams
            , newCommitteePubKeys: List.toUnfoldable newCommitteePubKeys
            , committeeSignatures: List.toUnfoldable newCommitteeSignatures
            , -- the previous merkle root is the merkle root we just saved..
              previousMerkleRoot: Just merkleRoot
            }
        saveRootTransactionId ← unwrap <$> MPTRoot.saveRoot saveRootParams
        committeeHashTransactionId ← unwrap <$>
          UpdateCommitteeHash.updateCommitteeHash uchParams
        pure $ CommitteeHandoverResp
          { saveRootTransactionId, committeeHashTransactionId }

    printEndpointResp endpointResp

printEndpointResp ∷ EndpointResp → Contract () Unit
printEndpointResp =
  log <<< stringifyEndpointResp
