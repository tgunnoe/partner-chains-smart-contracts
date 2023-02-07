{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- | "Bench.BenchResults" is the module which includes a database connection (along
 with associated queries) for gathering benchmark results.
-}
module Bench.BenchResults (
  -- * Database connection
  BenchResults (..),
  openBenchResults,
  closeBenchResults,
  freshBenchResults,
  withFreshBenchResults,

  -- * Data types for results of queries
  Description,
  IndependentVarIx,
  Ms,
  LovelaceFee,
  TrialIx,
  Trial (..),

  -- * High level interface to quering the database
  addTrial,
  withSelectAllDescriptions,
  selectAllDescriptions,
  selectFreshTrialIx,

  -- * Internal SQL queries + debugging utilities
  createTrialsTablesQuery,
  selectFreshTrialIxQuery,
  addTrialQuery,
  selectAllDescriptionsQuery,
  printQuery,
  --  * Errors
  BenchResultsError (..),
) where

import Bench.Logger qualified as Logger
import Control.Exception (Exception)
import Control.Exception qualified as Exception
import Control.Monad qualified as Monad
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Coerce qualified as Coerce
import Data.Int (Int64)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Database.SQLite3 (Database, ParamIndex, Statement, StepResult (..))
import Database.SQLite3 qualified as SQLite3
import Database.SQLite3.Direct (Utf8 (..))
import Database.SQLite3.Direct qualified as SQLite3.Direct
import System.IO qualified as IO

-- * High level API

{- | 'BenchResults' is the configuration used for storing the required data from
 the results of benchmarking. It includes:

      - 'brDatabase': a database holding all the benchmark data -- see
      'createTrialsTablesQuery'.
-}
newtype BenchResults = BenchResults
  { -- | the database connection holding all the data.
    brDatabase :: Database
  }

{- | @'openBenchResults' filePath@ initialises a 'BenchResults'. Namely, it:

      - creates an Sqlite3 database connection to the given @filePath@
      according to the schema in 'createTrialsTablesQuery'
-}
openBenchResults :: Text -> IO BenchResults
openBenchResults filePath =
  SQLite3.open filePath
    >>= \db -> do
      SQLite3.exec db createTrialsTablesQuery
      pure $ BenchResults db

{- | 'withFreshBenchResults' is a bracket style resource handler for
 'freshBenchResults'
-}
withFreshBenchResults :: FilePath -> Text -> (BenchResults -> IO a) -> IO a
withFreshBenchResults dir fileNameHint =
  Exception.bracket
    (freshBenchResults dir fileNameHint)
    closeBenchResults

{- | @'freshBenchResults' dir fileNameHint@ is 'openBenchResults' but initialises the database
 with a fresh name in the given directory @dir@ with the given filename hint @hint@
-}
freshBenchResults :: FilePath -> Text -> IO BenchResults
freshBenchResults dir fileNameHint = do
  (path, handle) <- IO.openTempFile dir $ Text.unpack fileNameHint
  Logger.logInfo $ "Creating benchmark results database at: " ++ path

  -- just close the handle immediatly, since we're just using this for the
  -- fresh name
  IO.hClose handle

  openBenchResults $ Text.pack path

{- | 'closeBenchResults' does the necessary cleanup when closing the database
 connection.
-}
closeBenchResults :: BenchResults -> IO ()
closeBenchResults benchResult = SQLite3.close $ brDatabase benchResult

-- | See 'Trial' for details
type Description = Text

-- | See 'Trial' for details
type IndependentVarIx = Int64

-- | See 'Trial' for details
type Ms = Int64

-- | See 'Trial' for details
type LovelaceFee = Int64

-- | See 'Trial' for details
type TrialIx = Int64

-- | 'Trial' is all the data relating to a single benchmark.
data Trial =
  -- note: internally SQLite doesn't have it's own unsigned int type.. TODO:
  -- we can add our own in and package it up ourselves. But, 'Int64' should
  -- be large enough for our needs.
  --
  -- In particular, 'Int64' is contains enough to measure many many years (in
  -- milliseconds); and
  -- <https://docs.cardano.org/cardano-testnet/tools/plutus-fee-estimator>
  -- claims that transaction prices can be at most <= 3 ada i.e., 3 million
  -- lovelace which surely fits in 'Int64'.
  --
  -- Honestly, both fit in an 'Int32'; but let's just be safe.
  Trial
  { -- | 'tDescription' is a brief description of what the benchmark
    -- was e.g. "FUELMintingPolicy".
    tDescription :: !Description
  , -- | 'tIndependentVarIx' is an integer denoting the @i@th time we've run a
    -- benchmark. E.g., we can run "FUELMintingPolicy" in sequence twice, so we'd have
    -- @tIndependentVarIx = 1@ for the first execution, and @tIndependentVarIx = 2@ for
    -- the second execution.
    tIndependentVarIx :: !IndependentVarIx
  , -- | 'tTrialIx' is an index to uniquely identify this trial
    -- from other "same" benchmarks i.e., to uniquely identify same benchmarks
    -- up to @tDescription@ an @tIndependentVarIx@.
    tTrialIx :: !TrialIx
  , -- | 'tMs' is an 'Int64' denoting the milliseconds to run the
    -- benchmark
    tMs :: !Ms
  , -- | 'tLovelaceFee' is the lovelace fee of the transaction
    tLovelaceFee :: !LovelaceFee
  }

