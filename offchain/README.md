# Off-chain Operations

This document describes usage of the partner chains CLI.  This command line tool
provides a set of commands (also known as "endpoints"), that are used to manage
the Cardano components of a partner chain by submitting transactions to the
Cardano network.

**NOTE:** terms _partner chain_ and _sidechain_ are used interchangeably in this
document.

## 1. Development

If you want to develop for this submodule, please consult the notes in
[CONTRIBUTING.md](./CONTRIBUTING.md) before setting up your environment.

## 2. Environment setup

In order to execute off-chain commands with the CLI, you need to setup the
runtime dependencies:

- cardano-node
- ogmios
- kupo

Luckily, we have a dockerised setup, that spins up all these easily with a
preset Preview or Preprod. Just run:

```
nix run .#ctl-runtime-preview
```

To change the testnet you're using, you have to change the network name in the `flake.nix`

```
      runtimeConfig = {
        network = {
          name = "NETWORK_NAME";
          magic = NETWORK_MAGIC;
        };
      };
```

**TODO**: the above statement is incorrect, we no longer seem to have testnet
configuration in `flake.nix`.

You can also run these components directly without using Docker, more about these
can be found [here](https://github.com/Plutonomicon/cardano-transaction-lib/blob/develop/doc/runtime.md).

Or by using a nix derivation, that brings required runtime dependencies into
scope:
https://github.com/szg251/cardano-dev-shell

**TODO:** Do we consider the above a valid method of running the runtime
dependencies?  If so, shouldn't we somehow pull this into the project (if
license permits?) instead of relying on someone's private repo?

### 2.1. Configuring hosted runtime dependencies

In case you are running the runtime dependencies (ogmios and kupo) on a hosted
environment, or anything else than the default settings, you can either configure
it via CLI arguments, or set these in the configuration file (see Section 3.1).

The arguments for ogmios and kupo are using the following scheme:

```
  --ogmios-host localhost  Address host of ogmios (default: "localhost")
  --ogmios-path some/path  Address path of ogmios
  --ogmios-port 1234       Port of ogmios (default: 1337u)
  --ogmios-secure          Whether ogmios is using an HTTPS connection
```

So in case you want to use a remote ogmios service on `https://1.2.3.4:5678`,
you want to use the following arguments:
```
nix run .#sidechain-main-cli -- [...] --ogmios-host 1.2.3.4 --ogmios-port 5678 --ogmios-secure
```
where `[...]` represents a command and command-specific flags and options.

