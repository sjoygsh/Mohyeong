package eu.kanade.tachiyomi.data.sync

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.POST
import eu.kanade.tachiyomi.network.await
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File

class SyncYomiTransport(
    private val host: String,
    private val apiKey: String,
    private val networkHelper: NetworkHelper,
) : SyncTransport.ServerMediated {

    override suspend fun exchange(
        local: File,
        lastSyncTimestamp: Long,
        deviceId: String,
    ): ByteArray {
        val request = POST(
            url = "$host/api/sync/content",
            body = local.asRequestBody(OCTET_STREAM),
        ).newBuilder()
            .header("Authorization", "Bearer $apiKey")
            .header("X-Sync-Device-Id", deviceId)
            .header("X-Sync-Last-Sync", lastSyncTimestamp.toString())
            .build()

        val response = networkHelper.client.newCall(request).await()
        try {
            if (!response.isSuccessful) {
                throw SyncException("Sync server returned HTTP ${response.code}")
            }
            val merged = response.body.bytes()
            if (merged.isEmpty()) {
                throw SyncException("Sync server returned empty payload")
            }
            return merged
        } finally {
            response.close()
        }
    }

    companion object {
        private val OCTET_STREAM = "application/octet-stream".toMediaTypeOrNull()
    }
}
