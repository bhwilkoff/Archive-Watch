package app.archivewatch.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterTile
import app.archivewatch.android.ui.Route
import kotlinx.coroutines.launch

/**
 * A playlist somebody else made, opened from a link.
 *
 * The list arrives INSIDE the url (PlaylistShare), so there is nothing to
 * fetch and nothing of ours hosting it. Two rules follow, the same two the
 * Apple apps and the web keep:
 *
 * BROWSE AND PLAY FIRST. Signed in or not, the films are here and they play —
 * the owner's rule for the web, and nothing is withheld from a stranger
 * because nothing here is ours to withhold.
 *
 * ADDING IT IS A CHOICE, never a side effect of opening a link. Copying the
 * playlist into the library automatically would mean a link tapped out of
 * curiosity had edited somebody's library.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SharedListScreen(
    container: AppContainer,
    nav: Nav,
    name: String,
    archiveIDs: List<String>,
) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    val scope = rememberCoroutineScope()

    val items by produceState<List<CatalogItem>?>(null, dbVersion) {
        value = container.catalog.awaitDb().itemsByIDs(archiveIDs)
    }

    // Matched on CONTENTS, not name: the same collection sent under two names
    // should not become two copies in the library.
    val alreadyHave by produceState(false, userChanges) {
        value = container.userState.playlists().any { it.archiveIDs == archiveIDs }
    }
    var added by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(name) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (added || alreadyHave) {
                        Icon(Icons.Default.Check, contentDescription = "In your library",
                             modifier = Modifier.padding(horizontal = 12.dp))
                    } else {
                        IconButton(onClick = {
                            scope.launch {
                                container.userState.createPlaylist(name, archiveIDs)
                                added = true
                            }
                        }) {
                            Icon(Icons.Default.Add, contentDescription = "Add to my library")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val rows = items
        when {
            rows == null -> LoadingBox(Modifier.padding(padding))
            rows.isEmpty() -> Box(Modifier.padding(padding)) {
                EmptyState("None of these titles are in the catalogue any more.")
            }
            else -> Column(Modifier.padding(padding)) {
                // A title the link names that this catalogue no longer serves is
                // STATED, never silently dropped — otherwise the sharer and the
                // viewer are looking at different collections and neither can
                // tell. Every other platform says this; leaving it off here
                // would have made Android the one that quietly lies.
                val missing = archiveIDs.size - rows.size
                Text(
                    if (missing > 0)
                        "Shared playlist · ${rows.size} of ${archiveIDs.size} titles — " +
                            "$missing ${if (missing == 1) "is" else "are"} no longer in the catalogue."
                    else "Shared playlist · ${rows.size} ${if (rows.size == 1) "title" else "titles"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 110.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize(),
                ) {
                    items(rows, key = { it.archiveID }) { item ->
                        PosterTile(item, onClick = { nav.push(Route.Detail(item.archiveID)) })
                    }
                }
            }
        }
    }
}
