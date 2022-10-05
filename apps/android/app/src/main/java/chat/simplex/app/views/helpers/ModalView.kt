package chat.simplex.app.views.helpers

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chat.simplex.app.TAG

@Composable
fun ModalView(
  close: () -> Unit,
  background: Color = MaterialTheme.colors.background,
  modifier: Modifier = Modifier.padding(horizontal = 16.dp),
  content: @Composable () -> Unit,
) {
  BackHandler(onBack = close)
  Surface(Modifier.fillMaxSize()) {
    Column(Modifier.background(background)) {
      CloseSheetBar(close)
      Box(modifier) { content() }
    }
  }
}

class ModalManager {
  private val modalViews = arrayListOf<(@Composable (close: () -> Unit) -> Unit)?>()
  private val modalCount = mutableStateOf(0)

  fun showModal(content: @Composable () -> Unit) {
    showCustomModal { close -> ModalView(close, content = content) }
  }

  fun showModalCloseable(content: @Composable (close: () -> Unit) -> Unit) {
    showCustomModal { close -> ModalView(close, content = { content(close) }) }
  }

  fun showCustomModal(modal: @Composable (close: () -> Unit) -> Unit) {
    Log.d(TAG, "ModalManager.showModal")
    modalViews.add(modal)
    modalCount.value = modalViews.count()
  }

  fun closeModal() {
    if (modalViews.isNotEmpty()) {
      modalViews.removeAt(modalViews.count() - 1)
    }
    modalCount.value = modalViews.count()
  }

  fun closeModals() {
    while (modalViews.isNotEmpty()) closeModal()
  }

  @Composable
  fun showInView() {
    if (modalCount.value > 0) modalViews.lastOrNull()?.invoke(::closeModal)
  }

  companion object {
    val shared = ModalManager()
  }
}
