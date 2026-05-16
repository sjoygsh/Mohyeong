package eu.kanade.tachiyomi.data.sync

import java.io.File

/**
 * Abstraction over the wire/medium used to ship the backup payload between devices.
 *
 * There are two flavours:
 *
 *  - [ServerMediated]: a backend service receives the payload, performs the merge of incoming
 *    state against authoritative server state, and replies with the merged payload that should be
 *    applied locally. SyncYomi works this way.
 *
 *  - [FileStorage]: the remote is just a dumb blob store. The client is responsible for pulling
 *    whatever payload exists remotely, merging it against the local DB (via BackupRestorer's
 *    timestamp-aware merge), and then pushing the merged snapshot back. WebDAV (and any cloud
 *    file provider — Google Drive, Dropbox, OneDrive, etc.) works this way.
 *
 * Inputs are passed as [File] so transports can stream uploads directly from disk via OkHttp's
 * `File.asRequestBody(...)`; the merged payload returned from server-mediated transports is small
 * enough to stay in memory.
 */
sealed interface SyncTransport {

    interface ServerMediated : SyncTransport {
        /**
         * Push the local snapshot and receive a merged payload.
         *
         * @param local the local .tachibk snapshot on disk; streamed to the network.
         * @param lastSyncTimestamp epoch millis of last successful sync (0 if never).
         * @param deviceId stable id for this device.
         */
        suspend fun exchange(local: File, lastSyncTimestamp: Long, deviceId: String): ByteArray
    }

    interface FileStorage : SyncTransport {
        /** Returns the remote payload bytes, or null if no remote file exists yet. */
        suspend fun pull(): ByteArray?

        /** Uploads the merged snapshot at [payload], replacing whatever is currently stored remotely. */
        suspend fun push(payload: File)
    }
}
