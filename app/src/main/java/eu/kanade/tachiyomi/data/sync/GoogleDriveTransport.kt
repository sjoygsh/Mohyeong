package eu.kanade.tachiyomi.data.sync

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.await
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okio.BufferedSink
import okio.source
import org.json.JSONObject
import java.io.File

/**
 * Stores a single .tachibk file on Google Drive using an OAuth 2.0 access token (e.g. one minted
 * via the OAuth Playground for the scope `https://www.googleapis.com/auth/drive.file`). Merge
 * happens client-side via BackupRestorer.
 *
 * The access token is reused from the sync apiKey field. The user is responsible for refreshing
 * it; this transport does not perform the OAuth refresh dance.
 */
class GoogleDriveTransport(
    private val accessToken: String,
    private val networkHelper: NetworkHelper,
) : SyncTransport.FileStorage {

    override suspend fun pull(): ByteArray? {
        val fileId = lookupFileId() ?: return null

        val downloadUrl = "$DRIVE_API/files/$fileId".toHttpUrl().newBuilder()
            .addQueryParameter("alt", "media")
            .build()
        val request = Request.Builder()
            .url(downloadUrl)
            .header("Authorization", "Bearer $accessToken")
            .get()
            .build()

        val response = networkHelper.client.newCall(request).await()
        try {
            return when (response.code) {
                in 200..299 -> response.body.bytes().takeIf { it.isNotEmpty() }
                404 -> null
                401, 403 -> throw SyncException("Drive auth failed (HTTP ${response.code})")
                else -> throw SyncException("Drive pull failed (HTTP ${response.code})")
            }
        } finally {
            response.close()
        }
    }

    override suspend fun push(payload: File) {
        val existing = lookupFileId()

        val request = if (existing == null) {
            // Multipart create. The payload is streamed directly from disk inside the multipart
            // body so we never load the backup into memory.
            val boundary = "mihon_sync_${System.currentTimeMillis()}"
            val metadata = JSONObject().apply { put("name", FILE_NAME) }.toString()
            Request.Builder()
                .url("$UPLOAD_API/files?uploadType=multipart")
                .header("Authorization", "Bearer $accessToken")
                .post(MultipartRelatedBody(boundary, metadata, payload))
                .build()
        } else {
            Request.Builder()
                .url("$UPLOAD_API/files/$existing?uploadType=media")
                .header("Authorization", "Bearer $accessToken")
                .patch(payload.asRequestBody(OCTET_STREAM))
                .build()
        }

        val response = networkHelper.client.newCall(request).await()
        try {
            if (!response.isSuccessful) {
                throw SyncException("Drive push failed (HTTP ${response.code})")
            }
        } finally {
            response.close()
        }
    }

    private suspend fun lookupFileId(): String? {
        val url = "$DRIVE_API/files".toHttpUrl().newBuilder()
            .addQueryParameter("q", "name='$FILE_NAME' and trashed=false")
            .addQueryParameter("spaces", "drive")
            .addQueryParameter("fields", "files(id,name)")
            .addQueryParameter("pageSize", "1")
            .build()

        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $accessToken")
            .get()
            .build()

        val response = networkHelper.client.newCall(request).await()
        try {
            if (!response.isSuccessful) {
                if (response.code == 401 || response.code == 403) {
                    throw SyncException("Drive auth failed (HTTP ${response.code})")
                }
                throw SyncException("Drive lookup failed (HTTP ${response.code})")
            }
            val json = JSONObject(response.body.string())
            val files = json.optJSONArray("files") ?: return null
            if (files.length() == 0) return null
            return files.getJSONObject(0).optString("id").takeIf { it.isNotBlank() }
        } finally {
            response.close()
        }
    }

    companion object {
        private const val FILE_NAME = "mihon-sync.tachibk"
        private const val DRIVE_API = "https://www.googleapis.com/drive/v3"
        private const val UPLOAD_API = "https://www.googleapis.com/upload/drive/v3"
        private val OCTET_STREAM = "application/octet-stream".toMediaTypeOrNull()
    }
}

/**
 * Streaming multipart/related body for Drive's create-file endpoint. Writes the metadata part,
 * then the payload file (chunked off disk via Okio), then the trailing boundary — never
 * materialising the file in memory.
 */
private class MultipartRelatedBody(
    boundary: String,
    metadataJson: String,
    private val payload: File,
) : RequestBody() {

    private val prologue: ByteArray = buildString {
        append("--").append(boundary).append("\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        append(metadataJson).append("\r\n")
        append("--").append(boundary).append("\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
    }.toByteArray(Charsets.UTF_8)

    private val epilogue: ByteArray = "\r\n--$boundary--".toByteArray(Charsets.UTF_8)

    private val mediaType: MediaType? =
        "multipart/related; boundary=$boundary".toMediaTypeOrNull()

    override fun contentType(): MediaType? = mediaType

    override fun contentLength(): Long =
        prologue.size.toLong() + payload.length() + epilogue.size.toLong()

    override fun writeTo(sink: BufferedSink) {
        sink.write(prologue)
        payload.inputStream().use { input ->
            input.source().use { source ->
                sink.writeAll(source)
            }
        }
        sink.write(epilogue)
    }
}
