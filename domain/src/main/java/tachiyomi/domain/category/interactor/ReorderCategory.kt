package tachiyomi.domain.category.interactor

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import logcat.LogPriority
import tachiyomi.core.common.util.lang.withNonCancellableContext
import tachiyomi.core.common.util.system.logcat
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.category.model.CategoryUpdate
import tachiyomi.domain.category.repository.CategoryRepository

class ReorderCategory(
    private val categoryRepository: CategoryRepository,
) {
    private val mutex = Mutex()

    suspend fun await(category: Category, newIndex: Int) = withNonCancellableContext {
        mutex.withLock {
            val all = categoryRepository.getAll()
                .filterNot(Category::isSystemCategory)

            // Reorder is constrained to siblings (same parent_id). The newIndex passed by the
            // flat-list UI is interpreted by ignoring entries that belong to other parents.
            val siblings = all.filter { it.parentId == category.parentId }.toMutableList()
            val currentSiblingIndex = siblings.indexOfFirst { it.id == category.id }
            if (currentSiblingIndex == -1) {
                return@withNonCancellableContext Result.Unchanged
            }

            // Translate the flat newIndex to a sibling index by counting how many siblings
            // appear at or before newIndex in the flat list.
            val flatIndex = all.indexOfFirst { it.id == category.id }
            val movingForward = newIndex > flatIndex
            val targetSiblingIndex = if (movingForward) {
                all.subList(0, (newIndex + 1).coerceAtMost(all.size))
                    .count { it.parentId == category.parentId && it.id != category.id }
                    .coerceIn(0, siblings.size - 1)
            } else {
                all.subList(0, newIndex.coerceIn(0, all.size))
                    .count { it.parentId == category.parentId && it.id != category.id }
                    .coerceIn(0, siblings.size - 1)
            }

            if (currentSiblingIndex == targetSiblingIndex) {
                return@withNonCancellableContext Result.Unchanged
            }

            try {
                siblings.add(targetSiblingIndex, siblings.removeAt(currentSiblingIndex))

                // Preserve the original `sort` slots used by these siblings (so unrelated
                // categories' sort values are untouched) and redistribute them in new order.
                val originalSorts = all
                    .filter { it.parentId == category.parentId }
                    .map { it.order }
                    .sorted()

                val updates = siblings.mapIndexed { index, sibling ->
                    CategoryUpdate(
                        id = sibling.id,
                        order = originalSorts.getOrElse(index) { index.toLong() },
                    )
                }

                categoryRepository.updatePartial(updates)
                Result.Success
            } catch (e: Exception) {
                logcat(LogPriority.ERROR, e)
                Result.InternalError(e)
            }
        }
    }

    sealed interface Result {
        data object Success : Result
        data object Unchanged : Result
        data class InternalError(val error: Throwable) : Result
    }
}
