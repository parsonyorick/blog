module Main where

import Introit
import Control.Exception
import Data.List ( sortOn )
import Data.Ord ( Down(..) )
import Data.Typeable ( Typeable )
import qualified Text

import Data.Time.Format ( parseTimeM, defaultTimeLocale )
import Data.Yaml ( (.:) )
import qualified Data.Yaml as Yaml
import Development.Shake
import Development.Shake.Config
import Development.Shake.FilePath
import Network.URI ( parseAbsoluteURI )
import System.Directory ( createDirectoryIfMissing )
import qualified Cheapskate
import Text.Blaze.Html ( Html )
import qualified Text.Blaze.Html.Renderer.String as Blaze
import qualified Text.Sass as Sass

import Pages
import Post
import Site


localConfigFile, productionConfigFile :: FilePath
localConfigFile = "config.local"
productionConfigFile = "config.live"

stylesDir, buildDir, postsDir :: FilePath
stylesDir = "styles"
buildDir = "_site"
postsDir = "posts"


main :: IO ()
main = do
  hsSourceFiles <- getDirectoryFilesIO "" ["*.hs"]
  shakeVersion <- getHashedShakeVersion hsSourceFiles
  shakeArgs shakeOptions{ shakeVersion
                        , shakeThreads = 3
                        , shakeColor = True } $ do

    usingConfigFile localConfigFile

    getPost <- newCache readPostFromFile

    getAllPostSourceFiles <- fmap ($ ()) $ newCache $ \() ->
        map (postsDir </>) <$> getDirectoryFiles postsDir ["*.md"]

    getAllPosts <- fmap ($ ()) $ newCache $ \() -> do
        posts <- traverse getPost =<< getAllPostSourceFiles
        let (errors, successes) = partitionEithers posts
        -- We log the same errors individualy in getPost.
        let sortByDate = sortOn (Down . composed)
        return $ sortByDate successes

    getStylesheets <- fmap ($ ()) $ newCache $ \() ->
        map ((stylesDir </>) . (-<.> "css"))
        <$> getDirectoryFiles stylesDir ["*.scss"]

    let getSiteConfig = do
         Just siteTitle <- fmap Text.pack
            <$> getConfig "site_title"
         Just baseUrl   <- (parseAbsoluteURI =<<)
            <$> getConfig "base_url"
         Just sourceUrl <- (parseAbsoluteURI =<<)
            <$> getConfig "source_url"
         copyrightYear  <- fromMaybe 2018 <$> fmap read
            <$> getConfig "copyright"
         author         <- Text.pack <$> fromMaybe "Anonymous"
            <$> getConfig "author"
         styleSheets    <- getStylesheets
         return Site.Configuration
            { siteTitle
            , baseUrl
            , sourceUrl
            , copyrightYear
            , author
            , styleSheets }

    action $ do
        posts <- map (-<.> "html") <$> getAllPostSourceFiles
        styles <- getStylesheets
        let pages = ["archive.html", "index.html"]
        need $ map (buildDir </>) (styles <> pages <> posts)

    (buildDir </> postsDir </> "*.html") %> \out -> do
        let src = dropDirectory1 out -<.> "md"
        thisPostOrError <- getPost src
        siteConfig <- getSiteConfig
        ($ thisPostOrError)
         $ either (putQuiet . (("Error in " <> src <> ", namely: ") <>) . whatHappened)
         $ \thisPost -> do
            let html = Pages.post thisPost siteConfig
            renderHtmlToFile out html

    (buildDir </> "index.html") %> \out -> do
        allPosts <- getAllPosts
        siteConfig <- getSiteConfig
        renderHtmlToFile out (Pages.home allPosts siteConfig)

    (buildDir </> "archive.html") %> \out -> do
        allPosts <- getAllPosts
        siteConfig <- getSiteConfig
        renderHtmlToFile out (Pages.archive allPosts siteConfig)

    (buildDir </> stylesDir </> "*.css") %> \out -> do
        let src = dropDirectory1 out -<.> "scss"
        need [src]
        scssOrError <- liftIO $ Sass.compileFile src Sass.def
        case scssOrError of
            Left err -> do
                message <- liftIO $ Sass.errorMessage err
                putQuiet ("Error in " <> src <> ", namely: " <> show message)
            Right scss -> do
                liftIO $ createDirectoryIfMissing True (takeDirectory out)
                liftIO $ writeFile out scss


renderHtmlToFile :: FilePath -> Html -> Action ()
renderHtmlToFile out markup = do
    let html = Blaze.renderHtml markup
    liftIO $ createDirectoryIfMissing True (takeDirectory out)
    liftIO $ writeFile out html

readPostFromFile :: FilePath -> Action (Either Whoops Post)
readPostFromFile filepath = do
    need [filepath]
    contents <- liftIO $ Text.readFile filepath
    return $ do
      (meta, body) <- extractMetadataBlockAndBody contents
      reconstructPost meta body

 where
   extractMetadataBlockAndBody :: Text -> Either Whoops (Yaml.Value, Cheapskate.Doc)
   extractMetadataBlockAndBody stuff = do
      afterFirstMarker <-
         maybe (Left noMetadataBlockError) Right
         (Text.stripPrefix metadataBlockMarker stuff)
      let (metadataBlock, rest) =
            Text.breakOn metadataBlockMarker afterFirstMarker
      body <-
         maybe (Left noBodyError) Right
         (Text.stripPrefix metadataBlockMarker rest)
      yaml <-
         (first Whoops . Yaml.decodeEither . Text.encodeUtf8)
         metadataBlock
      let markdown =
            Cheapskate.markdown Cheapskate.def body
      return (yaml, markdown)

   metadataBlockMarker = "---"

   noMetadataBlockError = Whoops $
      "Expecting initial metadata block marker, namely \""
      <> Text.unpack metadataBlockMarker
      <> "\", in " <> filepath
      <> ", but it wasn't there."

   noBodyError = Whoops $
      "There is no text body following the metadata block in " <> filepath <> "."

   reconstructPost :: Yaml.Value -- ^ Markdown body.
                   -> Cheapskate.Doc -- ^ YAML metadata block.
                   -> Either Whoops Post
   reconstructPost yaml content = first Whoops $ ($ yaml) $ Yaml.parseEither $
      Yaml.withObject "metadata" $ \metadata -> do
         title    <- metadata .: "title"
         date     <- metadata .: "date"
         synopsis <- metadata .: "synopsis"
         composed <- parseTimeM True defaultTimeLocale dateFormat date
         let slug = (Text.pack . takeBaseName) filepath
         return Post{ title
                    , synopsis = Cheapskate.markdown Cheapskate.def synopsis
                    , slug
                    , composed
                    -- TODO: Distinguish these --- maybe.
                    , published = composed
                    , content }

   dateFormat = "%e %B %Y"


newtype Whoops = Whoops { whatHappened :: String } deriving ( Typeable )

instance Show Whoops where
   show = show . whatHappened

instance Exception Whoops
