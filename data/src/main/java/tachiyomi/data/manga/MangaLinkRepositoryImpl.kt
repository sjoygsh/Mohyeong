package tachiyomi.data.manga

import app.cash.sqldelight.async.coroutines.awaitAsList
import kotlinx.coroutines.flow.Flow
import tachiyomi.data.Database
import tachiyomi.data.subscribeToList
import tachiyomi.domain.manga.model.Manga
import tachiyomi.domain.manga.repository.MangaLinkBackupRow
import tachiyomi.domain.manga.repository.MangaLinkRepository

class MangaLinkRepositoryImpl(
    private val database: Database,
) : MangaLinkRepository {

    override suspend fun getLinkedMangas(primaryId: Long): List<Manga> {
        return database.manga_linksQueries
            .getLinkedMangas(primaryId, MangaMapper::mapManga)
            .awaitAsList()
    }

    override fun getLinkedMangasAsFlow(primaryId: Long): Flow<List<Manga>> {
        return database.manga_linksQueries
            .getLinkedMangas(primaryId, MangaMapper::mapManga)
            .subscribeToList()
    }

    override suspend fun getPrimariesOfLinked(linkedId: Long): List<Manga> {
        return database.manga_linksQueries
            .getPrimariesOfLinked(linkedId, MangaMapper::mapManga)
            .awaitAsList()
    }

    override suspend fun link(primaryId: Long, linkedId: Long, priority: Long) {
        database.manga_linksQueries.insertLink(primaryId, linkedId, priority)
    }

    override suspend fun unlink(primaryId: Long, linkedId: Long) {
        database.manga_linksQueries.deleteLink(primaryId, linkedId)
    }

    override suspend fun deleteAllForManga(mangaId: Long) {
        database.manga_linksQueries.deleteAllLinksForManga(mangaId)
    }

    override suspend fun setPriority(primaryId: Long, linkedId: Long, priority: Long) {
        database.manga_linksQueries.updatePriority(priority, primaryId, linkedId)
    }

    override suspend fun getAllForBackup(): List<MangaLinkBackupRow> {
        return database.manga_linksQueries
            .getAllLinksForBackup { primarySource, primaryUrl, linkedSource, linkedUrl, priority ->
                MangaLinkBackupRow(primarySource, primaryUrl, linkedSource, linkedUrl, priority)
            }
            .awaitAsList()
    }
}
