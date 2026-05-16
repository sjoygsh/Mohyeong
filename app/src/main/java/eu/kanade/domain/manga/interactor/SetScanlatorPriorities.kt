package eu.kanade.domain.manga.interactor

import tachiyomi.data.Database

class SetScanlatorPriorities(
    private val database: Database,
) {

    /**
     * Replaces the stored priority list for the given manga with [orderedScanlators].
     * The first element has highest priority (lowest priority value).
     */
    suspend fun await(mangaId: Long, orderedScanlators: List<String>) {
        database.transaction {
            database.scanlator_priorityQueries.clearForManga(mangaId)
            orderedScanlators.forEachIndexed { index, scanlator ->
                database.scanlator_priorityQueries.insert(mangaId, scanlator, index.toLong())
            }
        }
    }
}
