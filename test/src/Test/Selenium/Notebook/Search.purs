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

module Test.Selenium.Notebook.Search
       (test)
       where

import Prelude
import Control.Monad.Eff.Random (randomInt)
import Control.Monad.Eff.Class (liftEff)
import Data.Foldable (for_, traverse_)
import Data.Traversable (traverse)
import Data.List (replicateM, length, (!!))
import Data.Maybe (Maybe(..), fromMaybe)
import Selenium.Types
import Selenium.ActionSequence (leftClick, sendKeys)
import Test.Config (SearchQueryConfig(), platformFromConfig)
import Test.Selenium.Monad
import Test.Selenium.Log
import Test.Selenium.Common
import Test.Selenium.Types
import Test.Selenium.Notebook.Contexts
import Test.Selenium.Notebook.Getters

import qualified Data.String as S
import qualified Data.String.Regex as R
import qualified Config as SDConfig
import qualified Test.Selenium.Notebook.Common as C
import qualified Test.Selenium.Notebook.FileList as FL


checkInitialSearch :: Check Unit
checkInitialSearch =
  withSearchCell $ C.checkInitial do
    config <- getConfig
    value <- getElementByCss config.searchCell.fileListInput "there is no file list"
             >>= flip attribute "value"
    if value /= ""
      then errorMsg "file list should be empty"
      else pure unit

    search <- getElementByCss config.searchCell.searchInput "there is no search input"
              >>= flip attribute "value"
    if value /= ""
      then errorMsg "search input should be empty"
      else pure unit
    successMsg "Ok, initial values are empty"
    getElementByCss config.searchCell.searchButton "There is no search button"
    getElementByCss config.searchCell.searchClear "There is no search clear"
    successMsg "Ok, all needed elements are present"


checkIncorrectInputs :: Check Unit
checkIncorrectInputs = do
  for_ [getPlayButton, getRefreshButton, getSearchButton] \btnCheck -> do
    checkBothEmpty btnCheck
    checkFileListEmpty btnCheck
    checkSearchEmpty btnCheck
    checkInexistentFileMounted btnCheck
    checkInexistentFileNotMounted btnCheck
    checkDirectoryFailure btnCheck
    checkSearchIncorrect btnCheck


checkBothEmpty :: Check Element -> Check Unit
checkBothEmpty btnCheck = do
  withSearchCell $ C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when both inputs are empty"

checkFileListEmpty :: Check Element -> Check Unit
checkFileListEmpty btnCheck = do
  withSearchCell do
    config <- getConfig
    input <- getSearchInput
    actions do
      leftClick input
      sendKeys config.searchCell.allQuery
    C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when file list is empty"

checkSearchEmpty :: Check Element -> Check Unit
checkSearchEmpty btnCheck = do
  withSearchCell do
    config <- getConfig
    input <- getSearchFileList
    actions do
      leftClick input 
      sendKeys config.explore.smallZips
    C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when search input is empty"

checkInexistentFileMounted :: Check Element -> Check Unit
checkInexistentFileMounted btnCheck = do
  withSearchCell do
    config <- getConfig
    fl <- getSearchFileList
    ip <- getSearchInput
    actions do
      leftClick fl
      sendKeys config.explore.mounted
      leftClick ip
      sendKeys config.searchCell.allQuery
    C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when file list contains incorrect mounted file"


checkInexistentFileNotMounted :: Check Element -> Check Unit
checkInexistentFileNotMounted btnCheck  = withSearchCell do
  config <- getConfig
  input <- getSearchFileList
  actions do
    leftClick input
    sendKeys config.explore.notMounted
  C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when file list contains unmounted file"

checkDirectoryFailure :: Check Element -> Check Unit
checkDirectoryFailure btnCheck = withSearchCell do
  config <- getConfig
  input <- getSearchFileList
  actions do
    leftClick input
    sendKeys config.explore.notMounted
  C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when file list contains directory"

checkSearchIncorrect :: Check Element -> Check Unit
checkSearchIncorrect btnCheck = withSearchCell do
  btn <- btnCheck
  config <- getConfig
  fl <- getSearchFileList
  ip <- getSearchInput
  actions do
    leftClick fl
    sendKeys config.explore.smallZips
    leftClick ip
    sendKeys config.searchCell.incorrectQuery
    leftClick btn
  C.checkIncorrect btnCheck
  successMsg "Ok, expected behaviour when search input contains incorrect query"


checkSearchClear :: Check Unit
checkSearchClear = withSearchCell do
  clear <- getSearchClear
  ip <- getSearchInput
  actions do 
    leftClick ip
    sendKeys "foo bar baz"
  await "value of search input has not been setted" do
    (== "foo bar baz") <$> attribute ip "value" 

  successMsg "Ok, correct value in search input"
  
  actions $ leftClick clear
  await "value of search input has not been cleared" do
    (== "") <$> attribute ip "value"

  successMsg "Ok, value has been cleared"
  
