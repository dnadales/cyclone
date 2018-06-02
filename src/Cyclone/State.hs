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
    , getPeers
    , thisPid
    , startTalk
    , canTalk
    , stopTalk
      -- * Inbound queue manipulation
    , appendNumber
    , getReceivedNumbers
    -- * Random number generation
    , getDouble
    --  TODO: sort these functions
    , waitForAck
    , enqueueNumber
    , reEnqueueWaiting
    , dequeueNumber
    , neighbor
    )
where

import           Control.Concurrent.MVar       (MVar, modifyMVar, newMVar)
import           Control.Concurrent.STM        (STM, atomically, retry)
import           Control.Concurrent.STM.TQueue (TQueue, newTQueueIO, readTQueue,
                                                tryReadTQueue, writeTQueue)
import           Control.Concurrent.STM.TVar   (TVar, modifyTVar', newTVarIO,
                                                readTVar, readTVarIO, writeTVar)
import           Control.Distributed.Process   (ProcessId)
import           Control.Monad                 (unless, when)
import           Control.Monad.IO.Class        (MonadIO, liftIO)
import           Data.List                     (cycle, elemIndex)
import           Data.Maybe                    (isJust)
import           Data.Set                      (Set)
import qualified Data.Set                      as Set
import           System.Random                 (StdGen, mkStdGen, randomR)

import           Cyclone.Messages              (Number, who)

data State = State
    { -- | List of peers known so far.
      _peers      :: TVar [ProcessId]
      -- | Process id of the current process (where the state was created).
    , thisPid     :: ProcessId
      -- | Set of numbers received so far.
    , _inbound    :: TVar (Set Number)
      -- | Can messages be sent?
    , _talk       :: TVar Bool
    , -- | Random generator
      _rndGen     :: MVar StdGen
    , -- | Outbound queue
      _outbound   :: TQueue Number
      -- | Number (if any) awaiting for acknowledgment.
    , _waitingAck :: TVar (Maybe Number)
      -- | Neighbor of the current process (it can be itself).
    , _neighbor   :: TVar (Maybe ProcessId)
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
          <*> newTQueueIO
          <*> newTVarIO Nothing -- This process is not awaiting ACK.
          <*> newTVarIO Nothing -- No neighbor at the beginning.

-- | When a peer is set, the neighbor will be determined.
--
setPeers :: MonadIO m => State -> [ProcessId] -> m ()
setPeers st ps = liftIO $ atomically $ setPeersSTM st ps

setPeersSTM :: State -> [ProcessId] -> STM ()
setPeersSTM st ps = do
    let n = determineNeighbor (thisPid st) ps
    writeTVar (_peers st) ps
    writeTVar (_neighbor st) n

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
-- If the number that is received is in the set of messages awaiting
-- acknowledgment, then it is removed from it.
appendNumber :: MonadIO m => State -> Number -> m ()
appendNumber st n = liftIO $ atomically $ do
    -- If the number we got was sent by us, it means the message round-tripped,
    -- so all the nodes got it.
    if who n == thisPid st
       then do
           writeTVar (_waitingAck st) Nothing
           modifyTVar' (_inbound st) (Set.insert n)
        else do
            ns <- readTVar (_inbound st)
            unless (n `Set.member` ns) (writeTQueue (_outbound st) n)
            modifyTVar' (_inbound st) (Set.insert n)

-- | Retrieve all the numbers received so far, sorted increasingly.
getReceivedNumbers :: MonadIO m => State -> m [Number]
getReceivedNumbers st = fmap Set.toAscList $
    liftIO $ readTVarIO (_inbound st)

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
getDouble :: MonadIO m => State -> m Double
getDouble st = liftIO $ modifyMVar (_rndGen st) genValidDouble
    where
        genValidDouble g = let (v, g') = randomR (0, 1) g in
            if v == 0 then genValidDouble g else return (g', v)

-- | Wait till an acknowledgment has been sent.
waitForAck :: MonadIO m => State -> m ()
waitForAck st = liftIO $ atomically $ do
    mN <- readTVar (_waitingAck st)
    when (isJust mN) retry

-- | Add a @Number@ message to the queue.
enqueueNumber :: MonadIO m => State -> Number -> m ()
enqueueNumber st n = liftIO $ atomically $ enqueueNumberSTM st n

enqueueNumberSTM :: State -> Number -> STM ()
enqueueNumberSTM st n = do
    writeTQueue (_outbound st) n
    when (who n == thisPid st) (writeTVar (_waitingAck st) (Just n))

-- | Dequeue a @Number@ message.
dequeueNumber :: MonadIO m => State -> m Number
dequeueNumber st = liftIO $ atomically $ readTQueue (_outbound st)

-- | Re-enqueue a waiting number.
reEnqueueWaiting :: MonadIO m => State -> m ()
reEnqueueWaiting st = liftIO $ atomically $ do
    mN <- readTVar (_waitingAck st)
    maybe (return ()) (writeTQueue (_outbound st)) mN

-- | Retrieves the neighbor. The function will block until a neighbor is found.
neighbor :: MonadIO m => State -> m ProcessId
neighbor st = liftIO $ atomically $ do
    mn <- readTVar (_neighbor st)
    maybe retry return mn

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
