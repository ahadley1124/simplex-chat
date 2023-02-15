{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}

module Simplex.Chat.Messages where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as J
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Time.Clock (UTCTime, diffUTCTime, nominalDay)
import Data.Time.LocalTime (TimeZone, ZonedTime, utcToZonedTime)
import Data.Type.Equality
import Data.Typeable (Typeable)
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))
import GHC.Generics (Generic)
import Simplex.Chat.Markdown
import Simplex.Chat.Protocol
import Simplex.Chat.Types
import Simplex.Messaging.Agent.Protocol (AgentMsgId, MsgErrorType (..), MsgMeta (..), SwitchPhase (..))
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Parsers (dropPrefix, enumJSON, fromTextField_, fstToLower, singleFieldJSON, sumTypeJSON)
import Simplex.Messaging.Protocol (MsgBody)
import Simplex.Messaging.Util (eitherToMaybe, safeDecodeUtf8, (<$?>))

data ChatType = CTDirect | CTGroup | CTContactRequest | CTContactConnection
  deriving (Eq, Show, Ord, Generic)

data ChatName = ChatName ChatType Text
  deriving (Show)

chatTypeStr :: ChatType -> String
chatTypeStr = \case
  CTDirect -> "@"
  CTGroup -> "#"
  CTContactRequest -> "<@"
  CTContactConnection -> ":"

chatNameStr :: ChatName -> String
chatNameStr (ChatName cType name) = chatTypeStr cType <> T.unpack name

data ChatRef = ChatRef ChatType Int64
  deriving (Eq, Show, Ord)

instance ToJSON ChatType where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CT"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CT"

data ChatInfo (c :: ChatType) where
  DirectChat :: Contact -> ChatInfo 'CTDirect
  GroupChat :: GroupInfo -> ChatInfo 'CTGroup
  ContactRequest :: UserContactRequest -> ChatInfo 'CTContactRequest
  ContactConnection :: PendingContactConnection -> ChatInfo 'CTContactConnection

deriving instance Show (ChatInfo c)

chatInfoChatTs :: ChatInfo c -> Maybe UTCTime
chatInfoChatTs = \case
  DirectChat Contact {chatTs} -> chatTs
  GroupChat GroupInfo {chatTs} -> chatTs
  _ -> Nothing

chatInfoUpdatedAt :: ChatInfo c -> UTCTime
chatInfoUpdatedAt = \case
  DirectChat Contact {updatedAt} -> updatedAt
  GroupChat GroupInfo {updatedAt} -> updatedAt
  ContactRequest UserContactRequest {updatedAt} -> updatedAt
  ContactConnection PendingContactConnection {updatedAt} -> updatedAt

chatInfoToRef :: ChatInfo c -> ChatRef
chatInfoToRef = \case
  DirectChat Contact {contactId} -> ChatRef CTDirect contactId
  GroupChat GroupInfo {groupId} -> ChatRef CTGroup groupId
  ContactRequest UserContactRequest {contactRequestId} -> ChatRef CTContactRequest contactRequestId
  ContactConnection PendingContactConnection {pccConnId} -> ChatRef CTContactConnection pccConnId

data JSONChatInfo
  = JCInfoDirect {contact :: Contact}
  | JCInfoGroup {groupInfo :: GroupInfo}
  | JCInfoContactRequest {contactRequest :: UserContactRequest}
  | JCInfoContactConnection {contactConnection :: PendingContactConnection}
  deriving (Generic)

instance ToJSON JSONChatInfo where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCInfo"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCInfo"

instance ToJSON (ChatInfo c) where
  toJSON = J.toJSON . jsonChatInfo
  toEncoding = J.toEncoding . jsonChatInfo

jsonChatInfo :: ChatInfo c -> JSONChatInfo
jsonChatInfo = \case
  DirectChat c -> JCInfoDirect c
  GroupChat g -> JCInfoGroup g
  ContactRequest g -> JCInfoContactRequest g
  ContactConnection c -> JCInfoContactConnection c

data AChatInfo = forall c. AChatInfo (SChatType c) (ChatInfo c)

deriving instance Show AChatInfo

instance ToJSON AChatInfo where
  toJSON (AChatInfo _ c) = J.toJSON c
  toEncoding (AChatInfo _ c) = J.toEncoding c

data ChatItem (c :: ChatType) (d :: MsgDirection) = ChatItem
  { chatDir :: CIDirection c d,
    meta :: CIMeta d,
    content :: CIContent d,
    formattedText :: Maybe MarkdownList,
    quotedItem :: Maybe (CIQuote c),
    file :: Maybe (CIFile d)
  }
  deriving (Show, Generic)

instance MsgDirectionI d => ToJSON (ChatItem c d) where
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

data CIDirection (c :: ChatType) (d :: MsgDirection) where
  CIDirectSnd :: CIDirection 'CTDirect 'MDSnd
  CIDirectRcv :: CIDirection 'CTDirect 'MDRcv
  CIGroupSnd :: CIDirection 'CTGroup 'MDSnd
  CIGroupRcv :: GroupMember -> CIDirection 'CTGroup 'MDRcv

deriving instance Show (CIDirection c d)

data JSONCIDirection
  = JCIDirectSnd
  | JCIDirectRcv
  | JCIGroupSnd
  | JCIGroupRcv {groupMember :: GroupMember}
  deriving (Generic, Show)

instance ToJSON JSONCIDirection where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCI"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCI"

instance ToJSON (CIDirection c d) where
  toJSON = J.toJSON . jsonCIDirection
  toEncoding = J.toEncoding . jsonCIDirection

jsonCIDirection :: CIDirection c d -> JSONCIDirection
jsonCIDirection = \case
  CIDirectSnd -> JCIDirectSnd
  CIDirectRcv -> JCIDirectRcv
  CIGroupSnd -> JCIGroupSnd
  CIGroupRcv m -> JCIGroupRcv m

data CChatItem c = forall d. MsgDirectionI d => CChatItem (SMsgDirection d) (ChatItem c d)

deriving instance Show (CChatItem c)

instance ToJSON (CChatItem c) where
  toJSON (CChatItem _ ci) = J.toJSON ci
  toEncoding (CChatItem _ ci) = J.toEncoding ci

chatItemId' :: ChatItem c d -> ChatItemId
chatItemId' ChatItem {meta = CIMeta {itemId}} = itemId

chatItemTs :: CChatItem c -> UTCTime
chatItemTs (CChatItem _ ci) = chatItemTs' ci

chatItemTs' :: ChatItem c d -> UTCTime
chatItemTs' ChatItem {meta = CIMeta {itemTs}} = itemTs

chatItemTimed :: ChatItem c d -> Maybe CITimed
chatItemTimed ChatItem {meta = CIMeta {itemTimed}} = itemTimed

data ChatDirection (c :: ChatType) (d :: MsgDirection) where
  CDDirectSnd :: Contact -> ChatDirection 'CTDirect 'MDSnd
  CDDirectRcv :: Contact -> ChatDirection 'CTDirect 'MDRcv
  CDGroupSnd :: GroupInfo -> ChatDirection 'CTGroup 'MDSnd
  CDGroupRcv :: GroupInfo -> GroupMember -> ChatDirection 'CTGroup 'MDRcv

