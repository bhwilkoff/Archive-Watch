package app.archivewatch.android.ui.tv

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route

/**
 * Cartoon Mode, on a television.
 *
 * Measured wrong on the phone screen, like the rest: a uiautomator dump on the
 * Google TV put shelf headers and film captions at x=32 (left of the 96 safe
 * edge), the "Cartoon Mode" title at y=36, and the **Marathon button clipped on
 * BOTH axes** at y=44 with its right edge at 1840 — the primary action of the
 * surface, sitting in the corner a panel cuts twice. 6 of 18 text nodes outside
 * the band.
 *
 * A shelf page, not a grid, so it takes TvShelfRow rather than TvPosterGrid —
 * TvShelfRow already insets its header and leads its LazyRow with the overscan
 * margin, so the shelves need nothing but to be used.
 *
 * The POOL and the shelf definitions are unchanged: the same ten characters,
 * the same `full = true` browse so the marathon has downloadURLs to queue, the
 * same four-item floor before a shelf is worth drawing.
 */
@Composable
fun TvCartoonScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val characterDefs = listOf(
        "Popeye" to listOf("popeye"), "Betty Boop" to listOf("betty boop"),
        "Porky Pig" to listOf("porky"), "Mr. Magoo" to listOf("magoo"),
        "Looney Tunes" to listOf("looney"), "Felix the Cat" to listOf("felix"),
        "Daffy Duck" to listOf("daffy"), "Casper" to listOf("casper"),
        "Mighty Mouse" to listOf("mighty mouse"), "Superman" to listOf("superman"),
    )

    val state by produceState<Pair<List<CatalogItem>, List<Pair<String, List<CatalogItem>>>>?>(
        null, dbVersion,
    ) {
        val db = container.catalog.awaitDb()
        // full = true: the marathon needs downloadURL to build a lineup.
        val pool = db.browse(contentType = "animation", limit = 240, full = true)
            .filter { it.downloadURL != null }
        val shelves = characterDefs.mapNotNull { (name, terms) ->
            val rows = pool.filter { item ->
                terms.any { item.title.lowercase().contains(it) }
            }.take(20)
            if (rows.size >= 4) name to rows else null
        }
        value = pool to shelves
    }

    val marathon = remember { FocusRequester() }
    val shelves = state?.second.orEmpty()
    val pool = state?.first.orEmpty()
    ClaimInitialFocus(marathon, key = pool.isEmpty())
    val railFocus = LocalTvRailFocus.current

    Column(Modifier.fillMaxSize()) {
        TvPageHeader(
            eyebrow = "CARTOONS",
            title = "Cartoon Mode",
            compact = true,   // a shelf page: the shelves must start high
            meta = when {
                state == null -> "Rounding up the cartoons…"
                shelves.isEmpty() -> "No cartoon shelves are available right now."
                else -> "${shelves.size} characters · ${pool.size} cartoons"
            },
        ) {
            // Drawn even while the pool is empty so the page always has
            // something focusable (§3.1), and a no-op until there is a queue —
            // the alternative is a surface where the remote goes dead.
            TvActionPill(
                label = "Marathon",
                onClick = {
                    val queue = pool.shuffled().mapNotNull { item ->
                        item.downloadURL?.let {
                            QueueEntry(item.archiveID, item.title, "Cartoon Marathon", it)
                        }
                    }
                    if (queue.isNotEmpty()) {
                        nav.push(
                            Route.Player(
                                PlaySpec(
                                    id = queue.first().id,
                                    title = queue.first().title,
                                    subtitle = "Cartoon Marathon",
                                    url = queue.first().url,
                                    queue = queue,
                                    queueIndex = 0,
                                    // A marathon is an ephemeral lineup, like a
                                    // channel — it must never write resume
                                    // progress into somebody's library.
                                    persistProgress = false,
                                ),
                            ),
                        )
                    }
                },
                focusRequester = marathon,
                primary = true,
                exitLeftTo = railFocus,
            )
        }

        LazyColumn(Modifier.fillMaxSize()) {
            items(shelves.size) { index ->
                val (name, rows) = shelves[index]
                TvShelfRow(
                    title = name,
                    items = rows,
                    onItem = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
                )
            }
        }
    }
}
