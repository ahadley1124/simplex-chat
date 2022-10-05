package chat.simplex.app.views.helpers

import android.util.Log
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import chat.simplex.app.R
import chat.simplex.app.TAG

class AlertManager {
  var alertView = mutableStateOf<(@Composable () -> Unit)?>(null)
  var presentAlert = mutableStateOf<Boolean>(false)

  fun showAlert(alert: @Composable () -> Unit) {
    Log.d(TAG, "AlertManager.showAlert")
    alertView.value = alert
    presentAlert.value = true
  }

  fun hideAlert() {
    presentAlert.value = false
    alertView.value = null
  }

  fun showAlertDialogButtons(
    title: String,
    text: String? = null,
    buttons: @Composable () -> Unit,
  ) {
    val alertText: (@Composable () -> Unit)? = if (text == null) null else { -> Text(text) }
    showAlert {
      AlertDialog(
        onDismissRequest = this::hideAlert,
        title = { Text(title) },
        text = alertText,
        buttons = buttons
      )
    }
  }

  fun showAlertDialog(
    title: String,
    text: String? = null,
    confirmText: String = generalGetString(R.string.ok),
    onConfirm: (() -> Unit)? = null,
    dismissText: String = generalGetString(R.string.cancel_verb),
    onDismiss: (() -> Unit)? = null,
    onDismissRequest: (() -> Unit)? = null,
    destructive: Boolean = false
  ) {
    val alertText: (@Composable () -> Unit)? = if (text == null) null else { -> Text(text) }
    showAlert {
      AlertDialog(
        onDismissRequest = { onDismissRequest?.invoke(); hideAlert() },
        title = { Text(title) },
        text = alertText,
        confirmButton = {
          TextButton(onClick = {
            onConfirm?.invoke()
            hideAlert()
          }) { Text(confirmText, color = if (destructive) MaterialTheme.colors.error else Color.Unspecified) }
        },
        dismissButton = {
          TextButton(onClick = {
            onDismiss?.invoke()
            hideAlert()
          }) { Text(dismissText) }
        }
      )
    }
  }

  fun showAlertMsg(
    title: String, text: String? = null,
    confirmText: String = generalGetString(R.string.ok), onConfirm: (() -> Unit)? = null
  ) {
    val alertText: (@Composable () -> Unit)? = if (text == null) null else { -> Text(text) }
    showAlert {
      AlertDialog(
        onDismissRequest = this::hideAlert,
        title = { Text(title) },
        text = alertText,
        confirmButton = {
          TextButton(onClick = {
            onConfirm?.invoke()
            hideAlert()
          }) { Text(confirmText) }
        }
      )
    }
  }

  @Composable
  fun showInView() {
    if (presentAlert.value) alertView.value?.invoke()
  }

  companion object {
    val shared = AlertManager()
  }
}