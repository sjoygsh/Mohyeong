package tachiyomi.domain.category.interactor

import logcat.LogPriority
import tachiyomi.core.common.util.lang.withNonCancellableContext
import tachiyomi.core.common.util.system.logcat
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.category.repository.CategoryRepository

class SetCategoryParent(
    private val categoryRepository: CategoryRepository,
) {

    /**
     * Reparents [categoryId] to [parentId]. Pass null (or the system category id) for top-level.
     * Refuses moves that would create a cycle.
     */
    suspend fun await(categoryId: Long, parentId: Long?): Result = withNonCancellableContext {
        try {
            if (categoryId == Category.UNCATEGORIZED_ID) {
                return@withNonCancellableContext Result.InvalidTarget
            }
            val sanitizedParent = parentId?.takeIf { it != Category.UNCATEGORIZED_ID }
            if (sanitizedParent == categoryId) {
                return@withNonCancellableContext Result.WouldCreateCycle
            }
            if (sanitizedParent != null) {
                val all = categoryRepository.getAll()
                val byId = all.associateBy { it.id }
                // Walk up from the proposed parent; if we ever hit categoryId, it's a cycle.
                var cursor: Long? = sanitizedParent
                val visited = mutableSetOf<Long>()
                while (cursor != null) {
                    if (cursor == categoryId) {
                        return@withNonCancellableContext Result.WouldCreateCycle
                    }
                    if (!visited.add(cursor)) {
                        // Detected a pre-existing cycle in stored data; bail out rather than loop.
                        return@withNonCancellableContext Result.WouldCreateCycle
                    }
                    cursor = byId[cursor]?.parentId
                }
            }
            categoryRepository.setParent(categoryId, sanitizedParent)
            Result.Success
        } catch (e: Exception) {
            logcat(LogPriority.ERROR, e)
            Result.InternalError(e)
        }
    }

    sealed interface Result {
        data object Success : Result
        data object WouldCreateCycle : Result
        data object InvalidTarget : Result
        data class InternalError(val error: Throwable) : Result
    }
}
