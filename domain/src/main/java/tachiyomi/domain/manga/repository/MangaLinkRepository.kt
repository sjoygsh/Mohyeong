package tachiyomi.domain.manga.repository

import kotlinx.coroutines.flow.Flow
import tachiyomi.domain.manga.model.Manga

/**
 * Repository for the multi-source link table that ties together manga entries
 * representing the same series on different sources. See issue #1837.
 */
interface MangaLinkRepository {

    suspend fun getLinkedMangas(primaryId: Long): List<Manga>

    fun getLinkedMangasAsFlow(primaryId: Long): Flow<List<Manga>>

    /**
     * Reverse lookup: given a manga that is on the linked side of some link row,
     * return every manga that has it as a linked entry. Used by callers that
     * receive a chapter from a linked source and need to route the user back to
     * the primary library entry.
     */
    suspend fun getPrimariesOfLinked(linkedId: Long): List<Manga>

    suspend fun link(primaryId: Long, linkedId: Long, priority: Long = 0L)

    suspend fun unlink(primaryId: Long, linkedId: Long)

    suspend fun deleteAllForManga(mangaId: Long)

    suspend fun setPriority(primaryId: Long, linkedId: Long, priority: Long)

    suspend fun getAllForBackup(): List<MangaLinkBackupRow>
}

/**
 * Source-and-URL identified link row, used by backup/sync since database IDs are not stable across devices.
 */
data class MangaLinkBackupRow(
    val primarySource: Long,
    val primaryUrl: String,
    val linkedSource: Long,
    val linkedUrl: String,
    val priority: Long,
)
