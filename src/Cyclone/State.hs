-- | State of a node, plus operations on this state.
--
-- The state includes an in memory list of peers.
--
module Cyclone.State
    ( -- * State
      State
    , mkState
      -- * Functions on the peers
    , setPeers
    , removePeer
    , neighbor
    )
where

import           Control.Concurrent.STM      (atomically, retry)
import           Control.Concurrent.STM.TVar (TVar, modifyTVar', newTVarIO,
                                              readTVar, readTVarIO, writeTVar)
import           Control.Distributed.Process (ProcessId)
import           Control.Monad.IO.Class      (MonadIO, liftIO)
import           Data.List                   (cycle, elemIndex)

data State = State
    { -- | List of peers known so far.
      _peers    :: TVar [ProcessId]
      -- | Process id of the current process.
    , _thisPid  :: ProcessId
      -- | Neighbor of the current process (it can be itself).
    , _neighbor :: TVar (Maybe ProcessId)
    }

-- | Create a new state, setting the given process id as the current process.
mkState :: MonadIO m => ProcessId -> m State
mkState pid = liftIO $
    State <$> newTVarIO []
          <*> pure pid
          <*> newTVarIO Nothing -- At the beginning a node is its own neighbor.

-- | When a peer is set, the neighbor will be determined.
--
setPeers :: MonadIO m => State -> [ProcessId] -> m ()
setPeers st ps = liftIO $ atomically $ do
    let n = determineNeighbor (_thisPid st) ps
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
removePeer :: MonadIO m => State -> [ProcessId] -> m ()
removePeer = undefined

