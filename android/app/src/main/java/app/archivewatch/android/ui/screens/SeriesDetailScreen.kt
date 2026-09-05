package app.archivewatch.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.data.SeriesDetail
import app.archivewatch.android.data.SeriesEpisode
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.tvFocusable
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.theme.BrandSurface
import coil3.compose.AsyncImage
import androidx.compose.foundation.layout.fillMaxHeight

/** Series → season dropdown → episode list (series JSON, contract §6.3). */
@Composable
fun SeriesDetailScreen(container: AppContainer, nav: Nav, slug: String) {
    var retry by remember { mutableIntStateOf(0) }
    val series by produceState<SeriesDetail?>(null, slug, retry) {
        value = container.editorial.series(slug)
    }
    var loadFailed by remember { mutableStateOf(false) }
    val current = series

    if (current == null) {
        // produceState resolves null on failure too; show loading briefly,
        // then a visible error if the fetch came back empty.
        val failed by produceState(false, slug, retry) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        if (failed || loadFailed) {
            EmptyState(
                "Couldn't load this series. Check your connection and try again.",
                onRetry = { loadFailed = false; retry++ },
            )
        } else LoadingBox()
        return
    }

    var seasonIndex by remember(current.seriesID) { mutableIntStateOf(0) }
    val seasons = current.seasons
    val season = seasons.getOrNull(seasonIndex)

    LazyColumn(Modifier.fillMaxSize()) {
        item(key = "header") {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                // Series posters are 2:3 (TVDB/TVmaze designed art). Cropping one
                // into this 16:9 box leaves a horizontal sliver, so the art below
                // is only an ambient wash and the poster is shown whole on top.
                val heroBackdrop = current.backdropURL
                val heroPoster = current.posterURL
                BackdropImage(
                    url = heroBackdrop ?: heroPoster,
                    contentDescription = null,
                    accent = Color(0xFF2D5BFF),   // Classic TV accent (Decision 013)
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0.4f to Color.Transparent,
                                1f to MaterialTheme.colorScheme.background,
                            ),
                        ),
                )
                // Above the scrim: its bottom is fully opaque.
                if (heroBackdrop == null && heroPoster != null) {
                    AsyncImage(
                        model = heroPoster,
                        contentDescription = current.title,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(vertical = 10.dp)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(8.dp)),
                    )
                }
                IconButton(
                    onClick = { nav.pop() },
                    modifier = Modifier.statusBarsPadding().padding(start = 4.dp),
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                    )
                }
            }
            Column(Modifier.padding(horizontal = 16.dp)) {
                Text(
                    current.title,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                val meta = listOfNotNull(
                    listOfNotNull(current.yearStart, current.yearEnd).distinct()
                        .joinToString("–").ifEmpty { null },
                    current.networks.firstOrNull(),
                    current.episodesCount?.let { have ->
                        current.canonicalEpisodesCount?.let { all -> "$have of $all episodes" }
                            ?: "$have episodes"
                    },
                ).joinToString(" · ")
                if (meta.isNotEmpty()) {
                    Text(
                        meta,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                current.overview?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                if (seasons.size > 1) {
                    SeasonMenu(seasons.map { it.seasonNumber }, seasonIndex) { seasonIndex = it }
                }
            }
        }
        items(season?.episodes.orEmpty(), key = { it.archiveID ?: "${it.seasonNumber}x${it.episodeNumber}-${it.title}" }) { episode ->
            EpisodeRow(episode, current.title) {
                // Open the episode's OWN Detail page (favorite / playlist / share / play,
                // Decision 045) — like any film. Falls back to inline play only if the episode
                // has no archiveID to resolve a Detail.
                val aid = episode.archiveID
                if (aid != null) {
                    nav.openItem(aid, current.seriesID, "tv-episode")
                } else if (episode.downloadURL != null) {
                    nav.push(
                        Route.Player(
                            PlaySpec(
                                id = episode.downloadURL!!,
                                title = current.title,
                                subtitle = episodeLabel(episode, current.title),
                                url = episode.downloadURL!!,
                                runtimeSeconds = episode.runtimeSeconds,
                            ),
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun SeasonMenu(seasonNumbers: List<Int?>, selected: Int, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val only = seasonNumbers.size == 1
    TextButton(onClick = { open = true }) {
        Text(seasonLabel(seasonNumbers.getOrNull(selected), only))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        seasonNumbers.forEachIndexed { index, number ->
            DropdownMenuItem(
                text = { Text(seasonLabel(number, only)) },
                onClick = { onSelect(index); open = false },
            )
        }
    }
}

/** seasonNumber may be null — "More Episodes" beside numbered seasons (contract
 *  §6.3), and plain "Episodes" when it is the ONLY group: most archive spines
 *  are entirely unnumbered, and "More" than nothing reads wrong. */
private fun seasonLabel(number: Int?, only: Boolean = false): String =
    number?.let { "Season $it" } ?: if (only) "Episodes" else "More Episodes"

private fun episodeLabel(episode: SeriesEpisode, seriesTitle: String?): String {
    val sxe = if (episode.seasonNumber != null && episode.episodeNumber != null) {
        "S%02dE%02d".format(episode.seasonNumber, episode.episodeNumber)
    } else null
    return listOfNotNull(sxe, episodeName(episode, seriesTitle)).joinToString(" · ")
}

/** An unanchored episode usually carries the SERIES title verbatim, so a
 *  season read as the same line repeated and the viewer could not tell one
 *  episode from another (seen on the Google TV: two rows both "13 Demon
 *  Street"). The archive id is the only thing that distinguishes them, and
 *  it is usually the episode name: 13_demon_street_fever_1959 -> "Fever".
 *  Ported from the Roku SeriesScreen rule; intervenes ONLY when the title
 *  tells the viewer nothing, and falls back to the title when nothing is
 *  left after dropping the series words and a trailing year. */
private fun episodeName(episode: SeriesEpisode, seriesTitle: String?): String? {
    val t = episode.title?.trim().orEmpty()
    val aid = episode.archiveID.orEmpty()
    if (aid.isEmpty()) return episode.title
    val st = seriesTitle?.trim()?.lowercase().orEmpty()
    if (t.isNotEmpty() && t.lowercase() != st) return t
    val seriesWords = st.split(Regex("[ \\-:]+")).filter { it.isNotEmpty() }.toSet()
    val words = aid.split(Regex("[_\\-.]+")).filter { it.isNotEmpty() }
    val kept = ArrayList<String>()
    for (w in words) {
        if (kept.isEmpty() && w.lowercase() in seriesWords) continue
        kept += w
    }
    if (kept.size > 1) {
        val last = kept.last()
        if (last.length == 4 && last.toIntOrNull()?.let { it in 1871..2099 } == true) kept.removeAt(kept.size - 1)
    }
    if (kept.isEmpty()) return episode.title
    return kept.joinToString(" ") { w -> w.replaceFirstChar { it.uppercase() } }
}

@Composable
private fun EpisodeRow(episode: SeriesEpisode, seriesTitle: String?, onPlay: () -> Unit) {
    val playable = episode.downloadURL != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (LocalIsTelevision.current) {
                    Modifier.tvFocusable(onClick = { if (playable) onPlay() })
                } else Modifier.clickable(enabled = playable, onClick = onPlay),
            )
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .width(120.dp)
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(6.dp))
                .background(BrandSurface),
        ) {
            episode.stillURL?.let {
                AsyncImage(
                    model = it,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            if (playable) {
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.9f),
                    modifier = Modifier.align(Alignment.Center),
                )
            }
        }
        Column(Modifier.weight(1f)) {
            Text(
                episodeLabel(episode, seriesTitle).ifEmpty { "Episode" },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            episode.overview?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (!playable) {
                Text(
                    "Not in the archive yet",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
