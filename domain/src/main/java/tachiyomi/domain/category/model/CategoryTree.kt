package tachiyomi.domain.category.model

/**
 * A category paired with its depth in the hierarchy after flattening (root = 0).
 */
data class CategoryWithDepth(
    val category: Category,
    val depth: Int,
)

/**
 * Flattens [categories] into a pre-order traversal of the parent-child tree.
 * Cycles, broken parent references, and the system category are tolerated:
 *  - Unreachable nodes (parent not present in the list) are treated as roots.
 *  - The system category is always included at depth 0 first if present.
 */
fun List<Category>.flattenedHierarchy(): List<CategoryWithDepth> {
    if (isEmpty()) return emptyList()
    val byId = associateBy { it.id }
    val childrenByParent = HashMap<Long?, MutableList<Category>>()
    for (cat in this) {
        val parent = cat.parentId?.takeIf { it != Category.UNCATEGORIZED_ID && byId.containsKey(it) }
        // If the parent reference is broken we promote to root.
        val effectiveParent = if (cat.parentId != null && parent == null && cat.parentId != Category.UNCATEGORIZED_ID) {
            null
        } else {
            parent
        }
        childrenByParent.getOrPut(effectiveParent) { mutableListOf() }.add(cat)
    }
    // Sort each sibling group by `order` for deterministic display.
    for (list in childrenByParent.values) {
        list.sortBy { it.order }
    }

    val result = ArrayList<CategoryWithDepth>(size)
    val visited = HashSet<Long>(size)

    fun dfs(node: Category, depth: Int) {
        if (!visited.add(node.id)) return
        result += CategoryWithDepth(node, depth)
        childrenByParent[node.id]?.forEach { dfs(it, depth + 1) }
    }

    childrenByParent[null]?.forEach { dfs(it, 0) }
    // Any node not yet visited (orphaned by a cycle) — emit at root depth.
    for (cat in this) {
        if (cat.id !in visited) dfs(cat, 0)
    }
    return result
}

/**
 * Returns the breadcrumb string for [category] using slashes, e.g. "Manga / Ongoing / Long".
 * Falls back to the bare name if any ancestor is missing.
 */
fun breadcrumbName(category: Category, all: List<Category>, separator: String = " / "): String {
    val byId = all.associateBy { it.id }
    val parts = ArrayDeque<String>()
    var cursor: Category? = category
    val visited = mutableSetOf<Long>()
    while (cursor != null && cursor.parentId != null && cursor.parentId != Category.UNCATEGORIZED_ID) {
        if (!visited.add(cursor.id)) break
        parts.addFirst(cursor.name)
        cursor = byId[cursor.parentId]
    }
    if (cursor != null) parts.addFirst(cursor.name)
    return parts.joinToString(separator)
}
