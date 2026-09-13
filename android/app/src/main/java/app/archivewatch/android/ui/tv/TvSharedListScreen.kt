package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
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
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.PlaySpec
import app.archivewatch.android.data.QueueEntry
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import kotlinx.coroutines.launch

private const val TV_GRID_COLUMNS = 6
private val SharedAccent = Color(0xFFFF5C35)

/**
 * A playlist somebody else made, opened from a link — on a television.
 *
 * This exists for the same reason TvSeriesScreen does. `TvAppRoot` rendered
 * the PHONE `SharedListScreen`, and that was verified on the owner's Google TV
 * on 2026-09-13: it works, and it is a phone. A Material3 `TopAppBar` puts the
 * only two actions behind a 24dp back arrow and a 24dp "+" — icon buttons with
 * no label, sized for a thumb, at the very top of a 65-inch panel — and the
 * grid is `GridCells.Adaptive(110.dp)`, which at TV width draws a dozen tiny
 * columns. Every rule in docs/TV-DESIGN.md about target size and legibility is
 * broken by reusing it, and the owner's standing instruction is that nothing
 * on a TV should be optimised for another form factor.
 *
 * So: the overscan-inset page the other TV screens use, an eyebrow that says
 * what this IS (a stranger arrives here from a link with no other context), the
 * name at TV size, the honest count line, and ONE real focusable button.
 *
 * The rules the other platforms keep are kept here unchanged:
 *
 * BROWSE AND PLAY FIRST — the films are here and they open, signed in or not.
 *
 * ADDING IS A CHOICE — never a side effect of opening a link, or a link tapped
 * out of curiosity would have edited somebody's library.
 *
 * ALREADY-HAVE IS MATCHED ON CONTENTS, not on the name, so the same collection
 * sent under two names does not become two copies.
 *
 * PLAY ALL leads, because on a television the thing a viewer wants from
 * somebody else's playlist is to watch it, not to file it. It builds a real
 * QUEUE (the shape TvPartyScreen uses) rather than opening the first film, so
 * the list plays through. Unlike a party lineup it PERSISTS progress and is
 * not muted: this is a playlist somebody chose to send, not an ephemeral
 * channel, so leaving it half-watched has to mean something.
 *
 * A film with no downloadURL is skipped from the queue rather than stalling
 * it, and if none of them can play the button is not drawn at all — a control
 * that cannot do its job must not be on screen for a remote to land on.
 */
@Composable
fun TvSharedListScreen(
    container: AppContainer,
    nav: Nav,
    name: String,
    archiveIDs: List<String>,
) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    val scope = rememberCoroutineScope()

    val items by produceState<List<CatalogItem>?>(null, dbVersion) {
        value = container.catalog.awaitDb().itemsByIDs(archiveIDs)
    }
    val alreadyHave by produceState(false, userChanges) {
        value = container.userState.playlists().any { it.archiveIDs == archiveIDs }
    }
    var added by remember { mutableStateOf(false) }

    val playButton = remember { FocusRequester() }
    val addButton = remember { FocusRequester() }

    val rows = items.orEmpty()
    // Claim onto the PRIMARY action once the rows are in. Keyed on the row
    // count because the button does not exist until there is something to
    // play — claiming focus on a FocusRequester that is not attached throws.
    val canPlay = rows.any { it.downloadURL != null }
    ClaimInitialFocus(if (canPlay) playButton else addButton, key = canPlay)
    val missing = archiveIDs.size - rows.size

    Column(Modifier.fillMaxSize()) {
        Text(
            "SHARED PLAYLIST",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = SharedAccent,
            modifier = Modifier.padding(start = TvDims.OverscanH, top = TvDims.OverscanV),
        )
        Text(
            name,
            fontSize = 44.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            modifier = Modifier.padding(start = TvDims.OverscanH, top = 4.dp),
        )
        // A title the link names that this catalogue no longer serves is STATED,
        // never silently dropped — otherwise the sharer and the viewer are
        // looking at different collections and neither can tell.
        Text(
            when {
                items == null -> "Loading…"
                rows.isEmpty() -> "None of these titles are in the catalogue any more."
                missing > 0 ->
                    "${rows.size} of ${archiveIDs.size} titles — $missing " +
                        "${if (missing == 1) "is" else "are"} no longer in the catalogue."
                else -> "${rows.size} ${if (rows.size == 1) "title" else "titles"}"
            },
            fontSize = 22.sp,
            color = Color(0xFFB9B9B9),
            modifier = Modifier.padding(start = TvDims.OverscanH, top = 8.dp, bottom = 18.dp),
        )

        val railFocus = LocalTvRailFocus.current
        val playable = rows.filter { it.downloadURL != null }
        Row(
            Modifier.padding(start = TvDims.OverscanH, bottom = 22.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (playable.isNotEmpty()) {
                Box(
                    Modifier
                        .tvFocusable(
                            onClick = {
                                val first = playable.first()
                                nav.push(
                                    Route.Player(
                                        PlaySpec(
                                            id = first.archiveID,
                                            title = first.title,
                                            url = first.downloadURL!!,
                                            queue = playable.map {
                                                QueueEntry(
                                                    id = it.archiveID,
                                                    title = it.title,
                                                    url = it.downloadURL!!,
                                                )
                                            },
                                        ),
                                    ),
                                )
                            },
                            focusRequester = playButton,
                            shape = RoundedCornerShape(28.dp),
                            exitLeftTo = railFocus,
                        )
                        .background(SharedAccent, RoundedCornerShape(28.dp)),
                ) {
                    Text(
                        "Play all",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.Black,
                        modifier = Modifier.padding(horizontal = 32.dp, vertical = 14.dp),
                    )
                }
            }
            Box(
                Modifier.tvFocusable(
                    onClick = {
                        if (!added && !alreadyHave) {
                            scope.launch {
                                container.userState.createPlaylist(name, archiveIDs)
                                added = true
                            }
                        }
                    },
                    focusRequester = addButton,
                    shape = RoundedCornerShape(28.dp),
                    exitLeftTo = if (playable.isEmpty()) railFocus else null,
                ),
            ) {
                Text(
                    if (added || alreadyHave) "In your library" else "Add to my library",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 14.dp),
                )
            }
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(TV_GRID_COLUMNS),
            contentPadding = PaddingValues(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH,
                bottom = TvDims.OverscanV,
            ),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalArrangement = Arrangement.spacedBy(26.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            itemsIndexed(rows, key = { _, it -> it.archiveID }) { index, item ->
                TvPosterTile(
                    item = item,
                    onClick = { nav.push(Route.Detail(item.archiveID)) },
                    exitLeftTo = if (index % TV_GRID_COLUMNS == 0) railFocus else null,
                )
            }
        }
    }
}
