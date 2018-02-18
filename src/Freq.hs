{-# language BangPatterns #-}
{-# language MagicHash    #-}
{-# language NoImplicitPrelude #-}

{-# OPTIONS_GHC -O2 -Wall #-}

module Freq where

import Control.Applicative (Applicative(..))
import Data.ByteString.Internal (ByteString(..))
import Data.Foldable
import Data.Map.Strict (Map)
import Data.Monoid
import Data.Semigroup
import Data.String (String)
import Data.Word (Word8)
import GHC.Base hiding (empty)

import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Unsafe as BU
import qualified Data.Map.Strict as DMS
import qualified Prelude as P

type Weight   = Double
type Prob     = Double
type FilePath = String
type Tal      = Map Word8 (Map Word8 Weight)

newtype Freq = Freq { freq :: Tal }

instance Semigroup Freq where
  {-# INLINE (<>) #-} 
  (Freq a) <> (Freq b) = Freq $ union a b

instance Monoid Freq where
  {-# INLINE mempty #-} 
  mempty  = empty
  {-# INLINE mappend #-} 
  (Freq a) `mappend` (Freq b) = Freq $ union a b

{-# INLINE empty #-}
empty :: Freq
empty = Freq DMS.empty

{-# INLINE singleton #-}
singleton :: Word8 -> Word8 -> Weight -> Freq
singleton k ka w = Freq $ DMS.singleton k (DMS.singleton ka w)

{-# INLINE union #-}
union :: Tal -> Tal -> Tal
union a b = DMS.unionWith (DMS.unionWith (P.+)) a b

{-# INLINE defWeight #-}
defWeight :: Weight
defWeight = 1.0

{-# INLINE defProb #-}
defProb :: Prob
defProb = 40.0

{-# INLINE measure #-}
measure :: Freq       -- ^ Frequency table
        -> ByteString -- ^ bytestring in question
        -> Prob       -- ^ Probability that the bytestring is not randomised
measure f !b = probability f b defProb

{-# INLINE probability #-}
probability :: Freq       -- ^ Frequency table
            -> ByteString -- ^ bytestring in question
            -> Prob       -- ^ Maximum probability that the bytestring is not randomised
            -> Prob       -- ^ Probability that the bytestring is not randomised
probability _ (PS _ _ 0) _ = 0
probability f !b !prob = (go 0 l b) P./ (P.fromIntegral l)
  where
    l :: Int
    l = BC.length b

    go :: Int -> Int -> ByteString -> Double
    go !p !q bs
      | p == q = 0
      | otherwise =
          let k = BU.unsafeIndex bs p
              r = BU.unsafeIndex bs (p P.+ 1)
          in probInternal f k r prob P.+ go (p P.+ 1) l bs 

{-# INLINE probInternal #-}
probInternal :: Freq  -- ^ Frequency table
             -> Word8 -- ^ Character 1
             -> Word8 -- ^ Character 2
             -> Prob  -- ^ Maximum probability that character 1 follows character 2
             -> Prob  -- ^ Probability that character 1 follows character 2
probInternal (Freq f) w1 w2 p =
  case DMS.lookup w1 f of
    Nothing -> 0
    Just g  ->
      case DMS.lookup w2 g of
        Nothing -> 0
        Just _  -> ratio p g

{-# INLINE ratio #-}
ratio :: Prob -> Map Word8 Weight -> Prob
ratio !p g = P.min p (100.0 P.* ((sum g) P./ (P.fromIntegral $ DMS.size g)))

create :: [FilePath] -> IO Freq
create paths = foldMapA createInternal' paths

{-# INLINE createInternal' #-}
createInternal' :: FilePath -> IO Freq
createInternal' path = do
  text <- BC.readFile path
  pure $ tally text

{-# INLINE tally' #-}
tally' :: Weight -> ByteString -> Freq
tally' _ (PS _ _ 0) = empty
tally' !w !b = Freq $ go 0 l b
  where
    l :: Int
    l = BC.length b

    go :: Int -> Int -> ByteString -> Tal
    go !p !q bs
      | p == q = DMS.empty
      | otherwise =
          let k = BU.unsafeIndex bs p
              r = BU.unsafeIndex bs (p P.+ 1)
          in (freq $ singleton k r w) `union` (go (p P.+ 1) l bs)

{-# INLINE tally #-}
tally :: ByteString -> Freq
tally !b = tally' defWeight b

newtype Ap f a = Ap { getAp :: f a }

instance (Applicative f, Monoid a) => Monoid (Ap f a) where
  {-# INLINE mempty #-} 
  mempty = Ap $ pure mempty
  {-# INLINE mappend #-} 
  mappend (Ap x) (Ap y) = Ap $ liftA2 mappend x y

foldMapA :: (Foldable t, Monoid m, Applicative f) => (a -> f m) -> t a -> f m
foldMapA f = getAp . foldMap (Ap . f)
