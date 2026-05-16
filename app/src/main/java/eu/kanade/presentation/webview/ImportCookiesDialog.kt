package eu.kanade.presentation.webview

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import eu.kanade.tachiyomi.util.system.toast
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource

@Composable
fun ImportCookiesDialog(
    url: String,
    onDismiss: () -> Unit,
    onImport: (raw: String) -> Int?,
) {
    val context = LocalContext.current
    var raw by remember { mutableStateOf("") }
    val invalidUrlMsg = stringResource(MR.strings.cookie_import_invalid_url)
    val resultTemplate = stringResource(MR.strings.cookie_import_result)
    val emptyMsg = stringResource(MR.strings.cookie_import_empty)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = stringResource(MR.strings.pref_import_cookies)) },
        text = {
            Column {
                Text(
                    text = url,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
                Text(
                    text = stringResource(MR.strings.cookie_import_help),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 12.dp),
                )
                OutlinedTextField(
                    value = raw,
                    onValueChange = { raw = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp),
                    placeholder = {
                        Text(text = "cf_clearance=...; session=...")
                    },
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val count = onImport(raw)
                when {
                    count == null -> context.toast(invalidUrlMsg)
                    count == 0 -> context.toast(emptyMsg)
                    else -> context.toast(resultTemplate.replace("%d", count.toString()))
                }
                onDismiss()
            }) {
                Text(text = stringResource(MR.strings.action_import))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(text = stringResource(MR.strings.action_cancel))
            }
        },
    )
}
