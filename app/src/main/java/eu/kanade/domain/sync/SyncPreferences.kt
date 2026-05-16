package eu.kanade.domain.sync

import tachiyomi.core.common.preference.Preference
import tachiyomi.core.common.preference.PreferenceStore

class SyncPreferences(
    private val preferenceStore: PreferenceStore,
) {

    fun host(): Preference<String> = preferenceStore.getString("sync_host", DEFAULT_HOST)

    fun username(): Preference<String> = preferenceStore.getString("sync_username", "")

    fun apiKey(): Preference<String> = preferenceStore.getString(
        Preference.privateKey("sync_api_key"),
        "",
    )

    fun service(): Preference<Int> = preferenceStore.getInt("sync_service", SyncService.NONE.value)

    fun lastSyncTimestamp(): Preference<Long> = preferenceStore.getLong("sync_last_sync_timestamp", 0L)

    fun autoSyncEnabled(): Preference<Boolean> = preferenceStore.getBoolean("sync_auto_enabled", false)

    fun autoSyncIntervalHours(): Preference<Int> = preferenceStore.getInt("sync_auto_interval_hours", 12)

    fun syncCategories(): Preference<Boolean> = preferenceStore.getBoolean("sync_data_categories", true)

    fun syncChapters(): Preference<Boolean> = preferenceStore.getBoolean("sync_data_chapters", true)

    fun syncTracking(): Preference<Boolean> = preferenceStore.getBoolean("sync_data_tracking", true)

    fun syncHistory(): Preference<Boolean> = preferenceStore.getBoolean("sync_data_history", true)

    fun syncOnAppStart(): Preference<Boolean> = preferenceStore.getBoolean("sync_on_app_start", false)

    fun deviceId(): Preference<String> = preferenceStore.getString("sync_device_id", "")

    fun lastSyncError(): Preference<String> = preferenceStore.getString("sync_last_error", "")

    companion object {
        const val DEFAULT_HOST = ""
    }
}

enum class SyncService(val value: Int) {
    NONE(0),
    SYNCYOMI(1),
    WEBDAV(2),
    GOOGLE_DRIVE(3),
    DROPBOX(4),
    ;

    companion object {
        fun fromInt(value: Int): SyncService = entries.firstOrNull { it.value == value } ?: NONE
    }
}
