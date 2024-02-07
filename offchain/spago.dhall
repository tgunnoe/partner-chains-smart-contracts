{ name = "sidechain-main-cli"
, dependencies =
  [ "aeson"
  , "argonaut"
  , "argonaut-core"
  , "arrays"
  , "bifunctors"
  , "bigints"
  , "cardano-transaction-lib"
  , "codec-argonaut"
  , "const"
  , "control"
  , "datetime"
  , "effect"
  , "either"
  , "exceptions"
  , "foldable-traversable"
  , "foreign-object"
  , "lists"
  , "maybe"
  , "monad-logger"
  , "mote"
  , "node-buffer"
  , "node-fs"
  , "node-fs-aff"
  , "node-path"
  , "node-process"
  , "nonempty"
  , "optparse"
  , "ordered-collections"
  , "parallel"
  , "partial"
  , "prelude"
  , "profunctor"
  , "quickcheck"
  , "random"
  , "strings"
  , "tailrec"
  , "test-unit"
  , "transformers"
  , "tuples"
  , "uint"
  , "unfoldable"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
}
