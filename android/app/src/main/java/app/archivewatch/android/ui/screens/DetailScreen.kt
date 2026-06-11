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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import app.archivewatch.android.data.UserPlaylist
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterImage
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.SectionHeader
import app.archivewatch.android.ui.ShelfRow
import app.archivewatch.android.ui.theme.BrandSurface
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch

@Composable
fun DetailScreen(container: AppContainer, nav: Nav, archiveID: String) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val item by produceState<CatalogItem?>(null, archiveID, dbVersion) {
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
        LoadingBox()
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        // Backdrop header with back button
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            AsyncImage(
                model = current.backdropURL ?: current.resolvedPosterURL,
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
                                        url = url,
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
                            .clickable { nav.push(Route.Person(member.name)) },
                    ) {
                        Box(
                            Modifier
                                .size(64.dp)
                                .clip(CircleShape)
                                .background(BrandSurface),
                        ) {
                            member.profileURL?.let { url ->
                                AsyncImage(
                                    model = url,
                                    contentDescription = member.name,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
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

        if (related.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ShelfRow("More Like This", related, onItem = {
                nav.openItem(it.archiveID, it.seriesID, it.contentType)
            })
        }
        Spacer(Modifier.height(32.dp))
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