checkSearchStop :: Check Unit
checkSearchStop = withSearchCell do
  config <- getConfig
  clear <- getSearchClear
  ip <- getSearchInput
  fl <- getSearchFileList
  play <- getPlayButton
  startSrc <- attribute clear "src"
  actions do
    leftClick fl
    sendKeys config.explore.smallZips
    leftClick ip
    sendKeys config.searchCell.allQuery
    leftClick play
  await "Src has not been changed" do
    (== startSrc) <$> (attribute clear "src")
  successMsg "Ok, src of search-clear has changed"
  actions do
    leftClick clear
  await "Search stop doesn't work" do
    src <- attribute clear "src"
    val <- attribute ip "value"
    pure $ val == "" && src == startSrc
  successMsg "Ok, search stopped"

checkOutputLabel :: Check Unit
checkOutputLabel = do
  config <- getConfig
  dummy <- liftEff $ randomInt 0 20
  replicateM dummy makeMarkdownCell
  makeSearchCell
  deleteCells getMdCells
  fileSearched config.explore.smallZips config.searchCell.allQuery do 
    label <- waitOutputLabel >>= innerHtml
    if extracted label /= ("out" <> show dummy)
      then errorMsg "Incorrect output"
      else successMsg "Ok, correct output"
  deleteAllCells
  where
  extracted content =
    S.trim $ R.replace (R.regex "^([^:]+).+$" R.noFlags) "$1" content


checkNextSearchCell :: String -> Check Unit
checkNextSearchCell expected = do
  config <- getConfig
  waitNextCellSearch >>= actions <<< leftClick
  await "Search cell has not been created" do
    ((== 2) <<< length) <$> getCells
  vals <- css config.searchCell.fileListInput
          >>= elements
          >>= traverse (flip attribute "value")
  if (vals !! 1) == (Just expected)
    then successMsg "Ok, correct next search cell value"
    else errorMsg $ "Incorrect next search cell value:"
         <> "\nexpected: " <> expected
         <> "\nactual  : " <> fromMaybe "" (vals !! 1)
  deleteAllCells


checkQuery :: SearchQueryConfig -> Check Unit
checkQuery conf = withSmallZipsSearchedAll do
  sectionMsg conf.query
  config <- getConfig
  ip <- getSearchInput
  btn <- getPlayButton
  
  fbEnabled <- (_.fb <<< runEnabledRecord) <$> getEnabledRecord 
  if not fbEnabled
    then pure unit
    else do
    afterTableChanged (getFastBackward >>= actions <<< leftClick)

  let platform = platformFromConfig config
  afterTableChanged $ actions do
    leftClick ip
    sendSelectAll platform
    sendDelete
    sendKeys conf.query 
    leftClick btn
  
  ffEnabled <- (_.ff <<< runEnabledRecord) <$> getEnabledRecord
  if not ffEnabled
    then pure unit
    else do
    afterTableChanged (getFastForward >>= actions <<< leftClick)

    
  {table: tableCount, pager: pagerCount} <- getRowCount
  if tableCount == conf.rows
     && pagerCount == 10
    then successMsg "Ok, correct row count"
    else errorMsg $ "Incorrect row count:"
         <> "\nin table: " <> show tableCount
         <> "\nin pager: " <> show pagerCount
         <> "\nshould be in table: " <> show conf.rows
         <> "\nshould be in pager: 10"
         
  count <- getPageCount
  if count == conf.pages
    then successMsg "Ok, correct page count"
    else errorMsg "Incorrect page count"

checkQueries :: Check Unit
checkQueries = 
  getConfig >>= _.searchQueries >>> traverse_ checkQuery 



test :: Check Unit
test = do
  config <- getConfig

  sectionMsg "check initial search state"
  checkInitialSearch

  sectionMsg "check make search cell"
  C.checkMakeCell getSearchCells makeSearchCell
  
  sectionMsg "check deleting search cells"
  C.checkDeleting getSearchCells
  
  sectionMsg "check file list in search cell"
  FL.test withSearchCell

  sectionMsg "check show/hide search editor"
  withSearchCell $ C.checkHideShow config.cell.searchEditor

  sectionMsg "check incorrect inputs"
  checkIncorrectInputs

  sectionMsg "check embed inputs"
  withSmallZipsSearchedAll C.checkEmbedButton 

  sectionMsg "check value clear"
  checkSearchClear

  sectionMsg "check search stop"
  checkSearchStop

  sectionMsg "check output label"
  checkOutputLabel 

  sectionMsg "check next search cell (explore)"
  withSmallZipsOpened $ checkNextSearchCell config.explore.smallZips 

  sectionMsg "check next search cell (search)"
  withSmallZipsSearchedAll $ checkNextSearchCell
    $  "/" <> config.mount.name 
    <> "/" <> config.database.name
    <> "/" <> Config.newNotebookName
    <> "." <> Config.notebookExtension
    <> "/" <> "out0"

  sectionMsg "check queries"
  checkQueries
