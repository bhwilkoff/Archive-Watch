package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.PosterImage
import app.archivewatch.android.ui.accentColor
import app.archivewatch.android.ui.theme.BrandSurface
import kotlinx.coroutines.launch

/**
 * TV content primitives. Deliberately thin: they reuse the shared
 * [PosterImage] / [accentColor] fallback chain verbatim so artwork behaviour
 * cannot drift between phone and TV (docs/TV-DESIGN.md §1.1 — one product).
 * What differs is size, focus treatment and type scale — nothing else.
 */

/** §4.6 — the one TV content tile: 2:3 poster + title + year, focus-scaled. */
@Composable
fun TvPosterTile(
    item: CatalogItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
    exitLeftTo: FocusRequester? = null,
    onFocused: () -> Unit = {},
) {
    Column(
        modifier = modifier
            .width(TvDims.PosterWidth)
            .tvFocusable(
                onClick = onClick,
                focusRequester = focusRequester,
                ringColor = item.accentColor,
                onFocused = onFocused,
                exitLeftTo = exitLeftTo,
                focusTag = "tile:" + item.title.take(28),
            ),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(10.dp))
                .background(BrandSurface),
        ) {
            PosterImage(item, Modifier.fillMaxSize())
        }
        Text(
            item.title,
            // §4.3 — 24sp is the ten-foot body floor. Tile captions sit at the
            // floor, never below it.
            fontSize = 24.sp,
            lineHeight = 28.sp,
            color = Color.White,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 10.dp),
        )
        item.year?.let {
            Text(
                it.toString(),
                fontSize = 20.sp,
                color = Color(0xFFB0B0B0),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

/**
 * §4.6 — a horizontal shelf. The row keeps the focused tile scrolled into view
 * (§3.3): a tile focused under the overscan margin or off-screen is a bug, and
 * the D-pad has no other way to reveal it.
 */
@Composable
fun TvShelfRow(
    title: String,
    items: List<CatalogItem>,
    onItem: (CatalogItem) -> Unit,
    subtitle: String? = null,
    firstItemFocusRequester: FocusRequester? = null,
    state: LazyListState = rememberLazyListState(),
    onItemFocused: ((CatalogItem) -> Unit)? = null,
) {
    if (items.isEmpty()) return
    val scope = rememberCoroutineScope()
    val railFocus = LocalTvRailFocus.current

    Column(Modifier.padding(bottom = TvDims.RowSpacing)) {
        Column(Modifier.padding(start = TvDims.OverscanH, bottom = 12.dp)) {
            Text(
                title,
                fontSize = 32.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
            if (subtitle != null) {
                Text(
                    subtitle,
                    fontSize = 20.sp,
                    color = Color(0xFF9A9A9A),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        LazyRow(
            state = state,
            // Leading inset = the overscan margin so the first tile is never
            // under the bezel; trailing inset lets the LAST tile scroll clear
            // of the edge when focused (§3.3).
            contentPadding = PaddingValues(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH * 2,
            ),
            horizontalArrangement = Arrangement.spacedBy(TvDims.PosterSpacing),
        ) {
            itemsIndexed(items, key = { _, it -> it.archiveID }) { index, item ->
                TvPosterTile(
                    item = item,
                    onClick = { onItem(item) },
                    focusRequester = if (index == 0) firstItemFocusRequester else null,
                    // §3.4 — the leftmost tile is the door back to the nav rail.
                    exitLeftTo = if (index == 0) railFocus else null,
                    onFocused = {
                        onItemFocused?.invoke(item)
                        scope.launch {
                            // Keep one tile of context visible behind the focused
                            // one rather than snapping it flush to the edge.
                            state.animateScrollToItem(
                                index = (index - 1).coerceAtLeast(0),
                            )
                        }
                    },
                )
            }
        }
    }
}

/** §4.3 — a section title used outside a shelf (grids, detail sections). */
@Composable
fun TvSectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        fontSize = 32.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.White,
        modifier = modifier,
    )
}

/** Loading / empty states sized for ten feet (`universal-feature-states`). */
@Composable
fun TvMessage(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxSize().padding(TvDims.OverscanH),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, fontSize = 26.sp, color = Color(0xFFB0B0B0))
    }
}
