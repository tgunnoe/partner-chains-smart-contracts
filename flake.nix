{
  description = "trustless-sidechain";

  nixConfig = {
    extra-substituters = [
      "https://cache.iog.io"
      "https://public-plutonomicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "public-plutonomicon.cachix.org-1:3AKJMhCLn32gri1drGuaZmFrmnue+KkKrhhubQk/CWc="
    ];
  };

  inputs = {
    cardano-transaction-lib.url = "github:Plutonomicon/cardano-transaction-lib/b7e8d396711f95e7a7b755a2a7e7089df712aaf5";

    plutip.follows = "cardano-transaction-lib/plutip";
    haskell-nix.url = "github:input-output-hk/haskell.nix/9af167fb4343539ca99465057262f289b44f55da";
    nixpkgs.follows = "cardano-transaction-lib/nixpkgs";
    iohk-nix.follows = "cardano-transaction-lib/plutip/iohk-nix";
    CHaP.follows = "cardano-transaction-lib/plutip/CHaP";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    n2c = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "haskell-nix/flake-utils";
    };
  };

  outputs = {
    self,
    nixpkgs,
    haskell-nix,
    CHaP,
    cardano-transaction-lib,
    plutip,
    ...
  } @ inputs: let
    previewRuntimeConfig = {
      # Conveniently, by default the ctl runtime configuration uses the
      # preview network. See here:
      # https://github.com/Plutonomicon/cardano-transaction-lib/blob/87233da45b7c433c243c539cb4d05258e551e9a1/nix/runtime.nix
      network = {
        name = "preview";
        magic = 2;
      };

      # Need use a more recent node version -- iirc. there was a hard fork
      # somewhat recently?
      node = {
        # the version of the node to use, corresponds to the image version tag,
        # i.e. `"inputoutput/cardano-node:${tag}"`
        tag = "1.35.4";
      };
    };

    preprodRuntimeConfig = {
      network = {
        name = "preprod";
        magic = 1;
      };

      node = {
        tag = "1.35.4";
      };
    };

    supportedSystems = ["x86_64-linux" "x86_64-darwin"];

    perSystem = nixpkgs.lib.genAttrs supportedSystems;

    nixpkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [
          (import "${inputs.iohk-nix}/overlays/crypto")
          haskell-nix.overlay
          cardano-transaction-lib.overlays.runtime
          cardano-transaction-lib.overlays.purescript
          cardano-transaction-lib.overlays.spago
        ];
        inherit (haskell-nix) config;
      };

    hsProjectFor = system: let
      pkgs = nixpkgsFor system;
    in
      pkgs.haskell-nix.cabalProject {
        src = ./onchain;
        inputMap = {
          "https://input-output-hk.github.io/cardano-haskell-packages" = CHaP;
        };
        compiler-nix-name = "ghc8107";
        modules = plutip.haskellModules;
        shell = {
          exactDeps = true;
          nativeBuildInputs = with pkgs; [
            # Shell utils
            bashInteractive
            git
            cabal-install

            # Lint / Format
            fd
            hlint
            haskellPackages.apply-refact
            haskellPackages.cabal-fmt
            haskellPackages.fourmolu
            #nixpkgs-fmt
            alejandra
            graphviz
          ];
          shellHook = ''
            [ -z "$(git config core.hooksPath)" -a -d hooks ] && {
                 git config core.hooksPath hooks
            }
          '';
          tools.haskell-language-server = {};
        };
      };

    psProjectFor = system: let
      projectName = "trustless-sidechain-ctl";
      pkgs = nixpkgsFor system;
      src = builtins.path {
        path = ./offchain;
        name = "${projectName}-src";
        # TODO: Add more filters
        filter = path: ftype: !(pkgs.lib.hasSuffix ".md" path);
      };
    in
      pkgs.purescriptProject {
        inherit src pkgs projectName;
        packageJson = ./offchain/package.json;
        packageLock = ./offchain/package-lock.json;
        spagoPackages = ./offchain/spago-packages.nix;
        withRuntime = true;
        shell.packages = with pkgs; [
          # Shell Utils
          bashInteractive
          git
          jq

          # Lint / Format
          fd
          dhall

          # CTL Runtime
          docker
        ];
      };

    formatCheckFor = system: let
      pkgs = nixpkgsFor system;
    in
      pkgs.runCommand "format-check"
      {
        nativeBuildInputs =
          self.devShells.${system}.hs.nativeBuildInputs
          ++ self.devShells.${system}.ps.nativeBuildInputs
          ++ self.devShells.${system}.ps.buildInputs;
      } ''

        pushd ${self}
        export LC_CTYPE=C.UTF-8
        export LC_ALL=C.UTF-8
        export LANG=C.UTF-8
        export IN_NIX_SHELL='pure'

        make nixpkgsfmt_check
        popd

        pushd ${self}/onchain/
        make format_check cabalfmt_check lint
        popd

        pushd ${self}/offchain
        make check-format
        popd

        mkdir $out
      '';

    upToDatePlutusScriptCheckFor = system: let
      pkgs = nixpkgsFor system;
      hsProject = (hsProjectFor system).flake {};
    in
      pkgs.runCommand "up-to-date-plutus-scripts-check"
      {
        nativeBuildInputs =
          self.devShells.${system}.hs.nativeBuildInputs
          ++ self.devShells.${system}.ps.nativeBuildInputs
          ++ self.devShells.${system}.ps.buildInputs;
      } ''
        export LC_CTYPE=C.UTF-8
        export LC_ALL=C.UTF-8
        export LANG=C.UTF-8
        export IN_NIX_SHELL='pure'

        # Acquire temporary files..
        TMP=$(mktemp)

        # Setup temporary files cleanup
        function cleanup() {
          rm -rf $TMP
        }
        trap cleanup EXIT

        pushd ${self}/onchain > /dev/null
        ${hsProject.packages."trustless-sidechain:exe:trustless-sidechain-serialise"}/bin/trustless-sidechain-serialise \
          --purescript-plutus-scripts="$TMP"
        popd > /dev/null

        pushd ${self}/offchain > /dev/null

        # Compare the generated file and the file provided in the repo.
        cmp $TMP src/TrustlessSidechain/RawScripts.purs || {
          exitCode=$? ;
          echo "Plutus scripts out of date." ;
          echo 'See `offchain/src/TrustlessSidechain/RawScripts.purs` for instructions to resolve this' ;
          exit $exitCode ;
        }

        popd > /dev/null

        touch $out
      '';

    # CTL's `runPursTest` won't pass command-line arugments to the `node`
    # invocation, so we can essentially recreate `runPursTest` here with and
    # pass the arguments
    ctlMainFor = system: let
      pkgs = nixpkgsFor system;
      project = psProjectFor system;
    in
      pkgs.writeShellApplication {
        name = "sidechain-main-cli";
        runtimeInputs = [project.nodejs];
        # Node's `process.argv` always contains the executable name as the
        # first argument, hence passing `sidechain-main-cli "$@"` rather than just
        # `"$@"`
        text = ''
          export NODE_PATH="${project.nodeModules}/lib/node_modules"
          node --enable-source-maps -e 'require("${project.compiled}/output/Main").main()' sidechain-main-cli "$@"
        '';
      };

    ctlBundleCliFor = system: let
      name = "trustless-sidechain-cli";
      version = "4.0.0";
      src = ./offchain;
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          cardano-transaction-lib.overlays.purescript
        ];
      };
      project = pkgs.purescriptProject {
        inherit src pkgs;
        projectName = name;
        withRuntime = false;
      };
    in
      pkgs.stdenv.mkDerivation rec {
        inherit name src version;
        buildInputs = [
          project.purs # this (commonjs ffi) instead of pkgs.purescript (esmodules ffi)
        ];
        runtimeInputs = [project.nodejs];
        unpackPhase = ''
          ln -s ${project.compiled}/* .
          ln -s ${project.nodeModules}/lib/node_modules node_modules
        '';
        buildPhase = ''
          purs bundle "output/*/*.js" -m Main --main Main -o main.js
        '';
        installPhase = ''
          mkdir -p $out
          tar chf $out/${name}-${version}.tar main.js node_modules
        '';
      };
    ociImageFor = system: let
      pkgs = nixpkgsFor system;
      ctlMain = ctlMainFor system;
      n2c = inputs.n2c.packages.${system}.nix2container;
    in
      n2c.buildImage {
        name = "sidechain-main-cli-docker";
        tag = "${self.shortRev or self.dirtyShortRev}";
        config = {
          Cmd = ["sidechain-main-cli"];
        };
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [pkgs.bashInteractive pkgs.coreutils ctlMain];
          pathsToLink = ["/bin"];
        };
      };
  in {
    project = perSystem hsProjectFor;

    flake = perSystem (system: (hsProjectFor system).flake {});

    packages =
      perSystem
      (system:
        self.flake.${system}.packages
        // {
          sidechain-main-cli = ctlMainFor system;
          # TODO: Fix web bundling
          # ctl-bundle-web = (psProjectFor system).bundlePursProject {
          #   main = "Main";
          #   entrypoint = "index.js"; # must be same as listed in webpack config
          #   webpackConfig = "webpack.config.js";
          #   bundledModuleName = "output.js";
          # };
          ctl-bundle-cli = ctlBundleCliFor system;
          sidechain-main-cli-image = ociImageFor system;
        });

    apps = perSystem (system:
      self.flake.${system}.apps
      // {
        ctl-runtime-preview = (nixpkgsFor system).launchCtlRuntime previewRuntimeConfig;
        ctl-runtime-preprod = (nixpkgsFor system).launchCtlRuntime preprodRuntimeConfig;
        sidechain-main-cli = {
          type = "app";
          program = "${ctlMainFor system}/bin/sidechain-main-cli";
        };
      });

    # This is used for nix build .#check.<system> because nix flake check
    # does not work with haskell.nix import-from-derivtion.
    check = perSystem (system:
      (nixpkgsFor system).runCommand "combined-check"
      {
        nativeBuildInputs =
          builtins.attrValues self.checks.${system}
          ++ builtins.attrValues self.flake.${system}.packages
          ++ self.devShells.${system}.hs.nativeBuildInputs
          ++ self.devShells.${system}.ps.nativeBuildInputs
          ++ self.devShells.${system}.ps.buildInputs;
      } "touch $out");

    checks = perSystem (system:
      self.flake.${system}.checks
      // {
        formatCheck = formatCheckFor system;
        upToDatePlutusScriptCheck = upToDatePlutusScriptCheckFor system;
        trustless-sidechain-ctl = (psProjectFor system).runPlutipTest {
          testMain = "Test.Main";
        };
      });

    devShells = perSystem (system: rec {
      ps = (psProjectFor system).devShell;
      hs = self.flake.${system}.devShell;
      default = (nixpkgsFor system).mkShell {
        inputsFrom = [ps hs];
        shellHook = ''
          ${hs.shellHook}
          ${ps.shellHook}
        '';
      };
    });
    _packages.x86_64-linux = builtins.removeAttrs self.packages.x86_64-linux ["ctl-runtime-preview" "ctl-runtime-preprod"];
  };
}
