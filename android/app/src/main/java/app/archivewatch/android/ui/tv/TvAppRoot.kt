package app.archivewatch.android.ui.tv

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.ui.DeepLinks
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import app.archivewatch.android.ui.Tab
import app.archivewatch.android.ui.screens.CartoonScreen
import app.archivewatch.android.ui.screens.ChannelsScreen
import app.archivewatch.android.ui.screens.CollectionGridScreen
import app.archivewatch.android.ui.screens.CollectionsScreen
import app.archivewatch.android.ui.screens.DetailScreen
import app.archivewatch.android.ui.screens.FilteredGridScreen
import app.archivewatch.android.ui.screens.PersonScreen
import app.archivewatch.android.ui.screens.PlayerScreen
import app.archivewatch.android.ui.screens.PlaylistScreen
import app.archivewatch.android.ui.screens.SearchScreen
import app.archivewatch.android.ui.screens.SeriesDetailScreen
import app.archivewatch.android.ui.screens.SettingsScreen
import app.archivewatch.android.ui.screens.SurpriseScreen
import app.archivewatch.android.ui.screens.LibraryScreen
import app.archivewatch.android.ui.screens.BrowseScreen

/**
 * The TV root shell (docs/TV-DESIGN.md §2 — the IA is inherited from
 * tvOS-DESIGN §2 and is NOT re-derived here).
 *
 * Reuses [Nav], [Route] and every screen-level data path from the phone build
 * verbatim; only the shell and the tab surfaces are TV-native. Routes not yet
 * given a TV treatment fall through to the shared screen — which is honest:
 * they are reachable and functional, and PARITY.md records which still need
 * the ten-foot pass.
 */
@Composable
fun TvAppRoot(container: AppContainer) {
    val nav = rememberSaveable(saver = Nav.Saver) { Nav() }

    LaunchedEffect(Unit) {
        DeepLinks.pendingItem.collect { id ->
            if (id != null) {
                DeepLinks.pendingItem.value = null
                if (id.startsWith("series:")) nav.push(Route.Series(id.removePrefix("series:")))
                else nav.push(Route.Detail(id))
            }
        }
    }
    LaunchedEffect(Unit) {
        DeepLinks.pendingAction.collect { action ->
            if (action != null) {
                DeepLinks.pendingAction.value = null
                when (action) {
                    "surprise" -> nav.push(Route.Surprise)
                    "channels" -> { nav.stack.clear(); nav.tab = Tab.Channels }
                }
            }
        }
    }

    // §1.7 — Back is sacred. It pops the stack; from the root it is NOT
    // consumed, so the system returns to the launcher home (TV-DB).
    BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }

    // §3.4 — Left from the leftmost content must reach the rail, or the tabs are
    // unreachable by remote and TV-DP fails. Compose's 2D focus search does NOT
    // cross from a LazyRow's first item into a sibling container on its own —
    // verified on the emulator, where Left simply stopped at the first tile.
    // `exit` fires only when focus actually LEAVES the content container, so
    // Left-within-a-row keeps working normally.
    val railFocus = remember { FocusRequester() }

    CompositionLocalProvider(LocalTvRailFocus provides railFocus) {
    Surface(color = MaterialTheme.colorScheme.background) {
        Row(Modifier.fillMaxSize()) {
            // The rail is hidden while a route is pushed: a full-screen detail
            // or player must not leave a competing focus target on screen.
            if (nav.stack.isEmpty()) {
                TvNavRail(nav, railFocus)
            }
            Box(Modifier.fillMaxSize()) {
                if (nav.stack.isEmpty()) {
                    when (nav.tab) {
                        Tab.Home -> TvHomeScreen(container, nav)
                        Tab.Browse -> BrowseScreen(container, nav)
                        Tab.Channels -> ChannelsScreen(container, nav)
                        Tab.Search -> SearchScreen(container, nav)
                        Tab.Library -> LibraryScreen(container, nav)
                    }
                }
                nav.stack.lastOrNull()?.let { route ->
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        when (route) {
                            is Route.Detail -> DetailScreen(container, nav, route.archiveID)
                            is Route.Series -> SeriesDetailScreen(container, nav, route.slug)
                            is Route.Player -> PlayerScreen(container, nav, route.spec)
                            is Route.Filtered -> FilteredGridScreen(container, nav, route)
                            is Route.Playlist -> PlaylistScreen(container, nav, route.playlistID)
                            is Route.Collection -> CollectionGridScreen(container, nav, route)
                            is Route.Person -> PersonScreen(container, nav, route.name, route.tmdbPersonID)
                            // §2 — creation is never offered on a TV build: a
                            // remote has no text entry or direct manipulation.
                            is Route.ClipStudio -> TvMessage(
                                "Clip Studio is available on iPhone, iPad and Mac."
                            )
                            Route.Collections -> CollectionsScreen(container, nav)
                            Route.Cartoon -> CartoonScreen(container, nav)
                            Route.Surprise -> SurpriseScreen(container, nav)
                            Route.Settings -> SettingsScreen(container, nav)
                        }
                    }
                }
            }
        }
    }
}

}

