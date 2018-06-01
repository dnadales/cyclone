-- | State of a node, plus operations on this state.
--
-- The state includes an in memory list of peers.
--
module Cyclone.State
    ( -- * State
      State
    , mkState
      -- * Functions on the peers list
    , setPeers
    , removePeer
    , neighbor
    , thisPid
      -- * Queue manipulation
      -- ** Outbound queue
    , enqueueNumber
    , dequeueNumber
      -- ** Inbound queue
    , appendNumber
    , getReceivedNumbers
    )
where

import           Control.Concurrent.STM        (STM, atomically, retry)
import           Control.Concurrent.STM.TQueue (TQueue, newTQueueIO, readTQueue,
                                                writeTQueue)
import           Control.Concurrent.STM.TVar   (TVar, modifyTVar', newTVarIO,
                                                readTVar, readTVarIO, writeTVar)
import           Control.Distributed.Process   (ProcessId)
import           Control.Monad.IO.Class        (MonadIO, liftIO)
import           Data.List                     (cycle, elemIndex)
import           Data.Set                      (Set)
import qualified Data.Set                      as Set

import           Cyclone.Messages              (Number)

data State = State
    { -- | List of peers known so far.
      _peers    :: TVar [ProcessId]
      -- | Process id of the current process.
    , thisPid   :: ProcessId
      -- | Neighbor of the current process (it can be itself).
    , _neighbor :: TVar (Maybe ProcessId)
      -- | Outbound queue (these messages have to be sent to the neighbors).
    , _outbound :: TQueue Number
      -- | Set of messages that haven't received an acknowledgment.
    , _waiting  :: TVar (Set Number)
      -- | List of numbers received so far.
    , _inbound  :: TVar [Number]
    }

-- | Create a new state, setting the given process id as the current process.
mkState :: MonadIO m => ProcessId -> m State
mkState pid = liftIO $
    State <$> newTVarIO []
          <*> pure pid
          <*> newTVarIO Nothing -- At the beginning a node is its own neighbor.
          <*> newTQueueIO
          <*> newTVarIO Set.empty
          <*> newTVarIO []

-- | When a peer is set, the neighbor will be determined.
--
setPeers :: MonadIO m => State -> [ProcessId] -> m ()
setPeers st ps = liftIO $ atomically $ setPeersSTM st ps

setPeersSTM :: State -> [ProcessId] -> STM ()
setPeersSTM st ps = do
    let n = determineNeighbor (thisPid st) ps
    writeTVar (_peers st) ps
    writeTVar (_neighbor st) n

-- | Determine the neighbor by simply looking at the element that follows the
-- given process id.
--
--
-- Pre-condition:
--
-- - The process id must be a member of the given list.
--
-- If the pre-condition is not met, then the function returns Nothing.
determineNeighbor :: ProcessId -> [ProcessId] -> Maybe ProcessId
determineNeighbor pid [] = Nothing
determineNeighbor pid ps =
    (ps'!!).(+ 1) <$> elemIndex pid ps
    where ps' = cycle ps

-- Retrieves the neighbor. The function will block until a neighbor is found.
neighbor :: MonadIO m => State -> m ProcessId
neighbor st = liftIO $ atomically $ do
    mn <- readTVar (_neighbor st)
    case mn of
        Just n  -> return n
        Nothing -> retry

-- | Remove a peer from the list. If the process that was removed is the
-- neighbor of the current process, then the new neighbor is updated.
removePeer :: MonadIO m => State -> ProcessId -> m ()
removePeer st pid = liftIO $ atomically $ do
    oldPeers <- readTVar (_peers st)
    setPeersSTM st (filter (/= pid) oldPeers)

-- | Add a @Number@ message to the queue.
enqueueNumber :: MonadIO m => State -> Number -> m ()
enqueueNumber st n = liftIO $ atomically $ writeTQueue (_outbound st) n

-- | Dequeue a @Number@ message. The message is put in the list of messages
-- that wait for an acknowledgment.
dequeueNumber :: MonadIO m => State -> m Number
dequeueNumber st = liftIO $ atomically $ do
    n <- readTQueue (_outbound st)
    modifyTVar' (_waiting st) (Set.insert n)
    return n

-- | Append a @Number@ to the list of numbers received so far.
--
-- If the number that is received in the set of messages awaiting
-- acknowledgment, then it is removed from it.
appendNumber :: MonadIO m => State -> Number -> m ()
appendNumber st n = liftIO $ atomically $ do
    modifyTVar' (_inbound st) (n:)
    modifyTVar' (_waiting st) (Set.delete n)

-- | Retrieve all the numbers received so far.
getReceivedNumbers :: MonadIO m => State -> m [Number]
getReceivedNumbers st = liftIO $ readTVarIO (_inbound st)
