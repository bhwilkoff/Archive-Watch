package app.archivewatch.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.BackdropImage
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterTile
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.accentColor
import kotlinx.coroutines.delay

// Search filter vocabulary — the Browse facet types (iOS parity: the Search
// tab's type/decade menus narrow FTS results without re-querying).
private val TYPE_FILTERS = listOf(
    "Films" to "feature-film", "TV" to "tv-series", "Silent" to "silent-film",
    "Animation" to "animation", "Shorts" to "short-film",
    "Newsreels" to "newsreel", "Documentary" to "documentary",
    "Ephemera" to "ephemeral", "Commercials" to "commercial",
)

/** Full-text search over the catalog's FTS5 index (contract §5 `search`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<CatalogItem>>(emptyList()) }
    var searched by remember { mutableStateOf(false) }
    var typeFilter by remember { mutableStateOf<Pair<String, String>?>(null) }
    var decadeFilter by remember { mutableStateOf<Int?>(null) }

    // ~180 ms debounce, re-run on DB swap.
    LaunchedEffect(query, dbVersion) {
        if (query.isBlank()) {
            results = emptyList()
            searched = false
            return@LaunchedEffect
        }
        delay(180)
        val db = container.catalog.awaitDb()
        results = db.search(query)
        searched = true
    }

    // Episode items (Decision 045) come back in `results` like any item; group them
    // into their own section. Films/shows get the type/decade filters.
    val episodeItems = results.filter { it.isEpisode }
    val filtered = results.filter { item ->
        !item.isEpisode &&
            (typeFilter == null || item.contentType == typeFilter!!.second) &&
            (decadeFilter == null || item.decade == decadeFilter)
    }
    // Episodes shown unless filtered to a non-TV type.
    val showEpisodes = (typeFilter == null || typeFilter!!.second == "tv-series") && episodeItems.isNotEmpty()

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            // M3 SearchBar (docked; results render live below rather than in the
            // expand overlay). The top-level SearchBar applies its own status-bar
            // inset, so no magic top padding.
            SearchBar(
                inputField = {
                    SearchBarDefaults.InputField(
                        query = query,
                        onQueryChange = { query = it },
                        onSearch = {},
                        expanded = false,
                        onExpandedChange = {},
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        trailingIcon = {
                            if (query.isNotEmpty()) {
                                IconButton(onClick = { query = "" }) {
                                    Icon(Icons.Default.Close, contentDescription = "Clear search")
                                }
                            }
                        },
                        placeholder = { Text("Search films, people, genres…") },
                    )
                },
                expanded = false,
                onExpandedChange = {},
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
            ) {}
            if (searched && results.isNotEmpty()) {
                FilterRow(
                    results = results,
                    typeFilter = typeFilter,
                    decadeFilter = decadeFilter,
                    onType = { typeFilter = it },
                    onDecade = { decadeFilter = it },
                )
            }
            when {
                query.isBlank() -> EmptyState("Search the whole archive — titles, directors, cast, genres.")
                searched && results.isEmpty() -> EmptyState("No matches for “$query”.")
                searched && filtered.isEmpty() && !showEpisodes -> EmptyState("No matches with these filters — clear one to widen the net.")
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    if (showEpisodes) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Text("Episodes", style = MaterialTheme.typography.titleLarge)
                        }
                        items(episodeItems, span = { GridItemSpan(maxLineSpan) },
                              key = { "ep-" + it.archiveID }) { ep ->
                            // Tapping opens the episode's OWN Detail (play/favorite/share/clip).
                            EpisodeItemRow(ep) { nav.openItem(ep.archiveID, ep.seriesID, ep.contentType) }
                        }
                        if (filtered.isNotEmpty()) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Text("Films & Shows", style = MaterialTheme.typography.titleLarge)
                            }
                        }
                    }
                    items(filtered, key = { it.archiveID }) { item ->
                        PosterTile(item, onClick = {
                            nav.openItem(item.archiveID, item.seriesID, item.contentType)
                        })
                    }
                }
            }
        }
    }
}

/** Type + decade chips over the result set; only facets present in the
    results are offered, so a filter can never zero the grid blindly. */
@Composable
private fun FilterRow(
    results: List<CatalogItem>,
    typeFilter: Pair<String, String>?,
    decadeFilter: Int?,
    onType: (Pair<String, String>?) -> Unit,
    onDecade: (Int?) -> Unit,
) {
    var typeMenu by remember { mutableStateOf(false) }
    var decadeMenu by remember { mutableStateOf(false) }
    val presentTypes = results.map { it.contentType }.toSet()
    val typeChoices = TYPE_FILTERS.filter { it.second in presentTypes }
    val decadeChoices = results.mapNotNull { it.decade }.distinct().sorted()

    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (typeChoices.size > 1) {
            Column {
                FilterChip(
                    selected = typeFilter != null,
                    onClick = { if (typeFilter != null) onType(null) else typeMenu = true },
                    label = { Text(typeFilter?.first ?: "Type") },
                    trailingIcon = {
                        Icon(
                            if (typeFilter != null) Icons.Default.Close
                            else Icons.Default.ArrowDropDown,
                            contentDescription = if (typeFilter != null) "Clear type filter" else null,
                        )
                    },
                )
                DropdownMenu(expanded = typeMenu, onDismissRequest = { typeMenu = false }) {
                    typeChoices.forEach { choice ->
                        DropdownMenuItem(
                            text = { Text(choice.first) },
                            onClick = { onType(choice); typeMenu = false },
                        )
                    }
                }
            }
        }
        if (decadeChoices.size > 1) {
            Column {
                FilterChip(
                    selected = decadeFilter != null,
                    onClick = { if (decadeFilter != null) onDecade(null) else decadeMenu = true },
                    label = { Text(decadeFilter?.let { "${it}s" } ?: "Decade") },
                    trailingIcon = {
                        Icon(
                            if (decadeFilter != null) Icons.Default.Close
                            else Icons.Default.ArrowDropDown,
                            contentDescription = if (decadeFilter != null) "Clear decade filter" else null,
                        )
                    },
                )
                DropdownMenu(expanded = decadeMenu, onDismissRequest = { decadeMenu = false }) {
                    decadeChoices.forEach { d ->
                        DropdownMenuItem(
                            text = { Text("${d}s") },
                            onClick = { onDecade(d); decadeMenu = false },
                        )
                    }
                }
            }
        }
    }
}

/** One episode search result: 16:9 still + episode title + "Series · S1·E2".
 *  Tapping opens the episode's own Detail (play/favorite/share/clip), Decision 045. */
@Composable
private fun EpisodeItemRow(item: CatalogItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Catalog art is 2:3 (both designed posters and our frame covers, which
        // frame_cover.py crops to a poster aspect), so a 16:9 thumb cropped the
        // poster to a sliver. Match the art's own shape instead.
        BackdropImage(
            url = item.posterURL ?: item.backdropURL,
            contentDescription = item.title,
            accent = item.accentColor,
            modifier = Modifier
                .size(width = 48.dp, height = 72.dp)
                .clip(RoundedCornerShape(6.dp)),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                item.title,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                listOfNotNull(item.seriesTitle, item.episodeNumberLabel).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
