{-# LANGUAGE TemplateHaskell #-}
module Cyclone
    (runCyclone, runCycloneSlave)
where

import           Control.Distributed.Process                        (NodeId,
                                                                     Process,
                                                                     RemoteTable,
                                                                     say, spawn,
                                                                     terminate)
import           Control.Distributed.Process.Backend.SimpleLocalnet (Backend, initializeBackend,
                                                                     startMaster,
                                                                     startSlave,
                                                                     terminateAllSlaves)
import           Control.Distributed.Process.Closure                (mkClosure,
                                                                     remotable)
import           Control.Distributed.Process.Node                   (initRemoteTable,
                                                                     runProcess)
import           Control.Monad                                      (forM)
import           Control.Monad.IO.Class                             (liftIO)
import           Network.Socket                                     (HostName,
                                                                     ServiceName)

import           Control.Concurrent                                 (threadDelay)

cycloneNode ::Int ->  Process ()
cycloneNode i = do
    liftIO $ putStrLn $ "Hello, I got " ++ show i
    say $ "Hello, I got " ++ show i

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
    ps <- forM slaves $ \nid -> do
        say $ "Starting slave on " ++ show nid
        spawn nid $ $(mkClosure 'cycloneNode) (1 :: Int)
    liftIO $ threadDelay 4000000
    terminateAllSlaves backend

runCycloneSlave :: HostName -> ServiceName -> IO ()
runCycloneSlave host port = do
    backend <- initializeBackend host port myRemoteTable
    startSlave backend
