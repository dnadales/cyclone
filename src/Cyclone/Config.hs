-- | Configuration options for 'cyclone'.
module Cyclone.Config
    ( Config
    , mkConfig
    , sendFor
    , waitFor
    , withSeed
    )
where

import           Data.Either.Validation (Validation (Failure, Success),
                                         validationToEither)

-- | Configuration for the master node.
data Config = Config
    { -- | Duration in seconds of the message sending interval.
      sendFor  :: Int
    , -- | Duration in seconds of the grace period.
      waitFor  :: Int
    , -- | Initial seed for the random number generator.
      withSeed :: Int
    }

-- | Make a new configuration value, after validating the given time intervals
-- (which should be non-negative).
mkConfig :: Int -- ^ Send for.
         -> Int -- ^ Wait for.
         -> Int -- ^ Seed
         -> Either [String] Config
mkConfig sFor wFor wSeed  = validationToEither $
    Config <$> valTimeInterval sFor "send for"
           <*> valTimeInterval wFor "wait for"
           <*> pure wSeed
    where
      valTimeInterval t what
          | 0 <= t = Success t
          | otherwise = Failure [what ++ " must be non-negative"]
