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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.data.CatalogItem
import app.archivewatch.android.data.UserPlaylist
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route

private const val TV_GRID_COLUMNS = 6

/**
 * TV Library.
 *
 * The phone screen falls through readably but fails three TV rules, which is
 * why this exists rather than reusing it:
 *  - its Material3 tab row is phone-sized and not a reliable D-pad target
 *  - when a section is empty NOTHING is focusable, so the remote goes dead
 *    inside the surface (§3.1)
 *  - it offers a **Clips** tab, and Clip Studio is explicitly never on TV
 *    (docs/TV-DESIGN.md §2 — a remote has no text entry or direct
 *    manipulation), so on a TV that tab can only ever be empty
 *
 * Data comes from the same `userState` / `CatalogDB` calls the phone uses.
 */
private enum class LibSection(val label: String) {
    Favorites("Favorites"),
    Continue("Continue Watching"),
    Playlists("Playlists"),
}

@Composable
fun TvLibraryScreen(container: AppContainer, nav: Nav) {
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.userState.changes.collectAsState()
    var section by remember { mutableStateOf(LibSection.Favorites) }

    val favorites by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        value = db.itemsByIDs(container.userState.favoriteIDs())
    }
    val continueWatching by produceState<List<CatalogItem>>(emptyList(), dbVersion, userChanges) {
        val db = container.catalog.awaitDb()
        value = db.itemsByIDs(container.userState.continueWatching().map { it.archiveID })
    }
    val playlists by produceState<List<UserPlaylist>>(emptyList(), userChanges) {
        value = container.userState.playlists()
    }

    val firstTab = remember { FocusRequester() }
    ClaimInitialFocus(firstTab)

    val items = when (section) {
        LibSection.Favorites -> favorites
        LibSection.Continue -> continueWatching
        LibSection.Playlists -> emptyList()
    }

    Column(Modifier.fillMaxSize()) {
        Text(
            "Library",
            fontSize = 32.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            modifier = Modifier.padding(
                start = TvDims.OverscanH,
                top = TvDims.OverscanV,
                bottom = 14.dp,
            ),
        )

        Row(
            Modifier.padding(start = TvDims.OverscanH, bottom = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val railFocus = LocalTvRailFocus.current
            LibSection.entries.forEachIndexed { index, s ->
                val selected = s == section
                Box(
                    Modifier
                        .tvFocusable(
                            onClick = { section = s },
                            focusRequester = if (index == 0) firstTab else null,
                            shape = RoundedCornerShape(24.dp),
                            scaleWhenFocused = 1.04f,
                            exitLeftTo = if (index == 0) railFocus else null,
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

        if (section == LibSection.Playlists) {
            if (playlists.isEmpty()) {
                TvEmpty("No playlists yet — add titles from any film's page on your phone or the web.")
            } else {
                Column(
                    Modifier.padding(horizontal = TvDims.OverscanH),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    playlists.forEach { pl ->
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .tvFocusable(
                                    onClick = { nav.push(Route.Playlist(pl.id)) },
                                    shape = RoundedCornerShape(12.dp),
                                    scaleWhenFocused = 1.01f,
                                )
                                .background(Color(0xFF141414), RoundedCornerShape(12.dp))
                                .padding(horizontal = 26.dp, vertical = 20.dp),
                        ) {
                            Text(pl.name, fontSize = 26.sp, color = Color.White)
                        }
                    }
                }
            }
            return@Column
        }

        if (items.isEmpty()) {
            TvEmpty(
                when (section) {
                    LibSection.Favorites -> "No favorites yet — press Favorite on any title."
                    else -> "Nothing in progress — playback picks up where you left off."
                },
            )
            return@Column
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(TV_GRID_COLUMNS),
            contentPadding = PaddingValues(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH,
                bottom = TvDims.OverscanV * 2,
            ),
            horizontalArrangement = Arrangement.spacedBy(TvDims.PosterSpacing),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            itemsIndexed(items, key = { _, it -> it.archiveID }) { _, item ->
                TvPosterTile(
                    item = item,
                    onClick = { nav.openItem(item.archiveID, item.seriesID, item.contentType) },
                )
            }
        }
    }
}

/**
 * An empty section's message. Deliberately NOT a focus anchor.
 *
 * §3.1 says something must always be focused — but the section chips above are
 * already focusable, so an anchor here does not satisfy the rule, it BREAKS it:
 * it silently stole focus from the chips, leaving the selected chip un-ringed
 * and sending the next Right/Select out to the nav rail. Verified on the
 * emulator. A focus anchor is only correct when a surface has NO other
 * focusable content (a loading screen); it must never compete with real
 * controls.
 */
@Composable
private fun TvEmpty(message: String) {
    TvMessage(message)
}
