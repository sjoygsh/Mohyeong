package eu.kanade.presentation.library.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import eu.kanade.presentation.util.rememberResourceBitmapPainter
import eu.kanade.tachiyomi.R
import kotlinx.coroutines.delay
import tachiyomi.domain.library.model.LibraryManga
import tachiyomi.i18n.MR
import tachiyomi.presentation.core.i18n.stringResource

private const val AUTO_ADVANCE_MS = 4500L
private const val LOOP_PAGES = 10_000

@Composable
fun LibraryMostReadCarousel(
    items: List<LibraryManga>,
    onClickManga: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return

    val count = items.size
    // Start from a high midpoint that's an exact multiple of count so page % count == 0.
    val startPage = remember(count) { (LOOP_PAGES / 2) - ((LOOP_PAGES / 2) % count) }
    val pagerState = rememberPagerState(initialPage = startPage) { LOOP_PAGES }

    // Auto-advance: pause while user is touching/dragging, resume otherwise.
    LaunchedEffect(pagerState, count) {
        while (true) {
            delay(AUTO_ADVANCE_MS)
            if (!pagerState.isScrollInProgress) {
                val next = pagerState.currentPage + 1
                pagerState.animateScrollToPage(next)
            }
        }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 12.dp),
    ) {
        Text(
            text = stringResource(MR.strings.label_most_read),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        HorizontalPager(
            state = pagerState,
            contentPadding = PaddingValues(horizontal = 16.dp),
            pageSpacing = 12.dp,
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp),
        ) { page ->
            val manga = items[page % count]
            BannerCard(
                manga = manga,
                onClick = { onClickManga(manga.id) },
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            val activeIndex = pagerState.currentPage % count
            repeat(count) { index ->
                val isActive = index == activeIndex
                val width by animateDpAsState(
                    targetValue = if (isActive) 18.dp else 6.dp,
                    label = "indicatorWidth",
                )
                Box(
                    modifier = Modifier
                        .padding(horizontal = 3.dp)
                        .size(width = width, height = 6.dp)
                        .clip(CircleShape)
                        .background(
                            if (isActive) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f)
                            },
                        ),
                )
            }
        }
    }
}

@Composable
private fun BannerCard(
    manga: LibraryManga,
    onClick: () -> Unit,
) {
    val total = manga.totalChapters.coerceAtLeast(1)
    val progress = (manga.readCount.toFloat() / total.toFloat()).coerceIn(0f, 1f)
    val percent = (progress * 100f).toInt()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(20.dp))
            .clickable(onClick = onClick),
    ) {
        AsyncImage(
            model = manga.manga,
            placeholder = ColorPainter(Color(0x1F888888)),
            error = rememberResourceBitmapPainter(id = R.drawable.cover_error),
            contentDescription = manga.manga.title,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.55f),
                            Color.Black.copy(alpha = 0.85f),
                        ),
                        startY = 80f,
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            Text(
                text = manga.manga.title,
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                modifier = Modifier.padding(top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier
                        .weight(1f)
                        .height(5.dp)
                        .clip(RoundedCornerShape(3.dp)),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = Color.White.copy(alpha = 0.25f),
                )
                Text(
                    text = stringResource(MR.strings.label_progress_percent, percent),
                    color = Color.White,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 10.dp),
                )
            }
        }
    }
}
