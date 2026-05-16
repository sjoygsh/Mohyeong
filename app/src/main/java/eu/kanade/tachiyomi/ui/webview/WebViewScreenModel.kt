package eu.kanade.tachiyomi.ui.webview

import android.content.Context
import androidx.core.net.toUri
import cafe.adriel.voyager.core.model.StateScreenModel
import eu.kanade.presentation.more.stats.StatsScreenState
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.util.system.openInBrowser
import eu.kanade.tachiyomi.util.system.toShareIntent
import eu.kanade.tachiyomi.util.system.toast
import logcat.LogPriority
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import tachiyomi.core.common.util.system.logcat
import tachiyomi.domain.source.service.SourceManager
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

class WebViewScreenModel(
    val sourceId: Long?,
    private val sourceManager: SourceManager = Injekt.get(),
    private val network: NetworkHelper = Injekt.get(),
) : StateScreenModel<StatsScreenState>(StatsScreenState.Loading) {

    var headers = emptyMap<String, String>()

    init {
        sourceId?.let { sourceManager.get(it) as? HttpSource }?.let { source ->
            try {
                headers = source.headers.toMultimap().mapValues { it.value.getOrNull(0) ?: "" }
            } catch (e: Exception) {
                logcat(LogPriority.ERROR, e) { "Failed to build headers" }
            }
        }
    }

    fun shareWebpage(context: Context, url: String) {
        try {
            context.startActivity(url.toUri().toShareIntent(context, type = "text/plain"))
        } catch (e: Exception) {
            context.toast(e.message)
        }
    }

    fun openInBrowser(context: Context, url: String) {
        context.openInBrowser(url, forceDefaultBrowser = true)
    }

    fun clearCookies(url: String) {
        url.toHttpUrlOrNull()?.let {
            val cleared = network.cookieJar.remove(it)
            logcat { "Cleared $cleared cookies for: $url" }
        }
    }

    /**
     * Parses a clipboard-friendly cookie blob and stores it for the given URL.
     *
     * Accepted formats:
     *  - Netscape cookies.txt: `domain<TAB>flag<TAB>path<TAB>secure<TAB>expiry<TAB>name<TAB>value`
     *  - Simple header form:   `name1=value1; name2=value2`
     *  - One per line:         `name=value` (one pair per line)
     *
     * Returns the number of cookies successfully imported, or null on a parse failure.
     */
    fun importCookies(url: String, raw: String): Int? {
        val httpUrl = url.toHttpUrlOrNull() ?: return null
        val cookies = CookieImportParser.parse(raw, httpUrl)
        if (cookies.isEmpty()) return 0
        network.cookieJar.saveFromResponse(httpUrl, cookies)
        logcat { "Imported ${cookies.size} cookies for: $url" }
        return cookies.size
    }
}