toCIDirection :: ChatDirection c d -> CIDirection c d
toCIDirection = \case
  CDDirectSnd _ -> CIDirectSnd
  CDDirectRcv _ -> CIDirectRcv
  CDGroupSnd _ -> CIGroupSnd
  CDGroupRcv _ m -> CIGroupRcv m

toChatInfo :: ChatDirection c d -> ChatInfo c
toChatInfo = \case
  CDDirectSnd c -> DirectChat c
  CDDirectRcv c -> DirectChat c
  CDGroupSnd g -> GroupChat g
  CDGroupRcv g _ -> GroupChat g

data NewChatItem d = NewChatItem
  { createdByMsgId :: Maybe MessageId,
    itemSent :: SMsgDirection d,
    itemTs :: ChatItemTs,
    itemContent :: CIContent d,
    itemText :: Text,
    itemStatus :: CIStatus d,
    itemSharedMsgId :: Maybe SharedMsgId,
    itemQuotedMsg :: Maybe QuotedMsg,
    createdAt :: UTCTime
  }
  deriving (Show)

-- | type to show one chat with messages
data Chat c = Chat
  { chatInfo :: ChatInfo c,
    chatItems :: [CChatItem c],
    chatStats :: ChatStats
  }
  deriving (Show, Generic)

instance ToJSON (Chat c) where
  toJSON = J.genericToJSON J.defaultOptions
  toEncoding = J.genericToEncoding J.defaultOptions

data AChat = forall c. AChat (SChatType c) (Chat c)

deriving instance Show AChat

instance ToJSON AChat where
  toJSON (AChat _ c) = J.toJSON c
  toEncoding (AChat _ c) = J.toEncoding c

data ChatStats = ChatStats
  { unreadCount :: Int,
    minUnreadItemId :: ChatItemId,
    unreadChat :: Bool
  }
  deriving (Show, Generic)

instance ToJSON ChatStats where
  toJSON = J.genericToJSON J.defaultOptions
  toEncoding = J.genericToEncoding J.defaultOptions

-- | type to show a mix of messages from multiple chats
data AChatItem = forall c d. MsgDirectionI d => AChatItem (SChatType c) (SMsgDirection d) (ChatInfo c) (ChatItem c d)

deriving instance Show AChatItem

instance ToJSON AChatItem where
  toJSON (AChatItem _ _ chat item) = J.toJSON $ JSONAnyChatItem chat item
  toEncoding (AChatItem _ _ chat item) = J.toEncoding $ JSONAnyChatItem chat item

data JSONAnyChatItem c d = JSONAnyChatItem {chatInfo :: ChatInfo c, chatItem :: ChatItem c d}
  deriving (Generic)

aChatItems :: AChat -> [AChatItem]
aChatItems (AChat ct Chat {chatInfo, chatItems}) = map aChatItem chatItems
  where
    aChatItem (CChatItem md ci) = AChatItem ct md chatInfo ci

aChatItemId :: AChatItem -> Int64
aChatItemId (AChatItem _ _ _ ci) = chatItemId' ci

updateFileStatus :: forall c d. ChatItem c d -> CIFileStatus d -> ChatItem c d
updateFileStatus ci@ChatItem {file} status = case file of
  Just f -> ci {file = Just (f :: CIFile d) {fileStatus = status}}
  Nothing -> ci

instance MsgDirectionI d => ToJSON (JSONAnyChatItem c d) where
  toJSON = J.genericToJSON J.defaultOptions
  toEncoding = J.genericToEncoding J.defaultOptions

-- This type is not saved to DB, so all JSON encodings are platform-specific
data CIMeta (d :: MsgDirection) = CIMeta
  { itemId :: ChatItemId,
    itemTs :: ChatItemTs,
    itemText :: Text,
    itemStatus :: CIStatus d,
    itemSharedMsgId :: Maybe SharedMsgId,
    itemDeleted :: Bool,
    itemEdited :: Bool,
    itemTimed :: Maybe CITimed,
    itemLive :: Maybe Bool,
    editable :: Bool,
    localItemTs :: ZonedTime,
    createdAt :: UTCTime,
    updatedAt :: UTCTime
  }
  deriving (Show, Generic)

mkCIMeta :: ChatItemId -> CIContent d -> Text -> CIStatus d -> Maybe SharedMsgId -> Bool -> Bool -> Maybe CITimed -> Maybe Bool -> TimeZone -> UTCTime -> ChatItemTs -> UTCTime -> UTCTime -> CIMeta d
mkCIMeta itemId itemContent itemText itemStatus itemSharedMsgId itemDeleted itemEdited itemTimed itemLive tz currentTs itemTs createdAt updatedAt =
  let localItemTs = utcToZonedTime tz itemTs
      editable = case itemContent of
        CISndMsgContent _ -> diffUTCTime currentTs itemTs < nominalDay && not itemDeleted
        _ -> False
   in CIMeta {itemId, itemTs, itemText, itemStatus, itemSharedMsgId, itemDeleted, itemEdited, itemTimed, itemLive, editable, localItemTs, createdAt, updatedAt}

instance ToJSON (CIMeta d) where toEncoding = J.genericToEncoding J.defaultOptions

data CITimed = CITimed
  { ttl :: Int, -- seconds
    deleteAt :: Maybe UTCTime
  }
  deriving (Show, Generic)

instance ToJSON CITimed where toEncoding = J.genericToEncoding J.defaultOptions

ttl' :: CITimed -> Int
ttl' CITimed {ttl} = ttl

contactTimedTTL :: Contact -> Maybe Int
contactTimedTTL Contact {mergedPreferences = ContactUserPreferences {timedMessages = ContactUserPreference {enabled, userPreference}}}
  | forUser enabled && forContact enabled = ttl
  | otherwise = Nothing
  where
    TimedMessagesPreference {ttl} = preference (userPreference :: ContactUserPref TimedMessagesPreference)

groupTimedTTL :: GroupInfo -> Maybe Int
groupTimedTTL GroupInfo {fullGroupPreferences = FullGroupPreferences {timedMessages = TimedMessagesGroupPreference {enable, ttl}}}
  | enable == FEOn = Just ttl
  | otherwise = Nothing

rcvContactCITimed :: Contact -> Maybe Int -> Maybe CITimed
rcvContactCITimed = rcvCITimed_ . contactTimedTTL

rcvGroupCITimed :: GroupInfo -> Maybe Int -> Maybe CITimed
rcvGroupCITimed = rcvCITimed_ . groupTimedTTL

rcvCITimed_ :: Maybe Int -> Maybe Int -> Maybe CITimed
rcvCITimed_ chatTTL itemTTL = (`CITimed` Nothing) <$> (chatTTL >> itemTTL)

data CIQuote (c :: ChatType) = CIQuote
  { chatDir :: CIQDirection c,
    itemId :: Maybe ChatItemId, -- Nothing in case MsgRef references the item the user did not receive yet
    sharedMsgId :: Maybe SharedMsgId, -- Nothing for the messages from the old clients
    sentAt :: UTCTime,
    content :: MsgContent,
    formattedText :: Maybe MarkdownList
  }
  deriving (Show, Generic)

instance ToJSON (CIQuote c) where
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

