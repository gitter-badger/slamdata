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

module Test.Selenium.Monad where

import Prelude
import Control.Monad.Error.Class (throwError)
import Control.Monad.Eff.Exception (error)
import Data.Either
import Data.Maybe
import Data.Foreign (Foreign())
import Data.Maybe.Unsafe (fromJust)
import Data.List
import DOM
import Test.Config (Config())
import Selenium
import Selenium.ActionSequence
import Selenium.Types
import Control.Monad.Eff.Console (CONSOLE())
import Control.Monad.Trans
import Control.Monad.Reader.Trans
import Control.Monad.Reader.Class
import qualified Control.Monad.Aff as A


type Check a = ReaderT { config :: Config, driver :: Driver }
               (A.Aff (console :: CONSOLE, selenium :: SELENIUM, dom :: DOM)) a


-- READER
getDriver :: Check Driver
getDriver = _.driver <$> ask

getConfig :: Check Config
getConfig = _.config <$> ask


-- AFF
apathize :: forall a. Check a -> Check Unit
apathize check = ReaderT \r ->
  A.apathize $ runReaderT check r

attempt :: forall a. Check a -> Check (Either _ a)
attempt check = ReaderT \r ->
  A.attempt $ runReaderT check r

later :: forall a. Int -> Check a -> Check a
later time check = ReaderT \r ->
  A.later' time $ runReaderT check r

retry :: forall a. Int -> Check a -> Check a
retry n action = do
  res <- attempt action
  case res of
    Left e -> if n > one
              then retry (n - one) action
              else lift $ throwError $ error "To many retries"
    Right r -> pure r 

-- SELENIUM
goTo :: String -> Check Unit
goTo url = do
  driver <- getDriver
  lift $ get driver url

waitCheck :: Check Boolean -> Int -> Check Unit
waitCheck check time = ReaderT \r -> do
  wait (runReaderT check r) time r.driver

css :: String -> Check Locator
css = lift <<< byCss

xpath :: String -> Check Locator
xpath = lift <<< byXPath

checkLocator :: (Element -> Check Element) -> Check Locator
checkLocator checkFn = ReaderT \r ->
  affLocator (\el -> runReaderT (checkFn el) r)

element :: Locator -> Check (Maybe Element)
element locator = do
  driver <- getDriver
  lift $ findElement driver locator

elements :: Locator -> Check (List Element)
elements locator = do
  driver <- getDriver
  lift $ findElements driver locator

child :: Element -> Locator -> Check (Maybe Element)
child el loc = lift $ findChild el loc

children :: Element -> Locator -> Check (List Element)
children el loc = lift $ findChildren el loc

innerHtml :: Element -> Check String
innerHtml  = lift <<< getInnerHtml

visible :: Element -> Check Boolean
visible = lift <<< isDisplayed

enabled :: Element -> Check Boolean
enabled = lift <<< isEnabled

getCss :: Element -> String -> Check String
getCss el key = lift $ getCssValue el key

attribute :: Element -> String -> Check String
attribute el attr = lift $ getAttribute el attr

clear :: Element -> Check Unit
clear = lift <<< clearEl

keys :: String -> Element -> Check Unit
keys ks el = lift $ sendKeysEl ks el

script :: String -> Check Foreign
script str = do
  driver <- getDriver
  lift $ executeStr driver str

getURL :: Check String
getURL = do
  getDriver >>= getCurrentUrl >>> lift

back :: Check Unit
back = do
  driver <- getDriver
  lift $ navigateBack driver

title :: Check String
title = do
  getDriver >>= getTitle >>> lift

actions :: Sequence Unit -> Check Unit
actions seq = do
  driver <- getDriver
  lift $ sequence driver seq

checker :: Check Boolean -> Check Boolean
checker check = do
  res <- check
  if res
    then pure true
    else later 500 $ checker check

-- | This repeats its argument until it returns just; this is only sensible in
-- | case the output of the passed check over time is monotonic.
waitUntilJust :: forall a. Check (Maybe a) -> Int -> Check a
waitUntilJust check time = do
  waitCheck (checker $ isJust <$> check) time
  fromJust <$> check

stop :: Check Unit
stop = waitCheck (later top $ pure false) top

waitTime :: Int -> Check Unit
waitTime n = later n $ pure unit 

reload :: Check Unit
reload = getDriver >>= refresh >>> lift
