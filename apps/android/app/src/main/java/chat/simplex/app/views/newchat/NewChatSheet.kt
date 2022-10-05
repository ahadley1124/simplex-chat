package chat.simplex.app.views.newchat

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.model.ChatModel
import chat.simplex.app.ui.theme.HighOrLowlight
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.views.chatlist.ScaffoldController
import chat.simplex.app.views.helpers.ModalManager

@Composable
fun NewChatSheet(chatModel: ChatModel, newChatCtrl: ScaffoldController) {
  if (newChatCtrl.expanded.value) BackHandler { newChatCtrl.collapse() }
  NewChatSheetLayout(
    addContact = {
      newChatCtrl.collapse()
      ModalManager.shared.showModal { CreateLinkView(chatModel, CreateLinkTab.ONE_TIME) }
    },
    connectViaLink = {
      newChatCtrl.collapse()
      ModalManager.shared.showModalCloseable { close -> ConnectViaLinkView(chatModel, close) }
    },
    createGroup = {
      newChatCtrl.collapse()
      ModalManager.shared.showCustomModal { close -> AddGroupView(chatModel, close) }
    }
  )
}

@Composable
fun NewChatSheetLayout(
  addContact: () -> Unit,
  connectViaLink: () -> Unit,
  createGroup: () -> Unit
) {
  Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(
      stringResource(R.string.add_contact_or_create_group),
      modifier = Modifier.padding(horizontal = 4.dp).padding(top = 20.dp, bottom = 20.dp),
      style = MaterialTheme.typography.body2
    )
    val boxModifier = Modifier.fillMaxWidth().height(80.dp).padding(horizontal = 0.dp)
    Divider(Modifier.padding(horizontal = 8.dp))
    Box(boxModifier) {
      ActionRowButton(
        stringResource(R.string.share_one_time_link),
        stringResource(R.string.to_share_with_your_contact),
        Icons.Outlined.AddLink,
        click = addContact
      )
    }
    Divider(Modifier.padding(horizontal = 8.dp))
    Box(boxModifier) {
      ActionRowButton(
        stringResource(R.string.connect_via_link_or_qr),
        stringResource(R.string.connect_via_link_or_qr_from_clipboard_or_in_person),
        Icons.Outlined.QrCode,
        click = connectViaLink
      )
    }
    Divider(Modifier.padding(horizontal = 8.dp))
    Box(boxModifier) {
      ActionRowButton(
        stringResource(R.string.create_group),
        stringResource(R.string.only_stored_on_members_devices),
        icon = Icons.Outlined.Group,
        click = createGroup
      )
    }
  }
}

@Composable
fun ActionRowButton(
  text: String, comment: String? = null, icon: ImageVector, disabled: Boolean = false,
  click: () -> Unit = {}
) {
  Surface(Modifier.fillMaxSize()) {
    Row(
      Modifier.clickable(onClick = click).size(48.dp).padding(8.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      val tint = if (disabled) HighOrLowlight else MaterialTheme.colors.primary
      Icon(icon, text, tint = tint, modifier = Modifier.size(48.dp).padding(start = 4.dp, end = 16.dp))

      Column {
        Text(
          text,
          textAlign = TextAlign.Left,
          fontWeight = FontWeight.Bold,
          color = tint
        )

        if (comment != null) {
          Text(
            comment,
            textAlign = TextAlign.Left,
            style = MaterialTheme.typography.body2
          )
        }
      }
    }
  }
}

@Composable
fun ActionButton(
  text: String?,
  comment: String?,
  icon: ImageVector,
  disabled: Boolean = false,
  click: () -> Unit = {}
) {
  Surface(shape = RoundedCornerShape(18.dp)) {
    Column(
      Modifier
        .clickable(onClick = click)
        .padding(8.dp),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      val tint = if (disabled) HighOrLowlight else MaterialTheme.colors.primary
      Icon(icon, text,
        tint = tint,
        modifier = Modifier
          .size(40.dp)
          .padding(bottom = 8.dp))
      if (text != null) {
        Text(
          text,
          textAlign = TextAlign.Center,
          fontWeight = FontWeight.Bold,
          color = tint,
          modifier = Modifier.padding(bottom = 4.dp)
        )
      }
      if (comment != null) {
        Text(
          comment,
          textAlign = TextAlign.Center,
          style = MaterialTheme.typography.body2
        )
      }
    }
  }
}

@Preview
@Composable
fun PreviewNewChatSheet() {
  SimpleXTheme {
    NewChatSheetLayout(
      addContact = {},
      connectViaLink = {},
      createGroup = {}
    )
  }
}
