{-# LANGUAGE DeriveGeneric, DeriveAnyClass
           , LambdaCase
#-}
module Routes
   ( Route(..)
   , targetFile
   , url
   ) where

import Introit
import qualified Text

import Data.Hashable ( Hashable )
import Development.Shake.FilePath
import GHC.Generics ( Generic )
import qualified Network.URI.Encode as URI

data Route
   = Home
   | Archive
   | Post String
   | AllTags
   | Tag Text
   | Stylesheet String
   | Image String
   deriving ( Eq, Generic, Hashable )

targetFile :: Route -> FilePath
targetFile = \case
   Home             -> htmlTargetFile Home
   Archive          -> htmlTargetFile Archive
   p@(Post _)       -> htmlTargetFile p
   AllTags          -> htmlTargetFile AllTags
   t@(Tag _)        -> htmlTargetFile t
   s@(Stylesheet _) -> urlToTargetFile (url s)
   i@(Image _)      -> urlToTargetFile (url i)
 where
   urlToTargetFile url =
     -- This is dumb, see below
      URI.decode $ tail (Text.unpack url)
   htmlTargetFile route =
      urlToTargetFile (url route) </> "index.html"

url :: Route -> Text
url = Text.pack . \case
   Home ->
      "/"
   Archive ->
      "/archive"
   Post slug ->
      "/posts" </> slug
   AllTags ->
      "/tags"
   Tag tag ->
      "/tags" </> Text.unpack (URI.encodeText tag)
   Stylesheet basename ->
      "/styles" </> basename <.> "css"
   Image filename ->
      "/images" </> filename