See [3.1. Using a configuration file](#3.1.-using-a-configuration-file) on how
to use a configuration file instead of command-line options.

## 3. Running the CLI

You can run the CLI tool either through Nix or by directly running the compiled
executables (these take the form of JavaScript files).

When using `nix`, commands and options passed to the CLI must be preceeded by
`--`.  For example, to display the list of all available commands one needs to
execute:

```
nix run .#sidechain-main-cli -- --help
```

**TODO**: instructions below on bundling and running JavaScript do not work and
need to be updated/rewritten.

**Bundle to a JavaScript file and run using node:**
```shell
nix build .#ctl-bundle-cli
```

This will produce a package `trustless-sidechain-cli-<version>.tar` with the
compiled `main.js` script that can be run using Node and all necessary
dependencies in `node_modules` directory.
```
node main.js --help
```

### 3.1. Using a configuration file

When running the CLI one needs to pass a single command (see section 3.3 below)
followed by options.  A set of options related to defining the partner chain
parameters is used by all commands.  Instead of having to pass these options on
the command line with every call, it is easier to put them in a configuration
file `$CWD/config.json` in the following format:

```json
  "sidechainParameters": {
    "chainId": 123,
    "genesisUtxo": "3824c3a7c4437cc6ca4f893cd1519ae1dbe77862304e14d910ddc1f32de69b60#1",
    "threshold": {
      "numerator": 2,
      "denominator": 3
    },
    "atmsKind": "plain-ecdsa-secp256k1",
    "governanceAuthority": "4f2d6145e1700ad11dc074cad9f4194cc53b0dbab6bd25dfea6c501a"
  },
  "runtimeConfig": {
    "network": "testnet",
    "ogmios": {
      "host": "localhost",
      "port": 1337,
      "secure": false,
      "path": null
    },
    "kupo": {
      "host": "localhost",
      "port": 1442,
      "secure": false,
      "path": null
    }
  },
  "paymentSigningKeyFile": "/absolute/path/to/payment.skey",
  "stakeSigningKeyFile": "/optional/path/to/stake.skey"
```

This allows to shorten a CLI call from:
```
nix run .#sidechain-main-cli -- burn-v1 \
  --sidechain-id 123 \
  --genesis-committee-hash-utxo 3824c3a7c4437cc6ca4f893cd1519ae1dbe77862304e14d910ddc1f32de69b60#1 \
  --threshold-numerator 2 \
  --threshold-denominator 3 \
  --atms-kind plain-ecdsa-secp256k1 \
  --governance-authority 4f2d6145e1700ad11dc074cad9f4194cc53b0dbab6bd25dfea6c501c \
  --network testnet \
  --ogmios-host localhost \
  --ogmios-port 1442 \
  --ogmios-secure false \
  --kupo-host localhost \
  --kupo-port 1337 \
  --kupo-secure false \
  --payment-signing-key-file payment.skey \
  --stake-signing-key-file stake.skey \
  --amount 5 \
  --recipient aabbcc
```

to:

```
nix run .#sidechain-main-cli -- burn-v1 \
  --amount 5 \
  --recipient aabbcc
```

**We henceforth assume that these common options are located in the
configuration file and omit them from any further examples.  Thus, all provided
options are specific to a particular command being demonstrated.**

You can find a sample configuration file in `config.example.json`.

When using the CLI arguments and the configuration file together, the **CLI
arguments override** values in the configuration file. You can also set any of
the above values to null, if you don't want to set a value for that property.
Any configuration entry where no configuration is defined will fallback to its
default value.

### 3.2. Using the CLI commands

Notes:

- `genesis-committee-hash-utxo` is pinned to the partner chain parameters, so we
  have to add an arbitrary UTxO here.

- If not using a config file, prior to running the contracts it may be desirable
  to have available your signing key in the environment. Example:
  ```bash
  export SIGNING_KEY=/Users/gergo/Dev/cardano/testnets/addresses/server.skey
  ```

  and then pass it on the command line as `--payment-signing-key-file
  $SIGNING_KEY`.

Available commands:
```
  init                     Initialise sidechain
  init-tokens-mint         Mint all sidechain initialisation tokens
  init-reserve-management  Initialise native token reserve management system
  init-checkpoint          Initialise checkpoint
  init-fuel                Initialise the FUEL and committee selection
                           mechanisms
  init-candidate-permission-token
                           Initialise candidate permission token
  addresses                Get the script addresses for a given sidechain
  claim-v1                 Claim a FUEL tokens from a proof
  burn-v1                  Burn a certain amount of FUEL tokens
  claim-v2                 Claim FUEL tokens from thin air
  burn-v2                  Burn a certain amount of FUEL tokens
  register                 Register a committee candidate
  candidate-permission-token
                           Mint candidate permission tokens
  deregister               Deregister a committee member
  committee-hash           Update the committee hash
  save-root                Saving a new merkle root
  committee-handover       An alias for saving the merkle root, followed by
                           updating the committee hash
  save-checkpoint          Saving a new checkpoint
  reserve-create           Create a new token reserve
  reserve-handover         Empty and remove an existing reserve
  reserve-deposit          Deposit assets to existing reserve
  reserve-release-funds    Release currently available funds from an existing
                           reserve
  insert-version-2         Initialize version 2 of a protocol
  update-version           Update an existing protocol version
  invalidate-version       Invalidate a protocol version
  list-versioned-scripts   Get scripts (validators and minting policies) that
                           are currently being versioned
  insert-d-parameter       Insert new D parameter
  update-d-parameter       Update a D parameter
  update-permissioned-candidates
                           Update a Permissioned Candidates list
  collect-garbage          Burn unneccessary NFTs
  init-token-status        List the number of each init token the wallet still
                           holds
  cli-version              Display semantic version of the CLI and its git hash
  utils                    Utility functions for cryptographic primitives and
                           messages.
```

#### 3.2.1.1 Initialising the sidechain in full

The `init` command initializes all components of a sidechain.  It first burns
the genesis UTxO and mints required initialization tokens, and then uses these
initialization tokens to initialize the following functionalities of a
sidechain:

  * claiming and burning the fuel as well as the committee selection mechanism
  * checkpointing
  * candidate permission tokens (optional - see below)
  * native token reserve management system

To initialise the sidechain, we run the following command:
```
nix run .#sidechain-main-cli -- init \
  --committee-pub-key aabbcc \
  --committee-pub-key ccbbaa \
  --sidechain-epoch 0 \
  --version 1
```

To use permissioned registrations, i.e. such registrations that require a
distinguished token, pass the optional `--candidate-permission-token-amount`
parameter followed by an integer to denote how many permission tokens should be
minted:
```
nix run .#sidechain-main-cli -- init \
  --committee-pub-key aabbcc \
  --committee-pub-key ccbbaa \
  --sidechain-epoch 0 \
  --version 1 \
  --candidate-permission-token-amount 42
```

The `init` command is idempotent, i.e. in case of failure it can safely be
re-run to finish an interrupted sidechain initialization.

#### 3.2.1.2 Initialising the sidechain in parts

As an alternative to using the `init` command, the user might want to perform
each initialization step individually.

##### Mint initialization tokens

A mandatory first step is to mint the so called "initialization tokens" (or
"init tokens" for short).  These tokens are required to subsequently initialize
desired components of a partner chain.  The command mints all tokens, regardless
of whether there's an intention to use all of them.

Spends Genesis Utxo

Mints:
* `"Checkpoint InitToken"`
* `"DistributedSet InitToken"`
* `"CandidatePermission InitToken"`
* `"Committee oracle InitToken"`
* `"Version oracle InitToken"` (multiple tokens)

```
nix run .#sidechain-main-cli -- init-tokens-mint --version 1
```

##### Init FUEL and committee selection

Initialise the FUEL and committee selection mechanisms.  Burn `"DistributedSet
InitToken"` and `"Committee oracle InitToken"`.

Insert policies:
* `CommitteeCertificateVerificationMintingPolicy`
* `CommitteeOraclePolicy`
* `DsKeyPolicy`
* `FUELMintingPolicy`
* `FUELBurningPolicy`
* `MerkleRootTokenPolicy`

Insert validators:
* `CommitteeHashValidator`
* `CommitteeCandidateValidator`
* `MerkleRootTokenValidator`

```
nix run .#sidechain-main-cli -- init-fuel
  --committee-pub-key aabbcc \
  --committee-pub-key ccbbaa \
  --sidechain-epoch 0 \
  --version 1
```

##### Init Checkpoint

Initialise the Checkpoint mechanism. Burns `"Checkpoint InitToken"`.

Insert validator: `CheckpointValidator`

```
nix run .#sidechain-main-cli -- init-checkpoint \
  --committee-pub-key aabbcc \
  --committee-pub-key ccbbaa \
  --sidechain-epoch 0 \
  --version 1
  --candidate-permission-token-amount 42
```

##### Initialise Candidate Permission Token

Initialise the Candidate Permission Token mechanism.
Burns `"Candidate permission token init"`.

Insert validator: `CheckpointValidator`

```
nix run .#sidechain-main-cli -- init-candidate-permission-token \
  --version 1
  --candidate-permission-token-amount 42
```

#### 3.2.2. List currently versioned scripts

```
nix run .#sidechain-main-cli -- list-versioned-scripts \
  --version 1
```

Returns the list of currently versioned scripts.

More specifically, it returns all scripts that were inserted in the version
oracle. This includes an initial set of scripts that were added by the `init`
command, and the scripts that were added when inserting a new protocol version
using the `insert-version`.

#### 3.2.3. Get script addresses of a sidechain

Script addresses depend on the sidechain parameters, so we get different
addresses for different parameters. To get the script addresses for a given
sidechain, you can use the following command:

```
nix run .#sidechain-main-cli -- addresses \
  --version 1
```

An optional `--use-candidate-permission-token` flag can be used to also display
policy of the candidate permission tokens.

#### 3.2.4. Claim FUEL tokens

```
nix run .#sidechain-main-cli -- claim-v1 \
  --combined-proof aabb \
  --distributed-set-utxo "a21f14faf41ffdecf311598f2a858f565b5eba0a9c8d6238988485a3ed64cf1f#0"
    # ^ Optional flag to avoid a linear scan through the UTxO set
```

Note: at the moment there also exists `claim-v2` command, which works with
scripts in version 2 - see below for how versions are managed.  `claim-v2`
exists for demonstration purposes only and does not require any proofs, allowing
to claim FUEL out of thin air:
```
nix run .#sidechain-main-cli -- claim-v2 \
  --amount 13
```

#### 3.2.5. Burn user owned FUEL tokens

```
nix run .#sidechain-main-cli -- burn-v1 \
  --amount 5 \
  --recipient aabbcc
```

Note: at the moment there also exists `burn-v2` command, which works with
scripts in version 2 - see below for how versions are managed.  `burn-v2` exists
for demonstration purposes only and uses same arguments as `burn-v1`.
```
nix run .#sidechain-main-cli -- burn-v2 \
  --amount 5 \
  --recipient aabbcc
```

#### 3.2.6. Register committee candidate

In order to generate the signatures, you can use the signature generator tool:
```
cabal run trustless-sidechain-gen-signatures -- register \
  --spo-signing-key c460e6d00d5e4e11240469046a988cecd136f10e12e6115ddc46566e01d199f4 \
  --sidechain-signing-key c460e6d00d5e4e11240469046a988cecd136f10e12e6115ddc46566e01d199f4 \
  --registration-utxo a03ebf281ed96549f74d0e724841fcf928194c44f6ff9a8056d1829598042c62#1
```

And use it's output for the registration:
```
nix run .#sidechain-main-cli -- register \
  --spo-public-key 67663ee94098ceca0dacbf7f947946bfdc4de1848d76da5249b1c3a18a41a57a \
  --sidechain-public-key 02599181389043ba0b83e53d3d665c2dfaa187453a24a4538723766f8f0509c55d \
  --spo-signature cf5fc5b10dff794ac0f5908c38d28a1d8e8430f17c2036cf14f4b28c990b6794f754ca809d69ecd52e4c4d542f90c43b017ff7f23cf46efc4d8f6b07a3895403 \
  --sidechain-signature 9da47b68b68cbca5cbaf7a0bd2a2bfedfe8c58e90ab8a709b8aed4c1644065885823203526b331284d15b238d11a60abb5c0cb3a8f2ef1102fbae736d98146bd \
  --registration-utxo a03ebf281ed96549f74d0e724841fcf928194c44f6ff9a8056d1829598042c62#1
```

Optionally, assuming that we are using a permissioned candidates system, one
can include the candidate permission token when registering as follows.
```
nix run .#sidechain-main-cli -- register \
  --spo-public-key e734ea6c2b6257de72355e472aa05a4c487e6b463c029ed306df2f01b5636b58 \
  --sidechain-public-key 0281158622b7d2eb738b885e1cca50218fb36ab4dc39014b83286b8ed95c78789d \
  --spo-signature de9a8ac3db51bab648a97b56bdbe6757d189633dac91b129156607cf6f3db51217ec1b3c327ab781c6e2de3c4338e3a989449e119daed60a3530aaf268cd3709 \
  --sidechain-signature 5fe405ba531216cf5bfe65f2826d618c5d4a84df7016fcc4f4a6a68323ecb5f56799e08aa8dba6bc087b9131c5b76483ededa250da0ddbf2d24e00991b627e6e \
  --registration-utxo "fff1c0f7f2834cb30a2136c7aadeb37a4680b30e3ae6ea088edc4e1ece939026#3" \
  --use-candidate-permission-token
```

#### 3.2.7. Deregister committee candidate

```
nix run .#sidechain-main-cli -- deregister \
  --spo-public-key aabbcc
```

#### 3.2.8. Committee hash update

```
nix run .#sidechain-main-cli -- committee-hash \
  --committee-pub-key-and-signature aabbcc01:aaaaaa \
  --committee-pub-key-and-signature aabbcc02 \
  --committee-pub-key-and-signature aabbcc03:bbbbbb \
  --committee-pub-key-and-signature aabbcc04:cccccc \
  --new-committee-pub-key ddeeff01 \
  --new-committee-pub-key ddeeff02 \
  --new-committee-pub-key ddeeff03 \
  --new-committee-pub-key ddeeff04 \
  --sidechain-epoch 6 \
  --new-committee-validator-cbor-encoded-address aadd \
  --previous-merkle-root abcdef
```

Note that `--new-committee-validator-cbor-encoded-address` can be found
from the JSON key `cborEncodedAddresses` from the output of the `addresses`
subcommand.

#### 3.2.9. Save merkle root

```
nix run .#sidechain-main-cli -- save-root \
  --merkle-root abababab \
  --committee-pub-key-and-signature aabbcc01:aaaaaa \
  --committee-pub-key-and-signature aabbcc02 \
  --committee-pub-key-and-signature aabbcc03:bbbbbb \
  --committee-pub-key-and-signature aabbcc04:cccccc \
  --previous-merkle-root abcdef
```

#### 3.2.10 Committee handover

```
nix run .#sidechain-main-cli -- committee-handover \
  --merkle-root abababab \
  --sidechain-epoch 6 \
  --previous-merkle-root abcdef \
  --new-committee-pub-key ddeeff01 \
  --new-committee-pub-key ddeeff02 \
  --new-committee-pub-key ddeeff03 \
  --committee-pub-key-and-new-committee-signature aabbcc01:aaaaaa \
  --committee-pub-key-and-new-committee-signature aabbcc02 \
  --committee-pub-key-and-new-committee-signature aabbcc03:bbbbbb \
  --committee-pub-key-and-new-merkle-root-signature aabbcc01:aaaaaa \
  --committee-pub-key-and-new-merkle-root-signature aabbcc02 \
  --committee-pub-key-and-new-merkle-root-signature aabbcc03:bbbbbb
```

#### 3.2.11 Candidiate permission token

```
nix run .#sidechain-main-cli -- candidate-permission-token \
  --candidate-permission-token-amount 10
```

#### 3.2.12 Save checkpoint

```
nix run .#sidechain-main-cli -- save-checkpoint \
  --new-checkpoint-block-hash d8063cc6e907f497360ca50238af5c2e2a95a8869a2ce74ab3e75fe6c9dcabd0d8063cc6e907f497360ca50238af5c2e2a95a8869a2ce74ab3e75fe6c9dcabd0 \
  --new-checkpoint-block-number 42 \
  --sidechain-epoch 5
```

#### 3.2.13 Create a new token reserve

```
nix run .#sidechain-main-cli -- reserve-create \
   --total-accrued-function-script-hash SCRIPT-HASH \
   --reserve-posixtime-t0 POSIXTIME \
   --reserve-asset-script-hash ASSET-SCRIPT-HASH \
   --reserve-asset-name RESERVE_ASSET_NAME \
   --reserve-initial-deposit-amount RESERVE-DEPOSIT-AMOUNT
```

Instead of `--reserve-asset-script-hash` and `--reserve-asset-name` one might
specify `--reserve-ada-asset` flag to indicate that Ada is to be used as the
reserve asset.

Optionally one might also pass `--reserve-initial-incentive-amount
RESERVE-INCENTIVE-AMOUNT` option to set the incentive, i.e. the amount of tokens
awarded for a reserve release.

#### 3.2.14 Empty and remove an existing reserve

```
nix run .#sidechain-main-cli -- reserve-handover
```

Perform the reserve handover.

#### 3.2.15 Deposit assets to existing reserve

```
nix run .#sidechain-main-cli -- reserve-deposit \
  --deposit-reserve-asset ASSET-SCRIPT-HASH \
  --reserve-asset-name RESERVE_ASSET_NAME \
  --reserve-initial-deposit-amount RESERVE-DEPOSIT-AMOUNT
```

Instead of `--deposit-reserve-asset` and `--reserve-asset-name` one might
specify `--reserve-ada-asset` flag to indicate that Ada is being used as the
reserve asset.

#### 3.2.16 Release currently available funds from an existing reserve


```
nix run .#sidechain-main-cli -- reserve-release-funds \
  --total-accrued-till-now INT \
  --reserve-transaction-input RESERVE-TRANSACTION-INPUT
```

#### 3.2.17 Insert new protocol version

This command is only for testing purposes and shouldn't be used.

```
nix run .#sidechain-main-cli --insert-version-2
```

#### 3.2.18 Update existing protocol version

```
nix run .#sidechain-main-cli -- update-version \
  --old-version 1 \
  --new-version 2
```

#### 3.2.19 Invalidate protocol version

```
nix run .#sidechain-main-cli -- invalidate-version \
  --version 1
```

#### 3.2.20 Insert a D parameter value

```
nix run .#sidechain-main-cli -- insert-d-parameter \
  --d-parameter-permissioned-candidates-count N \
  --d-parameter-registered-candidates-count M
```

where N and M are integers.  Note that this should be only done once and then
`update-d-parameter` value should be used (see below).  However, there is no
safeguard against inserting multiple D parameter values.

#### 3.2.21 Update a D parameter value

```
nix run .#sidechain-main-cli -- update-d-parameter \
  --d-parameter-permissioned-candidates-count N \
  --d-parameter-registered-candidates-count M
```

where N and M are integers.  If more than one D parameter value was inserted
this will remove all inserted values first and then replace them with a single
new value.

#### 3.2.22 Insert a list of permissioned candidates

```
nix run .#sidechain-main-cli -- update-permissioned-candidates \
  --add-candidate "SIDECHAIN_KEY_1:AURA_KEY_1:GRANDPA_KEY_1" \
  --add-candidate "SIDECHAIN_KEY_2:AURA_KEY_2:GRANDPA_KEY_2" \
  --add-candidate "SIDECHAIN_KEY_3:AURA_KEY_3:GRANDPA_KEY_3"
```

Insert a new list of permissioned candidates.  Each candidate is listed
separately using the `--permissioned-candidate-keys` flag followed by a string
of 3 keys separated from each other by a single colon.  This command should
only be used once to initialize the list.  All subsequent updates should be done
using the `update-permissioned-candidates` command below, though there is no
safeguard against calling `insert-permissioned-candidates` multiple times.

#### 3.2.23 Update a list of permissioned candidates

```
nix run .#sidechain-main-cli -- update-permissioned-candidates \
  --add-candidate "SIDECHAIN_KEY_1:AURA_KEY_1:GRANDPA_KEY_1" \
  --add-candidate "SIDECHAIN_KEY_2:AURA_KEY_2:GRANDPA_KEY_2" \
  --remove-candidate "SIDECHAIN_KEY_3:AURA_KEY_3:GRANDPA_KEY_3"
```

You can add and remove candidates in a single transaction.  Each candidate is
listed separately using the `--add-candidate` or `--remove-candidate` flag
followed by a string of four keys separated from each other by a single colon.

#### 3.2.24 Remove all permissioned candidates

```
nix run .#sidechain-main-cli -- update-permissioned-candidates \
  --remove-all-candidates
```

Remove all currently registered permissioned candidates. You can also remove all
candidates and add new ones in a single transaction. Just provide
`--add-candidate` as described above.

#### 3.2.25 Garbage collect redundant tokens

```
nix run .#sidechain-main-cli -- collect-garbage
```

Burn all waste tokens found on a user's PubKey address. These tokens include
ATMS Tokens and FUEL Mint and Burn tokens. These tokens don't play any role in
the system after they are minted. Their only purpose is to be minted alongside
some other tokens, as a proof that some kind of check has passed. After that
there is no other way to use them.

#### 3.2.26 Utils

All commands in this section are supposed to be used mostly by developers.

All commands in this section do not communicate with the Cardano network.

Utils commands that start with `key-gen` allow for public / private key pair generation.

Utils commands that start with `sign` are used to sign messages. Messages to be signed
can be arbitrary byte strings.

Utils commands that start with `encode` allow for producing messages in CBOR format.
One needs to provide all necessary fields of a message as CLI arguments and the command
produces CBOR encoded message of a desired type.

##### 3.2.26.1 Generate an ECDSA SECP256k1 public / private key pair

```
nix run .#sidechain-main-cli -- utils key-gen ecdsa-secp256k1
```

Sample output:

```
{ "endpoint": "EcdsaSecp256k1KeyGen",
  "rawHexPublicKey": "037e6950f2f2505990b7bdeea2125b6e1e75335831229e29bc451bec6ef2833ff6",
  "rawHexPrivateKey":"2ed258ab93bacb119492d842a2a450c4bfd6f91f0914f22f3b97664dffb0b9d6"
}
```

##### 3.2.26.2 Generate an Schnorr SECP256k1 public / private key pair

```
nix run .#sidechain-main-cli -- utils key-gen schnorr-secp256k1
```

Sample output:

```
{ "endpoint": "SchnorrSecp256k1KeyGen",
  "rawHexPublicKey": "303e8f4b884b97349c39a5011d7e2cc8dca0a0cf7898a29d0e37524ee5ffb5f0",
  "rawHexPrivateKey":"d2a77accb66f065001dc225fb0b0e570aac266241ab9358e823cb909ad62e07f"
}
```

##### 3.2.26.3 Sign a message with an ECDSA SECP256k1 private key

Available options:
  - `--private-key SIDECHAIN_PRIVATE_KEY` \
    Hex encoded raw bytes of an ECDSA SECP256k1 private key
  - `--message MESSAGE` \
    Hex encoded raw bytes of a message to sign
  - `[-no-hash-message]` \
    Do not hash the message with blake2b256 before signing

```
nix run .#sidechain-main-cli -- utils sign ecdsa-secp256k1 \
  --private-key "d2a77accb66f065001dc225fb0b0e570aac266241ab9358e823cb909ad62e07f" \
  --message "0xab40"
```

Sample output:
```
{ "endpoint": "EcdsaSecp256k1Sign",
  "rawHexPublicKey":"03303e8f4b884b97349c39a5011d7e2cc8dca0a0cf7898a29d0e37524ee5ffb5f0",
  "rawHexSignature":"fc2828280f31e6d8719eea9a826f7ed524d963ce07c42690181397445b856b2428aef1ca4a90d27bbc40d6c36c80cd58f1f3de78fffd770ad57e77c61cd4b3f3",
  "rawHexSignedMessage":"e659246d29f751fad80b79a5d5e30874a016f046ddb7692636ba9a584d393568"
}
```

##### 3.2.26.4 Sign a message with a Schnorr SECP256k1 private key

Arguments and the output format are the same as in 3.2.26.3.
```
nix run .#sidechain-main-cli -- utils sign schnorr-secp256k1 \
  --private-key "d2a77accb66f065001dc225fb0b0e570aac266241ab9358e823cb909ad62e07f" \
  --message "0xab40"
```

##### 3.2.26.5 Produce a CBOR encoded aggregated public key of the sidechain committee

The result corresponds to `UpdateCommitteeHashMessage` type in the code.

Available options:
  - `-i,--sidechain-id` \
    Sidechain ID
  - `-c,--genesis-committee-hash-utxo TX_ID#TX_IDX` \
    Input UTxO to be spent with the first committee hash setup
  - `-g,--governance-authority PUB_KEY_HASH` \
    Public key hash of governance authority
  - `--threshold-numerator INT` \
    The numerator for the ratio of the threshold
  - `--threshold-denominator INT` \
    The denominator for the ratio of the threshold
  - `--sidechain-epoch INT` \
    Sidechain epoch
  - `--previous-merkle-root MERKLE_ROOT` \
    Raw hex encoded previous merkle root if it exists
  - `--cbor-aggregated-public-keys AGGREGATED_SIDECHAIN_PUBLIC_KEYS` \
    A CBOR encoded aggregated public key of the sidechain committee
  - `--new-committee-validator-hash VALIDATOR_HASH` \
    Hex encoded validator hash to send the committee oracle to
  - `--new-committee-validator-bech32-address BECH32_ADDRESS` \
    bech32 of a validator address to send the committee oracle to

```
nix run .#sidechain-main-cli -- utils encode cbor-update-committee-message \
  --sidechain-epoch 5 \
  --cbor-aggregated-public-keys aabb \
  --new-committee-validator-hash ab2d6145e1700cd11dc074cad9f4194cc53b0dbab6bd25dfea6c501c
```

where we note that `--cbor-aggregated-public-keys` can be found
from the JSON key `cborEncodedAddresses` from the output of the `addresses`
subcommand.

##### 3.2.26.6 Produce a CBOR encoded block producer registration message

The result corresponds to `BlockProducerRegistrationMsg` type in the code.

Available options:
  - `-i,--sidechain-id` \
    Sidechain ID
  - `-c,--genesis-committee-hash-utxo TX_ID#TX_IDX` \
    Input UTxO to be spent with the first committee hash setup
  - `-g,--governance-authority PUB_KEY_HASH` \
    Public key hash of governance authority
  - `--threshold-numerator INT` \
    The numerator for the ratio of the threshold
  - `--threshold-denominator INT` \
    The denominator for the ratio of the threshold
  - `--sidechain-public-key SIDECHAIN_PUB_KEY` \
    Sidechain public key
  - `--input-utxo TX_ID#TX_IDX` \
    Input UTxO which must be spent by the transaction

```
nix run .#sidechain-main-cli -- utils encode cbor-block-producer-registration-message \
  --sidechain-public-key 02599181389043ba0b83e53d3d665c2dfaa187453a24a4538723766f8f0509c55d \
  --input-utxo ab24c3a7c4437cc6ca4f893cd1519ae1dbe77862304e14d910ddc1f32de69b60#5
```

##### 3.2.26.7 Produce a CBOR of a Merkle tree entry

The result corresponds to `MerkleTreeEntry` type in the code.

Available options:
  - `--index INDEX` \
    Integer to ensure uniqueness amongst Merkle tree entries
  - `-a,--amount` \
    Amount of FUEL token to be burnt/minted
  - `--recipient BECH32_ADDRESS` \
    Human readable bech32 address of the recipient.
  - `--previous-merkle-root MERKLE_ROOT` \
    Raw hex encoded previous merkle root if it exists

```
nix run .#sidechain-main-cli -- utils encode cbor-merkle-tree-entry \
  --index 5 \
  --amount 100 \
  --previous-merkle-root 0xabababababababaabababababababaababababababababbbabababababababab \
  --recipient aabbcc
```

##### 3.2.26.8 Produce a CBOR of a Merkle tree and the Merkle root hash from the provided Merkle tree entries

The result corresponds to `List MerkleTreeEntry` type in the code.

Available options:
  - `--cbor-merkle-tree-entry CBOR_MERKLE_TREE_ENTRY` \
    Cbor encoded Merkle tree entry

```
nix run .#sidechain-main-cli -- utils encode cbor-merkle-tree \
  --cbor-merkle-tree-entry abababababababaabababababababaababababababababbbabababababababab
```

##### 3.2.26.9 Produce a CBOR of a combined Merkle proof from the provided Merkle tree and Merkle tree entry

The result corresponds to `(MerkleTreeEntry, MerkleTree)` type in the code.

Available options:
  - `--cbor-merkle-tree-entry CBOR_MERKLE_TREE_ENTRY` \
    Cbor encoded Merkle tree entry
  - `--cbor-merkle-tree CBOR_MERKLE_TREE` \
    Cbor encoded Merkle tree

```
nix run .#sidechain-main-cli -- utils encode cbor-combined-merkle-proof \
  --cbor-merkle-tree-entry abababababababaabababababababaababababababababbbabababababababab \
  --cbor-merkle-tree abababababababaabababababababaababababababababbbabababababababab
```

##### 3.2.26.10 Produce a CBOR of a Merkle root insertion message

The result corresponds to `MerkleRootInsertionMessage` type in the code.

Available options:
  - `-i,--sidechain-id` \
    Sidechain ID
  - `-c,--genesis-committee-hash-utxo TX_ID#TX_IDX` \
    Input UTxO to be spent with the first committee hash setup
  - `-g,--governance-authority PUB_KEY_HASH` \
    Public key hash of governance authority
  - `--threshold-numerator INT` \
    The numerator for the ratio of the threshold
  - `--threshold-denominator INT` \
    The denominator for the ratio of the threshold
  - `--merkle-root MERKLE_ROOT` \
    Raw hex encoded Merkle root signed by the committee
  - `--previous-merkle-root MERKLE_ROOT` \
    Raw hex encoded previous merkle root if it exists

```
nix run .#sidechain-main-cli -- utils encode cbor-merkle-root-insertion-message \
  --merkle-root 0xabababababababaabababababababaababababababababbbabababababababab \
  --previous-merkle-root 0xabababababababaabababababababaababababababababbbabababababababab
```

##### 3.2.26.11 Aggregate the raw hex encoded public keys with the plain ATMS scheme which sorts, concatenates, and hashes

Available options:
  - `--public-key PUBLIC_KEY` \
    Hex encoded raw bytes of a sidechain public key

```
nix run .#sidechain-main-cli -- utils encode cbor-plain-aggregate-public-keys \
  --public-key 0xabababababababaabababababababaababababababababbbabababababababab
```
