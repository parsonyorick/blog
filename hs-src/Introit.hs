module Introit ( module X, Text, foldrMapM ) where

import Control.Applicative as X
import Control.Monad as X
import Control.Monad.Trans.Class as X
import Data.Bifunctor as X
import Data.Either as X
import Data.Foldable as X
import Data.List as X
import Data.Maybe as X
import Data.Monoid as X
import Data.Text ( Text )

foldrMapM :: (Foldable f, Monoid z, Monad m) => (a -> m z) -> f a -> m z
foldrMapM f =
   foldrM (\z1 z2 -> (<>) <$> f z1 <*> return z2) mempty