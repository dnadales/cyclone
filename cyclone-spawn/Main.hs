{-# LANGUAGE OverloadedStrings #-}
-- | Helper program to launch multiple programs and redirect their output to a file.
module Main where

import           Control.Concurrent.Async (async, mapConcurrently, wait)
import qualified Control.Foldl            as Fold
import           Control.Monad            (void)
import           Data.Monoid              (mempty)
import           System.Directory         (getTemporaryDirectory)
import           Turtle                   (decodeString, fold, input, inshell,
                                           liftIO, lineToText, nl, output,
                                           (</>))
import qualified Turtle

-- | 'cyclone-spawn' will spawn multiple programs, and redirect their output to
-- separate files.
--
-- The programs to be run are read from the a configuration file @cfgPath@,
-- which is assumed to be in the current working directory. Each line of this
-- file is interpreted verbatim as a command to be run. The output of the
-- program at line 'n' will be written to 'TMPDIR/program-n', where 'TMPDIR' is
-- the path to the temporary directory (OS dependent).
--
main :: IO ()
main = do
    tmpPath <- getTemporaryDirectory
    as      <- fold (runPrograms (decodeString tmpPath)) Fold.list
    void $ mapConcurrently wait as
    where
      runPrograms tmp = do
          (n, line) <- nl $ input cfgPath
          let sfx = show (n :: Int)
              outFile = tmp </> decodeString ("program-" ++ sfx)
              cmd = lineToText line
          liftIO $ async $ output outFile (inshell cmd mempty)

cfgPath :: Turtle.FilePath
cfgPath = ".cyclone-spawn.config"
