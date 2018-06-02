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

import           Cyclone.Config                                     (Config,
                                                                     sendFor,
                                                                     waitFor,
                                                                     withSeed)
import           Cyclone.Messages                                   (Dump (Dump),
                                                                     Number,
                                                                     Peers (Peers),
                                                                     QuietPlease (QuietPlease),
                                                                     mkNumber,
                                                                     value, who)
import           Cyclone.State                                      (State, appendNumber,
                                                                     canTalk,
                                                                     getNumber,
                                                                     getPeers,
                                                                     getReceivedNumbers,
                                                                     mkState,
                                                                     removePeer,
                                                                     setPeers,
                                                                     startTalk,
                                                                     stopTalk,
                                                                     thisPid)


-- | Start a node with the given seed for the random number generator.
cycloneNode :: Int -> Process ()
cycloneNode seed = do
    myPid     <- getSelfPid
    st        <- mkState myPid seed
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
          when b $ do
              d  <- getNumber st
              n  <- mkNumber (thisPid st) d
              ps <- getPeers st
              -- Send to all the process, excluding itself.
              let ps' = filter (/= thisPid st) ps
              -- This process register the number it generated, since it is
              -- faster than performing a network operation.
              handleNumber st n
              forM_ ps' (`send` n)
              talker st

      -- generator :: State -> Process ()
      -- generator st = do
      --     b <- canTalk st
      --     when b $ do
      --         waitForAck st -- TODO: should wait for ack
      --         d  <- getNumber st
      --         n  <- mkNumber (thisPid st) d
      --         enqueueNumber st n
      --         generator st

      -- watchDog :: State -> Process ()
      -- watchDog st = forever $ do
      --     threadDelay 10000
      --     reEnqueueWaiting st

      -- sender :: State -> Process ()
      -- sender st = do
      --     nPid <- neighbor st
      --     n <- dequeueNumber st
      --     send nPid n

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
          let vals = sum $ map (uncurry (*)) $ zip [1..] (value <$> ns)
          say $ show (length ns, vals)

remotable ['cycloneNode]

myRemoteTable :: RemoteTable
myRemoteTable = Cyclone.__remoteTable initRemoteTable

runCyclone :: Config
           -> HostName
           -> ServiceName
           -> IO ()
runCyclone cfg host port = do
    backend <- initializeBackend host port myRemoteTable
    startMaster backend (master cfg backend)

master :: Config -> Backend -> [NodeId] -> Process ()
master cfg  backend slaves = do
    -- Start the slaves.
    ps <- forM slaves $ \nid -> do
        say $ "Starting slave on " ++ show nid
        spawn nid $ $(mkClosure 'cycloneNode) (withSeed cfg)
    -- Send the process list to each slave
    forM ps (`send` (Peers ps))
    -- Allow the nodes to send messages
    delay $ (sendFor cfg) * 1000000
    forM ps (`send` QuietPlease)
    let (waitForMgs, waitForCalc) = (floor (w * 0.7), floor (w * 0.3))
        w = toRational $ waitFor cfg * 1000000
    -- Use the @waitFor@ argument to determine a period in which the messages
    -- can be received before performing the final calculation.
    delay waitForMgs
    forM ps (`send` Dump)
    delay waitForCalc
    terminateAllSlaves backend
    where
      delay mus = liftIO $ threadDelay $ mus

runCycloneSlave :: HostName -> ServiceName -> IO ()
runCycloneSlave host port = do
    backend <- initializeBackend host port myRemoteTable
    startSlave backend
