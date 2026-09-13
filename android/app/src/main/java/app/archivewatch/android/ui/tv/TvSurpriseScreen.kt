package app.archivewatch.android.ui.tv

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.uniqueBy

/**
 * Surprise, on a television.
 *
 * The phone screen fell through and was measurably wrong here: a uiautomator
 * dump on a Google TV put its film captions at x=32 and out to x=1888 against
 * an overscan-safe band of 96..1824, so BOTH edge columns were inside the 5%
 * a panel cuts — because `GridCells.Adaptive(110.dp)` packs phone-sized tiles
 * across 1920 and the Scaffold has no overscan inset. Its two actions were a
 * borderless TextButton and a Material Button in a TopAppBar, sized for a
 * thumb and sitting above the safe top edge.
 *
 * The PICK is unchanged — the same twelve doors, the same feature-film floor
 * for filler slots. Only the page around it is a television's.
 */
@Composable
fun TvSurpriseScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var roll by remember { mutableIntStateOf(0) }

    val items by produceState<List<CatalogItem>?>(null, dbVersion, roll) {
        val db = container.catalog.awaitDb()
        // Filler tiles are FEATURE FILMS (not random anything): the old `null`
        // fillers pulled shorts, cartoons and newsreels into what is meant to
        // be a shelf of films. Same list the phone uses.
        val types = listOf(
            "feature-film", "silent-film", "animation", "short-film", "newsreel", "ephemeral",
            "feature-film", "feature-film", "feature-film", "feature-film", "feature-film", "feature-film",
        )
        val picks = LinkedHashMap<String, CatalogItem>()
        for (t in types) {
            val pick = if (t == "feature-film") db.randomFeatureFilm()
                       else db.randomPlayable(contentType = t)
            pick?.let { picks.putIfAbsent(it.archiveID, it) }
        }
        value = picks.values.toList()
    }

    val rerollFocus = remember { FocusRequester() }
    val rows = items.orEmpty().uniqueBy { it.archiveID }
    // Claim once there is a page to claim onto. Keyed on emptiness because the
    // pills are drawn regardless, but a claim before first composition throws.
    ClaimInitialFocus(rerollFocus, key = rows.isEmpty())

    val railFocus = LocalTvRailFocus.current

    Column(Modifier.fillMaxSize()) {
        TvPageHeader(
            eyebrow = "SURPRISE",
            title = "Surprise Me",
            meta = when {
                items == null -> "Opening twelve doors…"
                rows.isEmpty() -> "Nothing to offer right now."
                else -> "${rows.size} doors — a different ${rows.size} every roll"
            },
        ) {
            TvActionPill(
                label = "Re-roll",
                onClick = { roll += 1 },
                focusRequester = rerollFocus,
                primary = true,
                exitLeftTo = railFocus,
            )
            TvActionPill(label = "Cartoons", onClick = { nav.push(Route.Cartoon) })
        }

        TvPosterGrid(
            rows = rows,
            onClick = { nav.openItem(it.archiveID, it.seriesID, it.contentType) },
            railFocus = railFocus,
        )
    }
}
