{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import           Control.Monad         (unless)
import           System.Console.Docopt (Arguments, Docopt, command, docopt,
                                        exitWithUsage, getArgWithDefault,
                                        isPresent, longOption, parseArgsOrExit)
import           System.Environment    (getArgs)
import           Text.Read             (readEither)

import           Cyclone               (runCyclone, runCycloneSlave)


patterns :: Docopt
patterns = [docopt|
cyclone

Usage:
  cyclone [-hpswr]
  cyclone slave [-hp]

Options:
  -h --host <string>        Host in which the node should be started.

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
    -- Note that we don't validate the host string.
    let host = getArgWithDefault args defaultHost (longOption "host")
    if (args `isPresent` command "slave")
       then runCycloneSlave host port
       else runCyclone host port
    where
      getPort :: Arguments -> IO String
      getPort args = do
          let portStr = getArgWithDefault args defaultPort (longOption "port")
          val <- case readEither portStr of
              Left _ -> do
                  putStrLn $ "Port number should be an integer. Got " ++ portStr
                  exitWithUsage patterns
              Right (val :: Int) ->
                  return val
          unless (minPortValue <= val && val <= maxPortValue) $ do
              putStrLn $ "Invalid port number: " ++ show val
                       ++ ", a port number should be in the range "
                       ++ show minPortValue ++ " - " ++ show maxPortValue
              exitWithUsage patterns
          return portStr
