{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}

-- | Messages sent around by the 'cyclone' nodes.
module Cyclone.Messages
    ( -- * Peers
      Peers(..)
      -- * Numbers
    , Number
    , mkNumber
    , value
    , timestamp
    , who
      -- * Finish
    , Dump (..)
    , QuietPlease (..)
    )
where

import           Control.Distributed.Process (ProcessId)
import           Control.Monad.IO.Class      (MonadIO, liftIO)
import           Data.Binary                 (Binary)
import           Data.Time.Clock.POSIX       (getPOSIXTime)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

-- | Message used to communicate the list of peers.
newtype Peers = Peers [ProcessId]
    deriving (Show, Typeable, Generic)

instance Binary Peers

-- | Numbers that are sent around by the nodes
data Number = Number
    { value     :: Double
    , timestamp :: Double
    -- | Process id that sent the message.
    , who       :: ProcessId
    } deriving (Eq, Ord, Show, Typeable, Generic)

instance Binary Number

-- instance Ord Number where
--     compare n m
--         |  timestamp n < timestamp m = LT
--         |  timestamp n == timestamp m = EQ
--         |  timestamp n > timestamp m = GT
--            -- && who n <= who m
--            -- && value n <= value m

-- instance Eq Number where
--     n == m =  timestamp n == timestamp m
--            && who n == who m
--            && value n == value m

-- | Make a @Number@ message, creating a timestamp with the current time, and adding it to it.
mkNumber :: MonadIO m => ProcessId -> Double -> m Number
mkNumber pid d = liftIO $ do
    t <- realToFrac <$> getPOSIXTime
    return $ Number { value = d, timestamp = t, who = pid}

-- | Stop sending messages.
data QuietPlease = QuietPlease
        deriving (Show, Typeable, Generic)

instance Binary QuietPlease

-- | Dump the messages received so far.
data Dump = Dump
        deriving (Show, Typeable, Generic)

instance Binary Dump
