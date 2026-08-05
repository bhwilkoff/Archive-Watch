package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.accentColor
import kotlinx.coroutines.launch

/**
 * TV Detail (docs/TV-DESIGN.md §2 — depth ≤ 2, so this is the last push).
 *
 * Reuses the phone screen's data path verbatim (`db.item` / `db.related` /
 * `userState`) and the same `PlaySpec` construction — only the presentation is
 * ten-foot. §1.6: the page is a door, not a poster, so the synopsis and the
 * "More Like This" row give the viewer somewhere to go next.
 */
@Composable
fun TvDetailScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val scope = rememberCoroutineScope()

    var retry by remember { mutableIntStateOf(0) }
    val item by produceState<CatalogItem?>(null, archiveID, dbVersion, retry) {
        value = container.catalog.db?.item(archiveID)
    }
    val related by produceState<List<CatalogItem>>(emptyList(), item) {
        value = item?.let { container.catalog.db?.related(it) } ?: emptyList()
    }
    var favorite by remember { mutableStateOf(false) }
    LaunchedEffect(archiveID) { favorite = container.userState.isFavorite(archiveID) }

    val playFocus = remember { FocusRequester() }
    val anchor = remember { FocusRequester() }

    val current = item
    if (current == null) {
        // Same 8s timeout as the phone screen: db.item() returns null BOTH while
        // the DB opens and for an id that isn't in the catalog, and without the
        // timeout the second case spins forever.
        val failed by produceState(false, archiveID, dbVersion, retry) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        FocusAnchor(anchor)
        ClaimInitialFocus(anchor)
        TvMessage(
            if (failed) "This title isn't in the catalog anymore — it may have moved."
            else "Loading…",
        )
        return
    }

    // §3.1 — Play owns initial focus: it is what the viewer came for, and it
    // means one press of the remote starts the film.
    ClaimInitialFocus(playFocus, key = current.archiveID)

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = TvDims.OverscanV * 2),
    ) {
        item(key = "hero") {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(430.dp),
            ) {
                BackdropImage(
                    url = current.backdropURL ?: current.posterURL,
                    contentDescription = current.title,
                    accent = current.accentColor,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color(0x99000000),
                                0.5f to Color(0x66000000),
                                1f to Color(0xFF000000),
                            ),
                        ),
                )
                Column(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.6f),
                ) {
                    Text(
                        current.title,
                        fontSize = 52.sp,
                        lineHeight = 58.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val meta = listOfNotNull(
                        current.year?.toString(),
                        current.runtimeSeconds?.let { "${it / 60} min" },
                        current.contentType.replace('-', ' ').replaceFirstChar { it.uppercase() },
                    ).joinToString("  ·  ")
                    Text(
                        meta,
                        fontSize = 22.sp,
                        color = Color(0xFFCFCFCF),
                        modifier = Modifier.padding(top = 10.dp),
                    )
                }
            }
        }

        item(key = "actions") {
            Row(
                Modifier.padding(start = TvDims.OverscanH, top = 8.dp, bottom = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val playable = current.downloadURL != null
                TvActionButton(
                    label = if (playable) "Play" else "Not playable",
                    icon = { Icon(Icons.Default.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(28.dp)) },
                    focusRequester = playFocus,
                    primary = true,
                    enabled = playable,
                    accent = current.accentColor,
                ) {
                    current.downloadURL?.let { url ->
                        nav.push(
                            Route.Player(
                                PlaySpec(
                                    id = current.archiveID,
                                    title = current.title,
                                    description = current.synopsis,
                                    url = url,
                                    captions = current.captions ?: emptyList(),
                                    runtimeSeconds = current.runtimeSeconds,
                                ),
                            ),
                        )
                    }
                }
                TvActionButton(
                    label = if (favorite) "Favorited" else "Favorite",
                    icon = {
                        Icon(
                            if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            null, tint = Color.White, modifier = Modifier.size(26.dp),
                        )
                    },
                    accent = current.accentColor,
                ) {
                    scope.launch { favorite = container.userState.toggleFavorite(current.archiveID) }
                }
            }
        }

        current.synopsis?.takeIf { it.isNotBlank() }?.let { synopsis ->
            item(key = "synopsis") {
                Text(
                    synopsis,
                    fontSize = 24.sp,
                    lineHeight = 34.sp,
                    color = Color(0xFFDDDDDD),
                    modifier = Modifier
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.72f),
                )
            }
        }

        if (related.isNotEmpty()) {
            item(key = "related") {
                TvShelfRow(
                    "More Like This",
                    related,
                    onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                )
            }
        }
    }
}

/**
 * A ten-foot action button. Deliberately NOT Material3 `Button`: the phone
 * button is sized for a fingertip and its ripple/elevation carry pressed state,
 * neither of which reads at ten feet. Here focus is the state that matters
 * (§3.2 — scale + ring + lift), so the button is a focusable surface.
 */
@Composable
private fun TvActionButton(
    label: String,
    icon: @Composable () -> Unit,
    accent: Color,
    focusRequester: FocusRequester? = null,
    primary: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .tvFocusable(
                onClick = { if (enabled) onClick() },
                focusRequester = focusRequester,
                shape = RoundedCornerShape(28.dp),
                ringColor = if (primary) Color.White else accent,
                scaleWhenFocused = 1.05f,
            )
            .background(
                when {
                    !enabled -> Color(0xFF2A2A2A)
                    primary -> accent
                    else -> Color(0xFF1C1C1C)
                },
                RoundedCornerShape(28.dp),
            )
            .padding(horizontal = 30.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        Text(
            label,
            fontSize = 24.sp,
            fontWeight = if (primary) FontWeight.SemiBold else FontWeight.Normal,
            color = when {
                !enabled -> Color(0xFF888888)
                primary -> Color.Black
                else -> Color.White
            },
        )
    }
}