data CIQDirection (c :: ChatType) where
  CIQDirectSnd :: CIQDirection 'CTDirect
  CIQDirectRcv :: CIQDirection 'CTDirect
  CIQGroupSnd :: CIQDirection 'CTGroup
  CIQGroupRcv :: Maybe GroupMember -> CIQDirection 'CTGroup -- member can be Nothing in case MsgRef has memberId that the user is not notified about yet

deriving instance Show (CIQDirection c)

instance ToJSON (CIQDirection c) where
  toJSON = J.toJSON . jsonCIQDirection
  toEncoding = J.toEncoding . jsonCIQDirection

jsonCIQDirection :: CIQDirection c -> Maybe JSONCIDirection
jsonCIQDirection = \case
  CIQDirectSnd -> Just JCIDirectSnd
  CIQDirectRcv -> Just JCIDirectRcv
  CIQGroupSnd -> Just JCIGroupSnd
  CIQGroupRcv (Just m) -> Just $ JCIGroupRcv m
  CIQGroupRcv Nothing -> Nothing

quoteMsgDirection :: CIQDirection c -> MsgDirection
quoteMsgDirection = \case
  CIQDirectSnd -> MDSnd
  CIQDirectRcv -> MDRcv
  CIQGroupSnd -> MDSnd
  CIQGroupRcv _ -> MDRcv

data CIFile (d :: MsgDirection) = CIFile
  { fileId :: Int64,
    fileName :: String,
    fileSize :: Integer,
    filePath :: Maybe FilePath, -- local file path
    fileStatus :: CIFileStatus d
  }
  deriving (Show, Generic)

instance MsgDirectionI d => ToJSON (CIFile d) where
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

data CIFileStatus (d :: MsgDirection) where
  CIFSSndStored :: CIFileStatus 'MDSnd
  CIFSSndTransfer :: CIFileStatus 'MDSnd
  CIFSSndCancelled :: CIFileStatus 'MDSnd
  CIFSSndComplete :: CIFileStatus 'MDSnd
  CIFSRcvInvitation :: CIFileStatus 'MDRcv
  CIFSRcvAccepted :: CIFileStatus 'MDRcv
  CIFSRcvTransfer :: CIFileStatus 'MDRcv
  CIFSRcvComplete :: CIFileStatus 'MDRcv
  CIFSRcvCancelled :: CIFileStatus 'MDRcv

deriving instance Eq (CIFileStatus d)

deriving instance Show (CIFileStatus d)

ciFileEnded :: CIFileStatus d -> Bool
ciFileEnded = \case
  CIFSSndStored -> False
  CIFSSndTransfer -> False
  CIFSSndCancelled -> True
  CIFSSndComplete -> True
  CIFSRcvInvitation -> False
  CIFSRcvAccepted -> False
  CIFSRcvTransfer -> False
  CIFSRcvCancelled -> True
  CIFSRcvComplete -> True

instance MsgDirectionI d => ToJSON (CIFileStatus d) where
  toJSON = strToJSON
  toEncoding = strToJEncoding

instance MsgDirectionI d => ToField (CIFileStatus d) where toField = toField . decodeLatin1 . strEncode

instance FromField ACIFileStatus where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

data ACIFileStatus = forall d. MsgDirectionI d => AFS (SMsgDirection d) (CIFileStatus d)

deriving instance Show ACIFileStatus

instance MsgDirectionI d => StrEncoding (CIFileStatus d) where
  strEncode = \case
    CIFSSndStored -> "snd_stored"
    CIFSSndTransfer -> "snd_transfer"
    CIFSSndCancelled -> "snd_cancelled"
    CIFSSndComplete -> "snd_complete"
    CIFSRcvInvitation -> "rcv_invitation"
    CIFSRcvAccepted -> "rcv_accepted"
    CIFSRcvTransfer -> "rcv_transfer"
    CIFSRcvComplete -> "rcv_complete"
    CIFSRcvCancelled -> "rcv_cancelled"
  strP = (\(AFS _ st) -> checkDirection st) <$?> strP

instance StrEncoding ACIFileStatus where
  strEncode (AFS _ s) = strEncode s
  strP =
    A.takeTill (== ' ') >>= \case
      "snd_stored" -> pure $ AFS SMDSnd CIFSSndStored
      "snd_transfer" -> pure $ AFS SMDSnd CIFSSndTransfer
      "snd_cancelled" -> pure $ AFS SMDSnd CIFSSndCancelled
      "snd_complete" -> pure $ AFS SMDSnd CIFSSndComplete
      "rcv_invitation" -> pure $ AFS SMDRcv CIFSRcvInvitation
      "rcv_accepted" -> pure $ AFS SMDRcv CIFSRcvAccepted
      "rcv_transfer" -> pure $ AFS SMDRcv CIFSRcvTransfer
      "rcv_complete" -> pure $ AFS SMDRcv CIFSRcvComplete
      "rcv_cancelled" -> pure $ AFS SMDRcv CIFSRcvCancelled
      _ -> fail "bad file status"

-- to conveniently read file data from db
data CIFileInfo = CIFileInfo
  { fileId :: Int64,
    fileStatus :: Maybe ACIFileStatus,
    filePath :: Maybe FilePath
  }
  deriving (Show)

data CIStatus (d :: MsgDirection) where
  CISSndNew :: CIStatus 'MDSnd
  CISSndSent :: CIStatus 'MDSnd
  CISSndErrorAuth :: CIStatus 'MDSnd
  CISSndError :: String -> CIStatus 'MDSnd
  CISRcvNew :: CIStatus 'MDRcv
  CISRcvRead :: CIStatus 'MDRcv

deriving instance Show (CIStatus d)

ciStatusNew :: forall d. MsgDirectionI d => CIStatus d
ciStatusNew = case msgDirection @d of
  SMDSnd -> CISSndNew
  SMDRcv -> CISRcvNew

instance ToJSON (CIStatus d) where
  toJSON = J.toJSON . jsonCIStatus
  toEncoding = J.toEncoding . jsonCIStatus

instance MsgDirectionI d => ToField (CIStatus d) where toField = toField . decodeLatin1 . strEncode

instance FromField ACIStatus where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

data ACIStatus = forall d. MsgDirectionI d => ACIStatus (SMsgDirection d) (CIStatus d)

deriving instance Show ACIStatus

instance MsgDirectionI d => StrEncoding (CIStatus d) where
  strEncode = \case
    CISSndNew -> "snd_new"
    CISSndSent -> "snd_sent"
    CISSndErrorAuth -> "snd_error_auth"
    CISSndError e -> "snd_error " <> encodeUtf8 (T.pack e)
    CISRcvNew -> "rcv_new"
    CISRcvRead -> "rcv_read"
  strP = (\(ACIStatus _ st) -> checkDirection st) <$?> strP

instance StrEncoding ACIStatus where
  strEncode (ACIStatus _ s) = strEncode s
  strP =
    A.takeTill (== ' ') >>= \case
      "snd_new" -> pure $ ACIStatus SMDSnd CISSndNew
      "snd_sent" -> pure $ ACIStatus SMDSnd CISSndSent
      "snd_error_auth" -> pure $ ACIStatus SMDSnd CISSndErrorAuth
      "snd_error " -> ACIStatus SMDSnd . CISSndError . T.unpack . safeDecodeUtf8 <$> A.takeByteString
      "rcv_new" -> pure $ ACIStatus SMDRcv CISRcvNew
      "rcv_read" -> pure $ ACIStatus SMDRcv CISRcvRead
      _ -> fail "bad status"

