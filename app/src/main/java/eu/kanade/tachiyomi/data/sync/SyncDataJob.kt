package eu.kanade.tachiyomi.data.sync

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkerParameters
import eu.kanade.domain.sync.SyncPreferences
import eu.kanade.domain.sync.SyncService
import eu.kanade.tachiyomi.util.system.isRunning
import eu.kanade.tachiyomi.util.system.workManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import logcat.LogPriority
import tachiyomi.core.common.util.system.logcat
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.util.concurrent.TimeUnit

class SyncDataJob(context: Context, workerParams: WorkerParameters) :
    CoroutineWorker(context, workerParams) {

    private val syncManager: SyncManager = Injekt.get()
    private val syncPreferences: SyncPreferences = Injekt.get()

    override suspend fun doWork(): Result {
        val service = SyncService.fromInt(syncPreferences.service().get())
        if (service == SyncService.NONE) return Result.success()

        return try {
            syncManager.sync()
            syncPreferences.lastSyncError().set("")
            Result.success()
        } catch (e: SyncException) {
            logcat(LogPriority.WARN, e) { "Sync failed: ${e.message}" }
            syncPreferences.lastSyncError().set(e.message.orEmpty().ifBlank { "Sync failed" })
            Result.retry()
        } catch (e: Exception) {
            logcat(LogPriority.ERROR, e) { "Sync crashed" }
            syncPreferences.lastSyncError().set(e.message.orEmpty().ifBlank { e::class.simpleName.orEmpty() })
            Result.failure()
        }
    }

    companion object {
        private const val TAG_AUTO = "SyncDataJob"
        private const val TAG_MANUAL = "$TAG_AUTO:manual"

        fun isManualJobRunning(context: Context): Boolean {
            return context.workManager.isRunning(TAG_MANUAL)
        }

        /**
         * Live signal for whether a manual sync is currently in progress. Backed by
         * [androidx.work.WorkManager.getWorkInfosByTagFlow] so it reactively updates when WorkManager
         * transitions the underlying work between ENQUEUED → RUNNING → SUCCEEDED/FAILED.
         */
        fun manualJobRunningFlow(context: Context): Flow<Boolean> {
            return context.workManager
                .getWorkInfosByTagFlow(TAG_MANUAL)
                .map { infos -> infos.any { it.state == WorkInfo.State.RUNNING } }
        }

        fun setupTask(context: Context, prefIntervalHours: Int? = null) {
            val prefs = Injekt.get<SyncPreferences>()
            val enabled = prefs.autoSyncEnabled().get() &&
                SyncService.fromInt(prefs.service().get()) != SyncService.NONE
            val interval = prefIntervalHours ?: prefs.autoSyncIntervalHours().get()

            if (!enabled || interval <= 0) {
                context.workManager.cancelUniqueWork(TAG_AUTO)
                return
            }

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<SyncDataJob>(
                interval.toLong(),
                TimeUnit.HOURS,
                15,
                TimeUnit.MINUTES,
            )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .addTag(TAG_AUTO)
                .build()

            context.workManager.enqueueUniquePeriodicWork(TAG_AUTO, ExistingPeriodicWorkPolicy.UPDATE, request)
        }

        fun startNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<SyncDataJob>()
                .addTag(TAG_MANUAL)
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .build()
            context.workManager.enqueueUniqueWork(TAG_MANUAL, ExistingWorkPolicy.KEEP, request)
        }
    }
}
