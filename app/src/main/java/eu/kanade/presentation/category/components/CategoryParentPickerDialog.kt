package eu.kanade.presentation.category.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SubdirectoryArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.collections.immutable.ImmutableList
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.category.model.CategoryWithDepth
import tachiyomi.domain.category.model.flattenedHierarchy
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.components.material.padding
import tachiyomi.presentation.core.i18n.stringResource

@Composable
fun CategoryParentPickerDialog(
    onDismissRequest: () -> Unit,
    target: Category,
    allCategories: ImmutableList<Category>,
    onConfirm: (parentId: Long?) -> Unit,
) {
    // Exclude the target itself + its descendants — selecting any of them would create a cycle.
    val descendantIds = remember(target, allCategories) {
        val children = allCategories.groupBy { it.parentId }
        val collected = mutableSetOf(target.id)
        val stack = ArrayDeque<Long>().apply { add(target.id) }
        while (stack.isNotEmpty()) {
            val cursor = stack.removeFirst()
            children[cursor].orEmpty().forEach {
                if (collected.add(it.id)) stack.add(it.id)
            }
        }
        collected
    }

    val candidates: List<CategoryWithDepth> = remember(allCategories, descendantIds) {
        allCategories
            .filterNot { it.id in descendantIds }
            .flattenedHierarchy()
    }

    var selected: Long? by remember { mutableStateOf(target.parentId) }

    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = {
            TextButton(onClick = {
                onConfirm(selected)
                onDismissRequest()
            }) {
                Text(text = stringResource(MR.strings.action_ok))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismissRequest) {
                Text(text = stringResource(MR.strings.action_cancel))
            }
        },
        title = { Text(text = stringResource(MR.strings.action_set_parent_category)) },
        text = {
            LazyColumn(modifier = Modifier.heightIn(max = 400.dp)) {
                item(key = "__none__") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { selected = null }
                            .padding(vertical = MaterialTheme.padding.small),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            selected = selected == null,
                            onClick = { selected = null },
                        )
                        Text(text = stringResource(MR.strings.action_no_parent))
                    }
                }
                items(candidates, key = { "cat-${it.category.id}" }) { item ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { selected = item.category.id }
                            .padding(
                                start = (item.depth * 16).dp,
                                top = MaterialTheme.padding.extraSmall,
                                bottom = MaterialTheme.padding.extraSmall,
                            ),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            selected = selected == item.category.id,
                            onClick = { selected = item.category.id },
                        )
                        if (item.depth > 0) {
                            Icon(
                                imageVector = Icons.Outlined.SubdirectoryArrowRight,
                                contentDescription = null,
                                modifier = Modifier.padding(end = MaterialTheme.padding.extraSmall),
                            )
                        }
                        Text(text = item.category.name)
                    }
                }
            }
        },
    )
}
