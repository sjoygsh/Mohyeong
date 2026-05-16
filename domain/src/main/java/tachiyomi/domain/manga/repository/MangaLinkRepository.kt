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
