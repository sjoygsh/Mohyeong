package eu.kanade.tachiyomi.data.sync

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.await
import okhttp3.Credentials
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File

/**
 * Stores a single .tachibk file on a WebDAV server. The merge happens client-side via the
 * BackupRestorer's per-row timestamp-based logic.
 *
 * Auth: HTTP Basic. The username comes from a dedicated preference; the password is reused from
 * the existing sync apiKey field.
 */
class WebDavTransport(
    private val host: String,
    private val username: String,
    private val password: String,
    private val networkHelper: NetworkHelper,
) : SyncTransport.FileStorage {

    private val fileUrl: String
        get() = "$host/$FILE_NAME"

    private val authHeader: String
        get() = Credentials.basic(username, password)

    override suspend fun pull(): ByteArray? {
        val request = Request.Builder()
            .url(fileUrl)
            .header("Authorization", authHeader)
            .get()
            .build()

        val response = networkHelper.client.newCall(request).await()
        try {
            return when (response.code) {
                in 200..299 -> response.body.bytes().takeIf { it.isNotEmpty() }
                404 -> null
                401, 403 -> throw SyncException("WebDAV auth failed (HTTP ${response.code})")
                else -> throw SyncException("WebDAV pull failed (HTTP ${response.code})")
            }
        } finally {
            response.close()
        }
    }

    override suspend fun push(payload: File) {
        val request = Request.Builder()
            .url(fileUrl)
            .header("Authorization", authHeader)
            .put(payload.asRequestBody(OCTET_STREAM))
            .build()

        val response = networkHelper.client.newCall(request).await()
        try {
            if (!response.isSuccessful) {
                throw SyncException("WebDAV push failed (HTTP ${response.code})")
            }
        } finally {
            response.close()
        }
    }

    companion object {
        private const val FILE_NAME = "mihon-sync.tachibk"
        private val OCTET_STREAM = "application/octet-stream".toMediaTypeOrNull()
    }
}