private data class RailItem(
    val label: String,
    val icon: ImageVector,
    val onSelect: () -> Unit,
    val selected: Boolean,
)

/**
 * Left navigation rail — the 10-foot idiom for top-level nav (a bottom tab bar
 * is a touch affordance and reads as an error on TV).
 *
 * Expands on focus so the labels are readable at ten feet without permanently
 * spending 220dp of a 1920px canvas.
 */
@Composable
private fun TvNavRail(nav: Nav, railFocus: FocusRequester) {
    var expanded by remember { mutableStateOf(false) }
    val width by animateDpAsState(
        if (expanded) TvDims.NavRailWidth else TvDims.NavRailCollapsed,
        label = "railWidth",
    )

    val items = listOf(
        RailItem("Home", Icons.Default.Home, { nav.stack.clear(); nav.tab = Tab.Home }, nav.tab == Tab.Home),
        RailItem("Browse", Icons.Outlined.GridView, { nav.stack.clear(); nav.tab = Tab.Browse }, nav.tab == Tab.Browse),
        RailItem("Channels", Icons.Default.LiveTv, { nav.stack.clear(); nav.tab = Tab.Channels }, nav.tab == Tab.Channels),
        RailItem("Search", Icons.Default.Search, { nav.stack.clear(); nav.tab = Tab.Search }, nav.tab == Tab.Search),
        RailItem("Library", Icons.Default.VideoLibrary, { nav.stack.clear(); nav.tab = Tab.Library }, nav.tab == Tab.Library),
        RailItem("Surprise", Icons.Default.Shuffle, { nav.push(Route.Surprise) }, false),
        RailItem("Settings", Icons.Default.Settings, { nav.push(Route.Settings) }, false),
    )

    Column(
        Modifier
            .width(width)
            .fillMaxHeight()
            .background(Color(0xFF0B0B0B))
            // §4.2 — the rail's controls must clear the overscan line too; 12dp
            // put the icons under the bezel on a real panel.
            .padding(vertical = TvDims.OverscanV, horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items.forEachIndexed { index, entry ->
            TvRailButton(
                item = entry,
                expanded = expanded,
                focusRequester = if (index == 0) railFocus else null,
                onFocused = { expanded = true },
            )
        }
        Spacer(Modifier.height(8.dp))
    }

    // NOTE: the rail deliberately does NOT claim initial focus.
    //
    // It used to, and that raced the content's own claim (§3.1): the shelf
    // claim scrolled the hero off-screen while the rail won the focus ring, so
    // first paint showed a headless hero. Initial focus belongs to the CONTENT
    // (the TV convention — Left from the content reaches the rail), and exactly
    // one surface may claim it. Verified on the Android TV emulator.
}

@Composable
private fun TvRailButton(
    item: RailItem,
    expanded: Boolean,
    focusRequester: FocusRequester?,
    onFocused: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .tvFocusable(
                onClick = item.onSelect,
                focusRequester = focusRequester,
                shape = RoundedCornerShape(8.dp),
                // The rail must not jump the layout when focused; the ring and
                // the tint carry the state instead of scale.
                scaleWhenFocused = 1f,
                onFocused = onFocused,
            )
            .background(
                if (item.selected) Color(0x22FF5C35) else Color.Transparent,
                RoundedCornerShape(8.dp),
            )
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            item.icon,
            contentDescription = item.label,
            tint = if (item.selected) Color(0xFFFF5C35) else Color.White,
            modifier = Modifier.size(28.dp),
        )
        if (expanded) {
            Text(
                item.label,
                fontSize = 22.sp,
                fontWeight = if (item.selected) FontWeight.SemiBold else FontWeight.Normal,
                color = if (item.selected) Color(0xFFFF5C35) else Color.White,
                modifier = Modifier.padding(start = 14.dp),
            )
        }
    }
}
