package tachiyomi.domain.manga.interactor

import tachiyomi.domain.manga.repository.MangaLinkRepository

class UnlinkManga(
    private val mangaLinkRepository: MangaLinkRepository,
) {

    suspend fun await(primaryId: Long, linkedId: Long) {
        mangaLinkRepository.unlink(primaryId, linkedId)
    }
}