data JSONCIStatus
  = JCISSndNew
  | JCISSndSent
  | JCISSndErrorAuth
  | JCISSndError {agentError :: String}
  | JCISRcvNew
  | JCISRcvRead
  deriving (Show, Generic)

instance ToJSON JSONCIStatus where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCIS"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCIS"

jsonCIStatus :: CIStatus d -> JSONCIStatus
jsonCIStatus = \case
  CISSndNew -> JCISSndNew
  CISSndSent -> JCISSndSent
  CISSndErrorAuth -> JCISSndErrorAuth
  CISSndError e -> JCISSndError e
  CISRcvNew -> JCISRcvNew
  CISRcvRead -> JCISRcvRead

type ChatItemId = Int64

type ChatItemTs = UTCTime

data ChatPagination
  = CPLast Int
  | CPAfter ChatItemId Int
  | CPBefore ChatItemId Int
  deriving (Show)

data CIDeleteMode = CIDMBroadcast | CIDMInternal
  deriving (Show, Generic)

instance ToJSON CIDeleteMode where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CIDM"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CIDM"

instance FromJSON CIDeleteMode where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CIDM"

ciDeleteModeToText :: CIDeleteMode -> Text
ciDeleteModeToText = \case
  CIDMBroadcast -> "this item is deleted (broadcast)"
  CIDMInternal -> "this item is deleted (internal)"

ciGroupInvitationToText :: CIGroupInvitation -> GroupMemberRole -> Text
ciGroupInvitationToText CIGroupInvitation {groupProfile = GroupProfile {displayName, fullName}} role =
  "invitation to join group " <> displayName <> optionalFullName displayName fullName <> " as " <> (decodeLatin1 . strEncode $ role)

rcvGroupEventToText :: RcvGroupEvent -> Text
rcvGroupEventToText = \case
  RGEMemberAdded _ p -> "added " <> profileToText p
  RGEMemberConnected -> "connected"
  RGEMemberLeft -> "left"
  RGEMemberRole _ p r -> "changed role of " <> profileToText p <> " to " <> safeDecodeUtf8 (strEncode r)
  RGEUserRole r -> "changed your role to " <> safeDecodeUtf8 (strEncode r)
  RGEMemberDeleted _ p -> "removed " <> profileToText p
  RGEUserDeleted -> "removed you"
  RGEGroupDeleted -> "deleted group"
  RGEGroupUpdated _ -> "group profile updated"
  RGEInvitedViaGroupLink -> "invited via your group link"

sndGroupEventToText :: SndGroupEvent -> Text
sndGroupEventToText = \case
  SGEMemberRole _ p r -> "changed role of " <> profileToText p <> " to " <> safeDecodeUtf8 (strEncode r)
  SGEUserRole r -> "changed role for yourself to " <> safeDecodeUtf8 (strEncode r)
  SGEMemberDeleted _ p -> "removed " <> profileToText p
  SGEUserLeft -> "left"
  SGEGroupUpdated _ -> "group profile updated"

rcvConnEventToText :: RcvConnEvent -> Text
rcvConnEventToText = \case
  RCESwitchQueue phase -> case phase of
    SPCompleted -> "changed address for you"
    _ -> decodeLatin1 (strEncode phase) <> " changing address for you..."

sndConnEventToText :: SndConnEvent -> Text
sndConnEventToText = \case
  SCESwitchQueue phase m -> case phase of
    SPCompleted -> "you changed address" <> forMember m
    _ -> decodeLatin1 (strEncode phase) <> " changing address" <> forMember m <> "..."
  where
    forMember member_ =
      maybe "" (\GroupMemberRef {profile = Profile {displayName}} -> " for " <> displayName) member_

profileToText :: Profile -> Text
profileToText Profile {displayName, fullName} = displayName <> optionalFullName displayName fullName

-- This type is used both in API and in DB, so we use different JSON encodings for the database and for the API
-- ! Nested sum types also have to use different encodings for database and API
-- ! to avoid breaking cross-platform compatibility, see RcvGroupEvent and SndGroupEvent
data CIContent (d :: MsgDirection) where
  CISndMsgContent :: MsgContent -> CIContent 'MDSnd
  CIRcvMsgContent :: MsgContent -> CIContent 'MDRcv
  CISndDeleted :: CIDeleteMode -> CIContent 'MDSnd -- legacy - since v4.3.0 item_deleted field is used
  CIRcvDeleted :: CIDeleteMode -> CIContent 'MDRcv -- legacy - since v4.3.0 item_deleted field is used
  CISndCall :: CICallStatus -> Int -> CIContent 'MDSnd
  CIRcvCall :: CICallStatus -> Int -> CIContent 'MDRcv
  CIRcvIntegrityError :: MsgErrorType -> CIContent 'MDRcv
  CIRcvGroupInvitation :: CIGroupInvitation -> GroupMemberRole -> CIContent 'MDRcv
  CISndGroupInvitation :: CIGroupInvitation -> GroupMemberRole -> CIContent 'MDSnd
  CIRcvGroupEvent :: RcvGroupEvent -> CIContent 'MDRcv
  CISndGroupEvent :: SndGroupEvent -> CIContent 'MDSnd
  CIRcvConnEvent :: RcvConnEvent -> CIContent 'MDRcv
  CISndConnEvent :: SndConnEvent -> CIContent 'MDSnd
  CIRcvChatFeature :: ChatFeature -> PrefEnabled -> Maybe Int -> CIContent 'MDRcv
  CISndChatFeature :: ChatFeature -> PrefEnabled -> Maybe Int -> CIContent 'MDSnd
  CIRcvChatPreference :: ChatFeature -> FeatureAllowed -> Maybe Int -> CIContent 'MDRcv
  CISndChatPreference :: ChatFeature -> FeatureAllowed -> Maybe Int -> CIContent 'MDSnd
  CIRcvGroupFeature :: GroupFeature -> GroupPreference -> Maybe Int -> CIContent 'MDRcv
  CISndGroupFeature :: GroupFeature -> GroupPreference -> Maybe Int -> CIContent 'MDSnd
  CIRcvChatFeatureRejected :: ChatFeature -> CIContent 'MDRcv
  CIRcvGroupFeatureRejected :: GroupFeature -> CIContent 'MDRcv
-- ^ This type is used both in API and in DB, so we use different JSON encodings for the database and for the API
-- ! ^ Nested sum types also have to use different encodings for database and API
-- ! ^ to avoid breaking cross-platform compatibility, see RcvGroupEvent and SndGroupEvent

deriving instance Show (CIContent d)

ciRequiresAttention :: forall d. MsgDirectionI d => CIContent d -> Bool
ciRequiresAttention content = case msgDirection @d of
  SMDSnd -> True
  SMDRcv -> case content of
    CIRcvMsgContent _ -> True
    CIRcvDeleted _ -> True
    CIRcvCall {} -> True
    CIRcvIntegrityError _ -> True
    CIRcvGroupInvitation {} -> True
    CIRcvGroupEvent rge -> case rge of
      RGEMemberAdded {} -> False
      RGEMemberConnected -> False
      RGEMemberLeft -> False
      RGEMemberRole {} -> False
      RGEUserRole _ -> True
      RGEMemberDeleted {} -> False
      RGEUserDeleted -> True
      RGEGroupDeleted -> True
      RGEGroupUpdated _ -> False
      RGEInvitedViaGroupLink -> False
    CIRcvConnEvent _ -> True
    CIRcvChatFeature {} -> False
    CIRcvChatPreference {} -> False
    CIRcvGroupFeature {} -> False
    CIRcvChatFeatureRejected _ -> True
    CIRcvGroupFeatureRejected _ -> True

