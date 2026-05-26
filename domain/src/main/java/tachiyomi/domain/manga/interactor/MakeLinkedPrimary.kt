package tachiyomi.domain.manga.interactor

import tachiyomi.domain.manga.repository.MangaLinkRepository

/**
 * Promotes a linked manga to be the primary of its cluster. Conceptually:
 *   before: oldPrimary -> [newPrimary, otherLinkedA, otherLinkedB]
 *   after:  newPrimary -> [oldPrimary, otherLinkedA, otherLinkedB]
 *
 * Implementation: delete every link row that involves oldPrimary on either
 * side, then re-insert them with newPrimary as the primary side. The newly
 * promoted manga gets oldPrimary as one of its new linked entries.
 *
 * Caller must ensure [newPrimaryId] is favorited before calling — otherwise
 * the cluster's library entry vanishes after the swap.
 */
class MakeLinkedPrimary(
    private val mangaLinkRepository: MangaLinkRepository,
    private val getLinkedMangas: GetLinkedMangas,
) {

    suspend fun await(oldPrimaryId: Long, newPrimaryId: Long) {
        if (oldPrimaryId == newPrimaryId) return

        // Snapshot current cluster: oldPrimary's linked list (which must include newPrimaryId).
        val currentLinked = getLinkedMangas.await(oldPrimaryId)
        if (currentLinked.none { it.id == newPrimaryId }) return

        // Wipe every link row touching oldPrimary on either side. This drops the
        // (oldPrimary -> *) edges; (* -> oldPrimary) edges are unlikely but cleared
        // defensively.
        mangaLinkRepository.deleteAllForManga(oldPrimaryId)

        // Re-insert with newPrimary as the primary side. Old primary becomes a
        // linked entry; siblings of newPrimary in the original cluster carry over.
        mangaLinkRepository.link(newPrimaryId, oldPrimaryId, priority = 0L)
        currentLinked
            .asSequence()
            .filter { it.id != newPrimaryId }
            .forEachIndexed { i, sibling ->
                mangaLinkRepository.link(newPrimaryId, sibling.id, priority = (i + 1).toLong())
            }
    }
}
