package app.archivewatch.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import android.content.Intent
import androidx.compose.material.icons.filled.Share
import androidx.compose.ui.platform.LocalContext
import app.archivewatch.android.data.PlaylistShare
import app.archivewatch.android.ui.tv.TvPageHeader
import app.archivewatch.android.ui.tv.TvPosterGrid
import app.archivewatch.android.ui.tv.TvRefineChip
import app.archivewatch.android.ui.tv.TvDims
import app.archivewatch.android.ui.tv.LocalTvRailFocus
import app.archivewatch.android.ui.tv.LocalIsTelevision
import app.archivewatch.android.ui.tv.TvActionPill
import app.archivewatch.android.ui.tv.TvConfirm
import app.archivewatch.android.ui.tv.TvShareOverlay
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.material3.FilterChip
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.BrowseSort
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.FeaturedCategory
import app.archivewatch.android.ui.EmptyState
import app.archivewatch.android.ui.uniqueBy
import app.archivewatch.android.ui.LoadingBox
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.tv.tvFocusable
import app.archivewatch.android.ui.PosterTile
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.theme.colorFromHex
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

// Discovery + serendipity surfaces (ANDROID-DESIGN §4.1 amendment, parity
// wave 2026-06-11): category/era tile rows on Home, the filtered grid they
// open, the Surprise grid, and the playlist grid.

