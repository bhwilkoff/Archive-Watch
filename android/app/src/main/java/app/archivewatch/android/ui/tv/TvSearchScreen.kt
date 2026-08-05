package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import kotlinx.coroutines.delay

/**
 * TV Search (docs/TV-DESIGN.md §3.6 — "text entry is the last resort").
 *
 * An on-screen keyboard driven by a D-pad is genuinely slow, so this surface is
 * built so the keyboard is OPTIONAL:
 *
 *  - a focusable letter grid on the left for when the viewer does know the name
 *  - and, when the query is empty, **browse doors** on the right — decades and
 *    themes — so a viewer can find something without ever typing a character.
 *
 * That second half is the §3.6 requirement and the §1.5 guardrail: dropping it
 * would make Search a dead end for anyone unwilling to spell a title with a
 * remote.
 */
private val KEY_ROWS = listOf(
    "ABCDEF",
    "GHIJKL",
    "MNOPQR",
    "STUVWX",
    "YZ0123",
    "456789",
)

@Composable
fun TvSearchScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<CatalogItem>>(emptyList()) }
    var decades by remember { mutableStateOf<List<Pair<Int, Int>>>(emptyList()) }
    var keywords by remember { mutableStateOf<List<String>>(emptyList()) }

    val firstKey = remember { FocusRequester() }

    LaunchedEffect(dbVersion) {
        val db = container.catalog.db ?: return@LaunchedEffect
        decades = db.decadeCounts()
        keywords = db.topKeywords(limit = 18)
    }

    // Same 180ms debounce as the phone screen, re-run on DB swap.
    LaunchedEffect(query, dbVersion) {
        if (query.isBlank()) {
            results = emptyList()
            return@LaunchedEffect
        }
        delay(180)
        val db = container.catalog.db ?: return@LaunchedEffect
        results = db.search(query)
    }

    ClaimInitialFocus(firstKey)

    Row(Modifier.fillMaxSize()) {
        // ---- left: the optional keyboard --------------------------------
        Column(
            Modifier
                .width(430.dp)
                .fillMaxHeight()
                .padding(start = TvDims.OverscanH, top = TvDims.OverscanV, end = 20.dp),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .background(Color(0xFF161616), RoundedCornerShape(10.dp))
                    .padding(horizontal = 18.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(
                    query.ifEmpty { "Search titles" },
                    fontSize = 26.sp,
                    color = if (query.isEmpty()) Color(0xFF777777) else Color.White,
                )
            }

            Column(Modifier.padding(top = 18.dp)) {
                KEY_ROWS.forEachIndexed { rowIndex, row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEachIndexed { colIndex, ch ->
                            TvKeyCap(
                                label = ch.toString(),
                                focusRequester = if (rowIndex == 0 && colIndex == 0) firstKey else null,
                                // §3.4 — the leftmost key column is the door back
                                // to the nav rail.
                                exitLeft = colIndex == 0,
                            ) { query += ch }
                        }
                    }
                }
                Row(
                    Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    TvKeyCap(label = "SPACE", wide = true, exitLeft = true) { query += " " }
                    TvKeyCap(label = "DEL", wide = true) { query = query.dropLast(1) }
                }
            }
        }

        // ---- right: results, or the no-typing doors ---------------------
        Box(Modifier.fillMaxSize()) {
            if (query.isBlank()) {
                TvSearchDoors(decades, keywords, nav)
            } else if (results.isEmpty()) {
                TvMessage("No titles match “$query”.")
            } else {
                Column(Modifier.fillMaxSize()) {
                    Text(
                        "${results.size} result${if (results.size == 1) "" else "s"}",
                        fontSize = 26.sp,
                        color = Color(0xFFB0B0B0),
                        modifier = Modifier.padding(top = TvDims.OverscanV, bottom = 14.dp),
                    )
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(4),
                        contentPadding = PaddingValues(
                            end = TvDims.OverscanH,
                            bottom = TvDims.OverscanV * 2,
                        ),
                        horizontalArrangement = Arrangement.spacedBy(TvDims.PosterSpacing),
                        verticalArrangement = Arrangement.spacedBy(22.dp),
                    ) {
                        items(results, key = { it.archiveID }) { item ->
                            TvPosterTile(
                                item = item,
                                onClick = {
                                    nav.openItem(item.archiveID, item.seriesID, item.contentType)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * §3.6 / §1.5 — the reason Search is not a keyboard-only dead end. Decades and
 * themes are reachable in two presses and land in the same filtered grid Browse
 * uses, so "find me something" never requires spelling anything.
 */
@Composable
private fun TvSearchDoors(
    decades: List<Pair<Int, Int>>,
    keywords: List<String>,
    nav: Nav,
) {
    LazyColumn(
        contentPadding = PaddingValues(
            top = TvDims.OverscanV,
            end = TvDims.OverscanH,
            bottom = TvDims.OverscanV * 2,
        ),
    ) {
        item(key = "hint") {
            Text(
                "Or browse without typing",
                fontSize = 32.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier.padding(bottom = 6.dp),
            )
        }
        item(key = "decades-label") {
            Text(
                "By decade",
                fontSize = 22.sp,
                color = Color(0xFF9A9A9A),
                modifier = Modifier.padding(top = 14.dp, bottom = 10.dp),
            )
        }
        item(key = "decades") {
            TvChipFlow(
                labels = decades.filter { it.second >= 30 }.map { "${it.first}s" },
                onSelect = { label ->
                    label.dropLast(1).toIntOrNull()?.let {
                        nav.push(Route.Filtered(title = label, decade = it))
                    }
                },
            )
        }
        if (keywords.isNotEmpty()) {
            item(key = "themes-label") {
                Text(
                    "By theme",
                    fontSize = 22.sp,
                    color = Color(0xFF9A9A9A),
                    modifier = Modifier.padding(top = 24.dp, bottom = 10.dp),
                )
            }
            item(key = "themes") {
                TvChipFlow(
                    labels = keywords,
                    onSelect = { nav.push(Route.Filtered(title = it, contentType = null)) },
                )
            }
        }
    }
}

/**
 * A wrapping run of focusable chips.
 *
 * FlowRow, NOT a manual `chunked(n)`: a fixed chunk size does not know the
 * panel width, and on the emulator it pushed the third decade chip off the
 * right edge — clipped content that the D-pad could still focus, which is
 * exactly the §3.3 "focused element off-screen" bug.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TvChipFlow(labels: List<String>, onSelect: (String) -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        labels.forEach { label ->
            Box(
                Modifier
                    .tvFocusable(
                        onClick = { onSelect(label) },
                        shape = RoundedCornerShape(22.dp),
                        scaleWhenFocused = 1.04f,
                    )
                    .background(Color(0xFF1C1C1C), RoundedCornerShape(22.dp))
                    .padding(horizontal = 22.dp, vertical = 12.dp),
            ) {
                Text(label, fontSize = 22.sp, color = Color.White, maxLines = 1)
            }
        }
    }
}

@Composable
private fun TvKeyCap(
    label: String,
    wide: Boolean = false,
    exitLeft: Boolean = false,
    focusRequester: FocusRequester? = null,
    onPress: () -> Unit,
) {
    val railFocus = LocalTvRailFocus.current
    Box(
        Modifier
            .tvFocusable(
                onClick = onPress,
                focusRequester = focusRequester,
                shape = RoundedCornerShape(8.dp),
                scaleWhenFocused = 1.10f,
                exitLeftTo = if (exitLeft) railFocus else null,
            )
            .then(if (wide) Modifier.width(126.dp) else Modifier.size(58.dp))
            .background(Color(0xFF232323), RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            fontSize = if (wide) 18.sp else 26.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White,
        )
    }
}
