package app.archivewatch.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Card
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
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.CollectionMeta
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.tvFocusable
import app.archivewatch.android.ui.PosterTile
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.ShelfRow
import app.archivewatch.android.ui.theme.colorFromHex

// Collections + Cartoon Mode + person filmography (parity wave 2026-06-12).

/** Curated collections list (collection_metadata.json → item_collections). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionsScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val collections by produceState<List<Pair<CollectionMeta, Int>>?>(null, dbVersion) {
        val db = container.catalog.awaitDb()
        value = container.editorial.collections().mapNotNull { meta ->
            val n = db.byCollection(meta.id, limit = 240).size
            if (n >= 6) meta to n else null
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Collections") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val list = collections
        if (list == null) { LoadingBox(Modifier.padding(padding)); return@Scaffold }
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            listItems(list, key = { it.first.id }) { (meta, count) ->
                val openCollection = {
                    nav.push(Route.Collection(meta.id, meta.title, meta.blurb))
                }
                Card(
                    modifier = if (LocalIsTelevision.current) {
                        Modifier.tvFocusable(onClick = openCollection, focusTag = "collection:" + meta.title)
                    } else {
                        Modifier.clickable(onClick = openCollection)
                    },
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier.size(16.dp)
                                .clip(RoundedCornerShape(5.dp))
                                .background(colorFromHex(meta.accent)
                                    ?: MaterialTheme.colorScheme.primary),
                        )
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(meta.title, fontWeight = FontWeight.SemiBold)
                            meta.blurb?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall,
                                     color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Text("$count", style = MaterialTheme.typography.labelMedium,
                             color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** One collection's grid. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionGridScreen(container: AppContainer, nav: Nav, route: Route.Collection) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val items by produceState<List<CatalogItem>?>(null, dbVersion) {
        value = container.catalog.db?.byCollection(route.id)
    }
    GridScaffold(title = route.title, subtitle = route.blurb, nav = nav, items = items)
}

/** Person filmography — name FTS, disambiguated by TMDB person id when we have one (two
 *  different "John Smith"s no longer collapse into one grid). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonScreen(container: AppContainer, nav: Nav, name: String, tmdbPersonID: Int? = null) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val items by produceState<List<CatalogItem>?>(null, dbVersion, tmdbPersonID) {
        val hits = container.catalog.db?.search(name, limit = 120) ?: emptyList()
        value = if (tmdbPersonID != null) {
            // Keep only titles whose cast/crew actually carries this person id; fall
            // back to the raw name hits if none are tagged (older items lack the id).
            val exact = hits.filter { item ->
                item.cast.any { it.tmdbPersonID == tmdbPersonID }
            }
            exact.ifEmpty { hits }
        } else {
            hits
        }
    }
    GridScaffold(title = name, subtitle = "Titles featuring $name", nav = nav, items = items)
}

/** Cartoon Mode: marathon + character shelves (the apps' kid-leaning surface). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CartoonScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val characterDefs = listOf(
        "Popeye" to listOf("popeye"), "Betty Boop" to listOf("betty boop"),
        "Porky Pig" to listOf("porky"), "Mr. Magoo" to listOf("magoo"),
        "Looney Tunes" to listOf("looney"), "Felix the Cat" to listOf("felix"),
        "Daffy Duck" to listOf("daffy"), "Casper" to listOf("casper"),
        "Mighty Mouse" to listOf("mighty mouse"), "Superman" to listOf("superman"),
    )
    val state by produceState<Pair<List<CatalogItem>, List<Pair<String, List<CatalogItem>>>>?>(
        null, dbVersion) {
        val db = container.catalog.awaitDb()
        val pool = db.browse(contentType = "animation", limit = 240)
            .filter { it.downloadURL != null }
        val shelves = characterDefs.mapNotNull { (name, terms) ->
            val rows = pool.filter { item ->
                terms.any { item.title.lowercase().contains(it) }
            }.take(20)
            if (rows.size >= 4) name to rows else null
        }
        value = pool to shelves
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Cartoon Mode") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Button(
                        onClick = {
                            val pool = state?.first?.shuffled().orEmpty()
                            val queue = pool.mapNotNull { item ->
                                item.downloadURL?.let {
                                    QueueEntry(item.archiveID, item.title, "Cartoon Marathon", it)
                                }
                            }
                            if (queue.isNotEmpty()) {
                                nav.push(Route.Player(PlaySpec(
                                    id = queue.first().id, title = queue.first().title,
                                    subtitle = "Cartoon Marathon", url = queue.first().url,
                                    queue = queue, queueIndex = 0, persistProgress = false,
                                )))
                            }
                        },
                        modifier = Modifier.padding(end = 12.dp),
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null,
                             modifier = Modifier.size(18.dp))
                        Text(" Marathon")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val s = state
        if (s == null) { LoadingBox(Modifier.padding(padding)); return@Scaffold }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            s.second.forEach { (name, rows) ->
                item(key = name) {
                    ShelfRow(name, rows, onItem = {
                        nav.openItem(it.archiveID, it.seriesID, it.contentType)
                    })
                }
            }
        }
    }
}

/** Shared grid scaffold for collection/person results. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GridScaffold(title: String, subtitle: String?, nav: Nav,
                         items: List<CatalogItem>?) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        when {
            items == null -> LoadingBox(Modifier.padding(padding))
            items.isEmpty() -> Box(Modifier.padding(padding)) {
                EmptyState("Nothing here yet.")
            }
            else -> Column(Modifier.fillMaxSize().padding(padding)) {
                subtitle?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurfaceVariant,
                         modifier = Modifier.padding(horizontal = 16.dp))
                }
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
