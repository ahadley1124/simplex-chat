package chat.simplex.app.views.chat.item

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import chat.simplex.app.*
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.HighOrLowlight
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.views.chat.ComposeContextItem
import chat.simplex.app.views.chat.ComposeState
import chat.simplex.app.views.helpers.*
import kotlinx.datetime.Clock

// TODO refactor so that FramedItemView can show all CIContent items if they're deleted (see Swift code)

@Composable
fun ChatItemView(
  cInfo: ChatInfo,
  cItem: ChatItem,
  composeState: MutableState<ComposeState>,
  imageProvider: (() -> ImageGalleryProvider)? = null,
  showMember: Boolean = false,
  useLinkPreviews: Boolean,
  linkMode: SimplexLinkMode,
  deleteMessage: (Long, CIDeleteMode) -> Unit,
  receiveFile: (Long) -> Unit,
  joinGroup: (Long) -> Unit,
  acceptCall: (Contact) -> Unit,
  scrollToItem: (Long) -> Unit,
  acceptFeature: (Contact, ChatFeature, Int?) -> Unit
) {
  val context = LocalContext.current
  val uriHandler = LocalUriHandler.current
  val sent = cItem.chatDir.sent
  val alignment = if (sent) Alignment.CenterEnd else Alignment.CenterStart
  val showMenu = remember { mutableStateOf(false) }
  val revealed = remember { mutableStateOf(false) }
  val fullDeleteAllowed = remember(cInfo) { cInfo.featureEnabled(ChatFeature.FullDelete) }
  val saveFileLauncher = rememberSaveFileLauncher(cxt = context, ciFile = cItem.file)
  val onLinkLongClick = { _: String -> showMenu.value = true }
  val live = composeState.value.liveMessage != null

  Box(
    modifier = Modifier
      .padding(bottom = 4.dp)
      .fillMaxWidth(),
    contentAlignment = alignment,
  ) {
    val onClick = {
      when (cItem.meta.itemStatus) {
        is CIStatus.SndErrorAuth -> {
          showMsgDeliveryErrorAlert(generalGetString(R.string.message_delivery_error_desc))
        }
        is CIStatus.SndError -> {
          showMsgDeliveryErrorAlert(generalGetString(R.string.unknown_error) + ": ${cItem.meta.itemStatus.agentError}")
        }
        else -> {}
      }
    }
    Column(
      Modifier
        .clip(RoundedCornerShape(18.dp))
        .combinedClickable(onLongClick = { showMenu.value = true }, onClick = onClick),
    ) {
      @Composable
      fun framedItemView() {
        FramedItemView(cInfo, cItem, uriHandler, imageProvider, showMember = showMember, linkMode = linkMode, showMenu, receiveFile, onLinkLongClick, scrollToItem)
      }

      fun deleteMessageQuestionText(): String {
        return if (fullDeleteAllowed) {
          generalGetString(R.string.delete_message_cannot_be_undone_warning)
        } else {
          generalGetString(R.string.delete_message_mark_deleted_warning)
        }
      }

      @Composable
      fun MsgContentItemDropdownMenu() {
        DropdownMenu(
          expanded = showMenu.value,
          onDismissRequest = { showMenu.value = false },
          Modifier.width(220.dp)
        ) {
          if (!cItem.meta.itemDeleted && !live) {
            ItemAction(stringResource(R.string.reply_verb), Icons.Outlined.Reply, onClick = {
              if (composeState.value.editing) {
                composeState.value = ComposeState(contextItem = ComposeContextItem.QuotedItem(cItem), useLinkPreviews = useLinkPreviews)
              } else {
                composeState.value = composeState.value.copy(contextItem = ComposeContextItem.QuotedItem(cItem))
              }
              showMenu.value = false
            })
          }
          ItemAction(stringResource(R.string.share_verb), Icons.Outlined.Share, onClick = {
            val filePath = getLoadedFilePath(SimplexApp.context, cItem.file)
            when {
              filePath != null -> shareFile(context, cItem.text, filePath)
              else -> shareText(context, cItem.content.text)
            }
            showMenu.value = false
          })
          ItemAction(stringResource(R.string.copy_verb), Icons.Outlined.ContentCopy, onClick = {
            copyText(context, cItem.content.text)
            showMenu.value = false
          })
          if (cItem.content.msgContent is MsgContent.MCImage || cItem.content.msgContent is MsgContent.MCFile || cItem.content.msgContent is MsgContent.MCVoice) {
            val filePath = getLoadedFilePath(context, cItem.file)
            if (filePath != null) {
              ItemAction(stringResource(R.string.save_verb), Icons.Outlined.SaveAlt, onClick = {
                when (cItem.content.msgContent) {
                  is MsgContent.MCImage -> saveImage(context, cItem.file)
                  is MsgContent.MCFile -> saveFileLauncher.launch(cItem.file?.fileName)
                  is MsgContent.MCVoice -> saveFileLauncher.launch(cItem.file?.fileName)
                  else -> {}
                }
                showMenu.value = false
              })
            }
          }
          if (cItem.meta.editable && cItem.content.msgContent !is MsgContent.MCVoice && !live) {
            ItemAction(stringResource(R.string.edit_verb), Icons.Filled.Edit, onClick = {
              composeState.value = ComposeState(editingItem = cItem, useLinkPreviews = useLinkPreviews)
              showMenu.value = false
            })
          }
          if (cItem.meta.itemDeleted && revealed.value) {
            ItemAction(
              stringResource(R.string.hide_verb),
              Icons.Outlined.VisibilityOff,
              onClick = {
                revealed.value = false
                showMenu.value = false
              }
            )
          }
          if (!(live && cItem.meta.isLive)) {
            DeleteItemAction(cItem, showMenu, questionText = deleteMessageQuestionText(), deleteMessage)
          }
        }
      }

      @Composable
      fun MarkedDeletedItemDropdownMenu() {
        DropdownMenu(
          expanded = showMenu.value,
          onDismissRequest = { showMenu.value = false },
          Modifier.width(220.dp)
        ) {
          ItemAction(
            stringResource(R.string.reveal_verb),
            Icons.Outlined.Visibility,
            onClick = {
              revealed.value = true
              showMenu.value = false
            }
          )
          DeleteItemAction(cItem, showMenu, questionText = deleteMessageQuestionText(), deleteMessage)
        }
      }

      @Composable
      fun ContentItem() {
        val mc = cItem.content.msgContent
        if (cItem.meta.itemDeleted && !revealed.value) {
          MarkedDeletedItemView(cItem, cInfo.timedMessagesTTL, showMember = showMember)
          MarkedDeletedItemDropdownMenu()
        } else if (cItem.quotedItem == null && !cItem.meta.itemDeleted && !cItem.meta.isLive) {
          if (mc is MsgContent.MCText && isShortEmoji(cItem.content.text)) {
            EmojiItemView(cItem, cInfo.timedMessagesTTL)
            MsgContentItemDropdownMenu()
          } else if (mc is MsgContent.MCVoice && cItem.content.text.isEmpty()) {
            CIVoiceView(mc.duration, cItem.file, cItem.meta.itemEdited, cItem.chatDir.sent, hasText = false, cItem, cInfo.timedMessagesTTL, longClick = { onLinkLongClick("") })
            MsgContentItemDropdownMenu()
          } else {
            framedItemView()
            MsgContentItemDropdownMenu()
          }
        } else {
          framedItemView()
          MsgContentItemDropdownMenu()
        }
      }

      @Composable fun DeletedItem() {
        DeletedItemView(cItem, cInfo.timedMessagesTTL, showMember = showMember)
        DropdownMenu(
          expanded = showMenu.value,
          onDismissRequest = { showMenu.value = false },
          Modifier.width(220.dp)
        ) {
          DeleteItemAction(cItem, showMenu, questionText = deleteMessageQuestionText(), deleteMessage)
        }
      }

      @Composable fun CallItem(status: CICallStatus, duration: Int) {
        CICallItemView(cInfo, cItem, status, duration, acceptCall)
      }

      when (val c = cItem.content) {
        is CIContent.SndMsgContent -> ContentItem()
        is CIContent.RcvMsgContent -> ContentItem()
        is CIContent.SndDeleted -> DeletedItem()
        is CIContent.RcvDeleted -> DeletedItem()
        is CIContent.SndCall -> CallItem(c.status, c.duration)
        is CIContent.RcvCall -> CallItem(c.status, c.duration)
        is CIContent.RcvIntegrityError -> IntegrityErrorItemView(cItem, cInfo.timedMessagesTTL, showMember = showMember)
        is CIContent.RcvGroupInvitation -> CIGroupInvitationView(cItem, c.groupInvitation, c.memberRole, joinGroup = joinGroup, chatIncognito = cInfo.incognito)
        is CIContent.SndGroupInvitation -> CIGroupInvitationView(cItem, c.groupInvitation, c.memberRole, joinGroup = joinGroup, chatIncognito = cInfo.incognito)
        is CIContent.RcvGroupEventContent -> CIEventView(cItem)
        is CIContent.SndGroupEventContent -> CIEventView(cItem)
        is CIContent.RcvConnEventContent -> CIEventView(cItem)
        is CIContent.SndConnEventContent -> CIEventView(cItem)
        is CIContent.RcvChatFeature -> CIChatFeatureView(cItem, c.feature, c.enabled.iconColor)
        is CIContent.SndChatFeature -> CIChatFeatureView(cItem, c.feature, c.enabled.iconColor)
        is CIContent.RcvChatPreference -> {
          val ct = if (cInfo is ChatInfo.Direct) cInfo.contact else null
          CIFeaturePreferenceView(cItem, ct, c.feature, c.allowed, acceptFeature)
        }
        is CIContent.SndChatPreference -> CIChatFeatureView(cItem, c.feature, HighOrLowlight, icon = c.feature.icon,)
        is CIContent.RcvGroupFeature -> CIChatFeatureView(cItem, c.groupFeature, c.preference.enable.iconColor)
        is CIContent.SndGroupFeature -> CIChatFeatureView(cItem, c.groupFeature, c.preference.enable.iconColor)
        is CIContent.RcvChatFeatureRejected -> CIChatFeatureView(cItem, c.feature, Color.Red)
        is CIContent.RcvGroupFeatureRejected -> CIChatFeatureView(cItem, c.groupFeature, Color.Red)
        is CIContent.InvalidJSON -> CIInvalidJSONView(c.json)
      }
    }
  }
}

