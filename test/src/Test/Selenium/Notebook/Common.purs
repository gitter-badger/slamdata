{-
Copyright 2015 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

-- | Contains common for all cells tests and
-- | generic tests that are specified in custom modules
-- | (i.e. Test.Selenium.Notebook.Explore)
module Test.Selenium.Notebook.Common where

import Prelude

import Control.Monad.Eff.Random (randomInt)
import Control.Monad.Eff.Class (liftEff)
import Data.List (List(), length, replicateM)
import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (Tuple(..))
import Data.Either (isRight)
import Selenium.ActionSequence
import Test.Selenium.Monad
import Test.Selenium.Log
import Test.Selenium.Common
import Test.Selenium.Notebook.Contexts
import Test.Selenium.Notebook.Getters
import Selenium.Types
import qualified Config as SDConfig
import qualified Data.StrMap as SM
import Utils.Halide (width', height', frameBorder)
import Halogen.HTML.Renderer.String (renderHTMLToString)
import qualified Halogen.HTML as H
import qualified Halogen.HTML.Attributes as A

import Utils.Log

checkNextCells :: SM.StrMap String -> Check Unit
checkNextCells m = do
  traverse_ traverseFn $ SM.toList m
  successMsg "Ok, all next cells are found"
  where
  traverseFn (Tuple msg sel) = void do
    waitExistentCss sel $ msg <> " is not present"


checkInitial :: Check Unit -> Check Unit
checkInitial custom = do
  config <- getConfig
  checkNotExists "Embed button is shown" config.cell.embedButton
  successMsg "Ok, there is no embed button"
  checkNotExists "Next cell menu is show" config.cell.nextCellList
  successMsg "Ok, there is no next cell menu"
  checkNotExists "Cell ouput label is shown" config.cell.cellOutputLabel
  successMsg "Ok, there is no output label"
  checkNotExists "Cell output result is shown" config.cell.cellOutputResult
  successMsg "Ok, there is no output result"
  checkNotExists "Failure messages button is shown" config.cell.showMessages
  successMsg "Ok, there is no show messages button"
  checkNotExists "Failures is shown" config.cell.failures
  successMsg "Ok, there is no failures"
  getElementByCss config.cell.evalLine "There is no eval line, but should"
  successMsg "Ok, there is eval line"
  status <- getStatusText
  successMsg "Ok, status text exists"
  html <- innerHtml status
  if html /= ""
    then errorMsg "Status text should be empty"
    else successMsg "Ok, status text is empty"
  custom 
  value <- getElementByCss config.explore.input "there is no input"
           >>= flip attribute "value"
  if value /= ""
    then errorMsg "value of input should be empty"
    else successMsg "Ok, input value is empty"
  getPlayButton
  successMsg "Ok, there is play button"
  getRefreshButton
  successMsg "Ok, there is refresh button"
  checkNotExists "Hide failures button should not exist" config.cell.hideMessages
  successMsg "Ok, there is no hide failures button"


checkEmbedButton :: Check Unit
checkEmbedButton = do
  config <- getConfig
  embed <- getEmbedButton
  actions $ leftClick embed
  waitCheck (checker $ isRight <$> attempt getModal) config.selenium.waitTime
  modal <- getElementByCss config.modal "Modal should be visible"
  box <- getElementByCss config.cell.embedBox "Embed box hidden"
  value <- attribute box "value"
  expected <- expectedValue
  if expected == value
    then successMsg "Ok, embedding cell value is correct"
    else do
    errorMsg $ "Embed value is not correct"
      <> "\nexpected: " <> expected
      <> "\nactual  : " <> value
  reloadAndSpyXHR
  where
  getModal = do
    config <- getConfig 
    getElementByCss config.cell.embedBox "Embed box hidden"
  expectedValue = do
    config <- getConfig 
    pure $ renderHTMLToString $
      H.iframe [ A.src $ url config
               , width' "100%"
               , height' "100%"
               , frameBorder 0
               ] [ ]
  url config =
    config.slamdataUrl <> config.notebookUrl <> "#/" <> config.mount.name <> "/" <>
    config.database.name <> config.explore.notebookPath



checkHideShow :: String -> Check Unit
checkHideShow sel = do
  config <- getConfig
  hide <- css config.cell.hide >>= element
  show <- css config.cell.show >>= element
  case Tuple hide show of
    Tuple Nothing _ -> errorMsg "Incorrect hide/show state"
    Tuple _ (Just _) -> errorMsg "Incorrect hide/show state"
    Tuple (Just hider) _ -> do
      editor <- getElementByCss sel "cell editor not found"
      actions $ leftClick hider
      mbEditor <- css sel >>= element
      case mbEditor of
        Just _ -> errorMsg "hide editor doesn't work"
        Nothing -> do
          newHide <- css config.cell.hide >>= element
          newShow <- css config.cell.show >>= element
          case Tuple newHide newShow of
            Tuple (Just _) _ -> errorMsg "Incorrect hide/show state after hiding"
            Tuple _ Nothing -> errorMsg "Incorrect hide/show state after hiding"
            Tuple _ (Just shower) -> do
              actions $ leftClick shower
              getElementByCss sel "cell editor not found"
              successMsg "Ok, hide/show button works"

checkDeleting :: Check (List Element) -> Check Unit
checkDeleting lstCheck = do
  deleteAllCells
  count <- length <$> lstCheck
  if count > 0
    then errorMsg "There are cell after deleting"
    else pure unit
  successMsg "Ok, deleted"
  waitTime (SDConfig.autosaveTick * 2)
  reloadAndSpyXHR
  reloadedCount <- length <$> lstCheck
  if reloadedCount > 0
    then errorMsg "Deleting have no effect"
    else pure unit
  successMsg "Ok, deleted in database"


checkMakeCell :: Check (List Element) -> Check Unit -> Check Unit
checkMakeCell lstCheck mkCell = do
  count <- length <$> lstCheck
  if count /= 0
    then errorMsg "Notebook already has cells"
    else pure unit
  toMake <- liftEff $ randomInt 1 20
  replicateM toMake mkCell
  await "Not all cells was created" do
    ((== toMake) <<< length) <$> lstCheck
  waitTime (SDConfig.autosaveTick * 2)
  reloadAndSpyXHR
  await "Cells have not been saved" do
    ((== toMake) <<< length) <$> lstCheck
  successMsg "Ok, cells have been saved"


checkNewCellMenu :: Check Unit
checkNewCellMenu = do
  expand <- getNewCellMenuTrigger
  html <- innerHtml expand
  vis <- newCellMenuExpanded
  if vis
    then errorMsg "At least one of new cell menu button is visible"
    else pure unit 
  successMsg "Ok, initial new cell menu is collapsed"
  actions $ leftClick expand
  await "Expand/collapse button has not been changed" do 
    newHtml <- innerHtml expand
    pure $ newHtml /= html
  newVis <- newCellMenuExpanded
  if not newVis
    then errorMsg "At least one of new cell menu is not visible after expanding"
    else pure unit 
  successMsg "Ok, expanded"
  -- checking collapse
  actions $ leftClick expand
  await "Expand/collapse butotn has not returned to default state" do
    collapsedHtml <- innerHtml expand
    pure $ collapsedHtml == html
  collapsedVis <- newCellMenuExpanded
  if collapsedVis
    then errorMsg "At least one of new cell menu button is visible after collapse"
    else successMsg "Ok, collapsed"

-- | This check passes if cel errors after click on `btn`
checkIncorrect :: Check Element -> Check Unit
checkIncorrect btnCheck = do
  btn <- btnCheck
  config <- getConfig
  actions $ leftClick btn
  failures <- waitExistentCss config.cell.failures "There is no failures but should"
  html <- innerHtml failures 
  show <- getElementByCss config.cell.showMessages "There is no showMessages but should"
  actions $ leftClick show
  await "There is no difference between hidden and shown failures" do
    shownHtml <- innerHtml failures
    pure $ shownHtml /= html
  successMsg "Ok, shown failures is defferent with hidden"
  hide <- waitExistentCss config.cell.hideMessages "There is no hideMessages"
  actions $ leftClick hide
  await "Hidden failures are not equal with initial" do 
    hiddenHtml <- innerHtml failures
    pure $ hiddenHtml == html
  successMsg "Ok, hidden failures is equal with initial"

checkTableEmpty :: Check Unit
checkTableEmpty = do
  config <- getConfig
  waitNotExistentCss "There should not be failures" config.cell.failures
  waitOutputLabel
  table <- waitExistentCss "table" "There is no table"
  tableHtml <- innerHtml table
  if tableHtml == "<thead></thead><tbody></tbody>"
    then successMsg "Ok, table is empty"
    else errorMsg "Table should be empty"

test :: Check Unit
test = do
  sectionMsg "check notebook page loaded"
  notebookLoaded

  sectionMsg "check new cell menu"
  checkNewCellMenu
