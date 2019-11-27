{-# LANGUAGE RebindableSyntax, NoMonomorphismRestriction #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}
module CLI ( runCLI ) where

import Data.String

import Prelude hiding ( (>>) )

import Options.Applicative

import Options ( Options(..) )

(>>) = (<>)

runCLI :: ParserInfo Options
runCLI = info parseCLI mempty

parseCLI :: Parser Options
parseCLI = Options
  <$> strOption do
        long "input-dir"
        metavar "DIRECTORY"
        help "Where to search for input files."
  <*> strOption do
        long "output-dir"
        metavar "DIRECTORY"
        help "Where to put the finished site."
  <*> switch do
        long "include-drafts"
        help "Build drafts too."
  <*> switch do
        long "include-tags"
        help "Also display tags on the site."