@Composable
fun DeleteItemAction(
  cItem: ChatItem,
  showMenu: MutableState<Boolean>,
  questionText: String,
  deleteMessage: (Long, CIDeleteMode) -> Unit
) {
  ItemAction(
    stringResource(R.string.delete_verb),
    Icons.Outlined.Delete,
    onClick = {
      showMenu.value = false
      deleteMessageAlertDialog(cItem, questionText, deleteMessage = deleteMessage)
    },
    color = Color.Red
  )
}

@Composable
fun ItemAction(text: String, icon: ImageVector, onClick: () -> Unit, color: Color = MaterialTheme.colors.onBackground) {
  DropdownMenuItem(onClick) {
    Row {
      Text(
        text,
        modifier = Modifier
          .fillMaxWidth()
          .weight(1F)
          .padding(end = 15.dp),
        color = color
      )
      Icon(icon, text, tint = color)
    }
  }
}

fun deleteMessageAlertDialog(chatItem: ChatItem, questionText: String, deleteMessage: (Long, CIDeleteMode) -> Unit) {
  AlertManager.shared.showAlertDialogButtons(
    title = generalGetString(R.string.delete_message__question),
    text = questionText,
    buttons = {
      Row(
        Modifier
          .fillMaxWidth()
          .padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.End,
      ) {
        TextButton(onClick = {
          deleteMessage(chatItem.id, CIDeleteMode.cidmInternal)
          AlertManager.shared.hideAlert()
        }) { Text(stringResource(R.string.for_me_only)) }
        if (chatItem.meta.editable) {
          Spacer(Modifier.padding(horizontal = 4.dp))
          TextButton(onClick = {
            deleteMessage(chatItem.id, CIDeleteMode.cidmBroadcast)
            AlertManager.shared.hideAlert()
          }) { Text(stringResource(R.string.for_everybody)) }
        }
      }
    }
  )
}

