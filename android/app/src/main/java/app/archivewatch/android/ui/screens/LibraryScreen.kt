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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.filled.Groups
import app.archivewatch.android.ui.JoinRoomDialog
import app.archivewatch.android.studio.StudioSyncFollower
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.uniqueBy
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
import app.archivewatch.android.data.PlaylistOrder
import app.archivewatch.android.data.PlaylistSort
import app.archivewatch.android.sync.DriveSync
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import app.archivewatch.android.data.VideoClip
import kotlinx.coroutines.launch

/** Library — Favorites, Continue, Playlists, History, Clips; all user.sqlite. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(container: AppContainer, nav: Nav) {
    var joining by remember { mutableStateOf(false) }
    val joinScope = rememberCoroutineScope()
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    var tabIndex by androidx.compose.runtime.saveable.rememberSaveable { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    var removeFromHistory by remember { mutableStateOf<CatalogItem?>(null) }

    // Only the tab on screen is read, and as grid rows (I3): a tile needs no blob.
    val favoritesList by produceState(app.archivewatch.android.ui.ResolvedList(emptyList(), 0), dbVersion, userChanges, tabIndex) {
        if (tabIndex != 0) return@produceState
        val ids = container.userState.favoriteIDs()
        value = app.archivewatch.android.ui.resolveListRows(ids, container.catalog.awaitDb().itemsByIDsKeyed(ids, lite = true))
    }
    val favorites = favoritesList.rows
    // With each card's progress, as on Home (time left and a bar).
    val continueState by produceState<Pair<List<CatalogItem>, Map<String, app.archivewatch.android.data.WatchProgress>>>(
        emptyList<CatalogItem>() to emptyMap(), dbVersion, userChanges, tabIndex,
    ) { if (tabIndex == 1) value = continueWithProgress(container) }
    val continueWatching = continueState.first
    val continueProgress = continueState.second
    val allPlaylists by produceState<List<UserPlaylist>>(emptyList(), userChanges) {
        value = container.userState.playlists()
    }
    val libContext = LocalContext.current
    var playlistSort by remember { mutableStateOf(PlaylistOrder.remembered(libContext, PlaylistOrder.LIST_KEY)) }
    val playlists = PlaylistOrder.sortedLists(allPlaylists, playlistSort)
    var playlistMenu by remember { mutableStateOf<String?>(null) }
    var renamingPlaylist by remember { mutableStateOf<UserPlaylist?>(null) }
    var deletingPlaylist by remember { mutableStateOf<UserPlaylist?>(null) }
    val clips by produceState<List<VideoClip>>(emptyList(), userChanges) {
        value = container.userState.clips()
    }
    // The complete watch record (Decision 078 parity): everything ever
    // played, newest first — finished or not.
    val historyList by produceState(app.archivewatch.android.ui.ResolvedList(emptyList(), 0), dbVersion, userChanges, tabIndex) {
        if (tabIndex != 3) return@produceState
        val ids = container.userState.history().map { it.archiveID }
        value = app.archivewatch.android.ui.resolveListRows(ids, container.catalog.awaitDb().itemsByIDsKeyed(ids, lite = true))
    }
    val history = historyList.rows

    if (joining) {
        JoinRoomDialog(
            onDismiss = { joining = false },
            onJoined = { code, filmID ->
                joining = false
                // The player is the one place an ExoPlayer exists, so the code
                // waits there — the same hand-off macOS, tvOS and iOS use.
                StudioSyncFollower.pending = code
                StudioSyncFollower.pendingFilm = filmID
                joinScope.launch {
                    val db = container.catalog.awaitDb()
                    db.itemsByIDs(listOf(filmID)).firstOrNull()
                        ?.let { nav.push(Route.Detail(it.archiveID)) }
                }
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Library") },
                // JOIN A ROOM (§11.9). The app bar rather than a sixth bottom
                // tab: the bar already carries five, and this screen's own tab
                // row had to become scrollable because five labels wrapped on
                // the owner's Pixel. It needs no camera (§11.10) — Decision
                // 132 gates HOSTING, and a joiner hosts nothing.
                actions = {
                    IconButton(onClick = { joining = true }) {
                        Icon(Icons.Filled.Groups, contentDescription = "Join a Watch Together room")
                    }
                },
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
            PrimaryScrollableTabRow(selectedTabIndex = tabIndex, edgePadding = 0.dp) {
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
                renamingPlaylist?.let { pl ->
                    RenamePlaylistDialog(
                        current = pl.name,
                        onDismiss = { renamingPlaylist = null },
                        onRename = { name ->
                            renamingPlaylist = null
                            scope.launch { container.userState.renamePlaylist(pl.id, name) }
                        },
                    )
                }
                deletingPlaylist?.let { pl ->
                    androidx.compose.material3.AlertDialog(
                        onDismissRequest = { deletingPlaylist = null },
                        title = { Text("Delete \u201c${pl.name}\u201d?") },
                        text = if (DriveSync.isSignedIn) {
                            { Text("It is removed from your other devices too.") }
                        } else null,
                        confirmButton = {
                            androidx.compose.material3.TextButton(onClick = {
                                deletingPlaylist = null
                                scope.launch { container.userState.deletePlaylist(pl.id) }
                            }) { Text("Delete") }
                        },
                        dismissButton = {
                            androidx.compose.material3.TextButton(onClick = { deletingPlaylist = null }) { Text("Cancel") }
                        },
                    )
                }
                if (playlists.isEmpty()) {
                    EmptyState("No playlists yet — use the playlist button on any title.")
                } else {
                    if (playlists.size > 1) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                            horizontalArrangement = RowArrangement.End) {
                            PlaylistSortMenu(playlistSort) {
                                playlistSort = it
                                PlaylistOrder.remember(libContext, it, PlaylistOrder.LIST_KEY)
                            }
                        }
                    }
                    LazyColumn(contentPadding = PaddingValues(16.dp),
                               verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        itemsIndexed(playlists, key = { _, pl -> pl.id }) { index, pl ->
                            // Long-press for the list's verbs, as a History poster
                            // is removed (§4.5); arranging is My Order's alone.
                            Box {
                                Card(modifier = Modifier.combinedClickable(
                                    onClick = { nav.push(Route.Playlist(pl.id)) },
                                    onLongClick = { playlistMenu = pl.id },
                                )) {
                                    Row(
                                        Modifier.padding(16.dp),
                                        horizontalArrangement = RowArrangement.SpaceBetween,
                                    ) {
                                        Text(pl.name, Modifier.weight(1f))
                                        Text(
                                            pl.archiveIDs.size.let { n -> "$n ${if (n == 1) "title" else "titles"}" },
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                DropdownMenu(expanded = playlistMenu == pl.id,
                                             onDismissRequest = { playlistMenu = null }) {
                                    DropdownMenuItem(text = { Text("Rename…") }, onClick = {
                                        playlistMenu = null; renamingPlaylist = pl
                                    })
                                    if (playlistSort == PlaylistSort.MY_ORDER && index > 0) {
                                        DropdownMenuItem(text = { Text("Move up") }, onClick = {
                                            playlistMenu = null
                                            scope.launch { container.userState.arrangePlaylists(
                                                PlaylistOrder.moved(playlists, index, index - 1)) }
                                        })
                                    }
                                    if (playlistSort == PlaylistSort.MY_ORDER && index < playlists.size - 1) {
                                        DropdownMenuItem(text = { Text("Move down") }, onClick = {
                                            playlistMenu = null
                                            scope.launch { container.userState.arrangePlaylists(
                                                PlaylistOrder.moved(playlists, index, index + 1)) }
                                        })
                                    }
                                    DropdownMenuItem(text = { Text("Delete playlist…") }, onClick = {
                                        playlistMenu = null; deletingPlaylist = pl
                                    })
                                }
                            }
                        }
                    }
                }
                return@Column
            }
            removeFromHistory?.let { item ->
                androidx.compose.material3.AlertDialog(
                    onDismissRequest = { removeFromHistory = null },
                    title = { Text("Remove from history?") },
                    text = { Text(item.title) },
                    confirmButton = {
                        androidx.compose.material3.TextButton(onClick = {
                            removeFromHistory = null
                            scope.launch {
                                historyList.storedIDs(item).forEach { container.userState.removeFromHistory(it) }
                            }
                        }) { Text("Remove") }
                    },
                    dismissButton = {
                        androidx.compose.material3.TextButton(onClick = { removeFromHistory = null }) { Text("Cancel") }
                    },
                )
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
                // One grid state per tab: a shared one anchors on the first
                // visible KEY, so History opened scrolled to wherever the
                // Favorites' first film sat in it.
                val gridState = androidx.compose.runtime.key(tabIndex) {
                    androidx.compose.foundation.lazy.grid.rememberLazyGridState()
                }
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    state = gridState,
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(items.uniqueBy { it.archiveID }, key = { it.archiveID }) { item ->
                        PosterTile(item, onClick = {
                            nav.openItem(item.archiveID, item.seriesID, item.contentType)
                        }, progress = if (tabIndex == 1) continueProgress[item.archiveID] else null,
                            onLongClick = if (tabIndex == 3) ({ removeFromHistory = item }) else null)
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
        EmptyState("No clips yet — open any title and tap the scissors.")
        return
    }
    // A long press ASKS, and a deleted clip takes its video file with it: it
    // deleted on the press alone and left the file behind (Pixel 8a).
    var confirmDelete by remember { mutableStateOf<VideoClip?>(null) }
    confirmDelete?.let { clip ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("Delete this clip?") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmDelete = null
                    scope.launch {
                        container.userState.deleteClip(clip.id)
                        runCatching { container.clipExporter.renderFile(clip.renderFilename).delete() }
                    }
                }) { Text("Delete") }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmDelete = null }) { Text("Cancel") }
            },
        )
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
                        } else {
                            // Renders live in the cache, which the system may clear.
                            android.widget.Toast.makeText(context,
                                "This clip's video is no longer on this phone.", android.widget.Toast.LENGTH_SHORT).show()
                        }
                    },
                    onLongClick = { confirmDelete = clip },
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
                        val aspect = runCatching {
                            app.archivewatch.android.data.ClipAspect.valueOf(clip.aspect).label
                        }.getOrDefault(clip.aspect)
                        Text(
                            listOfNotNull(
                                clip.sourceTitle.takeIf { clip.caption.isNotBlank() },
                                String.format(java.util.Locale.US, "%.1f s", clip.durationSeconds),
                                aspect,
                            ).joinToString(" · "),
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