-- | Adds a benchmark trial to the system.
addTrial :: Trial -> BenchResults -> IO ()
addTrial params benchResult =
  withPreparedStatement addTrialQuery (brDatabase benchResult) $ \preparedStmt -> do
    let -- quick convenience function since we're working with the same prepared statement
        getParamIndex = bindParameterIndex preparedStmt
    Monad.void $ do
      ix <- getParamIndex ":description"
      SQLite3.bindText preparedStmt ix $ tDescription params

    Monad.void $ do
      ix <- getParamIndex ":independentVarIx"
      SQLite3.bindInt64 preparedStmt ix $ tIndependentVarIx params

    Monad.void $ do
      ix <- getParamIndex ":trialIx"
      SQLite3.bindInt64 preparedStmt ix $ tTrialIx params

    Monad.void $ do
      ix <- getParamIndex ":ms"
      SQLite3.bindInt64 preparedStmt ix $ tMs params

    Monad.void $ do
      ix <- getParamIndex ":lovelaceFee"
      SQLite3.bindInt64 preparedStmt ix $ tLovelaceFee params

    -- this is an update query, so it will run to completion in a single call.
    _stepResult <- SQLite3.step preparedStmt

    return ()

{- | @'withSelectAllDescriptions' desc database $ \step -> ...@ is a bracket style
 resource handler to select all rows in the table @trials@
 corresponding to the given description where @step@ will give the next
 trial (if it exists).

 Note: we drop the @trialIx@ since from the results (these should be
 iid).

 Warning:
  - The usual caveats of bracket style resource handlers apply i.e., one
  should call the @step@ function outside of its closure.
-}
withSelectAllDescriptions :: Description -> BenchResults -> (IO (Maybe Trial) -> IO a) -> IO a
withSelectAllDescriptions description benchResult f =
  withPreparedStatement selectAllDescriptionsQuery (brDatabase benchResult) $ \preparedStmt -> do
    let -- quick convenience function since we're working with the same preparted statement
        getParamIndex = bindParameterIndex preparedStmt

    Monad.void $ do
      ix <- getParamIndex ":description"
      SQLite3.bindText preparedStmt ix description

    f $
      SQLite3.step preparedStmt >>= \case
        Done -> pure Nothing
        Row -> do
          independentVarIx <- SQLite3.columnInt64 preparedStmt 0
          trialIx <- SQLite3.columnInt64 preparedStmt 1
          ms <- SQLite3.columnInt64 preparedStmt 2
          lovelaceFee <- SQLite3.columnInt64 preparedStmt 3
          return $
            Just
              Trial
                { tDescription = description
                , tIndependentVarIx = fromIntegral independentVarIx
                , tTrialIx = trialIx
                , tMs = ms
                , tLovelaceFee = lovelaceFee
                }

{- | 'selectAllDescriptions' loads all results in memory from
 'withSelectAllDescriptions'.

 Warning: this most likely will have awful performance.
-}
selectAllDescriptions :: Description -> BenchResults -> IO [Trial]
selectAllDescriptions description benchResults =
  withSelectAllDescriptions description benchResults $ \step ->
    let go = \case
          Nothing -> return []
          Just o -> (o :) <$> (step >>= go)
     in step >>= go

{- | 'selectFreshTrialIx' returns a fresh 'TrialIx' used to running
 another trial of a sequence of independentVars.
-}
selectFreshTrialIx :: BenchResults -> IO TrialIx
selectFreshTrialIx benchResult =
  withPreparedStatement selectFreshTrialIxQuery (brDatabase benchResult) $
    \preparedStmt -> do
      -- aggegate functions reutrn a single value, so we just step the
      -- prepared statement once.
      _ <- SQLite3.step preparedStmt
      SQLite3.columnInt64 preparedStmt 0 -- returns the fresh trial ix

-- * Internal SQL queries

{- $internalSQLQueries
 Warning: when changing these queries, ensure that the high level API is
 changed accordingly
-}

