package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.data.SeriesDetail
import app.archivewatch.android.data.SeriesEpisode
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.KindEyebrow
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.screens.episodeName
import app.archivewatch.android.ui.screens.seasonLabel
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.PlaySpec

/** The Classic TV accent (Decision 013) — the series scene is always television. */
private val TvSeriesAccent = Color(0xFF2D5BFF)

/**
 * The TV-native Series scene (TV-DESIGN §4.9). Until 2026-09-04 the TV routed a
 * series to the shared PHONE screen — a centred poster card under a back-arrow
 * app bar, phone type at ten feet, no eyebrow, no episodes in frame. This is the
 * tvOS SeriesDetailView's shape on the Android TV Detail's idiom: the same hero
 * (a sharp 16:9 backdrop, or the poster blurred into an ambient wash with the
 * poster itself fitted whole at the trailing edge), the category eyebrow, a
 * meta line of year range · episode count · seasons · network, favorite + share,
 * the overview, season chips that SELECT ON FOCUS (the Apple TV app's rule — no
 * extra press), and episode rows with a still or a monogram, the number label,
 * the derived episode name, the blurb and a resume bar.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun TvSeriesScreen(container: AppContainer, nav: Nav, slug: String) {
    var retry by remember { mutableIntStateOf(0) }
    val series by produceState<SeriesDetail?>(null, slug, retry) {
        value = container.editorial.series(slug)
    }
    val scope = rememberCoroutineScope()
    val anchor = remember { FocusRequester() }
    val firstFocus = remember { FocusRequester() }
    val current = series

    if (current == null) {
        val failed by produceState(false, slug, retry) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        FocusAnchor(anchor)
        ClaimInitialFocus(anchor)
        TvMessage(if (failed) "Couldn't load this series. Check your connection and try again." else "Loading…")
        return
    }

    // The series is favorited under its own "series:<slug>" id, exactly as tvOS
    // does with the SeriesCard's archiveID, so the two islands agree.
    val seriesFavID = "series:$slug"
    var favorite by remember(seriesFavID) { mutableStateOf(false) }
    LaunchedEffect(seriesFavID) { favorite = container.userState.isFavorite(seriesFavID) }
    var showShare by remember { mutableStateOf(false) }

    var seasonIndex by remember(current.seriesID) { mutableIntStateOf(0) }
    val seasons = current.seasons
    val onlySeason = seasons.size == 1
    val season = seasons.getOrNull(seasonIndex)

    ClaimInitialFocus(firstFocus, key = current.seriesID)
    val listState = rememberLazyListState()
    // The TV Detail's guard: whatever bring-into-view did while focus was
    // claimed, the viewer ARRIVES at the top of the scene.
    LaunchedEffect(current.seriesID) {
        // 300 ms: AFTER the focus claim's own bring-into-view (the Detail's timing).
        kotlinx.coroutines.delay(300)
        runCatching { listState.scrollToItem(0) }
    }

    LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        item(key = "hero") {
          // ONE Column: the artwork and the action row are a single item (the TV
          // Detail's rule), and as bare siblings in a lazy item they were not
          // stacked — the action row was drawn over the hero's lower half, which
          // read as "the hero is a 300 px band" (measured at rest, no scroll).
          Column {
            // A fixed height, exactly as the TV Detail hero (400dp = the 2.4:1 band
            // at the 1920x1080 baseline), so the item measures identically to it.
            Box(Modifier.fillMaxWidth().height(400.dp)) {
                val heroBackdrop = current.backdropURL
                val heroPoster = current.posterURL
                val posterOnly = heroBackdrop == null
                BackdropImage(
                    url = heroBackdrop ?: heroPoster,
                    contentDescription = if (heroBackdrop != null) current.title else null,
                    accent = TvSeriesAccent,
                    modifier = Modifier.fillMaxSize(),
                    soft = posterOnly,
                )
                val top = if (posterOnly) Color(0xB3000000) else Color(0x99000000)
                val mid = if (posterOnly) Color(0x8C000000) else Color(0x66000000)
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(0f to top, 0.5f to mid, 1f to Color(0xFF000000)),
                    ),
                )
                if (posterOnly && heroPoster != null) {
                    AsyncImage(
                        model = heroPoster,
                        contentDescription = current.title,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .align(Alignment.CenterEnd)
                            .padding(end = TvDims.OverscanH, top = 20.dp, bottom = 20.dp)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(10.dp)),
                    )
                }
                Column(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.6f),
                ) {
                    KindEyebrow("tv-series", TvSeriesAccent, Modifier.padding(bottom = 6.dp))
                    Text(
                        current.title,
                        fontSize = 36.sp,
                        lineHeight = 40.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val have = current.episodesCount ?: seasons.sumOf { it.episodes.size }
                    val meta = listOfNotNull(
                        yearRange(current.yearStart, current.yearEnd),
                        episodeCountLabel(have, current.canonicalEpisodesCount),
                        seasons.size.takeIf { it > 0 }?.let { "$it season${if (it == 1) "" else "s"}" },
                        current.networks.firstOrNull()?.let { "Aired on $it" },
                    ).joinToString("  ·  ")
                    if (meta.isNotEmpty()) {
                        Text(meta, fontSize = 14.sp, color = Color(0xFFCFCFCF), modifier = Modifier.padding(top = 10.dp))
                    }
                }
            }
            // The action row lives INSIDE the hero item (the TV Detail's shape).
            // As its own lazy item, claiming initial focus on Favorite made the
            // list bring that item into view and scroll the hero to a 300 px
            // band at rest — measured on the Google TV at 16 s.
            Row(
                Modifier.padding(start = TvDims.OverscanH, top = 8.dp, bottom = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TvActionButton(
                    label = if (favorite) "Favorited" else "Favorite",
                    icon = {
                        Icon(
                            if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null,
                            tint = if (favorite) TvSeriesAccent else Color.White, modifier = Modifier.size(18.dp),
                        )
                    },
                    focusRequester = firstFocus,
                    accent = TvSeriesAccent,
                ) { scope.launch { favorite = container.userState.toggleFavorite(seriesFavID) } }
                TvActionButton(
                    label = "Share",
                    icon = { Icon(Icons.Default.Share, null, tint = Color.White, modifier = Modifier.size(18.dp)) },
                    accent = TvSeriesAccent,
                ) { showShare = true }
            }
          }
        }

        current.overview?.takeIf { it.isNotBlank() }?.let { overview ->
            item(key = "overview") {
                // Focusable so the D-pad can stop on it and the list scrolls it
                // into view — the whole text is readable, never a cut (the TV
                // Detail's rule).
                var focused by remember { mutableStateOf(false) }
                Text(
                    overview,
                    fontSize = 15.sp,
                    lineHeight = 23.sp,
                    color = if (focused) Color.White else Color(0xFFDDDDDD),
                    modifier = Modifier
                        .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 24.dp)
                        .fillMaxWidth(0.72f)
                        .onFocusChanged { focused = it.isFocused }
                        .focusable(),
                )
            }
        }

        if (seasons.size > 1) {
            item(key = "seasons") {
                // A plain scrollable Row, not a LazyRow: nested inside the
                // LazyColumn, a LazyRow swallowed the FIRST Right after focus
                // landed on a chip (measured 573 -> 576 -> 780 px, unchanged by
                // a 3 s settle or a focusGroup), while the search's non-lazy
                // chip row walks on the first press. Eight chips need no laziness.
                // NOT a scrollable container. A LazyRow and a horizontalScroll Row
                // both swallowed the FIRST Right after focus landed on a chip
                // (573 -> 576 -> 780 px), while the non-scrolling action Row in the
                // same LazyColumn walks on the first press: the scrollable's
                // bring-into-view is eating the key. Nine chips wrap to two lines.
                FlowRow(
                    Modifier.padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    seasons.forEachIndexed { idx, s ->
                        val on = idx == seasonIndex
                        // The season changes as focus moves across the chips — no
                        // extra Select press (the Apple TV app's behaviour).
                        Box(
                            Modifier
                                .tvFocusable(onClick = { seasonIndex = idx }, shape = RoundedCornerShape(24.dp), onFocused = { seasonIndex = idx })
                                .background(if (on) TvSeriesAccent else Color(0xFF1E1E22), RoundedCornerShape(24.dp))
                                .padding(horizontal = 22.dp, vertical = 10.dp),
                        ) {
                            Text(
                                seasonLabel(s.seasonNumber, onlySeason),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White,
                            )
                        }
                    }
                }
            }
        }

        items(season?.episodes.orEmpty(), key = { it.archiveID ?: "${it.seasonNumber}x${it.episodeNumber}-${it.title}" }) { ep ->
            TvEpisodeRow(container, ep, current.title, TvSeriesAccent) {
                val aid = ep.archiveID
                if (aid != null) {
                    nav.openItem(aid, current.seriesID, "tv-episode")
                } else if (ep.downloadURL != null) {
                    nav.push(
                        Route.Player(
                            PlaySpec(
                                id = ep.downloadURL!!,
                                title = current.title,
                                subtitle = episodeName(ep, current.title) ?: "",
                                url = ep.downloadURL!!,
                                runtimeSeconds = ep.runtimeSeconds,
                            ),
                        ),
                    )
                }
            }
        }

        // When we hold only part of the canonical run, say so — it sets the
        // expectation that the library keeps growing (tvOS partialFooter).
        val have = current.episodesCount ?: seasons.sumOf { it.episodes.size }
        val total = current.canonicalEpisodesCount
        if (total != null && total > have) {
            item(key = "partial") {
                Text(
                    "$have of $total episodes available — more are added as they surface in the archive.",
                    fontSize = 14.sp,
                    color = Color.White.copy(alpha = 0.45f),
                    modifier = Modifier.padding(start = TvDims.OverscanH, end = TvDims.OverscanH, top = 20.dp),
                )
            }
        }
    }

    if (showShare) {
        TvShareOverlay(
            title = current.title,
            url = "https://archivewatch.org/series/$slug",
            onDone = { showShare = false },
        )
    }
}

private fun yearRange(start: Int?, end: Int?): String? = when {
    start != null && end != null && start == end -> "$start"
    start != null && end != null -> "$start–$end"
    start != null -> "$start"
    end != null -> "$end"
    else -> null
}

private fun episodeCountLabel(have: Int, canonical: Int?): String? {
    if (have <= 0) return null
    if (canonical != null && canonical > have) return "$have of $canonical episodes"
    return "$have episode${if (have == 1) "" else "s"}"
}

/** One episode: a 16:9 still or a monogram plate on the left, the number label,
 *  the derived name, the blurb and a resume bar on the right. */
