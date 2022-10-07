{ name = "ctl-test"
, dependencies =
  [ "argonaut-core"
  , "arrays"
  , "bifunctors"
  , "bigints"
  , "cardano-transaction-lib"
  , "codec-argonaut"
  , "console"
  , "control"
  , "exceptions"
  , "foldable-traversable"
  , "foreign-object"
  , "lists"
  , "maybe"
  , "monad-logger"
  , "node-buffer"
  , "node-fs"
  , "node-fs-aff"
  , "node-path"
  , "node-process"
  , "optparse"
  , "ordered-collections"
  , "parallel"
  , "partial"
  , "prelude"
  , "profunctor-lenses"
  , "strings"
  , "transformers"
  , "uint"
  , "unfoldable"
  , "untagged-union"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
}
