.PHONY: build-nix hoogle nix-build-library nix-build-executables \
        nix-build-test requires_nix_shell ci-build-run format-staged \
		unreachable-commit-staged format-whitespace-staged format-nix-staged \
		format-hs-staged format-cabal-staged format-purs-staged format-js-staged \
		format-dhall-staged check-format-hs-staged check-format-cabal-staged \
		check-format-purs-staged check-format-js-staged check-format-dhall-staged \
		check-format-nix-staged check-format-whitespace

# Generate TOC for README.md
# It has to be manually inserted into the README.md for now.
generate-readme-contents:
	nix shell nixpkgs#nodePackages.npm --command "npx markdown-toc ./README.md --no-firsth1"

# Attempt the CI locally
# TODO

# Build the library with nix.
nix-build-library:
	@ nix build .#trustless-sidechain:lib:trustless-sidechain

current-system := $(shell nix eval --impure --expr builtins.currentSystem)

# Build the executables with nix (also builds the test suite).
nix-build-executables:
	@ nix build -L .#check.${current-system}

# Build the tests with nix.
nix-build-test:
	@ nix build -L .#trustless-sidechain:test:trustless-sidechain-test

# Target to use as dependency to fail if not inside nix-shell.
requires_nix_shell:
	@ [ "$(IN_NIX_SHELL)" ] || { \
	echo "The $(MAKECMDGOALS) target must be run from inside a nix shell"; \
	echo "    run 'nix develop' first"; \
	false; \
	}

NIX_SOURCES := $(shell fd -enix)

# `format-staged` is a .PHONY rule which formats only git's staged files
# relative to the current HEAD. Precisely, this uses targets of the form
# `format-*-staged` to format the various file types.
#
# Moreover, before running the formatters, this runs the target
# `unreachable-commit-staged` to save a snapshot of the staged files before
# running the formatters in case the formatters corrupt your work.
format-staged: unreachable-commit-staged requires_nix_shell
	@echo 'Formatting `*.hs`...'
	@$(MAKE) --no-print-directory format-hs-staged
	@echo 'Formatting `*.cabal`...'
	@$(MAKE) --no-print-directory format-cabal-staged
	@echo 'Formatting whitespace...'
	@$(MAKE) --no-print-directory format-whitespace-staged
	@echo 'Formatting `*.purs`...'
	@$(MAKE) --no-print-directory format-purs-staged
	@echo 'Formatting `*.js`...'
	@$(MAKE) --no-print-directory format-js-staged
	@echo 'Formatting `*.dhall`...'
	@$(MAKE) --no-print-directory format-dhall-staged
	@echo 'Formatting `*.nix` files...'
	@$(MAKE) --no-print-directory format-nix-staged

# `unreachable-commit-staged` constructs an unreachable git commit object of the
# current staged files.
#
# This internal commit object can be viewed with
# ```
# git log $(git cat-file --batch-check --batch-all | awk '$2 == "commit" {print $1}')
# ```
# which reads all commit objects (including the unreachable commit we just
# made) to `git log` where (by default) the most recent commit is shown first.
#
# If we'd like to reset to the aforementioned snapshot, one could execute
# ```
# git reset --hard <snapshot hash>
# ```
# and fix the commit message accordingly.
#
# Note: these commit objects will be gc'd as the are unreachable -- see `git
# gc`
unreachable-commit-staged:
	@echo 'Creating a git commit object to snapshot the current staged files...'
	@git stash create --staged -m "WIP: autogenerated 'unreachable-commit-staged' commit"

format-whitespace-staged:
	@git diff -z --name-only --diff-filter=d --cached HEAD ':!*.golden' \
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| while IFS= read -r -d '' file; do\
			TMP=$$(mktemp);\
			git stripspace <$$file >$$TMP;\
			cat $$TMP > $$file;\
			rm $$TMP;\
		done

format-nix-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.nix$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r alejandra

check-format-nix-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.nix$$'\
		| xargs -0 -r alejandra --check

FOURMOLU_EXTENSIONS := \
	-o -XBangPatterns \
	-o -XTypeApplications \
	-o -XTemplateHaskell \
	-o -XImportQualifiedPost \
	-o -XPatternSynonyms \
	-o -fplugin=RecordDotPreprocessor

format-hs-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.hs$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r fourmolu $(FOURMOLU_EXTENSIONS) --mode inplace --check-idempotence

check-format-hs-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.hs$$'\
		| xargs -0 -r fourmolu $(FOURMOLU_EXTENSIONS) --mode check --check-idempotence

format-cabal-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.cabal$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r cabal-fmt --inplace

check-format-cabal-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.cabal$$'\
		| xargs -0 -r cabal-fmt --check

format-purs-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.purs$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r purs-tidy format-in-place

check-format-purs-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.purs$$'\
		| xargs -0 -r purs-tidy check

format-js-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.js$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r eslint --fix

check-format-js-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.js$$'\
		| xargs -0 -r eslint

format-dhall-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.dhall$$'\
		| while IFS= read -r -d '' FILE; do test -f $$FILE && printf "$$FILE\0"; done\
		| xargs -0 -r dhall lint

check-format-dhall-staged: requires_nix_shell
	@git diff -z --name-only --diff-filter=d --cached HEAD\
		| grep -Ez '^.*\.dhall$$'\
		| xargs -0 -r dhall lint --check

nixpkgsfmt: requires_nix_shell
	alejandra $(NIX_SOURCES)

nixpkgsfmt_check: requires_nix_shell
	alejandra --check $(NIX_SOURCES)

lock: requires_nix_shell
	nix flake lock

lock_check: requires_nix_shell
	@nix flake lock --no-update-lock-file

check-format-whitespace: requires_nix_shell
	@git diff --check --cached HEAD --
