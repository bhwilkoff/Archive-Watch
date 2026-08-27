package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.BrowseSort
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.Nav
import kotlinx.coroutines.launch
import java.text.NumberFormat

private const val PAGE_SIZE = 60
private const val TV_GRID_COLUMNS = 6

/** The same scope vocabulary as the phone Browse — verbs of the catalog, not
 *  raw contentTypes. Duplicated deliberately: the phone enum is private, and a
 *  TV build must never widen a phone screen's API surface just to borrow it. */
private enum class TvScope(val label: String, val contentType: String?) {
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

/**
 * TV Browse (docs/TV-DESIGN.md §4.6 — a grid is for a CHOSEN scope, which is
 * exactly what Browse is).
 *
 * Scope chips ride a focusable row above the grid; Down enters the grid, Up
 * returns. Paging is driven by FOCUS, not scroll position: on a TV the viewer
 * moves focus, and a scroll listener would fire late or not at all (§3.3).
 */
@Composable
fun TvBrowseScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val scope = rememberCoroutineScope()

    var activeScope by remember { mutableStateOf(TvScope.All) }
    var activeDecade by remember { mutableStateOf<Int?>(null) }
    var activeSort by remember { mutableStateOf(BrowseSort.POPULAR) }
    var total by remember { mutableIntStateOf(0) }
    var endReached by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    val items = remember { mutableStateListOf<CatalogItem>() }

    val firstChip = remember { FocusRequester() }
    val firstTile = remember { FocusRequester() }
    val gridState = rememberLazyGridState()
    val chipState = rememberLazyListState()

    LaunchedEffect(dbVersion, activeScope, activeDecade, activeSort) {
        loading = true
        items.clear()
        endReached = false
        val db = container.catalog.awaitDb()
        if (activeScope == TvScope.TV) {
            val cards = db.seriesCards()
            items.addAll(cards)
            total = cards.size
            endReached = true
        } else {
            total = db.browseCount(contentType = activeScope.contentType, decade = activeDecade)
            val page = db.browse(
                contentType = activeScope.contentType,
                decade = activeDecade,
                sort = activeSort,
                limit = PAGE_SIZE,
                offset = 0,
            )
            items.addAll(page)
            endReached = page.size < PAGE_SIZE
        }
        loading = false
    }

    suspend fun loadMore() {
        if (endReached || loading || activeScope == TvScope.TV) return
        val db = container.catalog.db ?: return
        val page = db.browse(
            contentType = activeScope.contentType,
            decade = activeDecade,
            sort = activeSort,
            limit = PAGE_SIZE,
            offset = items.size,
        )
        items.addAll(page)
        if (page.size < PAGE_SIZE) endReached = true
    }

    // §3.1 — exactly one claim, and it is the content. Re-claimed when the
    // scope changes so the grid never comes back with nothing focused.
    ClaimInitialFocus(if (items.isEmpty()) firstChip else firstTile, key = activeScope to items.isEmpty())

    Column(Modifier.fillMaxSize()) {
        Text(
            if (total > 0) "Browse · ${NumberFormat.getInstance().format(total)} titles" else "Browse",
            fontSize = 32.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            modifier = Modifier.padding(
                start = TvDims.OverscanH,
                top = TvDims.OverscanV,
                bottom = 14.dp,
            ),
        )

        TvScopeChips(
            active = activeScope,
            onSelect = { activeScope = it },
            firstChipFocus = firstChip,
            state = chipState,
        )

        // Sort + era ride a second chip row (tvOS Browse parity: 4 sorts +
        // Era facet). Hidden for the TV scope — series cards carry their own
        // rating-then-depth order and eras belong to episodes, not spines.
        if (activeScope != TvScope.TV) {
            TvRefineChips(
                sort = activeSort,
                onSort = { activeSort = it },
                decade = activeDecade,
                onDecade = { activeDecade = it },
            )
        }

        if (loading && items.isEmpty()) {
            TvMessage("Loading…")
            return@Column
        }
        if (items.isEmpty()) {
            TvMessage("Nothing here yet.")
            return@Column
        }

        LazyVerticalGrid(
            // FIXED, not Adaptive: the D-pad needs "is this the first column?"
            // to hand focus back to the rail, and an adaptive column count is
            // not knowable at compose time. 6 across fits 1080p at PosterWidth.
            columns = GridCells.Fixed(TV_GRID_COLUMNS),
            state = gridState,
            contentPadding = PaddingValues(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH,
                top = 8.dp,
                bottom = TvDims.OverscanV * 2,
            ),
            horizontalArrangement = Arrangement.spacedBy(TvDims.PosterSpacing),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            itemsIndexed(items, key = { _, it -> it.archiveID }) { index, item ->
                TvPosterTile(
                    item = item,
                    onClick = { nav.openItem(item.archiveID, item.seriesID, item.contentType) },
                    focusRequester = if (index == 0) firstTile else null,
                    // NO explicit exitLeftTo here — and that is deliberate.
                    // A vertical grid's first column IS spatially adjacent to
                    // the rail, so Compose's own focus search crosses it, and
                    // it lands on the VERTICALLY NEAREST rail item, which is
                    // better than forcing a jump to Home. Verified on the
                    // emulator (Left from row 2 landed on Settings).
                    // The override is only needed for a LazyRow, where focus
                    // search will NOT cross out of the first item (§3.4).
                    onFocused = {
                        // Page in on FOCUS approach — the viewer's cursor is the
                        // signal on a TV, not the scroll offset.
                        if (index >= items.size - 12) scope.launch { loadMore() }
                    },
                )
            }
        }
    }
}

