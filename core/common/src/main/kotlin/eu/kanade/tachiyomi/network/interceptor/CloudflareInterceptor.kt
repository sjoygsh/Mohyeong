package eu.kanade.tachiyomi.network.interceptor

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.core.content.ContextCompat
import eu.kanade.tachiyomi.network.AndroidCookieJar
import eu.kanade.tachiyomi.util.system.isOutdated
import eu.kanade.tachiyomi.util.system.toast
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import tachiyomi.core.common.i18n.stringResource
import tachiyomi.i18n.MR
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch

class CloudflareInterceptor(
    private val context: Context,
    private val cookieManager: AndroidCookieJar,
    defaultUserAgentProvider: () -> String,
    private val isEnabled: () -> Boolean = { true },
) : WebViewInterceptor(context, defaultUserAgentProvider) {

    private val executor = ContextCompat.getMainExecutor(context)

    override fun shouldIntercept(response: Response): Boolean {
        if (!isEnabled()) return false

        // Fast path: explicit Cloudflare mitigation header set by recent edge releases
        if (response.header("cf-mitigated")?.equals("challenge", ignoreCase = true) == true) {
            return true
        }

        if (response.code !in ERROR_CODES) return false
        val server = response.header("Server").orEmpty().lowercase()
        if (server !in SERVER_CHECK && response.header("cf-ray") == null) return false

        // Inspect body for challenge markers. Caps body read to 256 KiB to avoid
        // pulling huge non-HTML responses into memory.
        val body = try {
            response.peekBody(MAX_BODY_PEEK_BYTES).string()
        } catch (_: Exception) {
            return false
        }
        return CHALLENGE_BODY_MARKERS.any { it in body }
    }

    override fun intercept(
        chain: Interceptor.Chain,
        request: Request,
        response: Response,
    ): Response {
        try {
            response.close()
            val host = request.url.host
            val preCookie = cookieManager.get(request.url)
                .firstOrNull { it.name == "cf_clearance" }

            // Coalesce concurrent solves for the same host onto a single WebView.
            // Other threads block on this lock; once released, they re-check the cookie jar and
            // skip the WebView round-trip if the first solver already obtained cf_clearance.
            val lock = hostLocks.computeIfAbsent(host) { Object() }
            synchronized(lock) {
                val nowCookie = cookieManager.get(request.url)
                    .firstOrNull { it.name == "cf_clearance" }
                if (nowCookie != null && nowCookie != preCookie) {
                    // Another waiter solved it while we were queued.
                    return chain.proceed(request)
                }
                cookieManager.remove(request.url, COOKIE_NAMES, 0)
                resolveWithWebView(request, nowCookie)
            }

            return chain.proceed(request)
        }
        // Because OkHttp's enqueue only handles IOExceptions, wrap the exception so that
        // we don't crash the entire app
        catch (e: CloudflareBypassException) {
            throw IOException(context.stringResource(MR.strings.information_cloudflare_bypass_failure), e)
        } catch (e: Exception) {
            throw IOException(e)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun resolveWithWebView(originalRequest: Request, oldCookie: Cookie?) {
        // We need to lock this thread until the WebView finds the challenge solution url, because
        // OkHttp doesn't support asynchronous interceptors.
        val latch = CountDownLatch(1)

        var webview: WebView? = null

        var challengeFound = false
        var cloudflareBypassed = false
        var isWebViewOutdated = false

        val origRequestUrl = originalRequest.url.toString()
        val headers = parseHeaders(originalRequest.headers)

        executor.execute {
            webview = createWebView(originalRequest)

            webview.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    fun isCloudFlareBypassed(): Boolean {
                        return cookieManager.get(origRequestUrl.toHttpUrl())
                            .firstOrNull { it.name == "cf_clearance" }
                            .let { it != null && it != oldCookie }
                    }

                    if (isCloudFlareBypassed()) {
                        cloudflareBypassed = true
                        latch.countDown()
                    }

                    if (url == origRequestUrl && !challengeFound) {
                        // The first request didn't return the challenge, abort.
                        latch.countDown()
                    }
                }

                override fun onReceivedHttpError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    errorResponse: WebResourceResponse?,
                ) {
                    if (request?.isForMainFrame == true) {
                        if (errorResponse?.statusCode in ERROR_CODES) {
                            // Found the Cloudflare challenge page.
                            challengeFound = true
                        } else {
                            // Unlock thread, the challenge wasn't found.
                            latch.countDown()
                        }
                    }
                }
            }

            webview.loadUrl(origRequestUrl, headers)
        }

        latch.awaitFor30Seconds()

        executor.execute {
            if (!cloudflareBypassed) {
                isWebViewOutdated = webview?.isOutdated() == true
            }

            webview?.run {
                stopLoading()
                destroy()
            }
        }

        // Throw exception if we failed to bypass Cloudflare
        if (!cloudflareBypassed) {
            // Prompt user to update WebView if it seems too outdated
            if (isWebViewOutdated) {
                context.toast(MR.strings.information_webview_outdated, Toast.LENGTH_LONG)
            }

            throw CloudflareBypassException()
        }
    }
}

private val ERROR_CODES = listOf(403, 503, 429)
private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")
private val COOKIE_NAMES = listOf("cf_clearance")
private const val MAX_BODY_PEEK_BYTES = 256L * 1024L

/**
 * Body fragments that indicate a Cloudflare interactive challenge page rather than a
 * geo-block / hard ban. Checked with simple substring matching, no DOM parsing.
 */
private val CHALLENGE_BODY_MARKERS = arrayOf(
    "challenge-error-title",
    "challenge-error-text",
    "window._cf_chl_opt",
    "cf_chl_opt",
    "Just a moment",
    "/cdn-cgi/challenge-platform/",
)

private val hostLocks = ConcurrentHashMap<String, Any>()

private class CloudflareBypassException : Exception()
