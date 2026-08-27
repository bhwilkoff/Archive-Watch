package app.archivewatch.android.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.BrowseSort
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.PosterTile
import java.text.NumberFormat

private const val PAGE_SIZE = 60

/** Browse scopes — the verbs of the catalog, not the raw contentTypes. */
private enum class Scope(val label: String, val contentType: String?) {
    All("All", null),
    Films("Films", "feature-film"),
    TV("TV", "tv-series"),
    Silent("Silent", "silent-film"),
    Animation("Animation", "animation"),
    Shorts("Shorts", "short-film"),
    Newsreels("Newsreels", "newsreel"),
    Documentary("Documentary", "documentary"),
    Ephemera("Ephemera", "ephemeral"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowseScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()

    var scope by remember { mutableStateOf(Scope.All) }
    var decade by remember { mutableStateOf<Int?>(null) }
    // Metadata-expansion facets (Decision 046): keyword (thematic) + studio filters.
    var keyword by remember { mutableStateOf<String?>(null) }
    var studio by remember { mutableStateOf<String?>(null) }
    var sort by remember { mutableStateOf(BrowseSort.POPULAR) }
    var total by remember { mutableIntStateOf(0) }
    var endReached by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    val items = remember { mutableStateListOf<CatalogItem>() }
    var decades by remember { mutableStateOf<List<Pair<Int, Int>>>(emptyList()) }
    var keywordChoices by remember { mutableStateOf<List<String>>(emptyList()) }
    var studioChoices by remember { mutableStateOf<List<String>>(emptyList()) }
    var specialsCount by remember { mutableIntStateOf(0) }

    // Facet menus only need loading once per DB (independent of the active filters).
    LaunchedEffect(dbVersion) {
        val db = container.catalog.awaitDb()
        decades = db.decadeCounts()
        keywordChoices = db.topKeywords()
        studioChoices = db.topStudios()
    }

    // Reset + first page whenever a facet, sort, or the DB changes.
    LaunchedEffect(dbVersion, scope, decade, keyword, studio, sort) {
        loading = true
        items.clear()
        endReached = false
        val db = container.catalog.awaitDb()
        if (scope == Scope.TV) {
            val cards = db.seriesCards()
            items.addAll(cards)
            total = cards.size
            endReached = true
            specialsCount = db.tvSpecialsCount()
        } else {
            total = db.browseCount(
                contentType = scope.contentType, decade = decade,
                keyword = keyword, studio = studio,
            )
            val page = db.browse(
                contentType = scope.contentType, decade = decade,
                keyword = keyword, studio = studio,
                sort = sort, limit = PAGE_SIZE, offset = 0,
            )
            items.addAll(page)
            endReached = page.size < PAGE_SIZE
        }
        loading = false
    }

    suspend fun loadMore() {
        if (endReached || loading || scope == Scope.TV) return
        val db = container.catalog.db ?: return
        val page = db.browse(
            contentType = scope.contentType, decade = decade,
            keyword = keyword, studio = studio,
            sort = sort, limit = PAGE_SIZE, offset = items.size,
        )
        items.addAll(page)
        if (page.size < PAGE_SIZE) endReached = true
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Browse") },
                actions = {
                    TextButton(onClick = { nav.push(Route.Collections) }) { Text("Collections") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // Scope chips
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Scope.entries.forEach { s ->
                    FilterChip(
                        selected = scope == s,
                        onClick = { scope = s },
                        label = { Text(s.label) },
                    )
                }
            }

            // Decade + sort + keyword/studio facets + real total (scrollable —
            // the metadata-expansion facets crowd the row on narrow phones).
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                DecadeMenu(decade, decades) { decade = it }
                SortMenu(sort) { sort = it }
                // Keyword/studio facets don't apply to the TV scope (series cards).
                if (scope != Scope.TV) {
                    if (keywordChoices.isNotEmpty()) {
                        FacetMenu("Keyword", keyword, keywordChoices) { keyword = it }
                    }
                    if (studioChoices.isNotEmpty()) {
                        FacetMenu("Studio", studio, studioChoices) { studio = it }
                    }
                }
                val count = NumberFormat.getIntegerInstance().format(total)
                Text(
                    "$count titles",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Standalone TV specials/episodes not folded into a series — out of
            // the film grids (owner directive 2026-06-18), reachable here.
            if (scope == Scope.TV && specialsCount > 0) {
                TextButton(
                    onClick = { nav.push(Route.Filtered(title = "TV Specials", contentType = "tv-special")) },
                    modifier = Modifier.padding(horizontal = 16.dp),
                ) { Text("TV Specials ($specialsCount) →") }
            }

            when {
                loading && items.isEmpty() -> app.archivewatch.android.ui.LoadingBox()
                items.isEmpty() -> EmptyState("Nothing here yet — try another scope or decade.")
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    itemsIndexed(items, key = { _, item -> item.archiveID }) { index, item ->
                        if (index >= items.size - 12) {
                            LaunchedEffect(items.size) { loadMore() }
                        }
                        PosterTile(item, onClick = {
                            nav.openItem(item.archiveID, item.seriesID, item.contentType)
                        })
                    }
                }
            }
        }
    }
}

@Composable
private fun DecadeMenu(
    selected: Int?,
    decades: List<Pair<Int, Int>>,
    onSelect: (Int?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = true }) {
        Text(selected?.let { "${it}s" } ?: "All decades")
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(text = { Text("All decades") }, onClick = { onSelect(null); open = false })
        decades.forEach { (d, count) ->
            DropdownMenuItem(
                text = { Text("${d}s ($count)") },
                onClick = { onSelect(d); open = false },
            )
        }
    }
}

/** A string-valued facet dropdown (keyword / studio, Decision 046). When a value
    is active the button shows it + a clear ("All") entry; mirrors DecadeMenu. */
@Composable
private fun FacetMenu(
    label: String,
    selected: String?,
    choices: List<String>,
    onSelect: (String?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = true }) { Text(selected ?: label) }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(text = { Text("All ${label.lowercase()}s") }, onClick = { onSelect(null); open = false })
        choices.forEach { value ->
            DropdownMenuItem(text = { Text(value) }, onClick = { onSelect(value); open = false })
        }
    }
}

@Composable
private fun SortMenu(selected: BrowseSort, onSelect: (BrowseSort) -> Unit) {
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = true }) { Text(selected.label) }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        BrowseSort.entries.forEach { s ->
            DropdownMenuItem(text = { Text(s.label) }, onClick = { onSelect(s); open = false })
        }
    }
}
