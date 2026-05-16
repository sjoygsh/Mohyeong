package eu.kanade.presentation.manga

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.request.ImageRequest
import coil3.request.crossfade
import eu.kanade.presentation.manga.components.MangaCover
import tachiyomi.domain.manga.model.Manga
import tachiyomi.domain.source.service.SourceManager
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

@Composable
fun LinkedSourcesDialog(
    loadLinked: suspend () -> List<Manga>,
    loadCandidates: suspend () -> List<Manga>,
    onLink: (Long) -> Unit,
    onUnlink: (Long) -> Unit,
    onOpenManga: (Long) -> Unit,
    onRefreshAll: () -> Unit,
    onDismissRequest: () -> Unit,
) {
    val sourceManager = remember { Injekt.get<SourceManager>() }

    var linked by remember { mutableStateOf<List<Manga>>(emptyList()) }
    var candidates by remember { mutableStateOf<List<Manga>>(emptyList()) }
    var refreshTrigger by remember { mutableStateOf(0) }
    var pickerOpen by remember { mutableStateOf(false) }

    LaunchedEffect(refreshTrigger) {
        linked = loadLinked()
    }
    LaunchedEffect(pickerOpen, refreshTrigger) {
        if (pickerOpen) candidates = loadCandidates()
    }

    AlertDialog(
        onDismissRequest = onDismissRequest,
        title = { Text(stringResource(MR.strings.action_linked_sources)) },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = stringResource(MR.strings.linked_sources_summary),
                    style = MaterialTheme.typography.bodyMedium,
                )
                HorizontalDivider()
                if (linked.isEmpty()) {
                    Text(
                        text = stringResource(MR.strings.linked_sources_empty),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 320.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        items(items = linked, key = { it.id }) { entry ->
                            LinkedRow(
                                manga = entry,
                                sourceName = sourceManager.getOrStub(entry.source).name,
                                onClick = {
                                    onDismissRequest()
                                    onOpenManga(entry.id)
                                },
                                onRemove = {
                                    onUnlink(entry.id)
                                    refreshTrigger += 1
                                },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    pickerOpen = true
                },
            ) {
                Icon(
                    imageVector = Icons.Outlined.Add,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.size(4.dp))
                Text(stringResource(MR.strings.action_link_from_library))
            }
        },
        dismissButton = {
            Row {
                if (linked.isNotEmpty()) {
                    TextButton(
                        onClick = {
                            onRefreshAll()
                            onDismissRequest()
                        },
                    ) {
                        Text(stringResource(MR.strings.action_refresh_linked))
                    }
                }
                TextButton(onClick = onDismissRequest) {
                    Text(stringResource(MR.strings.action_close))
                }
            }
        },
    )

    if (pickerOpen) {
        AlertDialog(
            onDismissRequest = { pickerOpen = false },
            title = { Text(stringResource(MR.strings.action_link_from_library)) },
            text = {
                if (candidates.isEmpty()) {
                    Text(stringResource(MR.strings.linked_sources_no_candidates))
                } else {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 360.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        items(items = candidates, key = { it.id }) { entry ->
                            CandidateRow(
                                manga = entry,
                                sourceName = sourceManager.getOrStub(entry.source).name,
                                onClick = {
                                    onLink(entry.id)
                                    refreshTrigger += 1
                                    pickerOpen = false
                                },
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { pickerOpen = false }) {
                    Text(stringResource(MR.strings.action_close))
                }
            },
        )
    }
}

@Composable
private fun LinkedRow(
    manga: Manga,
    sourceName: String,
    onClick: () -> Unit,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onClick() }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(modifier = Modifier.size(40.dp, 56.dp)) {
            MangaCover.Book(
                data = ImageRequest.Builder(LocalContext.current)
                    .data(manga)
                    .crossfade(true)
                    .build(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = manga.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = sourceName,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Outlined.Close,
                contentDescription = stringResource(MR.strings.action_remove),
            )
        }
    }
}

@Composable
private fun CandidateRow(
    manga: Manga,
    sourceName: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable { onClick() }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(modifier = Modifier.size(40.dp, 56.dp)) {
            MangaCover.Book(
                data = ImageRequest.Builder(LocalContext.current)
                    .data(manga)
                    .crossfade(true)
                    .build(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = manga.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = sourceName,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
