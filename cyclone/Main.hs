{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import           Control.Monad         (forM_, unless)
import           System.Console.Docopt (Arguments, Docopt, command, docopt,
                                        exitWithUsage, getArgWithDefault,
                                        isPresent, longOption, parseArgsOrExit)
import           System.Environment    (getArgs)
import           System.Random         (randomIO)
import           Text.Read             (readEither)

import           Cyclone               (runCyclone, runCycloneSlave)
import           Cyclone.Config        (Config, mkConfig)

patterns :: Docopt
patterns = [docopt|
cyclone

Usage:
  cyclone [-hpswr]
  cyclone slave [-hp]

Options:
  -h --host <string>        Host in which the node should be started (defaults
                            to "localhost").

  -p --port <number>        Port number in which the node should be started. If
                            not present the default port 9090 will be chosen.
                            Port numbers must be in the range 1024-65535.

  -s, --send-for <secs>     Duration in seconds of the message sending interval.

  -w, --wait-for <secs>     Duration in seconds of the grace period.

  -r, --with-seed <seed>    Initial seed for the random number generator.
|]

defaultPort :: String
defaultPort = "9090"

defaultHost :: String
defaultHost = "localhost"

minPortValue :: Int
minPortValue = 1024

maxPortValue :: Int
maxPortValue = 65535

main :: IO ()
main = do
    args  <- parseArgsOrExit patterns =<< getArgs
    port  <- getPort args
    cfg   <- getCfg args
    -- Note that we don't validate the host string.
    let host = getArgWithDefault args defaultHost (longOption "host")
    if args `isPresent` command "slave"
       then runCycloneSlave host port
       else runCyclone cfg host port
    where
      getPort :: Arguments -> IO String
      getPort args = do
          let portStr = getArgWithDefault args defaultPort (longOption "port")
          val <- getInt args "port" defaultPort
          unless (minPortValue <= val && val <= maxPortValue) $ do
              putStrLn $ "Invalid port number: " ++ show val
                       ++ ", a port number should be in the range "
                       ++ show minPortValue ++ " - " ++ show maxPortValue
              exitWithUsage patterns
          return portStr
      getInt :: Arguments -> String -> String ->  IO Int
      getInt args what deflt = do
          let valStr = getArgWithDefault args deflt (longOption what)
          case readEither valStr of
              Left _ -> do
                  putStrLn $ what ++ " should be an integer. Got " ++ valStr
                  exitWithUsage patterns
              Right (val :: Int) ->
                  return val
      getCfg :: Arguments -> IO Config
      getCfg args = do
          sFor  <- getSendFor args
          wFor  <- getWaitFor args
          wSeed <- getWithSeed args
          case mkConfig sFor wFor wSeed of
              Left errs -> do
                  forM_ errs putStrLn
                  exitWithUsage patterns
              Right cfg ->
                  return cfg
      getSendFor :: Arguments -> IO Int
      getSendFor args = getInt args "send-for" defaultSendFor
      getWaitFor :: Arguments -> IO Int
      getWaitFor args = getInt args "wait-for" defaultWaitFor
      getWithSeed :: Arguments -> IO Int
      getWithSeed args = do
          -- Determine a random seed in case no seed was selected.
          defaultSeed <- show <$> (randomIO :: IO Int)
          getInt args "with-seed" defaultSeed
      defaultSendFor = "1"
      defaultWaitFor = "1"