ciCreateStatus :: forall d. MsgDirectionI d => CIContent d -> CIStatus d
ciCreateStatus content = case msgDirection @d of
  SMDSnd -> ciStatusNew
  SMDRcv -> if ciRequiresAttention content then ciStatusNew else CISRcvRead

data RcvGroupEvent
  = RGEMemberAdded {groupMemberId :: GroupMemberId, profile :: Profile} -- CRJoinedGroupMemberConnecting
  | RGEMemberConnected -- CRUserJoinedGroup, CRJoinedGroupMember, CRConnectedToGroupMember
  | RGEMemberLeft -- CRLeftMember
  | RGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | RGEUserRole {role :: GroupMemberRole}
  | RGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile} -- CRDeletedMember
  | RGEUserDeleted -- CRDeletedMemberUser
  | RGEGroupDeleted -- CRGroupDeleted
  | RGEGroupUpdated {groupProfile :: GroupProfile} -- CRGroupUpdated
  -- RGEInvitedViaGroupLink chat items are not received - they're created when sending group invitations,
  -- but being RcvGroupEvent allows them to be assigned to the respective member (and so enable "send direct message")
  -- and be created as unread without adding / working around new status for sent items
  | RGEInvitedViaGroupLink -- CRSentGroupInvitationViaLink
  deriving (Show, Generic)

instance FromJSON RcvGroupEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "RGE"

instance ToJSON RcvGroupEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "RGE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "RGE"

newtype DBRcvGroupEvent = RGE RcvGroupEvent

instance FromJSON DBRcvGroupEvent where
  parseJSON v = RGE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "RGE") v

instance ToJSON DBRcvGroupEvent where
  toJSON (RGE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "RGE") v
  toEncoding (RGE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "RGE") v

data SndGroupEvent
  = SGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | SGEUserRole {role :: GroupMemberRole}
  | SGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile} -- CRUserDeletedMember
  | SGEUserLeft -- CRLeftMemberUser
  | SGEGroupUpdated {groupProfile :: GroupProfile} -- CRGroupUpdated
  deriving (Show, Generic)

instance FromJSON SndGroupEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "SGE"

instance ToJSON SndGroupEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "SGE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "SGE"

newtype DBSndGroupEvent = SGE SndGroupEvent

instance FromJSON DBSndGroupEvent where
  parseJSON v = SGE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "SGE") v

instance ToJSON DBSndGroupEvent where
  toJSON (SGE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "SGE") v
  toEncoding (SGE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "SGE") v

data RcvConnEvent = RCESwitchQueue {phase :: SwitchPhase}
  deriving (Show, Generic)

data SndConnEvent = SCESwitchQueue {phase :: SwitchPhase, member :: Maybe GroupMemberRef}
  deriving (Show, Generic)

instance FromJSON RcvConnEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "RCE"

instance ToJSON RcvConnEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "RCE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "RCE"

newtype DBRcvConnEvent = RCE RcvConnEvent

instance FromJSON DBRcvConnEvent where
  parseJSON v = RCE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "RCE") v

instance ToJSON DBRcvConnEvent where
  toJSON (RCE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "RCE") v
  toEncoding (RCE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "RCE") v

instance FromJSON SndConnEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "SCE"

instance ToJSON SndConnEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "SCE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "SCE"

newtype DBSndConnEvent = SCE SndConnEvent

instance FromJSON DBSndConnEvent where
  parseJSON v = SCE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "SCE") v

instance ToJSON DBSndConnEvent where
  toJSON (SCE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "SCE") v
  toEncoding (SCE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "SCE") v

newtype DBMsgErrorType = DBME MsgErrorType

instance FromJSON DBMsgErrorType where
  parseJSON v = DBME <$> J.genericParseJSON (singleFieldJSON fstToLower) v

instance ToJSON DBMsgErrorType where
  toJSON (DBME v) = J.genericToJSON (singleFieldJSON fstToLower) v
  toEncoding (DBME v) = J.genericToEncoding (singleFieldJSON fstToLower) v

data CIGroupInvitation = CIGroupInvitation
  { groupId :: GroupId,
    groupMemberId :: GroupMemberId,
    localDisplayName :: GroupName,
    groupProfile :: GroupProfile,
    status :: CIGroupInvitationStatus
  }
  deriving (Eq, Show, Generic, FromJSON)

instance ToJSON CIGroupInvitation where
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

data CIGroupInvitationStatus
  = CIGISPending
  | CIGISAccepted
  | CIGISRejected
  | CIGISExpired
  deriving (Eq, Show, Generic)

instance FromJSON CIGroupInvitationStatus where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CIGIS"

instance ToJSON CIGroupInvitationStatus where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CIGIS"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CIGIS"

ciContentToText :: CIContent d -> Text
ciContentToText = \case
  CISndMsgContent mc -> msgContentText mc
  CIRcvMsgContent mc -> msgContentText mc
  CISndDeleted cidm -> ciDeleteModeToText cidm
  CIRcvDeleted cidm -> ciDeleteModeToText cidm
  CISndCall status duration -> "outgoing call: " <> ciCallInfoText status duration
  CIRcvCall status duration -> "incoming call: " <> ciCallInfoText status duration
  CIRcvIntegrityError err -> msgIntegrityError err
  CIRcvGroupInvitation groupInvitation memberRole -> "received " <> ciGroupInvitationToText groupInvitation memberRole
  CISndGroupInvitation groupInvitation memberRole -> "sent " <> ciGroupInvitationToText groupInvitation memberRole
  CIRcvGroupEvent event -> rcvGroupEventToText event
  CISndGroupEvent event -> sndGroupEventToText event
  CIRcvConnEvent event -> rcvConnEventToText event
  CISndConnEvent event -> sndConnEventToText event
  CIRcvChatFeature feature enabled param -> featureStateText feature enabled param
  CISndChatFeature feature enabled param -> featureStateText feature enabled param
  CIRcvChatPreference feature allowed param -> prefStateText feature allowed param
  CISndChatPreference feature allowed param -> "you " <> prefStateText feature allowed param
  CIRcvGroupFeature feature pref param -> groupPrefStateText feature pref param
  CISndGroupFeature feature pref param -> groupPrefStateText feature pref param
  CIRcvChatFeatureRejected feature -> chatFeatureNameText feature <> ": received, prohibited"
  CIRcvGroupFeatureRejected feature -> groupFeatureNameText feature <> ": received, prohibited"

msgIntegrityError :: MsgErrorType -> Text
msgIntegrityError = \case
  MsgSkipped fromId toId
    | fromId == toId -> "1 skipped message"
    | otherwise -> T.pack (show $ toId - fromId + 1) <> " skipped messages"
  MsgBadId msgId -> "unexpected message ID " <> T.pack (show msgId)
  MsgBadHash -> "incorrect message hash"
  MsgDuplicate -> "duplicate message ID"

