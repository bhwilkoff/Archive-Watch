package app.archivewatch.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.PosterTile
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
        val db = container.catalog.db ?: return@LaunchedEffect
        results = db.search(query)
        searched = true
    }

    val filtered = results.filter { item ->
        (typeFilter == null || item.contentType == typeFilter!!.second) &&
            (decadeFilter == null || item.decade == decadeFilter)
    }

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                placeholder = { Text("Search films, people, genres…") },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .padding(top = 32.dp),
            )
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
                searched && filtered.isEmpty() -> EmptyState("No matches with these filters — clear one to widen the net.")
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
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