@Composable
private fun TvEpisodeRow(
    container: AppContainer,
    ep: SeriesEpisode,
    seriesTitle: String,
    accent: Color,
    onOpen: () -> Unit,
) {
    val name = episodeName(ep, seriesTitle) ?: ep.title ?: "Episode"
    val number = when {
        ep.seasonNumber != null && ep.episodeNumber != null -> "S${ep.seasonNumber} · E${ep.episodeNumber}"
        ep.episodeNumber != null -> "Ep. ${ep.episodeNumber}"
        else -> null
    }
    val playable = ep.downloadURL != null || ep.archiveID != null
    val progress by produceState<Float?>(null, ep.archiveID) {
        val id = ep.archiveID ?: return@produceState
        val p = container.userState.progressFor(id)
        value = if (p != null && p.durationMs > 0) (p.positionMs.toFloat() / p.durationMs).coerceIn(0f, 1f) else null
    }
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            // The reading width, not the full row: a focus ring around 1,800 px
            // of mostly empty space read as heavy on the glass.
            .fillMaxWidth(0.72f)
            .padding(start = TvDims.OverscanH, end = TvDims.OverscanH, bottom = 12.dp)
            .tvFocusable(onClick = { if (playable) onOpen() }, shape = RoundedCornerShape(12.dp), onFocused = { focused = true })
            .onFocusChanged { focused = it.isFocused }
            .padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .width(200.dp)
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFF1C1C22)),
            contentAlignment = Alignment.Center,
        ) {
            if (ep.stillURL != null) {
                AsyncImage(
                    model = ep.stillURL,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // A monogram, not the title: the name sits beside the plate, so a
                // repeated (truncated) title would say the same thing twice.
                Text(
                    name.firstOrNull()?.uppercase() ?: "",
                    fontSize = 40.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(0xFF54545E),
                )
            }
            if (playable) {
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.9f),
                    modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp).size(24.dp),
                )
            }
        }
        Column(Modifier.weight(1f)) {
            number?.let {
                Text(it, fontSize = 12.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.55f))
            }
            Text(
                name,
                fontSize = 18.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = if (number != null) 4.dp else 0.dp),
            )
            ep.overview?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    fontSize = 14.sp,
                    lineHeight = 19.sp,
                    color = Color.White.copy(alpha = if (focused) 0.75f else 0.6f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            if (!playable) {
                Text("Not available yet", fontSize = 12.sp, color = Color(0xFF9A9A9A), modifier = Modifier.padding(top = 4.dp))
            }
            progress?.let { frac ->
                Box(Modifier.padding(top = 10.dp).fillMaxWidth(0.6f).height(3.dp).background(Color(0xFF333338))) {
                    Box(Modifier.fillMaxWidth(frac).height(3.dp).background(accent))
                }
            }
        }
    }
}
