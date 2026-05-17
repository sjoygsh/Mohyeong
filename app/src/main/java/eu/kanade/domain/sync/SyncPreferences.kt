package eu.kanade.domain.sync

import tachiyomi.core.common.preference.Preference
import tachiyomi.core.common.preference.PreferenceStore

class SyncPreferences(
    private val preferenceStore: PreferenceStore,
) {

    init {
        // One-time migration: re-encrypt any plaintext credential values written by
        // v0.19.10 or earlier so they no longer sit on disk in cleartext.
        migrateToEncrypted(USERNAME_KEY)
        migrateToEncrypted(API_KEY_KEY)
    }

    private fun migrateToEncrypted(key: String) {
        val pref = preferenceStore.getString(key, "")
        val raw = pref.get()
        if (raw.isNotEmpty() && !raw.startsWith(SyncCrypto.MARKER)) {
            pref.set(SyncCrypto.encrypt(raw))
        }
    }

    fun host(): Preference<String> = preferenceStore.getString("sync_host", DEFAULT_HOST)

    fun username(): Preference<String> = EncryptedStringPreference(
        preferenceStore.getString(USERNAME_KEY, ""),
    )

    fun apiKey(): Preference<String> = EncryptedStringPreference(
        preferenceStore.getString(API_KEY_KEY, ""),
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
        private const val USERNAME_KEY = "sync_username"
        private val API_KEY_KEY = Preference.privateKey("sync_api_key")
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
