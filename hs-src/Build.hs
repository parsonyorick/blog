{-# LANGUAGE NondecreasingIndentation #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}
module Build ( Options(..), build )where

import Introit
import Data.List ( sortOn )

import Control.Monad.Trans.Reader
import Development.Shake
import Development.Shake.Config
import Development.Shake.FilePath
import qualified Text.Sass as Sass

import Actions
import Post
import qualified Templates
import qualified Routes as R
import Utilities


data Options = Options
   { buildDir :: FilePath
   , postsDir :: FilePath
   , draftsDir :: FilePath
   , stylesDir :: FilePath
   , imagesDir :: FilePath
   , siteConfigFile :: FilePath 
   , includeDrafts :: Bool }


build :: Options -> [String] -> Rules ()
build Options
      { buildDir
      , postsDir
      , stylesDir
      , imagesDir
      , siteConfigFile }
      targets = do

    usingConfigFile siteConfigFile

    getPost <- newCache readPost

    getAllMarkdownSourceFiles <- newCache $ \dir ->
        map (dir </>) <$> getDirectoryFiles dir ["*.md"]

    getAllPosts <- newCache $ \() -> do
        posts <- traverse getPost =<< getAllMarkdownSourceFiles postsDir
        return $ sortOn composed posts

    -- Specify our build targets.
    action $ do
        let pages = [R.Home, R.Archive]
        posts  <- map (R.Post . takeBaseName) <$>
            getAllMarkdownSourceFiles postsDir
        images <- map R.Image <$>
            getDirectoryContents imagesDir
        let styles = [R.Stylesheet "magenta"]
        let allTargets = pages <> posts <> images <> styles
        need $ map ((buildDir </>) . R.targetFile) allTargets

    flip runReaderT buildDir $ do

    templateRule R.Post $ \(R.Post slug) -> do
        thePost <- getPost (postsDir </> slug <.> "md")
        Templates.page (Just (title thePost)) (Templates.post thePost)

    templateRule (const R.Home) $ \R.Home -> do
       allPosts <- getAllPosts ()
       Templates.page Nothing (Templates.home allPosts)

    templateRule (const R.Archive) $ \R.Archive -> do
       allPosts <- getAllPosts ()
       Templates.page (Just "Archive") (Templates.archive allPosts)

    urlRule R.Stylesheet $ \route@(R.Stylesheet basename) buildDir -> do
        let src = stylesDir </> basename <.> "scss"
            file = buildDir </> R.targetFile route
        need [src]
        scssOrError <- liftIO $ Sass.compileFile src Sass.def
        either
          (throwFileError src <=< (liftIO . Sass.errorMessage))
          (liftIO . writeFile file)
          scssOrError

    urlRule R.Image $ \route@(R.Image filename) buildDir -> do
        let src = imagesDir </> filename
            file = buildDir </> R.targetFile route
        copyFile' src file