msgDirToDeletedContent_ :: SMsgDirection d -> CIDeleteMode -> CIContent d
msgDirToDeletedContent_ msgDir mode = case msgDir of
  SMDRcv -> CIRcvDeleted mode
  SMDSnd -> CISndDeleted mode

-- platform independent
instance ToField (CIContent d) where
  toField = toField . encodeJSON . dbJsonCIContent

-- platform specific
instance ToJSON (CIContent d) where
  toJSON = J.toJSON . jsonCIContent
  toEncoding = J.toEncoding . jsonCIContent

data ACIContent = forall d. MsgDirectionI d => ACIContent (SMsgDirection d) (CIContent d)

deriving instance Show ACIContent

-- platform specific
instance FromJSON ACIContent where
  parseJSON = fmap aciContentJSON . J.parseJSON

-- platform independent
instance FromField ACIContent where fromField = fromTextField_ $ fmap aciContentDBJSON . decodeJSON

-- platform specific
data JSONCIContent
  = JCISndMsgContent {msgContent :: MsgContent}
  | JCIRcvMsgContent {msgContent :: MsgContent}
  | JCISndDeleted {deleteMode :: CIDeleteMode}
  | JCIRcvDeleted {deleteMode :: CIDeleteMode}
  | JCISndCall {status :: CICallStatus, duration :: Int} -- duration in seconds
  | JCIRcvCall {status :: CICallStatus, duration :: Int}
  | JCIRcvIntegrityError {msgError :: MsgErrorType}
  | JCIRcvGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | JCISndGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | JCIRcvGroupEvent {rcvGroupEvent :: RcvGroupEvent}
  | JCISndGroupEvent {sndGroupEvent :: SndGroupEvent}
  | JCIRcvConnEvent {rcvConnEvent :: RcvConnEvent}
  | JCISndConnEvent {sndConnEvent :: SndConnEvent}
  | JCIRcvChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | JCISndChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | JCIRcvChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | JCISndChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | JCIRcvGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | JCISndGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | JCIRcvChatFeatureRejected {feature :: ChatFeature}
  | JCIRcvGroupFeatureRejected {groupFeature :: GroupFeature}
  deriving (Generic)

instance FromJSON JSONCIContent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "JCI"

instance ToJSON JSONCIContent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCI"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCI"

jsonCIContent :: CIContent d -> JSONCIContent
jsonCIContent = \case
  CISndMsgContent mc -> JCISndMsgContent mc
  CIRcvMsgContent mc -> JCIRcvMsgContent mc
  CISndDeleted cidm -> JCISndDeleted cidm
  CIRcvDeleted cidm -> JCIRcvDeleted cidm
  CISndCall status duration -> JCISndCall {status, duration}
  CIRcvCall status duration -> JCIRcvCall {status, duration}
  CIRcvIntegrityError err -> JCIRcvIntegrityError err
  CIRcvGroupInvitation groupInvitation memberRole -> JCIRcvGroupInvitation {groupInvitation, memberRole}
  CISndGroupInvitation groupInvitation memberRole -> JCISndGroupInvitation {groupInvitation, memberRole}
  CIRcvGroupEvent rcvGroupEvent -> JCIRcvGroupEvent {rcvGroupEvent}
  CISndGroupEvent sndGroupEvent -> JCISndGroupEvent {sndGroupEvent}
  CIRcvConnEvent rcvConnEvent -> JCIRcvConnEvent {rcvConnEvent}
  CISndConnEvent sndConnEvent -> JCISndConnEvent {sndConnEvent}
  CIRcvChatFeature feature enabled param -> JCIRcvChatFeature {feature, enabled, param}
  CISndChatFeature feature enabled param -> JCISndChatFeature {feature, enabled, param}
  CIRcvChatPreference feature allowed param -> JCIRcvChatPreference {feature, allowed, param}
  CISndChatPreference feature allowed param -> JCISndChatPreference {feature, allowed, param}
  CIRcvGroupFeature groupFeature preference param -> JCIRcvGroupFeature {groupFeature, preference, param}
  CISndGroupFeature groupFeature preference param -> JCISndGroupFeature {groupFeature, preference, param}
  CIRcvChatFeatureRejected feature -> JCIRcvChatFeatureRejected {feature}
  CIRcvGroupFeatureRejected groupFeature -> JCIRcvGroupFeatureRejected {groupFeature}

aciContentJSON :: JSONCIContent -> ACIContent
aciContentJSON = \case
  JCISndMsgContent mc -> ACIContent SMDSnd $ CISndMsgContent mc
  JCIRcvMsgContent mc -> ACIContent SMDRcv $ CIRcvMsgContent mc
  JCISndDeleted cidm -> ACIContent SMDSnd $ CISndDeleted cidm
  JCIRcvDeleted cidm -> ACIContent SMDRcv $ CIRcvDeleted cidm
  JCISndCall {status, duration} -> ACIContent SMDSnd $ CISndCall status duration
  JCIRcvCall {status, duration} -> ACIContent SMDRcv $ CIRcvCall status duration
  JCIRcvIntegrityError err -> ACIContent SMDRcv $ CIRcvIntegrityError err
  JCIRcvGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDRcv $ CIRcvGroupInvitation groupInvitation memberRole
  JCISndGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDSnd $ CISndGroupInvitation groupInvitation memberRole
  JCIRcvGroupEvent {rcvGroupEvent} -> ACIContent SMDRcv $ CIRcvGroupEvent rcvGroupEvent
  JCISndGroupEvent {sndGroupEvent} -> ACIContent SMDSnd $ CISndGroupEvent sndGroupEvent
  JCIRcvConnEvent {rcvConnEvent} -> ACIContent SMDRcv $ CIRcvConnEvent rcvConnEvent
  JCISndConnEvent {sndConnEvent} -> ACIContent SMDSnd $ CISndConnEvent sndConnEvent
  JCIRcvChatFeature {feature, enabled, param} -> ACIContent SMDRcv $ CIRcvChatFeature feature enabled param
  JCISndChatFeature {feature, enabled, param} -> ACIContent SMDSnd $ CISndChatFeature feature enabled param
  JCIRcvChatPreference {feature, allowed, param} -> ACIContent SMDRcv $ CIRcvChatPreference feature allowed param
  JCISndChatPreference {feature, allowed, param} -> ACIContent SMDSnd $ CISndChatPreference feature allowed param
  JCIRcvGroupFeature {groupFeature, preference, param} -> ACIContent SMDRcv $ CIRcvGroupFeature groupFeature preference param
  JCISndGroupFeature {groupFeature, preference, param} -> ACIContent SMDSnd $ CISndGroupFeature groupFeature preference param
  JCIRcvChatFeatureRejected {feature} -> ACIContent SMDRcv $ CIRcvChatFeatureRejected feature
  JCIRcvGroupFeatureRejected {groupFeature} -> ACIContent SMDRcv $ CIRcvGroupFeatureRejected groupFeature

