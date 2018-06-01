{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE TemplateHaskell    #-}
module Cyclone
    (runCyclone, runCycloneSlave)
where

import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process                        (NodeId,
                                                                     Process,
                                                                     ProcessId,
                                                                     ProcessMonitorNotification (ProcessMonitorNotification),
                                                                     RemoteTable,
                                                                     getSelfPid,
                                                                     match,
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
                                                                     forever)
import           Control.Monad.IO.Class                             (liftIO)
import           Data.Binary                                        (Binary)
import           Data.Typeable                                      (Typeable)
import           GHC.Generics                                       (Generic)
import           Network.Socket                                     (HostName,
                                                                     ServiceName)

import           Cyclone.State                                      (State,
                                                                     mkState,
                                                                     neighbor,
                                                                     removePeer,
                                                                     setPeers,
                                                                     thisPid)

-- | Message used to communicate the list of peers.
newtype Peers = Peers [ProcessId]
    deriving (Show, Typeable, Generic)

instance Binary Peers

cycloneNode :: Int -> Process ()
cycloneNode i = do
    liftIO $ putStrLn $ "Hello, I got " ++ show i
    say $ "Hello, I got " ++ show i
    myPid <- getSelfPid
    st <- mkState myPid
    spawnLocal (talker st)
    forever $ receiveWait [ match $ handlePeers st
                          , match $ handleMonitorNotification st
                          ]
    where
      handlePeers :: State -> Peers -> Process ()
      handlePeers st (Peers ps) = do
          forM_ (filter (/= thisPid st) ps) monitor
          setPeers st ps

      talker :: State -> Process ()
      talker st = forever $ do
          n <- neighbor st
          liftIO $ threadDelay 1000000
          liftIO $ putStrLn $ "This is my buddy: " ++ show n
          say $ "This is my buddy: " ++ show n

      handleMonitorNotification :: State
                                -> ProcessMonitorNotification
                                -> Process ()
      handleMonitorNotification st (ProcessMonitorNotification _ pid _) =
          removePeer st pid

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
    forM ps $ \pid ->
        send pid (Peers ps)

    liftIO $ threadDelay 10000000
    terminateAllSlaves backend

runCycloneSlave :: HostName -> ServiceName -> IO ()
runCycloneSlave host port = do
    backend <- initializeBackend host port myRemoteTable
    startSlave backend
