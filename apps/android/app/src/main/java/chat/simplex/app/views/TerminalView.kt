package chat.simplex.app.views

import android.content.Context
import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.SimpleButton
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.views.chat.*
import chat.simplex.app.views.helpers.*
import com.google.accompanist.insets.ProvideWindowInsets
import com.google.accompanist.insets.navigationBarsWithImePadding

@Composable
fun TerminalView(chatModel: ChatModel, close: () -> Unit) {
  val composeState = remember { mutableStateOf(ComposeState(useLinkPreviews = false)) }
  BackHandler(onBack = close)
  val authorized = remember { mutableStateOf(!chatModel.controller.appPrefs.performLA.get()) }
  val context = LocalContext.current
  LaunchedEffect(authorized.value) {
    if (!authorized.value) {
      runAuth(authorized = authorized, context)
    }
  }
  if (authorized.value) {
    TerminalLayout(
      chatModel.terminalItems,
      composeState,
      sendCommand = { sendCommand(chatModel, composeState) },
      close
    )
  } else {
    Surface(Modifier.fillMaxSize()) {
      Column(Modifier.background(MaterialTheme.colors.background)) {
        CloseSheetBar(close)
        Box(
          Modifier.fillMaxSize(),
          contentAlignment = Alignment.Center
        ) {
          SimpleButton(
            stringResource(R.string.auth_unlock),
            icon = Icons.Outlined.Lock,
            click = {
              runAuth(authorized = authorized, context)
            }
          )
        }
      }
    }
  }
}

private fun runAuth(authorized: MutableState<Boolean>, context: Context) {
  authenticate(
    generalGetString(R.string.auth_open_chat_console),
    generalGetString(R.string.auth_log_in_using_credential),
    context as FragmentActivity,
    completed = { laResult ->
      when (laResult) {
        LAResult.Success, LAResult.Unavailable -> authorized.value = true
        is LAResult.Error, LAResult.Failed -> authorized.value = false
      }
    }
  )
}

private fun sendCommand(chatModel: ChatModel, composeState: MutableState<ComposeState>) {
  val developerTools = chatModel.controller.appPrefs.developerTools.get()
  val prefPerformLA = chatModel.controller.appPrefs.performLA.get()
  val s = composeState.value.message
  if (s.startsWith("/sql") && (!prefPerformLA || !developerTools)) {
    val resp = CR.ChatCmdError(ChatError.ChatErrorChat(ChatErrorType.СommandError("Failed reading: empty")))
    chatModel.terminalItems.add(TerminalItem.cmd(CC.Console(s)))
    chatModel.terminalItems.add(TerminalItem.resp(resp))
    composeState.value = ComposeState(useLinkPreviews = false)
  } else {
    withApi {
      // show "in progress"
      chatModel.controller.sendCmd(CC.Console(s))
      composeState.value = ComposeState(useLinkPreviews = false)
      // hide "in progress"
    }
  }
}

@Composable
fun TerminalLayout(
  terminalItems: List<TerminalItem>,
  composeState: MutableState<ComposeState>,
  sendCommand: () -> Unit,
  close: () -> Unit
) {
  val smallFont = MaterialTheme.typography.body1.copy(color = MaterialTheme.colors.onBackground)
  val textStyle = remember { mutableStateOf(smallFont) }

  fun onMessageChange(s: String) {
    composeState.value = composeState.value.copy(message = s)
  }

  ProvideWindowInsets(windowInsetsAnimationsEnabled = true) {
    Scaffold(
      topBar = { CloseSheetBar(close) },
      bottomBar = {
        Box(Modifier.padding(horizontal = 8.dp)) {
          SendMsgView(composeState, sendCommand, ::onMessageChange, textStyle)
        }
      },
      modifier = Modifier.navigationBarsWithImePadding()
    ) { contentPadding ->
      Surface(
        modifier = Modifier
          .padding(contentPadding)
          .fillMaxWidth()
          .background(MaterialTheme.colors.background)
      ) {
        TerminalLog(terminalItems)
      }
    }
  }
}

@Composable
fun TerminalLog(terminalItems: List<TerminalItem>) {
  val listState = rememberLazyListState()
  val reversedTerminalItems by remember { derivedStateOf { terminalItems.reversed() } }
  LazyColumn(state = listState, reverseLayout = true) {
    items(reversedTerminalItems) { item ->
      Text("${item.date.toString().subSequence(11, 19)} ${item.label}",
        style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 18.sp, color = MaterialTheme.colors.primary),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
          .padding(horizontal = 8.dp, vertical = 4.dp)
          .clickable {
            ModalManager.shared.showModal {
              SelectionContainer(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text(item.details)
              }
            }
          }
      )
    }
  }
}

@Preview(showBackground = true)
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewTerminalLayout() {
  SimpleXTheme {
    TerminalLayout(
      terminalItems = TerminalItem.sampleData,
      composeState = remember { mutableStateOf(ComposeState(useLinkPreviews = false)) },
      sendCommand = {},
      close = {}
    )
  }
}