-- platform independent
data DBJSONCIContent
  = DBJCISndMsgContent {msgContent :: MsgContent}
  | DBJCIRcvMsgContent {msgContent :: MsgContent}
  | DBJCISndDeleted {deleteMode :: CIDeleteMode}
  | DBJCIRcvDeleted {deleteMode :: CIDeleteMode}
  | DBJCISndCall {status :: CICallStatus, duration :: Int}
  | DBJCIRcvCall {status :: CICallStatus, duration :: Int}
  | DBJCIRcvIntegrityError {msgError :: DBMsgErrorType}
  | DBJCIRcvGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | DBJCISndGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | DBJCIRcvGroupEvent {rcvGroupEvent :: DBRcvGroupEvent}
  | DBJCISndGroupEvent {sndGroupEvent :: DBSndGroupEvent}
  | DBJCIRcvConnEvent {rcvConnEvent :: DBRcvConnEvent}
  | DBJCISndConnEvent {sndConnEvent :: DBSndConnEvent}
  | DBJCIRcvChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | DBJCISndChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | DBJCIRcvChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | DBJCISndChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | DBJCIRcvGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | DBJCISndGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | DBJCIRcvChatFeatureRejected {feature :: ChatFeature}
  | DBJCIRcvGroupFeatureRejected {groupFeature :: GroupFeature}
  deriving (Generic)

instance FromJSON DBJSONCIContent where
  parseJSON = J.genericParseJSON . singleFieldJSON $ dropPrefix "DBJCI"

instance ToJSON DBJSONCIContent where
  toJSON = J.genericToJSON . singleFieldJSON $ dropPrefix "DBJCI"
  toEncoding = J.genericToEncoding . singleFieldJSON $ dropPrefix "DBJCI"

dbJsonCIContent :: CIContent d -> DBJSONCIContent
dbJsonCIContent = \case
  CISndMsgContent mc -> DBJCISndMsgContent mc
  CIRcvMsgContent mc -> DBJCIRcvMsgContent mc
  CISndDeleted cidm -> DBJCISndDeleted cidm
  CIRcvDeleted cidm -> DBJCIRcvDeleted cidm
  CISndCall status duration -> DBJCISndCall {status, duration}
  CIRcvCall status duration -> DBJCIRcvCall {status, duration}
  CIRcvIntegrityError err -> DBJCIRcvIntegrityError $ DBME err
  CIRcvGroupInvitation groupInvitation memberRole -> DBJCIRcvGroupInvitation {groupInvitation, memberRole}
  CISndGroupInvitation groupInvitation memberRole -> DBJCISndGroupInvitation {groupInvitation, memberRole}
  CIRcvGroupEvent rge -> DBJCIRcvGroupEvent $ RGE rge
  CISndGroupEvent sge -> DBJCISndGroupEvent $ SGE sge
  CIRcvConnEvent rce -> DBJCIRcvConnEvent $ RCE rce
  CISndConnEvent sce -> DBJCISndConnEvent $ SCE sce
  CIRcvChatFeature feature enabled param -> DBJCIRcvChatFeature {feature, enabled, param}
  CISndChatFeature feature enabled param -> DBJCISndChatFeature {feature, enabled, param}
  CIRcvChatPreference feature allowed param -> DBJCIRcvChatPreference {feature, allowed, param}
  CISndChatPreference feature allowed param -> DBJCISndChatPreference {feature, allowed, param}
  CIRcvGroupFeature groupFeature preference param -> DBJCIRcvGroupFeature {groupFeature, preference, param}
  CISndGroupFeature groupFeature preference param -> DBJCISndGroupFeature {groupFeature, preference, param}
  CIRcvChatFeatureRejected feature -> DBJCIRcvChatFeatureRejected {feature}
  CIRcvGroupFeatureRejected groupFeature -> DBJCIRcvGroupFeatureRejected {groupFeature}

aciContentDBJSON :: DBJSONCIContent -> ACIContent
aciContentDBJSON = \case
  DBJCISndMsgContent mc -> ACIContent SMDSnd $ CISndMsgContent mc
  DBJCIRcvMsgContent mc -> ACIContent SMDRcv $ CIRcvMsgContent mc
  DBJCISndDeleted cidm -> ACIContent SMDSnd $ CISndDeleted cidm
  DBJCIRcvDeleted cidm -> ACIContent SMDRcv $ CIRcvDeleted cidm
  DBJCISndCall {status, duration} -> ACIContent SMDSnd $ CISndCall status duration
  DBJCIRcvCall {status, duration} -> ACIContent SMDRcv $ CIRcvCall status duration
  DBJCIRcvIntegrityError (DBME err) -> ACIContent SMDRcv $ CIRcvIntegrityError err
  DBJCIRcvGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDRcv $ CIRcvGroupInvitation groupInvitation memberRole
  DBJCISndGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDSnd $ CISndGroupInvitation groupInvitation memberRole
  DBJCIRcvGroupEvent (RGE rge) -> ACIContent SMDRcv $ CIRcvGroupEvent rge
  DBJCISndGroupEvent (SGE sge) -> ACIContent SMDSnd $ CISndGroupEvent sge
  DBJCIRcvConnEvent (RCE rce) -> ACIContent SMDRcv $ CIRcvConnEvent rce
  DBJCISndConnEvent (SCE sce) -> ACIContent SMDSnd $ CISndConnEvent sce
  DBJCIRcvChatFeature {feature, enabled, param} -> ACIContent SMDRcv $ CIRcvChatFeature feature enabled param
  DBJCISndChatFeature {feature, enabled, param} -> ACIContent SMDSnd $ CISndChatFeature feature enabled param
  DBJCIRcvChatPreference {feature, allowed, param} -> ACIContent SMDRcv $ CIRcvChatPreference feature allowed param
  DBJCISndChatPreference {feature, allowed, param} -> ACIContent SMDSnd $ CISndChatPreference feature allowed param
  DBJCIRcvGroupFeature {groupFeature, preference, param} -> ACIContent SMDRcv $ CIRcvGroupFeature groupFeature preference param
  DBJCISndGroupFeature {groupFeature, preference, param} -> ACIContent SMDSnd $ CISndGroupFeature groupFeature preference param
  DBJCIRcvChatFeatureRejected {feature} -> ACIContent SMDRcv $ CIRcvChatFeatureRejected feature
  DBJCIRcvGroupFeatureRejected {groupFeature} -> ACIContent SMDRcv $ CIRcvGroupFeatureRejected groupFeature

data CICallStatus
  = CISCallPending
  | CISCallMissed
  | CISCallRejected -- only possible for received calls, not on type level
  | CISCallAccepted
  | CISCallNegotiated
  | CISCallProgress
  | CISCallEnded
  | CISCallError
  deriving (Show, Generic)

instance FromJSON CICallStatus where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CISCall"

instance ToJSON CICallStatus where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CISCall"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CISCall"

ciCallInfoText :: CICallStatus -> Int -> Text
ciCallInfoText status duration = case status of
  CISCallPending -> "calling..."
  CISCallMissed -> "missed"
  CISCallRejected -> "rejected"
  CISCallAccepted -> "accepted"
  CISCallNegotiated -> "connecting..."
  CISCallProgress -> "in progress " <> durationText duration
  CISCallEnded -> "ended " <> durationText duration
  CISCallError -> "error"

data SChatType (c :: ChatType) where
  SCTDirect :: SChatType 'CTDirect
  SCTGroup :: SChatType 'CTGroup
  SCTContactRequest :: SChatType 'CTContactRequest
  SCTContactConnection :: SChatType 'CTContactConnection

deriving instance Show (SChatType c)

