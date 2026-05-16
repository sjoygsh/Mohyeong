package eu.kanade.tachiyomi.ui.webview

import okhttp3.Cookie
import okhttp3.HttpUrl

/**
 * Parser for user-pasted cookie blobs. Tolerant by design — silently skips lines
 * it can't understand rather than failing the whole import.
 */
internal object CookieImportParser {

    fun parse(raw: String, url: HttpUrl): List<Cookie> {
        val text = raw.trim()
        if (text.isEmpty()) return emptyList()

        // Heuristic: if any line has 6+ tab-separated fields, treat the whole blob as Netscape.
        val looksNetscape = text.lineSequence()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .any { it.split('\t').size >= 6 }

        return if (looksNetscape) parseNetscape(text, url) else parseHeaderLike(text, url)
    }

    private fun parseNetscape(text: String, url: HttpUrl): List<Cookie> {
        val out = mutableListOf<Cookie>()
        for (line in text.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
            val parts = trimmed.split('\t')
            if (parts.size < 7) continue
            val domainRaw = parts[0].removePrefix(".").lowercase()
            val path = parts[2].ifBlank { "/" }
            val secure = parts[3].equals("TRUE", ignoreCase = true)
            val expiry = parts[4].toLongOrNull()
            val name = parts[5].trim()
            val value = parts[6]
            if (name.isEmpty()) continue

            val builder = Cookie.Builder()
                .name(name)
                .value(value)
                .path(path)
            try {
                if (domainRaw.isNotEmpty()) builder.domain(domainRaw) else builder.hostOnlyDomain(url.host)
            } catch (_: IllegalArgumentException) {
                builder.hostOnlyDomain(url.host)
            }
            if (secure) builder.secure()
            expiry?.let { if (it > 0) builder.expiresAt(it * 1000) }
            runCatching { out += builder.build() }
        }
        return out
    }

    private fun parseHeaderLike(text: String, url: HttpUrl): List<Cookie> {
        // Accept `;` and newlines as pair separators. Splits on the first '=' only.
        val pairs = text.splitToSequence(';', '\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() && '=' in it }
        val out = mutableListOf<Cookie>()
        for (pair in pairs) {
            val name = pair.substringBefore('=').trim()
            val value = pair.substringAfter('=').trim()
            if (name.isEmpty()) continue
            runCatching {
                out += Cookie.Builder()
                    .name(name)
                    .value(value)
                    .hostOnlyDomain(url.host)
                    .path("/")
                    .build()
            }
        }
        return out
    }
}
