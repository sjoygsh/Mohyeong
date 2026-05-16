package tachiyomi.domain.manga.interactor

import tachiyomi.domain.manga.repository.MangaLinkRepository

class LinkManga(
    private val mangaLinkRepository: MangaLinkRepository,
) {

    suspend fun await(primaryId: Long, linkedId: Long, priority: Long = 0L) {
        if (primaryId == linkedId) return
        mangaLinkRepository.link(primaryId, linkedId, priority)
    }
}