@Composable
private fun TvRefineChips(
    sort: BrowseSort,
    onSort: (BrowseSort) -> Unit,
    decade: Int?,
    onDecade: (Int?) -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(start = TvDims.OverscanH, end = TvDims.OverscanH),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(bottom = 18.dp),
    ) {
        items(BrowseSort.entries.toList(), key = { "sort-" + it.name }) { s ->
            TvChip(
                label = s.label,
                selected = s == sort,
                onClick = { onSort(s) },
            )
        }
        item(key = "era-div") {
            Box(Modifier.padding(horizontal = 6.dp)) {
                Text("·", fontSize = 24.sp, color = Color(0xFF666666))
            }
        }
        item(key = "era-all") {
            TvChip(label = "All eras", selected = decade == null, onClick = { onDecade(null) })
        }
        items((1890..2020 step 10).toList(), key = { "era-" + it }) { d ->
            TvChip(
                label = "${'$'}{d}s",
                selected = decade == d,
                onClick = { onDecade(if (decade == d) null else d) },
            )
        }
    }
}

@Composable
private fun TvChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .tvFocusable(
                onClick = onClick,
                shape = RoundedCornerShape(24.dp),
                scaleWhenFocused = 1.04f,
            )
            .background(
                if (selected) Color(0xFFFF5C35) else Color(0xFF1C1C1C),
                RoundedCornerShape(24.dp),
            )
            .padding(horizontal = 26.dp, vertical = 12.dp),
    ) {
        Text(
            label,
            fontSize = 24.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) Color.Black else Color.White,
        )
    }
}

@Composable
private fun TvScopeChips(
    active: TvScope,
    onSelect: (TvScope) -> Unit,
    firstChipFocus: FocusRequester,
    state: androidx.compose.foundation.lazy.LazyListState,
) {
    // The chips are a LazyRow, so focus search will NOT cross out of the first
    // chip into the rail — this one DOES need the explicit override (§3.4).
    val railFocus = LocalTvRailFocus.current
    LazyRow(
        state = state,
        contentPadding = PaddingValues(
            start = TvDims.OverscanH,
            end = TvDims.OverscanH,
        ),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(bottom = 18.dp),
    ) {
        items(TvScope.entries.toList(), key = { it.name }) { s ->
            val selected = s == active
            Box(
                Modifier
                    .tvFocusable(
                        onClick = { onSelect(s) },
                        focusRequester = if (s == TvScope.entries.first()) firstChipFocus else null,
                        shape = RoundedCornerShape(24.dp),
                        scaleWhenFocused = 1.04f,
                        exitLeftTo = if (s == TvScope.entries.first()) railFocus else null,
                    )
                    .background(
                        if (selected) Color(0xFFFF5C35) else Color(0xFF1C1C1C),
                        RoundedCornerShape(24.dp),
                    )
                    .padding(horizontal = 26.dp, vertical = 12.dp),
            ) {
                Text(
                    s.label,
                    fontSize = 24.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (selected) Color.Black else Color.White,
                )
            }
        }
    }
}
