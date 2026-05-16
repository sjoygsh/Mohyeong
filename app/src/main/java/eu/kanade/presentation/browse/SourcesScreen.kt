package eu.kanade.presentation.browse

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import eu.kanade.presentation.browse.components.BaseSourceItem
import eu.kanade.tachiyomi.ui.browse.source.SourcesScreenModel
import eu.kanade.tachiyomi.ui.browse.source.browse.BrowseSourceScreenModel.Listing
import eu.kanade.tachiyomi.util.system.LocaleHelper
import tachiyomi.domain.source.model.Pin
import tachiyomi.domain.source.model.Source
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.components.ScrollbarLazyColumn
import tachiyomi.presentation.core.components.material.SECONDARY_ALPHA
import tachiyomi.presentation.core.components.material.padding
import tachiyomi.presentation.core.components.material.topSmallPaddingValues
import tachiyomi.presentation.core.i18n.stringResource
import tachiyomi.presentation.core.screens.EmptyScreen
import tachiyomi.presentation.core.screens.LoadingScreen
import tachiyomi.presentation.core.theme.header
import tachiyomi.presentation.core.util.plus
import tachiyomi.source.local.isLocal

@Composable
fun SourcesScreen(
    state: SourcesScreenModel.State,
    contentPadding: PaddingValues,
    onClickItem: (Source, Listing) -> Unit,
    onClickPin: (Source) -> Unit,
    onLongClickItem: (Source) -> Unit,
    onChangeSearchQuery: (String?) -> Unit = {},
    onToggleSearchMode: () -> Unit = {},
    onSubmitGlobalSearch: (String) -> Unit = {},
) {
    when {
        state.isLoading -> LoadingScreen(Modifier.padding(contentPadding))
        state.isEmpty -> EmptyScreen(
            stringRes = MR.strings.source_empty_screen,
            modifier = Modifier.padding(contentPadding),
        )
        else -> {
            Column(
                modifier = Modifier.padding(
                    top = contentPadding.calculateTopPadding(),
                    start = contentPadding.calculateStartPadding(LocalLayoutDirection.current),
                    end = contentPadding.calculateEndPadding(LocalLayoutDirection.current),
                ),
            ) {
                SourcesSearchRow(
                    query = state.searchQuery.orEmpty(),
                    mode = state.searchMode,
                    onChangeQuery = { onChangeSearchQuery(it.takeIf { q -> q.isNotEmpty() }) },
                    onToggleMode = onToggleSearchMode,
                    onSubmitGlobalSearch = onSubmitGlobalSearch,
                )
                ScrollbarLazyColumn(
                    contentPadding = PaddingValues(bottom = contentPadding.calculateBottomPadding()) + topSmallPaddingValues,
                ) {
                    items(
                        items = state.displayedItems,
                        contentType = {
                            when (it) {
                                is SourceUiModel.Header -> "header"
                                is SourceUiModel.Item -> "item"
                            }
                        },
                        key = {
                            when (it) {
                                is SourceUiModel.Header -> it.hashCode()
                                is SourceUiModel.Item -> "source-${it.source.key()}"
                            }
                        },
                    ) { model ->
                        when (model) {
                            is SourceUiModel.Header -> {
                                SourceHeader(
                                    modifier = Modifier.animateItem(),
                                    language = model.language,
                                )
                            }
                            is SourceUiModel.Item -> SourceItem(
                                modifier = Modifier.animateItem(),
                                source = model.source,
                                onClickItem = onClickItem,
                                onLongClickItem = onLongClickItem,
                                onClickPin = onClickPin,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SourcesSearchRow(
    query: String,
    mode: SourcesScreenModel.SearchMode,
    onChangeQuery: (String) -> Unit,
    onToggleMode: () -> Unit,
    onSubmitGlobalSearch: (String) -> Unit,
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val isGlobal = mode == SourcesScreenModel.SearchMode.Global
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = onChangeQuery,
            modifier = Modifier.weight(1f),
            placeholder = {
                Text(
                    text = stringResource(
                        if (isGlobal) {
                            MR.strings.action_global_search_hint
                        } else {
                            MR.strings.action_filter_sources_hint
                        },
                    ),
                )
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                imeAction = if (isGlobal) ImeAction.Search else ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onSearch = {
                    if (isGlobal && query.isNotBlank()) {
                        onSubmitGlobalSearch(query)
                        keyboard?.hide()
                    }
                },
                onDone = { keyboard?.hide() },
            ),
        )
        IconButton(
            onClick = onToggleMode,
            modifier = Modifier.padding(start = 4.dp),
        ) {
            Icon(
                imageVector = if (isGlobal) Icons.Outlined.TravelExplore else Icons.Outlined.FilterAlt,
                contentDescription = stringResource(
                    if (isGlobal) {
                        MR.strings.action_search_mode_global
                    } else {
                        MR.strings.action_search_mode_filter
                    },
                ),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
    if (isGlobal && query.isNotBlank()) {
        // Hint row showing what pressing Enter will do.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 2.dp),
        ) {
            Text(
                text = stringResource(MR.strings.action_global_search_press_enter),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SourceHeader(
    language: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Text(
        text = LocaleHelper.getSourceDisplayName(language, context),
        modifier = modifier
            .padding(horizontal = MaterialTheme.padding.medium, vertical = MaterialTheme.padding.small),
        style = MaterialTheme.typography.header,
    )
}

@Composable
private fun SourceItem(
    source: Source,
    onClickItem: (Source, Listing) -> Unit,
    onLongClickItem: (Source) -> Unit,
    onClickPin: (Source) -> Unit,
    modifier: Modifier = Modifier,
) {
    BaseSourceItem(
        modifier = modifier,
        source = source,
        onClickItem = { onClickItem(source, Listing.Popular) },
        onLongClickItem = { onLongClickItem(source) },
        action = {
            if (source.supportsLatest) {
                TextButton(onClick = { onClickItem(source, Listing.Latest) }) {
                    Text(
                        text = stringResource(MR.strings.latest),
                        style = LocalTextStyle.current.copy(
                            color = MaterialTheme.colorScheme.primary,
                        ),
                    )
                }
            }
            SourcePinButton(
                isPinned = Pin.Pinned in source.pin,
                onClick = { onClickPin(source) },
            )
        },
    )
}

@Composable
private fun SourcePinButton(
    isPinned: Boolean,
    onClick: () -> Unit,
) {
    val icon = if (isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin
    val tint = if (isPinned) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onBackground.copy(
            alpha = SECONDARY_ALPHA,
        )
    }
    val description = if (isPinned) MR.strings.action_unpin else MR.strings.action_pin
    IconButton(onClick = onClick) {
        Icon(
            imageVector = icon,
            tint = tint,
            contentDescription = stringResource(description),
        )
    }
}

@Composable
fun SourceOptionsDialog(
    source: Source,
    onClickPin: () -> Unit,
    onClickDisable: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        title = {
            Text(text = source.visualName)
        },
        text = {
            Column {
                val textId = if (Pin.Pinned in source.pin) MR.strings.action_unpin else MR.strings.action_pin
                Text(
                    text = stringResource(textId),
                    modifier = Modifier
                        .clickable(onClick = onClickPin)
                        .fillMaxWidth()
                        .padding(vertical = 16.dp),
                )
                if (!source.isLocal()) {
                    Text(
                        text = stringResource(MR.strings.action_disable),
                        modifier = Modifier
                            .clickable(onClick = onClickDisable)
                            .fillMaxWidth()
                            .padding(vertical = 16.dp),
                    )
                }
            }
        },
        onDismissRequest = onDismiss,
        confirmButton = {},
    )
}

sealed interface SourceUiModel {
    data class Item(val source: Source) : SourceUiModel
    data class Header(val language: String) : SourceUiModel
}
