package app.archivewatch.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterTile
import app.archivewatch.android.ui.Route
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement as RowArrangement
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import android.net.Uri
import androidx.compose.material3.Card
import app.archivewatch.android.data.UserPlaylist
import app.archivewatch.android.data.VideoClip
import kotlinx.coroutines.launch

/** Library — Favorites, Continue Watching, Playlists, Clips; all user.sqlite. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    var tabIndex by remember { mutableIntStateOf(0) }

    val favorites by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        value = db.itemsByIDs(container.userState.favoriteIDs())
    }
    val continueWatching by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        value = db.itemsByIDs(container.userState.continueWatching().map { it.archiveID })
    }
    val playlists by produceState<List<UserPlaylist>>(emptyList(), userChanges) {
        value = container.userState.playlists()
    }
    val clips by produceState<List<VideoClip>>(emptyList(), userChanges) {
        value = container.userState.clips()
    }
    // The complete watch record (Decision 078 parity): everything ever
    // played, newest first — finished or not.
    val history by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        value = db.itemsByIDs(container.userState.history().map { it.archiveID })
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Library") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // Scrollable, not fixed: five labels at a phone width forced a
            // fixed TabRow to wrap "Playlists" / "Favorites" onto two lines
            // (owner, Pixel). A scrollable row keeps each label on one line
            // and lets the bar pan, which is the M3 idiom for 4+ tabs.
            ScrollableTabRow(selectedTabIndex = tabIndex, edgePadding = 0.dp) {
                Tab(selected = tabIndex == 0, onClick = { tabIndex = 0 }, text = { Text("Favorites") })
                Tab(selected = tabIndex == 1, onClick = { tabIndex = 1 }, text = { Text("Continue") })
                Tab(selected = tabIndex == 2, onClick = { tabIndex = 2 }, text = { Text("Playlists") })
                Tab(selected = tabIndex == 3, onClick = { tabIndex = 3 }, text = { Text("History") })
                Tab(selected = tabIndex == 4, onClick = { tabIndex = 4 }, text = { Text("Clips") })
            }
            if (tabIndex == 4) {
                ClipsTab(container, clips)
                return@Column
            }
            if (tabIndex == 2) {
                if (playlists.isEmpty()) {
                    EmptyState("No playlists yet — use the playlist button on any title.")
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp),
                               verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        listItems(playlists, key = { it.id }) { pl ->
                            Card(modifier = Modifier
                                    .clickable { nav.push(Route.Playlist(pl.id)) }) {
                                Row(
                                    Modifier.padding(16.dp),
                                    horizontalArrangement = RowArrangement.SpaceBetween,
                                ) {
                                    Text(pl.name, Modifier.weight(1f))
                                    Text(
                                        "${pl.archiveIDs.size} titles",
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
                return@Column
            }
            val items = when (tabIndex) {
                0 -> favorites
                1 -> continueWatching
                else -> history
            }
            if (items.isEmpty()) {
                EmptyState(
                    when (tabIndex) {
                        0 -> "No favorites yet — tap the heart on any title."
                        1 -> "Nothing in progress — start watching something."
                        else -> "Everything you watch shows up here."
                    },
                )
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(items, key = { it.archiveID }) { item ->
                        PosterTile(item, onClick = {
                            nav.openItem(item.archiveID, item.seriesID, item.contentType)
                        })
                    }
                }
            }
        }
    }
}

/**
 * Clips tab — saved Clip Studio exports (CREATE-STUDIO-PLAN §3 / §4.8). Tap to
 * share the cached MP4; long-press to delete the saved definition.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ClipsTab(container: AppContainer, clips: List<VideoClip>) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    if (clips.isEmpty()) {
        EmptyState("No clips yet — open a public-domain title and tap the scissors to create one.")
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        listItems(clips, key = { it.id }) { clip ->
            Card(
                modifier = Modifier.combinedClickable(
                    onClick = {
                        val file = container.clipExporter.renderFile(clip.renderFilename)
                        if (file.exists()) {
                            val uri: Uri = androidx.core.content.FileProvider.getUriForFile(
                                context, "${context.packageName}.fileprovider", file,
                            )
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "video/mp4"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_TEXT,
                                    "Clipped from archive.org with Archive Watch · archivewatch.org")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(send, null))
                        }
                    },
                    onLongClick = { scope.launch { container.userState.deleteClip(clip.id) } },
                ),
            ) {
                Row(
                    Modifier.padding(16.dp),
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            clip.caption.ifBlank { clip.sourceTitle },
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            "${clip.sourceTitle} · ${String.format("%.1fs", clip.durationSeconds)} · ${clip.aspect}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Icon(Icons.Default.Share, contentDescription = "Share clip",
                         tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}
