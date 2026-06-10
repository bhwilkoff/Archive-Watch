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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
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
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.theme.BrandSurface
import coil3.compose.AsyncImage

/** Series → season dropdown → episode list (series JSON, contract §6.3). */
@Composable
fun SeriesDetailScreen(container: AppContainer, nav: Nav, slug: String) {
    val series by produceState<SeriesDetail?>(null, slug) {
        value = container.editorial.series(slug)
    }
    var loadFailed by remember { mutableStateOf(false) }
    val current = series

    if (current == null) {
        // produceState resolves null on failure too; show loading briefly,
        // then a visible error if the fetch came back empty.
        val failed by produceState(false, slug) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        if (failed || loadFailed) EmptyState("Couldn't load this series. Check your connection and try again.")
        else LoadingBox()
        return
    }

    var seasonIndex by remember(current.seriesID) { mutableIntStateOf(0) }
    val seasons = current.seasons
    val season = seasons.getOrNull(seasonIndex)

    LazyColumn(Modifier.fillMaxSize()) {
        item(key = "header") {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                AsyncImage(
                    model = current.backdropURL ?: current.posterURL,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
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
                IconButton(
                    onClick = { nav.pop() },
                    modifier = Modifier.padding(top = 32.dp, start = 4.dp),
                ) {
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White)
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
            EpisodeRow(episode) {
                val url = episode.downloadURL ?: return@EpisodeRow
                // Episode binge: the whole playable season rides along as a
                // Media3 queue, so end-of-episode advances natively.
                val playable = season?.episodes.orEmpty().filter { it.downloadURL != null }
                val queue = playable.map { ep ->
                    QueueEntry(
                        id = ep.archiveID ?: ep.downloadURL!!,
                        title = current.title,
                        subtitle = episodeLabel(ep),
                        url = ep.downloadURL!!,
                    )
                }
                val qi = playable.indexOf(episode).coerceAtLeast(0)
                nav.push(
                    Route.Player(
                        PlaySpec(
                            id = episode.archiveID ?: url,
                            title = current.title,
                            subtitle = episodeLabel(episode),
                            url = url,
                            runtimeSeconds = episode.runtimeSeconds,
                            queue = queue,
                            queueIndex = qi,
                        ),
                    ),
                )
            }
        }
    }
}

@Composable
private fun SeasonMenu(seasonNumbers: List<Int?>, selected: Int, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = true }) {
        Text(seasonLabel(seasonNumbers.getOrNull(selected)))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        seasonNumbers.forEachIndexed { index, number ->
            DropdownMenuItem(
                text = { Text(seasonLabel(number)) },
                onClick = { onSelect(index); open = false },
            )
        }
    }
}

/** seasonNumber may be null — render as "More Episodes" (contract §6.3). */
private fun seasonLabel(number: Int?): String =
    number?.let { "Season $it" } ?: "More Episodes"

private fun episodeLabel(episode: SeriesEpisode): String {
    val sxe = if (episode.seasonNumber != null && episode.episodeNumber != null) {
        "S%02dE%02d".format(episode.seasonNumber, episode.episodeNumber)
    } else null
    return listOfNotNull(sxe, episode.title).joinToString(" · ")
}

@Composable
private fun EpisodeRow(episode: SeriesEpisode, onPlay: () -> Unit) {
    val playable = episode.downloadURL != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = playable, onClick = onPlay)
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
                episodeLabel(episode).ifEmpty { "Episode" },
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
