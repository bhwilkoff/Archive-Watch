package app.archivewatch.android.ui.screens

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import app.archivewatch.android.data.UserPlaylist
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.Review
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.ui.AvatarImage
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterImage
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.SectionHeader
import app.archivewatch.android.ui.ShelfRow
import app.archivewatch.android.ui.accentColor
import app.archivewatch.android.ui.theme.BrandSurface
import kotlinx.coroutines.launch

@Composable
fun DetailScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var retry by remember { mutableIntStateOf(0) }
    val item by produceState<CatalogItem?>(null, archiveID, dbVersion, retry) {
        value = container.catalog.db?.item(archiveID)
    }
    val related by produceState<List<CatalogItem>>(emptyList(), item) {
        value = item?.let { container.catalog.db?.related(it) } ?: emptyList()
    }
    var favorite by remember { mutableStateOf(false) }
    var showPlaylists by remember { mutableStateOf(false) }
    LaunchedEffect(archiveID) { favorite = container.userState.isFavorite(archiveID) }

    val current = item
    if (current == null) {
        // db.item() returns null both while the DB is opening AND for an id
        // that isn't in the catalog (e.g. a stale share link to an archive
        // copy the IMDb dedup dropped) — without a timeout that second case
        // spins forever. Same pattern as SeriesDetailScreen.
        val failed by produceState(false, archiveID, dbVersion, retry) {
            kotlinx.coroutines.delay(8_000)
            value = true
        }
        if (failed) {
            EmptyState(
                "This title isn't in the catalog anymore — it may have moved. Try searching its name.",
                onRetry = { retry++ },
            )
        } else LoadingBox()
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        // Backdrop header with back button
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            BackdropImage(
                url = current.backdropURL ?: current.posterURL,
                contentDescription = null,
                accent = current.accentColor,
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
                current.year?.toString(),
                current.director,
                current.runtimeSeconds?.let { "${it / 60} min" },
                current.genres.firstOrNull(),
            ).joinToString(" · ")
            if (meta.isNotEmpty()) {
                Text(
                    meta,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            // Tagline (Decision 046) — flavor line under the meta, italic.
            current.tagline?.takeIf { it.isNotBlank() }?.let {
                Text(
                    "“$it”",
                    style = MaterialTheme.typography.bodyMedium,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }

            if (showPlaylists) {
                AddToPlaylistDialog(container, current.archiveID) { showPlaylists = false }
            }
            Row(
                Modifier.padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(
                    onClick = {
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
                    },
                    enabled = current.downloadURL != null,
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Text(if (current.downloadURL != null) "Play" else "Not playable")
                }
                IconButton(onClick = {
                    scope.launch { favorite = container.userState.toggleFavorite(current.archiveID) }
                }) {
                    Icon(
                        if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                        contentDescription = "Favorite",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                IconButton(onClick = { showPlaylists = true }) {
                    Icon(
                        Icons.AutoMirrored.Filled.PlaylistAdd,
                        contentDescription = "Add to playlist",
                    )
                }
                // Create (Clip Studio) — rights-gated (CREATE-STUDIO-PLAN §2).
                // Hidden, not disabled, when the item isn't clippable.
                if (current.isClippable) {
                    IconButton(onClick = { nav.push(Route.ClipStudio(current.archiveID)) }) {
                        Icon(
                            Icons.Default.ContentCut,
                            contentDescription = "Create a clip",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                IconButton(onClick = {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT,
                            "${current.title} — https://archivewatch.org/item/${current.archiveID}")
                    }
                    context.startActivity(Intent.createChooser(send, null))
                }) {
                    Icon(
                        Icons.Default.Share,
                        contentDescription = "Share",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            current.synopsis?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.9f),
                )
            }

            // Rich metadata (Decision 046) — each row shown only when present.
            MetaDetailRows(current)

            // Episode item (Decision 045): jump to the full series.
            if (current.isEpisode && current.seriesID != null) {
                TextButton(onClick = { nav.push(Route.Series(current.seriesID!!)) }) {
                    Icon(Icons.Default.Tv, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Part of ${current.seriesTitle ?: "the series"}")
                }
            }
        }

        // Cast row (TMDb w185 profile URLs per contract §7)
        if (current.cast.isNotEmpty()) {
            SectionHeader("Cast")
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(current.cast.sortedBy { it.order }.take(15), key = { it.name }) { member ->
                    // Tap → person filmography (parity with the apps' PersonChip).
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.width(72.dp)
                            .clickable {
                                nav.push(Route.Person(member.name, member.tmdbPersonID))
                            },
                    ) {
                        AvatarImage(
                            url = member.profileURL,
                            name = member.name,
                            modifier = Modifier.size(64.dp).clip(CircleShape),
                        )
                        Text(
                            member.name,
                            style = MaterialTheme.typography.labelSmall,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            }
        }

        CommunityDetailSection(current)

        if (related.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ShelfRow("More Like This", related, onItem = {
                nav.openItem(it.archiveID, it.seriesID, it.contentType)
            })
        }
        Spacer(Modifier.height(32.dp))
    }
}

// Rich metadata surfaces (Decision 046 / docs/METADATA-EXPANSION.md): writer,
// composer, cinematographer, studios, franchise, awards — each rendered as a
// "Label  value" row only when the field is present. Detail-only blob fields, so
// they cost nothing on browse/sort. Renders nothing when none are present.
@Composable
private fun MetaDetailRows(item: CatalogItem) {
    val studios = item.studios.takeIf { it.isNotEmpty() }?.joinToString(", ")
    val rows = listOfNotNull(
        item.writer?.takeIf { it.isNotBlank() }?.let { "Writer" to it },
        item.composer?.takeIf { it.isNotBlank() }?.let { "Music" to it },
        item.cinematographer?.takeIf { it.isNotBlank() }?.let { "Cinematography" to it },
        studios?.let { "Studio" to it },
        item.franchise?.takeIf { it.isNotBlank() }?.let { "Series" to it },
        item.awards?.takeIf { it.isNotBlank() }?.let { "Awards" to it },
    )
    if (rows.isEmpty()) return
    Column(
        modifier = Modifier.padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        rows.forEach { (label, value) ->
            Row {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(112.dp),
                )
                Text(
                    value,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// archive.org community stats + genuine reviews (pre-filtered in the pipeline,
// comment_fit.py). Parity with the Apple CommunityDetailSection. Renders nothing
// when there's no data.
@Composable
private fun CommunityDetailSection(item: CatalogItem) {
    val reviews = item.displayReviews
    val hasStats = item.avgRatingDisplay != null || item.viewsDisplay != null || item.favoritesDisplay != null
    if (!hasStats && reviews.isEmpty()) return

    if (hasStats) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            item.avgRatingDisplay?.let { CommunityStat("★", it, "rating") }
            item.viewsDisplay?.let { CommunityStat("▶", it, "views") }
            item.favoritesDisplay?.let { CommunityStat("♥", it, "favorites") }
        }
    }
    if (reviews.isNotEmpty()) {
        SectionHeader("From archive.org viewers")
        Column(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            reviews.take(6).forEach { ReviewCard(it) }
        }
    }
}

@Composable
private fun CommunityStat(symbol: String, value: String, caption: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("$symbol ", style = MaterialTheme.typography.titleMedium)
        Column {
            Text(value, style = MaterialTheme.typography.titleSmall)
            Text(caption, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
        }
    }
}

@Composable
private fun ReviewCard(review: Review) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(BrandSurface)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val header = buildString {
            review.stars?.takeIf { it > 0 }?.let { append("★".repeat(it)).append("  ") }
            review.title?.takeIf { it.isNotBlank() }?.let { append(it) }
        }.trim()
        if (header.isNotEmpty()) {
            Text(header, style = MaterialTheme.typography.titleSmall, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
        review.body?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = Color.LightGray,
                maxLines = 6, overflow = TextOverflow.Ellipsis)
        }
        Text(review.displayName + (review.date?.let { " · $it" } ?: ""),
            style = MaterialTheme.typography.labelSmall, color = Color.Gray)
    }
}


/** Add-to-playlist: toggle membership per playlist, create inline. */
@Composable
private fun AddToPlaylistDialog(
    container: AppContainer,
    archiveID: String,
    onDone: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val userChanges by container.userState.changes.collectAsState()
    val playlists by produceState<List<UserPlaylist>>(emptyList(), userChanges) {
        value = container.userState.playlists()
    }
    var newName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDone,
        confirmButton = { TextButton(onClick = onDone) { Text("Done") } },
        title = { Text("Add to playlist") },
        text = {
            Column {
                playlists.forEach { pl ->
                    val inList = archiveID in pl.archiveIDs
                    TextButton(onClick = {
                        scope.launch { container.userState.togglePlaylistItem(pl.id, archiveID) }
                    }) {
                        Text("${if (inList) "✓ " else ""}${pl.name} (${pl.archiveIDs.size})")
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("New playlist") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    TextButton(
                        onClick = {
                            val name = newName.trim()
                            if (name.isNotEmpty()) {
                                scope.launch {
                                    container.userState.createPlaylist(name, archiveID)
                                    newName = ""
                                }
                            }
                        },
                    ) { Text("Add") }
                }
            }
        },
    )
}
