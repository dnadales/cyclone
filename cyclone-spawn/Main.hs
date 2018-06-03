{-# LANGUAGE OverloadedStrings #-}
-- | Helper program to launch multiple programs and redirect their output to a file.
module Main where

import           Control.Concurrent.Async (async, mapConcurrently, waitCatch)
import qualified Control.Foldl            as Fold
import           Control.Monad            (void)
import           Data.Monoid              (mempty)
import           Data.String              (fromString)
import           System.Directory         (getTemporaryDirectory)
import           System.Environment       (getArgs)
import           Turtle                   (decodeString, fold, input, inshell,
                                           liftIO, lineToText, nl, output,
                                           (</>))

import qualified Turtle

-- | 'cyclone-spawn' will spawn multiple programs, and redirect their output to
-- separate files.
--
-- The programs to be run are read from the a configuration file, which is
-- assumed to be in the current working directory. The default configuration
-- file is assumed to be ".cyclone-spawn.config". Other configuration file
-- paths (relative to the current working directory) can be given by passing an
-- argument to this program.
--
-- Each line of the configuration file is interpreted verbatim as a command to
-- be run. The output of the program at line 'n' will be written to
-- 'TMPDIR/program-n', where 'TMPDIR' is the path to the temporary directory
-- (OS dependent).
--
main :: IO ()
main = do
    args    <- getArgs
    let cfgPath = case args of
            [arg] -> fromString arg
            _     -> defaultCfgPath
    tmpPath <- getTemporaryDirectory
    as      <- fold (runPrograms (decodeString tmpPath) cfgPath) Fold.list
    void $ mapConcurrently waitCatch as
    where
      runPrograms tmp cfgPath = do
          (n, line) <- nl $ input cfgPath
          let sfx = show (n :: Int)
              outFile = tmp </> decodeString ("program-" ++ sfx)
              cmd = lineToText line
          liftIO $ async $ output outFile (inshell cmd mempty)

defaultCfgPath :: Turtle.FilePath
defaultCfgPath = ".cyclone-spawn.config"
