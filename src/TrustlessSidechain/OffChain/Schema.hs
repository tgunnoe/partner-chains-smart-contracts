module TrustlessSidechain.OffChain.Schema where

import Plutus.Contract (Endpoint, type (.\/))
import TrustlessSidechain.OffChain.Types (BurnParams, DeregisterParams, MintParams, RegisterParams, RootParams)

type TrustlessSidechainSchema =
  Endpoint "register" RegisterParams
    .\/ Endpoint "deregister" DeregisterParams
    .\/ Endpoint "burn" BurnParams
    .\/ Endpoint "mint" MintParams
    .\/ Endpoint "root" RootParams
