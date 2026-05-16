package eu.kanade.presentation.category

import android.content.Context
import androidx.compose.runtime.Composable
import tachiyomi.core.common.i18n.stringResource
import tachiyomi.domain.category.model.Category
import tachiyomi.domain.category.model.breadcrumbName
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource

val Category.visualName: String
    @Composable
    get() = when {
        isSystemCategory -> stringResource(MR.strings.label_default)
        else -> name
    }

fun Category.visualName(context: Context): String =
    when {
        isSystemCategory -> context.stringResource(MR.strings.label_default)
        else -> name
    }

/**
 * Visual name including parent path, e.g. "Manga / Ongoing". For the system or top-level
 * categories this falls through to the regular [visualName].
 */
@Composable
fun Category.hierarchicalVisualName(all: List<Category>): String = when {
    isSystemCategory -> stringResource(MR.strings.label_default)
    parentId == null || parentId == Category.UNCATEGORIZED_ID -> name
    else -> breadcrumbName(this, all)
}

fun Category.hierarchicalVisualName(context: Context, all: List<Category>): String = when {
    isSystemCategory -> context.stringResource(MR.strings.label_default)
    parentId == null || parentId == Category.UNCATEGORIZED_ID -> name
    else -> breadcrumbName(this, all)
}