{- | 'createTrialsTablesQuery' is a database query to create a table for which the
 rows store the results of a single benchmark and its associated information.
 We call a single row in the table a *trial*, and a the subset of columns
 which contains only the @description@, @ms@, and @lovelaceFee@ is called a *independentVar*.

 The table we generate is as follows.
 @
  description : Text  | independentVarIx : Integer  | trialIx : Integer  | ms : Integer | lovelaceFee : Integer
  -------------------------------------------------------------------------------------------------------------------
 @
 where

  - @trialIx@, @description@, and @independentVarIx@ are primary keys

  - @trialIx@ is the @k@th execution of the entire benchmark suite
  (since we run the benchmarks multiple times), where we note that
  @ms@ is iid w.r.t @trialIx@.

  - @description@ is a brief description of given benchmark

  - @independentVarIx@ is the @i@th time we run the given @description@ in
  a single suite.

  - @ms@ is the number of milliseconds that benchmark took.

  - @lovelaceFee@ is the lovelaceFee that benchmark took.

 To more clearly see the relationship between these variables, we could have,
 for example:
 @
  "FUELMintingPolicy"     | 1  | 1 | 10 | 10000
  "FUELMintingPolicy"     | 2  | 1 | 10 | 10000
  "FUELMintingPolicy"     | 3  | 1 | 10 | 10000
  "FUELMintingPolicy"     | 4  | 1 | 10 | 10000
  "FUELMintingPolicy"     | 1  | 2 | 10 | 10000
  "FUELMintingPolicy"     | 2  | 2 | 10 | 10000
  "FUELMintingPolicy"     | 3  | 2 | 10 | 10000
  "FUELMintingPolicy"     | 4  | 2 | 10 | 10000
 @
 to say that:
  - we are testing the "FUELMintingPolicy" 4 times (since @independentVarIx@ goes from
  @1..4@); and

  - we are running these "FUELMintingPolicy" tests twice (since @trialIx@
  goes from @1..2@)
-}
createTrialsTablesQuery :: Text
createTrialsTablesQuery =
  "CREATE TABLE IF NOT EXISTS\n\
  \trials\n\
  \   ( description TEXT\n\
  \   , independentVarIx INTEGER NOT NULL\n\
  \   , trialIx INTEGER NOT NULL\n\
  \   , ms INTEGER NOT NULL\n\
  \   , lovelaceFee INTEGER NOT NULL\n\
  \   , PRIMARY KEY(trialIx, independentVarIx, description)\n\
  \   );\n"

{- | 'selectFreshTrialIxQuery' returns a fresh 'trialIx' by taking the
 max and incrementing by 1.
-}
selectFreshTrialIxQuery :: Text
selectFreshTrialIxQuery =
  "SELECT ifnull(max(trialIx), 0) + 1\n\
  \FROM trials;"

-- | 'addTrialQuery' is a parameterized query which adds an trial.
addTrialQuery :: Text
addTrialQuery =
  "INSERT INTO trials(description, independentVarIx, trialIx, ms, lovelaceFee)\n\
  \SELECT :description, :independentVarIx, :trialIx, :ms, :lovelaceFee;"

--  | 'viewAllDescriptionQuery' fixes the @description@, and @SELECT@s all the
--  independentVars corresponding to that description.
selectAllDescriptionsQuery :: Text
selectAllDescriptionsQuery =
  "SELECT independentVarIx, trialIx, ms, lovelaceFee\n\
  \FROM trials\n\
  \WHERE description = :description\n\
  \ORDER BY trialIx ASC, independentVarIx ASC;"

-- * Utilities / internals

{- | Wraps 'Database.SQLite3.Direct.bindParameterIndex', but throws an
 exception if this fails.

 Some notes from the SQL documentation:

  - This wraps the following function: <https://www.sqlite.org/c3ref/bind_parameter_index.html>

  - Names should be prefixed with the initial ":" or "$" or "@" or "?"
  <https://www.sqlite.org/c3ref/bind_parameter_name.html>
-}
bindParameterIndex :: Statement -> Utf8 -> IO ParamIndex
bindParameterIndex stmt paramName =
  SQLite3.Direct.bindParameterIndex stmt paramName >>= \case
    Just paramIndex -> return paramIndex
    Nothing ->
      Exception.throwIO $
        BenchResultsError $
          List.unwords
            [ "internal error: non-existant 'bindParameterIndex' of"
            , "`" ++ ByteString.Char8.unpack (Coerce.coerce paramName) ++ "`."
            , "Most likely an incorrectly written SQL query."
            ]

{- | @'withPreparedStatement' sqlQuery@ is a bracket style resource handler for
 SQLite3 prepared statements.
-}
withPreparedStatement :: Text -> Database -> (Statement -> IO a) -> IO a
withPreparedStatement query database =
  Exception.bracket
    (SQLite3.prepare database query)
    SQLite3.finalize

-- | 'printQuery' wraps 'Data.Text.IO.putStrLn' to print a query conveniently
printQuery :: Text -> IO ()
printQuery = Text.IO.putStrLn

-- | 'BenchResultsError' newtype wrapper for internal errors of the system.
newtype BenchResultsError = BenchResultsError String
  deriving (Show)

instance Exception BenchResultsError