private fun showMsgDeliveryErrorAlert(description: String) {
  AlertManager.shared.showAlertMsg(
    title = generalGetString(R.string.message_delivery_error_title),
    text = description,
  )
}

@Preview
@Composable
fun PreviewChatItemView() {
  SimpleXTheme {
    ChatItemView(
      ChatInfo.Direct.sampleData,
      ChatItem.getSampleData(
        1, CIDirection.DirectSnd(), Clock.System.now(), "hello"
      ),
      useLinkPreviews = true,
      linkMode = SimplexLinkMode.DESCRIPTION,
      composeState = remember { mutableStateOf(ComposeState(useLinkPreviews = true)) },
      deleteMessage = { _, _ -> },
      receiveFile = {},
      joinGroup = {},
      acceptCall = { _ -> },
      scrollToItem = {},
      acceptFeature = { _, _, _ -> }
    )
  }
}

@Preview
@Composable
fun PreviewChatItemViewDeletedContent() {
  SimpleXTheme {
    ChatItemView(
      ChatInfo.Direct.sampleData,
      ChatItem.getDeletedContentSampleData(),
      useLinkPreviews = true,
      linkMode = SimplexLinkMode.DESCRIPTION,
      composeState = remember { mutableStateOf(ComposeState(useLinkPreviews = true)) },
      deleteMessage = { _, _ -> },
      receiveFile = {},
      joinGroup = {},
      acceptCall = { _ -> },
      scrollToItem = {},
      acceptFeature = { _, _, _ -> }
    )
  }
}
