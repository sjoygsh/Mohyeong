package eu.kanade.tachiyomi.data.backup.restore.restorers

import eu.kanade.tachiyomi.data.backup.models.BackupCategory
import tachiyomi.data.Database
import tachiyomi.domain.category.interactor.GetCategories
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.library.service.LibraryPreferences
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

class CategoriesRestorer(
    private val database: Database = Injekt.get(),
    private val getCategories: GetCategories = Injekt.get(),
    private val libraryPreferences: LibraryPreferences = Injekt.get(),
) {

    suspend operator fun invoke(backupCategories: List<BackupCategory>) {
        if (backupCategories.isEmpty()) return

        val dbCategories = getCategories.await()
        val dbCategoriesByName = dbCategories.associateBy { it.name }
        var nextOrder = dbCategories.maxOfOrNull { it.order }?.plus(1) ?: 0

        // First pass: ensure all categories exist, capture mapping from backup id -> live id.
        val backupIdToLiveId = HashMap<Long, Long>(backupCategories.size)
        val createdCategories = ArrayList<Category>(backupCategories.size)

        for (bc in backupCategories.sortedBy { it.order }) {
            val existing = dbCategoriesByName[bc.name]
            if (existing != null) {
                backupIdToLiveId[bc.id] = existing.id
                continue
            }
            val order = nextOrder++
            database.categoriesQueries.insert(
                name = bc.name,
                order = order,
                flags = bc.flags,
                parentId = null,
            )
            val refreshed = getCategories.await().firstOrNull { it.name == bc.name }
            if (refreshed != null) {
                backupIdToLiveId[bc.id] = refreshed.id
                createdCategories += refreshed
            }
        }

        // Second pass: set parent_id using the remapped ids. Skip self-references and broken refs.
        for (bc in backupCategories) {
            val liveId = backupIdToLiveId[bc.id] ?: continue
            val backupParent = bc.parentId ?: continue
            val liveParent = backupIdToLiveId[backupParent] ?: continue
            if (liveParent == liveId) continue
            database.categoriesQueries.updateParent(parentId = liveParent, categoryId = liveId)
        }

        libraryPreferences.categorizedDisplaySettings.set(
            (dbCategories + createdCategories)
                .distinctBy { it.flags }
                .size > 1,
        )
    }
}
