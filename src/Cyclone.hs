{-# LANGUAGE TemplateHaskell #-}
module Cyclone
    (runCyclone, runCycloneSlave)
where

import           Control.Concurrent                                 (forkIO)
import           Control.Concurrent.Async                           (race_)
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
                                                                     dequeueNumber,
                                                                     enqueueNumber,
                                                                     getDouble,
                                                                     getPeers,
                                                                     getReceivedNumbers,
                                                                     mkState,
                                                                     neighbor,
                                                                     reEnqueueWaiting,
                                                                     removePeer,
                                                                     setPeers,
                                                                     startTalk,
                                                                     stopTalk,
                                                                     thisPid,
                                                                     waitForAck)


-- | Start a node with the given seed for the random number generator.
cycloneNode :: Int -> Process ()
cycloneNode seed = do
    myPid     <- getSelfPid
    st        <- mkState myPid seed
    startTalk st
    -- _ <- spawnLocal (talker st)
    _ <- spawnLocal (generator st)
    _ <- spawnLocal (sender st)
    _ <- spawnLocal (watchdog st)
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

      generator :: State -> Process ()
      generator st = do
          b <- canTalk st
          when b $ do
              waitForAck st
              -- liftIO $ threadDelay 1000
              d  <- getDouble st
              n  <- mkNumber (thisPid st) d
              enqueueNumber st n
              generator st

      watchdog :: State -> Process ()
      watchdog st = forever $ do
          liftIO $ race_ (threadDelay 1000 >> reEnqueueWaiting st) (waitForAck st)

      sender :: State -> Process ()
      sender st = forever $ do
          nPid <- neighbor st
          n <- dequeueNumber st
          send nPid n

      handleNumber :: State -> Number -> Process ()
      handleNumber st n = do
          appendNumber st n

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
