package eu.kanade.tachiyomi.extension.util

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.net.toUri
import eu.kanade.domain.base.BasePreferences
import eu.kanade.tachiyomi.extension.installer.Installer
import eu.kanade.tachiyomi.extension.model.Extension
import eu.kanade.tachiyomi.extension.model.InstallStep
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.util.storage.getUriCompat
import eu.kanade.tachiyomi.util.system.isPackageInstalled
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.launch
import logcat.LogPriority
import okhttp3.OkHttpClient
import okhttp3.Request
import tachiyomi.core.common.util.system.logcat
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.io.File

/**
 * The installer which installs, updates and uninstalls the extensions.
 *
 * @param context The application context.
 */
internal class ExtensionInstaller(
    private val context: Context,
) {

    private val scope = CoroutineScope(Dispatchers.IO)
    private val activeJobs = mutableMapOf<String, Job>()
    private val activeSteps = mutableMapOf<Long, MutableStateFlow<InstallStep>>()
    private val pollJobs = mutableMapOf<Long, Job>()
    private val extensionInstaller = Injekt.get<BasePreferences>().extensionInstaller

    private val httpClient: OkHttpClient = Injekt.get<NetworkHelper>().client

    /**
     * Adds the given extension to the downloads queue and returns an observable containing its
     * step in the installation process.
     *
     * @param url The url of the apk.
     * @param extension The extension to install.
     */
    fun downloadAndInstall(url: String, extension: Extension): Flow<InstallStep> {
        val downloadId = extension.pkgName.hashCode().toLong()
        cancelInstall(extension.pkgName)

        val step = MutableStateFlow(InstallStep.Pending)
        activeSteps[downloadId] = step

        val job = scope.launch {
            val tmpFile = File(context.cacheDir, "extension_${extension.pkgName}.apk")
            try {
                step.value = InstallStep.Downloading
                val request = Request.Builder().url(url).build()
                val response = httpClient.newCall(request).execute()

                if (!response.isSuccessful) {
                    throw Exception("Failed to download extension")
                }
                response.body.byteStream().use { input ->
                    tmpFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                step.value = InstallStep.Installing
                installApk(downloadId, tmpFile, extension.pkgName)
            } catch (e: Exception) {
                if (e is InterruptedException) {
                    // Canceled
                } else {
                    logcat(LogPriority.ERROR, e)
                    step.value = InstallStep.Error
                }
            }
        }

        activeJobs[extension.pkgName] = job

        return step.asStateFlow()
            .onCompletion {
                activeJobs.remove(extension.pkgName)
                activeSteps.remove(downloadId)
                pollJobs.remove(downloadId)?.cancel()
                job.cancel()
            }
    }

    /**
     * Starts an intent to install the extension at the given uri.
     *
     * @param tempFile The file of the extension to install. Delete after use.
     */
    private fun installApk(downloadId: Long, tempFile: File, pkgName: String) {
        when (val installer = extensionInstaller.get()) {
            BasePreferences.ExtensionInstaller.LEGACY -> {
                val intent = Intent(context, ExtensionInstallActivity::class.java)
                    .setDataAndType(tempFile.getUriCompat(context), APK_MIME)
                    .putExtra(EXTRA_DOWNLOAD_ID, downloadId)
                    .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)

                context.startActivity(intent)
                startInstallVerificationPoll(downloadId, pkgName)
            }
            BasePreferences.ExtensionInstaller.PRIVATE -> {
                try {
                    if (ExtensionLoader.installPrivateExtensionFile(context, tempFile)) {
                        updateInstallStep(downloadId, InstallStep.Installed)
                    } else {
                        updateInstallStep(downloadId, InstallStep.Error)
                    }
                } catch (e: Exception) {
                    logcat(LogPriority.ERROR, e) { "Failed to read downloaded extension file." }
                    updateInstallStep(downloadId, InstallStep.Error)
                }

                tempFile.delete()
            }
            else -> {
                val intent = ExtensionInstallService.getIntent(
                    context,
                    downloadId,
                    tempFile.getUriCompat(context),
                    installer,
                )
                ContextCompat.startForegroundService(context, intent)
                startInstallVerificationPoll(downloadId, pkgName)
            }
        }
    }

    /**
     * Polls PackageManager for completion of an install initiated via the system installer popup.
     * This is a fallback for cases where the install-result broadcast is lost — most commonly when
     * MIUI/HyperOS kills [ExtensionInstallService] while the popup is foregrounded, causing the
     * registered receiver to be torn down before the system fires its STATUS_SUCCESS broadcast.
     *
     * Cancels itself as soon as the step transitions out of [InstallStep.Installing] (e.g. the
     * broadcast got through normally), to avoid stomping on the broadcast result.
     */
    private fun startInstallVerificationPoll(downloadId: Long, pkgName: String) {
        pollJobs.remove(downloadId)?.cancel()
        val initialVersion = getInstalledVersionCode(pkgName)
        val pollJob = scope.launch {
            val deadline = System.currentTimeMillis() + INSTALL_POLL_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                delay(INSTALL_POLL_INTERVAL_MS)
                val step = activeSteps[downloadId]?.value
                // Broadcast already resolved this — bail.
                if (step == null || step != InstallStep.Installing) return@launch

                val current = getInstalledVersionCode(pkgName)
                if (current != null && current != initialVersion) {
                    updateInstallStep(downloadId, InstallStep.Installed)
                    return@launch
                }
            }
            // Timed out without the package version changing. If we're still in Installing,
            // surface an error so the UI doesn't stay stuck on the spinner forever.
            if (activeSteps[downloadId]?.value == InstallStep.Installing) {
                logcat(LogPriority.WARN) { "Install verification poll timed out for $pkgName" }
                updateInstallStep(downloadId, InstallStep.Error)
            }
        }
        pollJobs[downloadId] = pollJob
        pollJob.invokeOnCompletion { pollJobs.remove(downloadId) }
    }

    private fun getInstalledVersionCode(pkgName: String): Long? {
        return try {
            val info = context.packageManager.getPackageInfo(pkgName, 0)
            PackageInfoCompat.getLongVersionCode(info)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    /**
     * Cancels extension install and remove from download manager and installer.
     */
    fun cancelInstall(pkgName: String) {
        val downloadId = pkgName.hashCode().toLong()
        activeJobs.remove(pkgName)?.cancel()
        pollJobs.remove(downloadId)?.cancel()
        Installer.cancelInstallQueue(context, downloadId)
    }

    /**
     * Starts an intent to uninstall the extension by the given package name.
     *
     * @param pkgName The package name of the extension to uninstall
     */
    fun uninstallApk(pkgName: String) {
        if (context.isPackageInstalled(pkgName)) {
            @Suppress("DEPRECATION")
            val intent = Intent(Intent.ACTION_UNINSTALL_PACKAGE, "package:$pkgName".toUri())
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } else {
            ExtensionLoader.uninstallPrivateExtension(context, pkgName)
            ExtensionInstallReceiver.notifyRemoved(context, pkgName)
        }
    }

    /**
     * Sets the step of the installation of an extension.
     *
     * @param downloadId The id of the download.
     * @param step New install step.
     */
    fun updateInstallStep(downloadId: Long, step: InstallStep) {
        activeSteps[downloadId]?.let { it.value = step }
    }

    companion object {
        const val APK_MIME = "application/vnd.android.package-archive"
        const val EXTRA_DOWNLOAD_ID = "ExtensionInstaller.extra.DOWNLOAD_ID"
        private const val INSTALL_POLL_INTERVAL_MS = 1_500L
        private const val INSTALL_POLL_TIMEOUT_MS = 60_000L
    }
}
