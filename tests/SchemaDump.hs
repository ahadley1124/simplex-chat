{-# LANGUAGE OverloadedStrings #-}

module SchemaDump where

import ChatClient (withTmpFiles)
import Control.DeepSeq
import Control.Monad (void)
import Simplex.Chat.Store (createChatStore)
import System.Process (readCreateProcess, shell)
import Test.Hspec

testDB :: FilePath
testDB = "tests/tmp/test_chat.db"

schema :: FilePath
schema = "src/Simplex/Chat/Migrations/chat_schema.sql"

schemaDumpTest :: Spec
schemaDumpTest =
  it "verify and overwrite schema dump" testVerifySchemaDump

testVerifySchemaDump :: IO ()
testVerifySchemaDump =
  withTmpFiles $ do
    void $ createChatStore testDB "" False
    void $ readCreateProcess (shell $ "touch " <> schema) ""
    savedSchema <- readFile schema
    savedSchema `deepseq` pure ()
    void $ readCreateProcess (shell $ "sqlite3 " <> testDB <> " '.schema --indent' > " <> schema) ""
    currentSchema <- readFile schema
    savedSchema `shouldBe` currentSchema
