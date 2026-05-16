package eu.kanade.presentation.manga.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource

@Composable
fun BookmarkNoteDialog(
    initialNote: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var text by remember { mutableStateOf(initialNote) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = stringResource(MR.strings.bookmark_note_title)) },
        text = {
            Column {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp),
                    placeholder = {
                        Text(text = stringResource(MR.strings.bookmark_note_placeholder))
                    },
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onSave(text)
                onDismiss()
            }) {
                Text(text = stringResource(MR.strings.action_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(text = stringResource(MR.strings.action_cancel))
            }
        },
    )
}
