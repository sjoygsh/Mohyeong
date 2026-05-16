package eu.kanade.tachiyomi.data.sync

import android.content.Context
import androidx.core.net.toUri
import eu.kanade.domain.sync.SyncPreferences
import eu.kanade.domain.sync.SyncService
import eu.kanade.tachiyomi.data.backup.BackupNotifier
import eu.kanade.tachiyomi.data.backup.create.BackupCreator
import eu.kanade.tachiyomi.data.backup.create.BackupOptions
import eu.kanade.tachiyomi.data.backup.restore.BackupRestorer
import eu.kanade.tachiyomi.data.backup.restore.RestoreOptions
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import logcat.LogPriority
import tachiyomi.core.common.util.system.logcat
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.io.File
import java.time.Instant
import java.util.UUID

class SyncManager(
    private val context: Context,
    private val syncPreferences: SyncPreferences = Injekt.get(),
    private val networkHelper: NetworkHelper = Injekt.get(),
) {

    /**
     * Performs a full bidirectional sync. Two flavours depending on transport:
     *
     * - Server-mediated (SyncYomi): snapshot local → POST to server → server merges → apply merged.
     * - File-storage (WebDAV / Drive / Dropbox): pull remote payload (if any) → apply it locally
     *   (BackupRestorer does timestamp-based per-row merge) → snapshot the now-merged state →
     *   push that snapshot back to remote.
     *
     * Uploads stream straight off disk so peak memory is bounded by the merged-payload pull
     * (typically much smaller than a full library), not the full local backup size.
     *
     * Throws [SyncException] on any failure so callers can surface a useful message.
     */
    suspend fun sync() = withContext(Dispatchers.IO) {
        val service = SyncService.fromInt(syncPreferences.service().get())
        if (service == SyncService.NONE) {
            throw SyncException("Sync service not configured")
        }
        val deviceId = ensureDeviceId()
        val transport = buildTransport(service)

        val pushFile = File(context.cacheDir, "sync_push.tachibk")
        val pullFile = File(context.cacheDir, "sync_pull.tachibk")

        try {
            when (transport) {
                is SyncTransport.ServerMediated -> serverMediatedSync(transport, deviceId, pushFile, pullFile)
                is SyncTransport.FileStorage -> fileStorageSync(transport, pushFile, pullFile)
            }
        } catch (e: SyncException) {
            throw e
        } catch (e: Exception) {
            logcat(LogPriority.ERROR, e) { "Sync failed" }
            throw SyncException(e.message ?: "Sync failed", e)
        } finally {
            runCatching { pushFile.delete() }
            runCatching { pullFile.delete() }
        }
    }

    private suspend fun serverMediatedSync(
        transport: SyncTransport.ServerMediated,
        deviceId: String,
        pushFile: File,
        pullFile: File,
    ) {
        snapshotLocal(pushFile)
        val merged = transport.exchange(
            local = pushFile,
            lastSyncTimestamp = syncPreferences.lastSyncTimestamp().get(),
            deviceId = deviceId,
        )
        pullFile.writeBytes(merged)
        applyMerged(pullFile)
        syncPreferences.lastSyncTimestamp().set(Instant.now().toEpochMilli())
    }

    private suspend fun fileStorageSync(
        transport: SyncTransport.FileStorage,
        pushFile: File,
        pullFile: File,
    ) {
        // 1. Pull remote payload (if any) and apply it locally. BackupRestorer's per-row
        //    timestamp merge resolves conflicts between the remote snapshot and local state.
        val remoteBytes = transport.pull()
        if (remoteBytes != null) {
            pullFile.writeBytes(remoteBytes)
            applyMerged(pullFile)
        }

        // 2. Snapshot the now-merged local state and push it back as the new authoritative copy.
        snapshotLocal(pushFile)
        transport.push(pushFile)

        syncPreferences.lastSyncTimestamp().set(Instant.now().toEpochMilli())
    }

    private suspend fun snapshotLocal(pushFile: File) {
        pushFile.parentFile?.mkdirs()
        if (!pushFile.exists()) pushFile.createNewFile()
        BackupCreator(context, isAutoBackup = false).backup(pushFile.toUri(), buildBackupOptions())
    }

    private suspend fun applyMerged(pullFile: File) {
        val notifier = BackupNotifier(context)
        BackupRestorer(context, notifier, isSync = true).restore(
            uri = pullFile.toUri(),
            options = RestoreOptions(
                libraryEntries = true,
                categories = syncPreferences.syncCategories().get(),
                appSettings = false,
                sourceSettings = false,
                extensionRepoSettings = false,
            ),
        )
    }

    private fun buildTransport(service: SyncService): SyncTransport {
        val host = syncPreferences.host().get().trim().trimEnd('/')
        val apiKey = syncPreferences.apiKey().get()
        return when (service) {
            SyncService.NONE -> throw SyncException("Sync service not configured")
            SyncService.SYNCYOMI -> {
                if (host.isEmpty()) throw SyncException("Sync host is empty")
                SyncYomiTransport(host, apiKey, networkHelper)
            }
            SyncService.WEBDAV -> {
                if (host.isEmpty()) throw SyncException("WebDAV URL is empty")
                val username = syncPreferences.username().get()
                if (username.isBlank()) throw SyncException("WebDAV username is empty")
                if (apiKey.isBlank()) throw SyncException("WebDAV password is empty")
                WebDavTransport(host, username, apiKey, networkHelper)
            }
            SyncService.GOOGLE_DRIVE -> {
                if (apiKey.isBlank()) throw SyncException("Google Drive access token is empty")
                GoogleDriveTransport(apiKey, networkHelper)
            }
            SyncService.DROPBOX -> {
                if (apiKey.isBlank()) throw SyncException("Dropbox access token is empty")
                DropboxTransport(apiKey, networkHelper)
            }
        }
    }

    private fun buildBackupOptions(): BackupOptions = BackupOptions(
        libraryEntries = true,
        categories = syncPreferences.syncCategories().get(),
        chapters = syncPreferences.syncChapters().get(),
        tracking = syncPreferences.syncTracking().get(),
        history = syncPreferences.syncHistory().get(),
        appSettings = false,
        extensionRepoSettings = false,
        sourceSettings = false,
        privateSettings = false,
        readEntries = false,
    )

    private fun ensureDeviceId(): String {
        val existing = syncPreferences.deviceId().get()
        if (existing.isNotBlank()) return existing
        val generated = UUID.randomUUID().toString()
        syncPreferences.deviceId().set(generated)
        return generated
    }
}

class SyncException(message: String, cause: Throwable? = null) : Exception(message, cause)
