package tachiyomi.domain.manga.interactor

import kotlinx.coroutines.flow.Flow
import tachiyomi.domain.manga.model.Manga
import tachiyomi.domain.manga.repository.MangaLinkRepository

class GetLinkedMangas(
    private val mangaLinkRepository: MangaLinkRepository,
) {

    suspend fun await(primaryId: Long): List<Manga> {
        return mangaLinkRepository.getLinkedMangas(primaryId)
    }

    fun subscribe(primaryId: Long): Flow<List<Manga>> {
        return mangaLinkRepository.getLinkedMangasAsFlow(primaryId)
    }

    /** Reverse lookup — see [MangaLinkRepository.getPrimariesOfLinked]. */
    suspend fun primariesOf(linkedId: Long): List<Manga> {
        return mangaLinkRepository.getPrimariesOfLinked(linkedId)
    }

    /** Bulk reverse-lookup snapshot — see [MangaLinkRepository.subscribeAllPrimariesByLinked]. */
    fun subscribeAllPrimariesByLinked(): Flow<Map<Long, Manga>> {
        return mangaLinkRepository.subscribeAllPrimariesByLinked()
    }
}
