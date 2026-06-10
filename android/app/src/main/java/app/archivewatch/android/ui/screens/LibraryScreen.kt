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

/** Library — Favorites and Continue Watching, both from user.sqlite. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    var tabIndex by remember { mutableIntStateOf(0) }

    val favorites by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.db ?: return@produceState
        value = db.itemsByIDs(container.userState.favoriteIDs())
    }
    val continueWatching by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.db ?: return@produceState
        value = db.itemsByIDs(container.userState.continueWatching().map { it.archiveID })
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
            TabRow(selectedTabIndex = tabIndex) {
                Tab(selected = tabIndex == 0, onClick = { tabIndex = 0 }, text = { Text("Favorites") })
                Tab(selected = tabIndex == 1, onClick = { tabIndex = 1 }, text = { Text("Continue Watching") })
            }
            val items = if (tabIndex == 0) favorites else continueWatching
            if (items.isEmpty()) {
                EmptyState(
                    if (tabIndex == 0) "No favorites yet — tap the heart on any title."
                    else "Nothing in progress — start watching something.",
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
