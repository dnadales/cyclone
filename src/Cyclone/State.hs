-- | State of a node, plus operations on this state.
--
-- The state includes an in memory list of peers.
--
module Cyclone.State
    ( -- * State
      State
    , mkState
      -- * Peers
    , setPeers
    , removePeer
    , getPeers
    , thisPid
      -- * Message sending logic
    , startTalk
    , canTalk
    , stopTalk
      -- * Inbound queue
    , appendNumber
    , getReceivedNumbers
    , getNumber
    , lastNumberOf
    )
where

import           Control.Concurrent.MVar       (MVar, modifyMVar, newMVar)
import           Control.Concurrent.STM        (STM, atomically, retry)
import           Control.Concurrent.STM.TQueue (TQueue, newTQueueIO, readTQueue,
                                                tryReadTQueue, writeTQueue)
import           Control.Concurrent.STM.TVar   (TVar, modifyTVar', newTVarIO,
                                                readTVar, readTVarIO, writeTVar)
import           Control.Distributed.Process   (ProcessId)
import           Control.Monad.IO.Class        (MonadIO, liftIO)
import           Data.List                     (cycle, elemIndex)
import           Data.Map.Strict               (Map)
import qualified Data.Map.Strict               as Map
import           Data.Set                      (Set)
import qualified Data.Set                      as Set
import           System.Random                 (StdGen, mkStdGen, randomR)

import           Cyclone.Messages              (Number, who)

data State = State
    { -- | List of peers known so far.
      _peers      :: TVar [ProcessId]
      -- | Process id of the current process (where the state was created).
    , thisPid     :: ProcessId
      -- | List of numbers received so far.
    , _inbound    :: TVar (Set Number)
      -- | Can messages be sent?
    , _talk       :: TVar Bool
    , -- | Random generator
      _rndGen     :: MVar StdGen
    , -- | Last values received by a the peers
      _lastNumber :: TVar (Map ProcessId Number)
    }

-- | Create a new state, setting the given process id as the current process,
-- and creating a random number generator with the given seed.
--
mkState :: MonadIO m => ProcessId -> Int -> m State
mkState pid seed = liftIO $
    State <$> newTVarIO []
          <*> pure pid
          <*> newTVarIO Set.empty
          <*> newTVarIO False -- Don't talk at the beginning.
          <*> newMVar (mkStdGen seed)
          <*> newTVarIO Map.empty

-- | When a peer is set, the neighbor will be determined.
--
setPeers :: MonadIO m => State -> [ProcessId] -> m ()
setPeers st ps = liftIO $ atomically $ setPeersSTM st ps

setPeersSTM :: State -> [ProcessId] -> STM ()
setPeersSTM st ps = writeTVar (_peers st) ps

-- | Remove a peer from the list. If the process that was removed is the
-- neighbor of the current process, then the new neighbor is updated.
removePeer :: MonadIO m => State -> ProcessId -> m ()
removePeer st pid = liftIO $ atomically $ do
    oldPeers <- readTVar (_peers st)
    setPeersSTM st (filter (/= pid) oldPeers)

-- | Get the current list of peers, retrying if the list of peers is empty.
getPeers :: MonadIO m => State -> m [ProcessId]
getPeers st = liftIO $ atomically $ do
    ps <- readTVar (_peers st)
    if null ps
        then retry
        else return ps

-- | Append a @Number@ to the list of numbers received so far.
--
-- If the number that is received in the set of messages awaiting
-- acknowledgment, then it is removed from it.
appendNumber :: MonadIO m => State -> Number -> m ()
appendNumber st n = liftIO $ atomically $ do
    modifyTVar' (_inbound st) (Set.insert n)
    modifyTVar' (_lastNumber st) (Map.insert (who n) n)

-- | Retrieve all the numbers received so far.
getReceivedNumbers :: MonadIO m => State -> m [Number]
getReceivedNumbers st =
    fmap Set.toAscList . liftIO  . readTVarIO $ _inbound st

-- | Signal that a process can start talking.
startTalk :: MonadIO m => State -> m ()
startTalk st = liftIO $ atomically $ writeTVar (_talk st) True

-- | Can a process start talking?
canTalk :: MonadIO m => State -> m Bool
canTalk st = liftIO $ readTVarIO (_talk st)

-- | Signal that a process has to stop talking.
stopTalk :: MonadIO m => State -> m ()
stopTalk st = liftIO $ atomically $ writeTVar (_talk st) False

-- | Get a random number, updating the state of the generator.
getNumber :: MonadIO m => State -> m Double
getNumber st = liftIO $ modifyMVar (_rndGen st) genValidDouble
    where
        genValidDouble g = let (v, g') = randomR (0, 1) g in
            if v == 0 then genValidDouble g else return (g', v)

-- | Retrieve the last number (if any), what we received from the given peer.
lastNumberOf :: MonadIO m => State -> ProcessId -> m (Maybe Number)
lastNumberOf st pid =
    fmap (Map.lookup pid ) . liftIO . readTVarIO $ _lastNumber st