/** Category tiles — featured.json accents, count-gated ≥30 (the apps' rule). */
@Composable
fun CategoryTilesRow(categories: List<FeaturedCategory>, onCategory: (FeaturedCategory) -> Unit) {
    Column {
        Text(
            "Browse by Category",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(horizontal = 16.dp),
        ) {
            items(categories, key = { it.id }) { cat ->
                val accent = colorFromHex(cat.accent) ?: MaterialTheme.colorScheme.primary
                Box(
                    modifier = Modifier
                        .size(width = 150.dp, height = 92.dp)
                        // TV: `clickable` gives no D-pad focus (see Components.PosterTile).
                        // Focus goes OUTSIDE the paint, as on TvPosterTile: painted
                        // outside the scaled, shadowed layer, a tile lost its
                        // background once focus had passed through it.
                        .then(
                            if (LocalIsTelevision.current) {
                                Modifier.tvFocusable(onClick = { onCategory(cat) }, focusTag = "category:" + cat.displayName)
                            } else Modifier,
                        )
                        .clip(RoundedCornerShape(10.dp))
                        .background(
                            Brush.linearGradient(
                                listOf(accent.copy(alpha = 0.95f), accent.copy(alpha = 0.55f)),
                            ),
                        )
                        .then(if (LocalIsTelevision.current) Modifier else Modifier.clickable { onCategory(cat) })
                        .padding(12.dp),
                    contentAlignment = Alignment.BottomStart,
                ) {
                    Text(
                        cat.displayName,
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}

/** Era tiles — the LAST Home row (the apps' order). */
@Composable
fun EraTilesRow(decades: List<Pair<Int, Int>>, onDecade: (Int) -> Unit) {
    Column {
        Text(
            "Browse by Era",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(horizontal = 16.dp),
        ) {
            items(decades, key = { it.first }) { (decade, count) ->
                Column(
                    modifier = Modifier
                        .size(width = 130.dp, height = 92.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .then(
                            if (LocalIsTelevision.current) {
                                Modifier.tvFocusable(onClick = { onDecade(decade) }, focusTag = "decade:" + decade)
                            } else Modifier.clickable { onDecade(decade) },
                        )
                        .padding(12.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        "${decade}s",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Black,
                    )
                    Text(
                        "$count titles",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

private const val FILTERED_PAGE = 60

/** The grid a category/era tile opens (the apps' FilteredGridView). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilteredGridScreen(container: AppContainer, nav: Nav, route: Route.Filtered) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    // Public Domain Day explorer (iOS parity): year chips walk BACK through
    // recent entry years; each chip re-filters the grid to that year's films.
    var pdYearShown by remember(route) { mutableStateOf(route.year) }
    // A genre tile lands here, and this screen had no way to order what it
    // showed — reported from an iPad on r/classicfilms, 2026-09-10: "would be
    // nice to have sort features like by year browsing through film noir".
    // Browse itself has had the control all along; the grid a CATEGORY opens
    // never did, on any platform. iOS and macOS were fixed in 1.42.8; this is
    // the same gap on Android, and `browse()` already takes the sort, so it
    // was only ever a missing control.
    var sort by remember(route) { mutableStateOf(BrowseSort.POPULAR) }
    // Paged like Browse, with the real count: a fixed limit of 240 told a
    // viewer the 1930s held "240 titles" (4,576 do) and ended the grid there.
    var items by remember { mutableStateOf<List<CatalogItem>?>(null) }
    var total by remember { mutableStateOf<Int?>(null) }
    var endReached by remember { mutableStateOf(false) }
    val pageScope = rememberCoroutineScope()
    var paging by remember { mutableStateOf(false) }
    LaunchedEffect(dbVersion, pdYearShown, sort) {
        items = null                     // show the loader while re-sorting
        val db = container.catalog.awaitDb()
        val year = pdYearShown ?: route.year
        total = db.browseCount(contentType = route.contentType, decade = route.decade, year = year)
        val page = db.browse(contentType = route.contentType, decade = route.decade,
                             year = year, sort = sort, limit = FILTERED_PAGE)
        endReached = page.size < FILTERED_PAGE
        items = page
    }
    fun loadMore() {
        val have = items ?: return
        if (endReached || paging) return
        paging = true
        pageScope.launch {
            val db = container.catalog.awaitDb()
            val page = db.browse(contentType = route.contentType, decade = route.decade,
                                 year = pdYearShown ?: route.year, sort = sort,
                                 limit = FILTERED_PAGE, offset = have.size)
            if (page.size < FILTERED_PAGE) endReached = true
            items = have + page
            paging = false
        }
    }
    // TV: the header and the SORT are the two things the phone screen cannot
    // lend a television. Its sort is a Material DropdownMenu — a phone-sized
    // target that opens a nested focus context a remote then has to escape —
    // and its grid is GridCells.Adaptive(110.dp) with no overscan inset. On TV
    // every sort is a chip, visible at once, one press each (TvRefineChip),
    // which is what TvBrowseScreen has always done for the same control.
    if (LocalIsTelevision.current) {
        val rows = items.orEmpty().uniqueBy { it.archiveID }
        Column(Modifier.fillMaxSize()) {
            TvPageHeader(
                eyebrow = if (route.pdExplorer) "PUBLIC DOMAIN DAY" else "BROWSE",
                title = route.title,
                meta = when {
                    items == null -> "Loading…"
                    rows.isEmpty() -> "No titles match this filter in the catalog."
                    else -> (total ?: rows.size).let { n -> "%,d %s".format(n, if (n == 1) "title" else "titles") }
                },
                compact = true,
            )
            LazyRow(
                contentPadding = PaddingValues(
                    start = TvDims.OverscanH,
                    end = TvDims.OverscanH,
                ),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(bottom = 16.dp),
            ) {
                items(BrowseSort.entries.toList(), key = { "sort-" + it.name }) { s ->
                    TvRefineChip(s.label, s == sort) { sort = s }
                }
                if (route.pdExplorer && route.year != null) {
                    items((0..9).map { route.year!! - it }, key = { "y" + it }) { y ->
                        TvRefineChip(y.toString(), pdYearShown == y) { pdYearShown = y }
                    }
                }
            }
            TvPosterGrid(
                rows = rows,
                onClick = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                railFocus = LocalTvRailFocus.current,
                onNearEnd = { loadMore() },
            )
        }
        return
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(route.title) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = { SortMenu(sort) { sort = it } },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val list = items
        when {
            list == null -> LoadingBox(Modifier.padding(padding))
            list.isEmpty() -> Box(Modifier.padding(padding)) {
                EmptyState("No titles match this filter in the catalog.")
            }
            else -> Column(Modifier.fillMaxSize().padding(padding)) {
                if (route.pdExplorer && route.year != null) {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(top = 4.dp, bottom = 4.dp),
                    ) {
                        items((0..9).map { route.year!! - it }, key = { it }) { y ->
                            FilterChip(
                                selected = pdYearShown == y,
                                onClick = { pdYearShown = y },
                                label = { Text(y.toString()) },
                            )
                        }
                    }
                }
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 110.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    val unique = list.uniqueBy { it.archiveID }
                    itemsIndexed(unique, key = { _, item -> item.archiveID }) { index, item ->
                        if (index >= unique.size - 12) LaunchedEffect(unique.size) { loadMore() }
                        PosterTile(item, onClick = {
                            nav.openItem(item.archiveID, item.seriesID, item.contentType)
                        })
                    }
                }
            }
        }
    }
}

/** Surprise — a re-rollable random grid (the apps' serendipity surface). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SurpriseScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var roll by remember { mutableIntStateOf(0) }
    val items by produceState<List<CatalogItem>?>(null, dbVersion, roll) {
        value = container.catalog.awaitDb().surpriseDoors()
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Surprise Me") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = { nav.push(Route.Cartoon) }) { Text("Cartoons") }
                    Button(onClick = { roll += 1 }, modifier = Modifier.padding(end = 12.dp)) {
                        Icon(Icons.Default.Shuffle, contentDescription = null,
                             modifier = Modifier.size(18.dp))
                        Text("  Re-roll")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val list = items
        if (list == null) { LoadingBox(Modifier.padding(padding)); return@Scaffold }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 110.dp),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            items(list.uniqueBy { it.archiveID }, key = { it.archiveID }) { item ->
                PosterTile(item, onClick = {
                    nav.openItem(item.archiveID, item.seriesID, item.contentType)
                })
            }
        }
    }
}

/** One playlist's grid, with delete (Library → playlist). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistScreen(container: AppContainer, nav: Nav, playlistID: String) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    val scope = rememberCoroutineScope()

    val state by produceState<Pair<String, List<CatalogItem>>?>(null, dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        val pl = container.userState.playlists().find { it.id == playlistID } ?: return@produceState
        value = pl.name to db.itemsByIDs(pl.archiveIDs)
    }

    // SHARE. The playlist rides inside the link (PlaylistShare), so whoever
    // receives it needs no account and we host nothing. The link is built from
    // the STORED ids rather than the resolved rows: a title the catalogue has
    // since dropped should still travel, and the receiving end says how many
    // it could resolve.
    val ctx = LocalContext.current
    val isTv = LocalIsTelevision.current
    var shareUrl by remember { mutableStateOf<String?>(null) }
    var shareName by remember { mutableStateOf("") }
    val onShare: () -> Unit = {
        scope.launch {
            val pl = container.userState.playlists().find { it.id == playlistID }
            val url = pl?.let { PlaylistShare.url(it.name, it.archiveIDs) }
            if (url != null) {
                shareName = pl.name
                if (isTv) {
                    // A television has no share sheet: the link becomes a QR,
                    // the same device TvShareOverlay already uses for titles.
                    shareUrl = url
                } else {
                    ctx.startActivity(Intent.createChooser(
                        Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, pl.name)
                            putExtra(Intent.EXTRA_TEXT, url)
                        }, null))
                }
            }
        }
    }
    // TV. Three things the phone page cannot lend a television, and the middle
    // one was not a layout problem at all:
    //
    //  1. Share and Delete were UNLABELLED 24dp icon buttons in a TopAppBar.
    //  2. SHARE DID NOTHING. `shareUrl` was assigned on the TV branch and read
    //     by nobody — TvShareOverlay was imported, named in the comment above,
    //     and never called. Pressing Share on a television set a variable.
    //  3. DELETE ASKED NOTHING. An unlabelled trash icon destroyed the
    //     playlist on one press, with no question and no undo, which is not
    //     something to hand a remote.
    if (isTv) {
        val rows = state?.second.orEmpty().uniqueBy { it.archiveID }
        var confirmDelete by remember { mutableStateOf(false) }
        val railFocus = LocalTvRailFocus.current
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
                TvPageHeader(
                    eyebrow = "PLAYLIST",
                    title = state?.first ?: "Playlist",
                    meta = when {
                        state == null -> "Loading…"
                        rows.isEmpty() -> "Empty — add titles from any Detail page."
                        else -> "${rows.size} ${if (rows.size == 1) "title" else "titles"}"
                    },
                    compact = true,
                ) {
                    TvActionPill(
                        label = "Share",
                        onClick = onShare,
                        primary = true,
                        exitLeftTo = railFocus,
                    )
                    TvActionPill(label = "Delete", onClick = { confirmDelete = true })
                }
                TvPosterGrid(
                    rows = rows,
                    onClick = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                    railFocus = railFocus,
                )
            }
            shareUrl?.let { url ->
                TvShareOverlay(title = shareName, url = url, onDone = { shareUrl = null })
            }
            if (confirmDelete) {
                TvConfirm(
                    question = "Delete this playlist?",
                    detail = "\"" + (state?.first ?: "") + "\" will be removed from your " +
                        "library. The films stay in the catalog.",
                    confirmLabel = "Delete",
                    onConfirm = {
                        confirmDelete = false
                        scope.launch {
                            container.userState.deletePlaylist(playlistID)
                            nav.pop()
                        }
                    },
                    onCancel = { confirmDelete = false },
                )
            }
        }
        return
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state?.first ?: "Playlist") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onShare) {
                        Icon(Icons.Default.Share, contentDescription = "Share playlist")
                    }
                    IconButton(onClick = {
                        scope.launch {
                            container.userState.deletePlaylist(playlistID)
                            nav.pop()
                        }
                    }) {
                        Icon(Icons.Default.Delete, contentDescription = "Delete playlist")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        val items = state?.second
        when {
            items == null -> LoadingBox(Modifier.padding(padding))
            items.isEmpty() -> Box(Modifier.padding(padding)) {
                EmptyState("This playlist is empty — add titles from any Detail page.")
            }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 110.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize().padding(padding),
            ) {
                items(items.uniqueBy { it.archiveID }, key = { it.archiveID }) { item ->
                    PosterTile(item, onClick = {
                        nav.openItem(item.archiveID, item.seriesID, item.contentType)
                    })
                }
            }
        }
    }
}
