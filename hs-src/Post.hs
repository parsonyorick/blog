{-# LANGUAGE MultiParamTypeClasses #-}
module Post ( Post(..), Tag ) where

import Prelude hiding ( read )

import Introit
import Prose
import Properties
import qualified Text

import Data.Time.Calendar ( Day )
import Data.Time.Format ( parseTimeM, defaultTimeLocale )
import Data.Yaml ( (.:), (.:?), (.!=) )
import qualified Data.Yaml as Yaml
import qualified Text.MMark as MMark


data Post = Post
   { url :: Text -- ^ Route to this post.
   , postTitle :: Maybe Prose
   , postPageTitle :: Text
   , prose :: Prose -- ^ The post body.
   , mSynopsis :: Maybe Prose -- ^ A little summary or tagline.
   , description :: Maybe Text -- ^ A slightly longer and self-contained description.
   , published :: Day -- ^ Date of publication.
   , isDraft :: Bool -- ^ Whether this post is a draft or is published.
   , tags :: [Tag] -- ^ Some tags.
   }

type Tag = Text

instance HasTitle Post Prose where
  title = postTitle

instance HasPageTitle Post where
  titleForPage = postPageTitle

instance HasDate Post where
  date = published

instance HasContent Post where
  content = content . prose

instance HasPreview Post where
  preview = preview . prose

instance HasIncipit Post where
  incipit = incipit . prose

instance Parse Post where
  parse = parsePost

parsePost :: FilePath -> Text -> Either String Post
parsePost filepath contents = do
  body <- parse filepath contents
  yaml <- maybe (Left noMetadataError) Right $
     MMark.projectYaml (content body)
  withMetadata body yaml
 where
   withMetadata prose = Yaml.parseEither $
      Yaml.withObject "metadata" \metadata -> do
         mTitle    <- metadata .:? "title"
         date     <- metadata .: "date"
         synopsisRaw <- metadata .:? "synopsis"
         description <- metadata .:? "description"
         isDraft <- metadata .:? "draft" .!= False
         tags     <- metadata .:? "tags" .!= []
         published <- parseTimeM True defaultTimeLocale dateFormat date
         let url = Text.pack $ '/' : filepath
             parseMaybe text =
               either (const Nothing) Just (parse filepath text)
             postTitle = mTitle >>= parseMaybe
             postPageTitle =
               maybe (incipit prose) plain (content <$> postTitle)
             mSynopsis = synopsisRaw >>= parseMaybe
         return Post{..}

   noMetadataError =
      "Couldn't find a metadata block in file " <> filepath

   dateFormat = "%e %B %Y"
