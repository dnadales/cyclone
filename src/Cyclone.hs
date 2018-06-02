{-# LANGUAGE TemplateHaskell #-}
module Cyclone
    (runCyclone, runCycloneSlave)
where

import           Control.Concurrent                                 (forkIO)
import qualified Data.Set                                           as Set

import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process                        (NodeId,
                                                                     Process,
                                                                     ProcessId,
                                                                     ProcessMonitorNotification (ProcessMonitorNotification),
                                                                     RemoteTable,
                                                                     exit,
                                                                     getSelfPid,
                                                                     match,
                                                                     matchAny,
                                                                     monitor,
                                                                     receiveWait,
                                                                     say, send,
                                                                     spawn,
                                                                     spawnLocal,
                                                                     terminate)
import           Control.Distributed.Process.Backend.SimpleLocalnet (Backend, initializeBackend,
                                                                     startMaster,
                                                                     startSlave,
                                                                     terminateAllSlaves)
import           Control.Distributed.Process.Closure                (mkClosure,
                                                                     remotable)
import           Control.Distributed.Process.Node                   (initRemoteTable,
                                                                     runProcess)
import           Control.Monad                                      (forM,
                                                                     forM_,
                                                                     forever,
                                                                     when)
import           Control.Monad.IO.Class                             (liftIO)
import           Data.Binary                                        (Binary)
import           Data.List                                          (sort)
import           Data.Typeable                                      (Typeable)
import           GHC.Generics                                       (Generic)
import           Network.Socket                                     (HostName,
                                                                     ServiceName)

import           Cyclone.Messages                                   (Dump (Dump),
                                                                     Number,
                                                                     Peers (Peers),
                                                                     QuietPlease (QuietPlease),
                                                                     mkNumber,
                                                                     who)
import           Cyclone.State                                      (State, appendNumber,
                                                                     canTalk,
                                                                     getPeers,
                                                                     getReceivedNumbers,
                                                                     mkState,
                                                                     removePeer,
                                                                     setPeers,
                                                                     startTalk,
                                                                     stopTalk,
                                                                     thisPid)


cycloneNode :: Int -> Process ()
cycloneNode i = do
    myPid     <- getSelfPid
    st        <- mkState myPid
    startTalk st
    _ <- spawnLocal (talker st)
    forever $ receiveWait [ match $ handlePeers st
                          , match $ handleMonitorNotification st
                          , match $ handleNumber st
                          , match $ handleQuiet st
                          , match $ handleDump st
                          , matchAny $ \msg -> say $
                              "Message not handled: " ++ show msg
                          ]
    where
      handlePeers :: State -> Peers -> Process ()
      handlePeers st (Peers ps) = do
          forM_ (filter (/= thisPid st) ps) monitor
          setPeers st ps

      talker :: State -> Process ()
      talker st = do
          b <- canTalk st
          if b
              then do
                  ps <- getPeers st
                  n <- mkNumber (thisPid st) 1
                  -- Send to all the process, excluding itself.
                  let ps' = filter (/= thisPid st) ps
                  handleNumber st n
                  forM_ ps' (`send` n)
                  talker st
              else return ()

      handleNumber :: State -> Number -> Process ()
      handleNumber st n = appendNumber st n

      handleMonitorNotification :: State
                                -> ProcessMonitorNotification
                                -> Process ()
      handleMonitorNotification st (ProcessMonitorNotification _ pid _) =
          removePeer st pid

      handleQuiet :: State -> QuietPlease -> Process ()
      handleQuiet st _ = stopTalk st

      handleDump :: State -> Dump -> Process ()
      handleDump st _ = do
          ns <- getReceivedNumbers st
          say $ "I got " ++ show (length ns) ++ " numbers."

remotable ['cycloneNode]

myRemoteTable :: RemoteTable
myRemoteTable = Cyclone.__remoteTable initRemoteTable

runCyclone :: HostName
           -> ServiceName
           -> IO ()
runCyclone host port = do
    backend <- initializeBackend host port myRemoteTable
    startMaster backend (master backend)

master :: Backend -> [NodeId] -> Process ()
master backend slaves = do
    -- Start the slaves.
    ps <- forM slaves $ \nid -> do
        say $ "Starting slave on " ++ show nid
        spawn nid $ $(mkClosure 'cycloneNode) (1 :: Int)
    -- Send the process list to each slave
    forM ps (`send` (Peers ps))
    -- TODO: here use the 'send-for' argument
    liftIO $ threadDelay 1000000
    forM ps (`send` QuietPlease)

    -- TODO: here we have to determine some time to allow for the messages to
    -- finish arriving.
    liftIO $ threadDelay 1000000
    forM ps (`send` Dump)

    -- TODO: here use the 'wait-for' argument
    liftIO $ threadDelay 100000
    terminateAllSlaves backend

runCycloneSlave :: HostName -> ServiceName -> IO ()
runCycloneSlave host port = do
    backend <- initializeBackend host port myRemoteTable
    startSlave backend
