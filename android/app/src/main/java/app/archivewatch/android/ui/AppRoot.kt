package app.archivewatch.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.ui.screens.BrowseScreen
import app.archivewatch.android.ui.screens.ChannelsScreen
import app.archivewatch.android.ui.screens.CartoonScreen
import app.archivewatch.android.ui.screens.CollectionGridScreen
import app.archivewatch.android.ui.screens.CollectionsScreen
import app.archivewatch.android.ui.screens.PersonScreen
import app.archivewatch.android.ui.screens.DetailScreen
import app.archivewatch.android.ui.screens.HomeScreen
import app.archivewatch.android.ui.screens.LibraryScreen
import app.archivewatch.android.ui.screens.PlayerScreen
import app.archivewatch.android.ui.screens.SearchScreen
import app.archivewatch.android.ui.screens.SeriesDetailScreen
import app.archivewatch.android.ui.screens.SettingsScreen
import app.archivewatch.android.ui.screens.FilteredGridScreen
import app.archivewatch.android.ui.screens.PlaylistScreen
import app.archivewatch.android.ui.screens.SurpriseScreen

/**
 * Root scaffold: NavigationSuiteScaffold (bottom bar → rail → drawer by
 * window size) over four content tabs, with a plain state-based back
 * stack rendered above the tab content. Settings is NOT a tab — it rides
 * the Home top-bar gear (same verb placement as iOS).
 */
@Composable
fun AppRoot(container: AppContainer) {
    val nav = remember { Nav() }

    // archivewatch://item/{id} deep link → Detail.
    LaunchedEffect(Unit) {
        DeepLinks.pendingItem.collect { id ->
            if (id != null) {
                DeepLinks.pendingItem.value = null
                nav.push(Route.Detail(id))
            }
        }
    }
    // App Shortcut actions (archivewatch://surprise | /channels).
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

    BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }

    Surface(color = MaterialTheme.colorScheme.background) {
        NavigationSuiteScaffold(
            navigationSuiteItems = {
                item(
                    selected = nav.tab == Tab.Home && nav.stack.isEmpty(),
                    onClick = { nav.stack.clear(); nav.tab = Tab.Home },
                    icon = { Icon(Icons.Default.Home, contentDescription = null) },
                    label = { Text(Tab.Home.label) },
                )
                item(
                    selected = nav.tab == Tab.Browse && nav.stack.isEmpty(),
                    onClick = { nav.stack.clear(); nav.tab = Tab.Browse },
                    icon = { Icon(Icons.Outlined.GridView, contentDescription = null) },
                    label = { Text(Tab.Browse.label) },
                )
                item(
                    selected = nav.tab == Tab.Channels && nav.stack.isEmpty(),
                    onClick = { nav.stack.clear(); nav.tab = Tab.Channels },
                    icon = { Icon(Icons.Default.LiveTv, contentDescription = null) },
                    label = { Text(Tab.Channels.label) },
                )
                item(
                    selected = nav.tab == Tab.Search && nav.stack.isEmpty(),
                    onClick = { nav.stack.clear(); nav.tab = Tab.Search },
                    icon = { Icon(Icons.Default.Search, contentDescription = null) },
                    label = { Text(Tab.Search.label) },
                )
                item(
                    selected = nav.tab == Tab.Library && nav.stack.isEmpty(),
                    onClick = { nav.stack.clear(); nav.tab = Tab.Library },
                    icon = { Icon(Icons.Default.VideoLibrary, contentDescription = null) },
                    label = { Text(Tab.Library.label) },
                )
            },
        ) {
            Box(Modifier.fillMaxSize()) {
                when (nav.tab) {
                    Tab.Home -> HomeScreen(container, nav)
                    Tab.Browse -> BrowseScreen(container, nav)
                    Tab.Channels -> ChannelsScreen(container, nav)
                    Tab.Search -> SearchScreen(container, nav)
                    Tab.Library -> LibraryScreen(container, nav)
                }
                // The pushed stack renders above the tab content; only the
                // top route is composed.
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
                            is Route.Person -> PersonScreen(container, nav, route.name)
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
