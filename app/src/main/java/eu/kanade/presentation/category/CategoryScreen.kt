package eu.kanade.presentation.category

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Modifier
import eu.kanade.presentation.category.components.CategoryFloatingActionButton
import eu.kanade.presentation.category.components.CategoryListItem
import eu.kanade.presentation.components.AppBar
import eu.kanade.tachiyomi.ui.category.CategoryScreenState
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.category.model.CategoryWithDepth
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.components.material.Scaffold
import tachiyomi.presentation.core.components.material.padding
import tachiyomi.presentation.core.components.material.topSmallPaddingValues
import tachiyomi.presentation.core.i18n.stringResource
import tachiyomi.presentation.core.screens.EmptyScreen
import tachiyomi.presentation.core.util.plus

@Composable
fun CategoryScreen(
    state: CategoryScreenState.Success,
    onClickCreate: () -> Unit,
    onClickRename: (Category) -> Unit,
    onClickDelete: (Category) -> Unit,
    onClickSetParent: (Category) -> Unit,
    onChangeOrder: (Category, Int) -> Unit,
    navigateUp: () -> Unit,
) {
    val lazyListState = rememberLazyListState()
    Scaffold(
        topBar = { scrollBehavior ->
            AppBar(
                title = stringResource(MR.strings.action_edit_categories),
                navigateUp = navigateUp,
                scrollBehavior = scrollBehavior,
            )
        },
        floatingActionButton = {
            CategoryFloatingActionButton(
                lazyListState = lazyListState,
                onCreate = onClickCreate,
            )
        },
    ) { paddingValues ->
        if (state.isEmpty) {
            EmptyScreen(
                stringRes = MR.strings.information_empty_category,
                modifier = Modifier.padding(paddingValues),
            )
            return@Scaffold
        }

        CategoryContent(
            flattened = state.flattened,
            lazyListState = lazyListState,
            paddingValues = paddingValues,
            onClickRename = onClickRename,
            onClickDelete = onClickDelete,
            onClickSetParent = onClickSetParent,
            onChangeOrder = onChangeOrder,
        )
    }
}

@Composable
private fun CategoryContent(
    flattened: List<CategoryWithDepth>,
    lazyListState: LazyListState,
    paddingValues: PaddingValues,
    onClickRename: (Category) -> Unit,
    onClickDelete: (Category) -> Unit,
    onClickSetParent: (Category) -> Unit,
    onChangeOrder: (Category, Int) -> Unit,
) {
    val itemsState = remember { flattened.toMutableStateList() }
    val reorderableState = rememberReorderableLazyListState(lazyListState, paddingValues) { from, to ->
        val item = itemsState.removeAt(from.index)
        itemsState.add(to.index, item)
        onChangeOrder(item.category, to.index)
    }

    LaunchedEffect(flattened) {
        if (!reorderableState.isAnyItemDragging) {
            itemsState.clear()
            itemsState.addAll(flattened)
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = lazyListState,
        contentPadding = paddingValues +
            topSmallPaddingValues +
            PaddingValues(horizontal = MaterialTheme.padding.medium),
        verticalArrangement = Arrangement.spacedBy(MaterialTheme.padding.small),
    ) {
        items(
            items = itemsState,
            key = { entry -> entry.category.key },
        ) { entry ->
            ReorderableItem(reorderableState, entry.category.key) {
                CategoryListItem(
                    modifier = Modifier.animateItem(),
                    category = entry.category,
                    depth = entry.depth,
                    onRename = { onClickRename(entry.category) },
                    onDelete = { onClickDelete(entry.category) },
                    onSetParent = { onClickSetParent(entry.category) },
                )
            }
        }
    }
}

private val Category.key inline get() = "category-$id"