instance TestEquality SChatType where
  testEquality SCTDirect SCTDirect = Just Refl
  testEquality SCTGroup SCTGroup = Just Refl
  testEquality SCTContactRequest SCTContactRequest = Just Refl
  testEquality SCTContactConnection SCTContactConnection = Just Refl
  testEquality _ _ = Nothing

class ChatTypeI (c :: ChatType) where
  chatTypeI :: SChatType c

instance ChatTypeI 'CTDirect where chatTypeI = SCTDirect

instance ChatTypeI 'CTGroup where chatTypeI = SCTGroup

data NewMessage e = NewMessage
  { chatMsgEvent :: ChatMsgEvent e,
    msgBody :: MsgBody
  }
  deriving (Show)

data SndMessage = SndMessage
  { msgId :: MessageId,
    sharedMsgId :: SharedMsgId,
    msgBody :: MsgBody
  }

data RcvMessage = RcvMessage
  { msgId :: MessageId,
    chatMsgEvent :: AChatMsgEvent,
    sharedMsgId_ :: Maybe SharedMsgId,
    msgBody :: MsgBody
  }

data PendingGroupMessage = PendingGroupMessage
  { msgId :: MessageId,
    cmEventTag :: ACMEventTag,
    msgBody :: MsgBody,
    introId_ :: Maybe Int64
  }

type MessageId = Int64

data ConnOrGroupId = ConnectionId Int64 | GroupId Int64

data MsgDirection = MDRcv | MDSnd
  deriving (Eq, Show, Generic)

instance FromJSON MsgDirection where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "MD"

instance ToJSON MsgDirection where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "MD"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "MD"

instance ToField MsgDirection where toField = toField . msgDirectionInt

data SMsgDirection (d :: MsgDirection) where
  SMDRcv :: SMsgDirection 'MDRcv
  SMDSnd :: SMsgDirection 'MDSnd

deriving instance Show (SMsgDirection d)

instance TestEquality SMsgDirection where
  testEquality SMDRcv SMDRcv = Just Refl
  testEquality SMDSnd SMDSnd = Just Refl
  testEquality _ _ = Nothing

instance ToField (SMsgDirection d) where toField = toField . msgDirectionInt . toMsgDirection

data AMsgDirection = forall d. MsgDirectionI d => AMsgDirection (SMsgDirection d)

deriving instance Show AMsgDirection

toMsgDirection :: SMsgDirection d -> MsgDirection
toMsgDirection = \case
  SMDRcv -> MDRcv
  SMDSnd -> MDSnd

fromMsgDirection :: MsgDirection -> AMsgDirection
fromMsgDirection = \case
  MDRcv -> AMsgDirection SMDRcv
  MDSnd -> AMsgDirection SMDSnd

class MsgDirectionI (d :: MsgDirection) where
  msgDirection :: SMsgDirection d

instance MsgDirectionI 'MDRcv where msgDirection = SMDRcv

instance MsgDirectionI 'MDSnd where msgDirection = SMDSnd

msgDirectionInt :: MsgDirection -> Int
msgDirectionInt = \case
  MDRcv -> 0
  MDSnd -> 1

msgDirectionIntP :: Int64 -> Maybe MsgDirection
msgDirectionIntP = \case
  0 -> Just MDRcv
  1 -> Just MDSnd
  _ -> Nothing

data SndMsgDelivery = SndMsgDelivery
  { connId :: Int64,
    agentMsgId :: AgentMsgId
  }
  deriving (Show)

data RcvMsgDelivery = RcvMsgDelivery
  { connId :: Int64,
    agentMsgId :: AgentMsgId,
    agentMsgMeta :: MsgMeta,
    agentAckCmdId :: CommandId
  }
  deriving (Show)

data MsgMetaJSON = MsgMetaJSON
  { integrity :: Text,
    rcvId :: Int64,
    rcvTs :: UTCTime,
    serverId :: Text,
    serverTs :: UTCTime,
    sndId :: Int64
  }
  deriving (Eq, Show, FromJSON, Generic)

instance ToJSON MsgMetaJSON where toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

msgMetaToJson :: MsgMeta -> MsgMetaJSON
msgMetaToJson MsgMeta {integrity, recipient = (rcvId, rcvTs), broker = (serverId, serverTs), sndMsgId = sndId} =
  MsgMetaJSON
    { integrity = (decodeLatin1 . strEncode) integrity,
      rcvId,
      rcvTs,
      serverId = (decodeLatin1 . B64.encode) serverId,
      serverTs,
      sndId
    }

msgMetaJson :: MsgMeta -> Text
msgMetaJson = decodeLatin1 . LB.toStrict . J.encode . msgMetaToJson

data MsgDeliveryStatus (d :: MsgDirection) where
  MDSRcvAgent :: MsgDeliveryStatus 'MDRcv
  MDSRcvAcknowledged :: MsgDeliveryStatus 'MDRcv
  MDSSndPending :: MsgDeliveryStatus 'MDSnd
  MDSSndAgent :: MsgDeliveryStatus 'MDSnd
  MDSSndSent :: MsgDeliveryStatus 'MDSnd
  MDSSndReceived :: MsgDeliveryStatus 'MDSnd
  MDSSndRead :: MsgDeliveryStatus 'MDSnd

data AMsgDeliveryStatus = forall d. AMDS (SMsgDirection d) (MsgDeliveryStatus d)

instance (Typeable d, MsgDirectionI d) => FromField (MsgDeliveryStatus d) where
  fromField = fromTextField_ msgDeliveryStatusT'

instance ToField (MsgDeliveryStatus d) where toField = toField . serializeMsgDeliveryStatus

serializeMsgDeliveryStatus :: MsgDeliveryStatus d -> Text
serializeMsgDeliveryStatus = \case
  MDSRcvAgent -> "rcv_agent"
  MDSRcvAcknowledged -> "rcv_acknowledged"
  MDSSndPending -> "snd_pending"
  MDSSndAgent -> "snd_agent"
  MDSSndSent -> "snd_sent"
  MDSSndReceived -> "snd_received"
  MDSSndRead -> "snd_read"

msgDeliveryStatusT :: Text -> Maybe AMsgDeliveryStatus
msgDeliveryStatusT = \case
  "rcv_agent" -> Just $ AMDS SMDRcv MDSRcvAgent
  "rcv_acknowledged" -> Just $ AMDS SMDRcv MDSRcvAcknowledged
  "snd_pending" -> Just $ AMDS SMDSnd MDSSndPending
  "snd_agent" -> Just $ AMDS SMDSnd MDSSndAgent
  "snd_sent" -> Just $ AMDS SMDSnd MDSSndSent
  "snd_received" -> Just $ AMDS SMDSnd MDSSndReceived
  "snd_read" -> Just $ AMDS SMDSnd MDSSndRead
  _ -> Nothing

msgDeliveryStatusT' :: forall d. MsgDirectionI d => Text -> Maybe (MsgDeliveryStatus d)
msgDeliveryStatusT' s =
  msgDeliveryStatusT s >>= \(AMDS d st) ->
    case testEquality d (msgDirection @d) of
      Just Refl -> Just st
      _ -> Nothing

checkDirection :: forall t d d'. (MsgDirectionI d, MsgDirectionI d') => t d' -> Either String (t d)
checkDirection x = case testEquality (msgDirection @d) (msgDirection @d') of
  Just Refl -> Right x
  Nothing -> Left "bad direction"
