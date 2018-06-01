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
    , timestamp)
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
    } deriving (Show, Eq, Ord, Typeable, Generic)

instance Binary Number

-- | Make a @Number@ message, creating a timestamp with the current time, and adding it to it.
mkNumber :: MonadIO m => Double -> m Number
mkNumber d = liftIO $ do
    t <- realToFrac <$> getPOSIXTime
    return $ Number d t
