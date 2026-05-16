package tachiyomi.presentation.core.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastForEach
import dev.icerock.moko.resources.StringResource
import kotlinx.collections.immutable.ImmutableList
import tachiyomi.presentation.core.components.ActionButton
import tachiyomi.presentation.core.components.material.padding
import tachiyomi.presentation.core.i18n.stringResource
import tachiyomi.presentation.core.util.secondaryItemAlpha

data class EmptyScreenAction(
    val stringRes: StringResource,
    val icon: ImageVector,
    val onClick: () -> Unit,
)

@Composable
fun EmptyScreen(
    stringRes: StringResource,
    modifier: Modifier = Modifier,
    actions: ImmutableList<EmptyScreenAction>? = null,
) {
    EmptyScreen(
        message = stringResource(stringRes),
        modifier = modifier,
        actions = actions,
    )
}

@Composable
fun EmptyScreen(
    message: String,
    modifier: Modifier = Modifier,
    actions: ImmutableList<EmptyScreenAction>? = null,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = message,
            modifier = Modifier.secondaryItemAlpha(),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )

        if (!actions.isNullOrEmpty()) {
            Row(
                modifier = Modifier
                    .padding(top = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(MaterialTheme.padding.small),
            ) {
                actions.fastForEach {
                    ActionButton(
                        modifier = Modifier.weight(1f),
                        title = stringResource(it.stringRes),
                        icon = it.icon,
                        onClick = it.onClick,
                    )
                }
            }
        }
    }
}

