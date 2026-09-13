package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CollectionMeta
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.theme.colorFromHex

private const val COLLECTION_COLUMNS = 3

/**
 * Collections, on a television.
 *
 * The phone screen is a LazyColumn of full-width Cards, and it was MEASURED
 * wrong here rather than merely judged: a uiautomator dump on a Google TV put
 * the "Collections" title at y=36 (above the 54 safe top), every count badge
 * at x=1814..1860 (past the 1824 safe right edge, so "240" is clipped on a
 * panel that overscans) and a blurb at y=1048 — 8 of 19 text nodes outside the
 * band. It was reachable, because the Card already takes tvFocusable under
 * LocalIsTelevision; being reachable is not the same as being readable.
 *
 * A GRID rather than a list, which is the shape the Roku channel settled on
 * for the same surface: full-width rows waste a 16:9 panel and force the count
 * out to the far edge, where overscan eats it.
 */
@Composable
fun TvCollectionsScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val collections by produceState<List<Pair<CollectionMeta, Int>>?>(null, dbVersion) {
        val db = container.catalog.awaitDb()
        value = container.editorial.collections().mapNotNull { meta ->
            val n = db.byCollection(meta.id, limit = 240).size
            if (n >= 6) meta to n else null
        }
    }

    val firstCard = remember { FocusRequester() }
    val rows = collections.orEmpty()
    ClaimInitialFocus(firstCard, key = rows.isEmpty())
    val railFocus = LocalTvRailFocus.current

    Column(Modifier.fillMaxSize()) {
        TvPageHeader(
            eyebrow = "BROWSE",
            title = "Collections",
            meta = when {
                collections == null -> "Reading the shelves…"
                rows.isEmpty() -> "No collections are available right now."
                else -> "${rows.size} curated collections"
            },
        )

        LazyVerticalGrid(
            columns = GridCells.Fixed(COLLECTION_COLUMNS),
            contentPadding = PaddingValues(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH,
                bottom = TvDims.OverscanV,
            ),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            itemsIndexed(rows, key = { _, it -> it.first.id }) { index, (meta, count) ->
                Box(
                    Modifier
                        .fillMaxWidth()
                        .tvFocusable(
                            onClick = { nav.push(Route.Collection(meta.id, meta.title, meta.blurb)) },
                            focusRequester = if (index == 0) firstCard else null,
                            shape = RoundedCornerShape(14.dp),
                            exitLeftTo = if (index % COLLECTION_COLUMNS == 0) railFocus else null,
                        )
                        .background(Color(0xFF161616), RoundedCornerShape(14.dp)),
                ) {
                    Column(Modifier.padding(20.dp)) {
                        // The accent is the collection's own colour (Decision
                        // 013 — content meaning, never chrome), drawn as a bar
                        // rather than a 16dp dot: at ten feet a dot is noise.
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .background(
                                    colorFromHex(meta.accent) ?: TvAccent,
                                    RoundedCornerShape(3.dp),
                                ),
                        )
                        Text(
                            meta.title,
                            fontSize = 26.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 14.dp),
                        )
                        Text(
                            "$count films",
                            fontSize = 19.sp,
                            color = TvAccent,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                        meta.blurb?.let {
                            Text(
                                it,
                                fontSize = 19.sp,
                                color = Color(0xFFB9B9B9),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(top = 8.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}
