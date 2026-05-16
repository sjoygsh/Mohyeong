package eu.kanade.presentation.more.settings.screen

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import eu.kanade.domain.sync.SyncPreferences
import eu.kanade.domain.sync.SyncService
import eu.kanade.presentation.more.settings.Preference
import eu.kanade.tachiyomi.data.sync.SyncDataJob
import eu.kanade.tachiyomi.util.system.toast
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentMap
import tachiyomi.presentation.core.util.collectAsState
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.text.DateFormat
import java.util.Date

object SettingsSyncScreen : SearchableSettings {

    @ReadOnlyComposable
    @Composable
    override fun getTitleRes() = MR.strings.pref_category_sync

    @Composable
    override fun getPreferences(): List<Preference> {
        val context = LocalContext.current
        val syncPreferences = remember { Injekt.get<SyncPreferences>() }

        val service by syncPreferences.service().collectAsState()
        val lastSync by syncPreferences.lastSyncTimestamp().collectAsState()
        val lastError by syncPreferences.lastSyncError().collectAsState()
        // Reactive: tracks WorkManager state for the manual sync job so the subtitle and the
        // "Sync now" button enable-state update live as a sync starts/finishes.
        val runningFlow = remember(context) { SyncDataJob.manualJobRunningFlow(context) }
        val running by runningFlow.collectAsState(initial = SyncDataJob.isManualJobRunning(context))

        val lastSyncText = if (lastSync > 0L) {
            DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(lastSync))
        } else {
            stringResource(MR.strings.sync_never)
        }

        val statusSubtitle = when {
            running -> stringResource(MR.strings.sync_running)
            lastError.isNotBlank() -> stringResource(MR.strings.sync_last_error, lastError)
            else -> stringResource(MR.strings.pref_sync_last, lastSyncText)
        }

        val needsHost = service == SyncService.SYNCYOMI.value || service == SyncService.WEBDAV.value
        val needsUsername = service == SyncService.WEBDAV.value
        val credentialTitleRes = when (service) {
            SyncService.WEBDAV.value -> MR.strings.pref_sync_password
            SyncService.GOOGLE_DRIVE.value, SyncService.DROPBOX.value -> MR.strings.pref_sync_access_token
            else -> MR.strings.pref_sync_api_key
        }

        return listOfNotNull(
            Preference.PreferenceItem.ListPreference(
                preference = syncPreferences.service(),
                entries = persistentListOf(
                    SyncService.NONE.value to stringResource(MR.strings.sync_service_none),
                    SyncService.SYNCYOMI.value to stringResource(MR.strings.sync_service_syncyomi),
                    SyncService.WEBDAV.value to stringResource(MR.strings.sync_service_webdav),
                    SyncService.GOOGLE_DRIVE.value to stringResource(MR.strings.sync_service_google_drive),
                    SyncService.DROPBOX.value to stringResource(MR.strings.sync_service_dropbox),
                ).toMap().toPersistentMap(),
                title = stringResource(MR.strings.pref_sync_service),
            ),
            if (needsHost) {
                Preference.PreferenceItem.EditTextPreference(
                    preference = syncPreferences.host(),
                    title = stringResource(MR.strings.pref_sync_host),
                    subtitle = "%s",
                    enabled = service != SyncService.NONE.value,
                )
            } else {
                null
            },
            if (needsUsername) {
                Preference.PreferenceItem.EditTextPreference(
                    preference = syncPreferences.username(),
                    title = stringResource(MR.strings.pref_sync_username),
                    subtitle = "%s",
                    enabled = service != SyncService.NONE.value,
                )
            } else {
                null
            },
            Preference.PreferenceItem.EditTextPreference(
                preference = syncPreferences.apiKey(),
                title = stringResource(credentialTitleRes),
                subtitle = stringResource(MR.strings.pref_sync_api_key_summary),
                enabled = service != SyncService.NONE.value,
            ),
            Preference.PreferenceGroup(
                title = stringResource(MR.strings.pref_sync_data_category),
                preferenceItems = persistentListOf(
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.syncCategories(),
                        title = stringResource(MR.strings.categories),
                    ),
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.syncChapters(),
                        title = stringResource(MR.strings.chapters),
                    ),
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.syncTracking(),
                        title = stringResource(MR.strings.track),
                    ),
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.syncHistory(),
                        title = stringResource(MR.strings.history),
                    ),
                ),
            ),
            Preference.PreferenceGroup(
                title = stringResource(MR.strings.pref_sync_automation),
                preferenceItems = persistentListOf(
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.autoSyncEnabled(),
                        title = stringResource(MR.strings.pref_sync_auto_enabled),
                        subtitle = stringResource(MR.strings.pref_sync_auto_enabled_summary),
                        onValueChanged = {
                            SyncDataJob.setupTask(context)
                            true
                        },
                    ),
                    Preference.PreferenceItem.ListPreference(
                        preference = syncPreferences.autoSyncIntervalHours(),
                        entries = persistentListOf(
                            6 to stringResource(MR.strings.update_6hour),
                            12 to stringResource(MR.strings.update_12hour),
                            24 to stringResource(MR.strings.update_24hour),
                            48 to stringResource(MR.strings.update_48hour),
                        ).toMap().toPersistentMap(),
                        title = stringResource(MR.strings.pref_sync_interval),
                        onValueChanged = {
                            SyncDataJob.setupTask(context, it)
                            true
                        },
                    ),
                    Preference.PreferenceItem.SwitchPreference(
                        preference = syncPreferences.syncOnAppStart(),
                        title = stringResource(MR.strings.pref_sync_on_start),
                    ),
                ),
            ),
            Preference.PreferenceItem.TextPreference(
                title = stringResource(MR.strings.pref_sync_now),
                subtitle = statusSubtitle,
                enabled = service != SyncService.NONE.value && !running,
                onClick = {
                    SyncDataJob.startNow(context)
                    context.toast(MR.strings.pref_sync_started)
                },
            ),
        )
    }
}
