package chat.simplex.app.views.chat.group

import InfoRow
import SectionDivider
import SectionItemView
import SectionSpacer
import SectionTextFooter
import SectionView
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.chat.TimedMessagesTTLPicker
import chat.simplex.app.views.helpers.*
import chat.simplex.app.views.usersettings.PreferenceToggleWithIcon

@Composable
fun GroupPreferencesView(m: ChatModel, chatId: String, close: () -> Unit,) {
  val groupInfo = remember { derivedStateOf { (m.getChat(chatId)?.chatInfo as? ChatInfo.Group)?.groupInfo } }
  val gInfo = groupInfo.value ?: return
  var preferences by rememberSaveable(gInfo, stateSaver = serializableSaver()) { mutableStateOf(gInfo.fullGroupPreferences) }
  var currentPreferences by rememberSaveable(gInfo, stateSaver = serializableSaver()) { mutableStateOf(preferences) }

  fun savePrefs(afterSave: () -> Unit = {}) {
    withApi {
      val gp = gInfo.groupProfile.copy(groupPreferences = preferences.toGroupPreferences())
      val gInfo = m.controller.apiUpdateGroup(gInfo.groupId, gp)
      if (gInfo != null) {
        m.updateGroup(gInfo)
        currentPreferences = preferences
      }
      afterSave()
    }
  }
  ModalView(
    close = {
      if (preferences == currentPreferences) close()
      else showUnsavedChangesAlert({ savePrefs(close) }, close)
    },
    background = if (isInDarkTheme()) MaterialTheme.colors.background else SettingsBackgroundLight
  ) {
    GroupPreferencesLayout(
      preferences,
      currentPreferences,
      gInfo,
      applyPrefs = { prefs ->
        preferences = prefs
      },
      reset = {
        preferences = currentPreferences
      },
      savePrefs = ::savePrefs,
    )
  }
}

@Composable
private fun GroupPreferencesLayout(
  preferences: FullGroupPreferences,
  currentPreferences: FullGroupPreferences,
  groupInfo: GroupInfo,
  applyPrefs: (FullGroupPreferences) -> Unit,
  reset: () -> Unit,
  savePrefs: () -> Unit,
) {
  Column(
    Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
    horizontalAlignment = Alignment.Start,
  ) {
    AppBarTitle(stringResource(R.string.group_preferences))
    val timedMessages = remember(preferences) { mutableStateOf(preferences.timedMessages.enable) }
    val onTTLUpdated = { ttl: Int? ->
      applyPrefs(preferences.copy(timedMessages = preferences.timedMessages.copy(ttl = ttl ?: 86400)))
    }
    FeatureSection(GroupFeature.TimedMessages, timedMessages, groupInfo, preferences, onTTLUpdated) { enable ->
      if (enable == GroupFeatureEnabled.ON) {
         applyPrefs(preferences.copy(timedMessages = TimedMessagesGroupPreference(enable = enable, ttl = preferences.timedMessages.ttl ?: 86400)))
      } else {
        applyPrefs(preferences.copy(timedMessages = TimedMessagesGroupPreference(enable = enable, ttl = currentPreferences.timedMessages.ttl)))
      }
    }
    SectionSpacer()
    val allowDirectMessages = remember(preferences) { mutableStateOf(preferences.directMessages.enable) }
    FeatureSection(GroupFeature.DirectMessages, allowDirectMessages, groupInfo, preferences, onTTLUpdated) {
      applyPrefs(preferences.copy(directMessages = GroupPreference(enable = it)))
    }
    SectionSpacer()
    val allowFullDeletion = remember(preferences) { mutableStateOf(preferences.fullDelete.enable) }
    FeatureSection(GroupFeature.FullDelete, allowFullDeletion, groupInfo, preferences, onTTLUpdated) {
      applyPrefs(preferences.copy(fullDelete = GroupPreference(enable = it)))
    }
    SectionSpacer()
    val allowVoice = remember(preferences) { mutableStateOf(preferences.voice.enable) }
    FeatureSection(GroupFeature.Voice, allowVoice, groupInfo, preferences, onTTLUpdated) {
      applyPrefs(preferences.copy(voice = GroupPreference(enable = it)))
    }
    if (groupInfo.canEdit) {
      SectionSpacer()
      ResetSaveButtons(
        reset = reset,
        save = savePrefs,
        disabled = preferences == currentPreferences
      )
    }
  }
}

@Composable
private fun FeatureSection(
  feature: GroupFeature,
  enableFeature: State<GroupFeatureEnabled>,
  groupInfo: GroupInfo,
  preferences: FullGroupPreferences,
  onTTLUpdated: (Int?) -> Unit,
  onSelected: (GroupFeatureEnabled) -> Unit
) {
  SectionView {
    val on = enableFeature.value == GroupFeatureEnabled.ON
    val icon = if (on) feature.iconFilled else feature.icon
    val iconTint = if (on) SimplexGreen else HighOrLowlight
    val timedOn = feature == GroupFeature.TimedMessages && enableFeature.value == GroupFeatureEnabled.ON
    if (groupInfo.canEdit) {
      SectionItemView {
        PreferenceToggleWithIcon(
          feature.text,
          icon,
          iconTint,
          enableFeature.value == GroupFeatureEnabled.ON,
        ) { checked ->
          onSelected(if (checked) GroupFeatureEnabled.ON else GroupFeatureEnabled.OFF)
        }
      }
      if (timedOn) {
        SectionDivider()
        val ttl = rememberSaveable(preferences.timedMessages) { mutableStateOf(preferences.timedMessages.ttl) }
        TimedMessagesTTLPicker(ttl, onTTLUpdated)
      }
    } else {
      InfoRow(
        feature.text,
        enableFeature.value.text,
        icon = icon,
        iconTint = iconTint,
      )
      if (timedOn) {
        SectionDivider()
        InfoRow(generalGetString(R.string.delete_after), TimedMessagesPreference.ttlText(preferences.timedMessages.ttl))
      }
    }
  }
  SectionTextFooter(feature.enableDescription(enableFeature.value, groupInfo.canEdit))
}

@Composable
private fun ResetSaveButtons(reset: () -> Unit, save: () -> Unit, disabled: Boolean) {
  SectionView {
    SectionItemView(reset, disabled = disabled) {
      Text(stringResource(R.string.reset_verb), color = if (disabled) HighOrLowlight else MaterialTheme.colors.primary)
    }
    SectionDivider()
    SectionItemView(save, disabled = disabled) {
      Text(stringResource(R.string.save_and_notify_group_members), color = if (disabled) HighOrLowlight else MaterialTheme.colors.primary)
    }
  }
}

private fun showUnsavedChangesAlert(save: () -> Unit, revert: () -> Unit) {
  AlertManager.shared.showAlertDialogStacked(
    title = generalGetString(R.string.save_preferences_question),
    confirmText = generalGetString(R.string.save_and_notify_group_members),
    dismissText = generalGetString(R.string.exit_without_saving),
    onConfirm = save,
    onDismiss = revert,
  )
}
