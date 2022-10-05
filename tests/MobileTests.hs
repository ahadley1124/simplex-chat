{-# LANGUAGE CPP #-}

module MobileTests where

import ChatClient
import ChatTests
import Control.Monad.Except
import Simplex.Chat.Mobile
import Simplex.Chat.Store
import Test.Hspec

mobileTests :: Spec
mobileTests = do
  describe "mobile API" $ do
    it "start new chat without user" testChatApiNoUser
    it "start new chat with existing user" testChatApi

noActiveUser :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
noActiveUser = "{\"resp\":{\"chatCmdError\":{\"chatError\":{\"error\":{\"errorType\":{\"noActiveUser\":{}}}}}}}"
#else
noActiveUser = "{\"resp\":{\"type\":\"chatCmdError\",\"chatError\":{\"type\":\"error\",\"errorType\":{\"type\":\"noActiveUser\"}}}}"
#endif

activeUserExists :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
activeUserExists = "{\"resp\":{\"chatCmdError\":{\"chatError\":{\"error\":{\"errorType\":{\"activeUserExists\":{}}}}}}}"
#else
activeUserExists = "{\"resp\":{\"type\":\"chatCmdError\",\"chatError\":{\"type\":\"error\",\"errorType\":{\"type\":\"activeUserExists\"}}}}"
#endif

activeUser :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
activeUser = "{\"resp\":{\"activeUser\":{\"user\":{\"userId\":1,\"userContactId\":1,\"localDisplayName\":\"alice\",\"profile\":{\"profileId\":1,\"displayName\":\"alice\",\"fullName\":\"Alice\",\"localAlias\":\"\"},\"activeUser\":true}}}}"
#else
activeUser = "{\"resp\":{\"type\":\"activeUser\",\"user\":{\"userId\":1,\"userContactId\":1,\"localDisplayName\":\"alice\",\"profile\":{\"profileId\":1,\"displayName\":\"alice\",\"fullName\":\"Alice\",\"localAlias\":\"\"},\"activeUser\":true}}}"
#endif

chatStarted :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
chatStarted = "{\"resp\":{\"chatStarted\":{}}}"
#else
chatStarted = "{\"resp\":{\"type\":\"chatStarted\"}}"
#endif

contactSubSummary :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
contactSubSummary = "{\"resp\":{\"contactSubSummary\":{\"contactSubscriptions\":[]}}}"
#else
contactSubSummary = "{\"resp\":{\"type\":\"contactSubSummary\",\"contactSubscriptions\":[]}}"
#endif

memberSubSummary :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
memberSubSummary = "{\"resp\":{\"memberSubSummary\":{\"memberSubscriptions\":[]}}}"
#else
memberSubSummary = "{\"resp\":{\"type\":\"memberSubSummary\",\"memberSubscriptions\":[]}}"
#endif

pendingSubSummary :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
pendingSubSummary = "{\"resp\":{\"pendingSubSummary\":{\"pendingSubscriptions\":[]}}}"
#else
pendingSubSummary = "{\"resp\":{\"type\":\"pendingSubSummary\",\"pendingSubscriptions\":[]}}"
#endif

parsedMarkdown :: String
#if defined(darwin_HOST_OS) && defined(swiftJSON)
parsedMarkdown = "{\"formattedText\":[{\"format\":{\"bold\":{}},\"text\":\"hello\"}]}"
#else
parsedMarkdown = "{\"formattedText\":[{\"format\":{\"type\":\"bold\"},\"text\":\"hello\"}]}"
#endif

testChatApiNoUser :: IO ()
testChatApiNoUser = withTmpFiles $ do
  Right cc <- chatMigrateInit testDBPrefix ""
  Left (DBMErrorNotADatabase _) <- chatMigrateInit testDBPrefix "myKey"
  chatSendCmd cc "/u" `shouldReturn` noActiveUser
  chatSendCmd cc "/_start" `shouldReturn` noActiveUser
  chatSendCmd cc "/u alice Alice" `shouldReturn` activeUser
  chatSendCmd cc "/_start" `shouldReturn` chatStarted

testChatApi :: IO ()
testChatApi = withTmpFiles $ do
  let dbPrefix = testDBPrefix <> "1"
      f = chatStoreFile dbPrefix
  st <- createChatStore f "myKey" True
  Right _ <- withTransaction st $ \db -> runExceptT $ createUser db aliceProfile True
  Right cc <- chatMigrateInit dbPrefix "myKey"
  Left (DBMErrorNotADatabase _) <- chatMigrateInit dbPrefix ""
  Left (DBMErrorNotADatabase _) <- chatMigrateInit dbPrefix "anotherKey"
  chatSendCmd cc "/u" `shouldReturn` activeUser
  chatSendCmd cc "/u alice Alice" `shouldReturn` activeUserExists
  chatSendCmd cc "/_start" `shouldReturn` chatStarted
  chatRecvMsg cc `shouldReturn` contactSubSummary
  chatRecvMsg cc `shouldReturn` memberSubSummary
  chatRecvMsgWait cc 10000 `shouldReturn` pendingSubSummary
  chatRecvMsgWait cc 10000 `shouldReturn` ""
  chatParseMarkdown "hello" `shouldBe` "{}"
  chatParseMarkdown "*hello*" `shouldBe` parsedMarkdown
