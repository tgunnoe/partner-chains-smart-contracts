let upstream =
      https://github.com/purescript/package-sets/releases/download/psc-0.14.5-20211116/packages.dhall
        sha256:7ba810597a275e43c83411d2ab0d4b3c54d0b551436f4b1632e9ff3eb62e327a

let additions =
      { aeson =
        { dependencies =
          [ "aff"
          , "argonaut"
          , "argonaut-codecs"
          , "argonaut-core"
          , "arrays"
          , "bifunctors"
          , "bigints"
          , "const"
          , "control"
          , "effect"
          , "either"
          , "exceptions"
          , "foldable-traversable"
          , "foreign-object"
          , "gen"
          , "identity"
          , "maybe"
          , "newtype"
          , "node-buffer"
          , "node-fs-aff"
          , "node-path"
          , "nonempty"
          , "numbers"
          , "partial"
          , "prelude"
          , "quickcheck"
          , "record"
          , "sequences"
          , "spec"
          , "strings"
          , "stringutils"
          , "transformers"
          , "tuples"
          , "typelevel"
          , "typelevel-prelude"
          , "uint"
          , "untagged-union"
          ]
        , repo = "https://github.com/mlabs-haskell/purescript-aeson.git"
        , version = "286862a975f4bafbef15540c365bbbb0480e0bf7"
        }
      , aeson-helpers =
        { dependencies =
          [ "aff"
          , "argonaut-codecs"
          , "argonaut-core"
          , "arrays"
          , "bifunctors"
          , "contravariant"
          , "control"
          , "effect"
          , "either"
          , "enums"
          , "foldable-traversable"
          , "foreign-object"
          , "maybe"
          , "newtype"
          , "ordered-collections"
          , "prelude"
          , "profunctor"
          , "psci-support"
          , "quickcheck"
          , "record"
          , "spec"
          , "spec-quickcheck"
          , "transformers"
          , "tuples"
          , "typelevel-prelude"
          ]
        , repo =
            "https://github.com/mlabs-haskell/purescript-bridge-aeson-helpers.git"
        , version = "44d0dae060cf78babd4534320192b58c16a6f45b"
        }
      , sequences =
        { dependencies =
          [ "arrays"
          , "assert"
          , "console"
          , "effect"
          , "lazy"
          , "maybe"
          , "newtype"
          , "nonempty"
          , "partial"
          , "prelude"
          , "profunctor"
          , "psci-support"
          , "quickcheck"
          , "quickcheck-laws"
          , "tuples"
          , "unfoldable"
          , "unsafe-coerce"
          ]
        , repo = "https://github.com/hdgarrood/purescript-sequences"
        , version = "v3.0.2"
        }
      , properties =
        { dependencies = [ "prelude", "console" ]
        , repo = "https://github.com/Risto-Stevcev/purescript-properties.git"
        , version = "v0.2.0"
        }
      , lattice =
        { dependencies = [ "prelude", "console", "properties" ]
        , repo = "https://github.com/Risto-Stevcev/purescript-lattice.git"
        , version = "v0.3.0"
        }
      , mote =
        { dependencies = [ "these", "transformers", "arrays" ]
        , repo = "https://github.com/garyb/purescript-mote"
        , version = "v1.1.0"
        }
      , medea =
        { dependencies =
          [ "aff"
          , "argonaut"
          , "arrays"
          , "bifunctors"
          , "control"
          , "effect"
          , "either"
          , "enums"
          , "exceptions"
          , "foldable-traversable"
          , "foreign-object"
          , "free"
          , "integers"
          , "lists"
          , "maybe"
          , "mote"
          , "naturals"
          , "newtype"
          , "node-buffer"
          , "node-fs-aff"
          , "node-path"
          , "nonempty"
          , "ordered-collections"
          , "parsing"
          , "partial"
          , "prelude"
          , "psci-support"
          , "quickcheck"
          , "quickcheck-combinators"
          , "safely"
          , "spec"
          , "strings"
          , "these"
          , "transformers"
          , "typelevel"
          , "tuples"
          , "unicode"
          , "unordered-collections"
          , "unsafe-coerce"
          ]
        , repo = "https://github.com/juspay/medea-ps.git"
        , version = "8b215851959aa8bbf33e6708df6bd683c89d1a5a"
        }
      , purescript-toppokki =
        { dependencies =
          [ "prelude"
          , "record"
          , "functions"
          , "node-http"
          , "aff-promise"
          , "node-buffer"
          , "node-fs-aff"
          ]
        , repo = "https://github.com/firefrorefiddle/purescript-toppokki"
        , version = "6983e07bf0aa55ab779bcef12df3df339a2b5bd9"
        }
      , cardano-transaction-lib =
        { dependencies =
          [ "aeson"
          , "aeson-helpers"
          , "aff"
          , "aff-promise"
          , "aff-retry"
          , "affjax"
          , "arraybuffer-types"
          , "arrays"
          , "bifunctors"
          , "bigints"
          , "checked-exceptions"
          , "console"
          , "const"
          , "contravariant"
          , "control"
          , "datetime"
          , "debug"
          , "effect"
          , "either"
          , "encoding"
          , "enums"
          , "exceptions"
          , "foldable-traversable"
          , "foreign"
          , "foreign-object"
          , "heterogeneous"
          , "http-methods"
          , "identity"
          , "integers"
          , "js-date"
          , "lattice"
          , "lists"
          , "math"
          , "maybe"
          , "medea"
          , "media-types"
          , "monad-logger"
          , "mote"
          , "newtype"
          , "node-buffer"
          , "node-child-process"
          , "node-fs"
          , "node-fs-aff"
          , "node-path"
          , "node-process"
          , "node-streams"
          , "nonempty"
          , "now"
          , "numbers"
          , "optparse"
          , "ordered-collections"
          , "orders"
          , "parallel"
          , "partial"
          , "posix-types"
          , "prelude"
          , "profunctor"
          , "profunctor-lenses"
          , "purescript-toppokki"
          , "quickcheck"
          , "quickcheck-combinators"
          , "quickcheck-laws"
          , "rationals"
          , "record"
          , "refs"
          , "safe-coerce"
          , "spec"
          , "spec-quickcheck"
          , "strings"
          , "tailrec"
          , "text-encoding"
          , "these"
          , "transformers"
          , "tuples"
          , "typelevel"
          , "typelevel-prelude"
          , "uint"
          , "undefined"
          , "unfoldable"
          , "untagged-union"
          , "variant"
          ]
        , repo = "https://github.com/Plutonomicon/cardano-transaction-lib.git"
        , version = "a690f60497494ba5d8460261f959deba4f778eda"
        }
      }

in  upstream // additions
