package eu.kanade.domain.manga.interactor

import app.cash.sqldelight.async.coroutines.awaitAsList
import tachiyomi.data.Database

class GetScanlatorPriorities(
    private val database: Database,
) {

    /**
     * Returns scanlator names ordered by their stored priority (most-preferred first).
     * Scanlators with no stored priority are not included.
     */
    suspend fun await(mangaId: Long): List<String> {
        return database.scanlator_priorityQueries
            .getPrioritiesByMangaId(mangaId)
            .awaitAsList()
            .map { it.scanlator }
    }
}
