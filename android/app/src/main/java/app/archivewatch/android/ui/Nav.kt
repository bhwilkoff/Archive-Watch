package app.archivewatch.android.ui

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.archivewatch.android.data.PlaySpec
import kotlinx.coroutines.flow.MutableStateFlow

/** Top-level content tabs (Settings rides the Home top bar gear). */
enum class Tab(val label: String) {
    Home("Home"), Browse("Browse"), Channels("Channels"), Search("Search"), Library("Library")
}

/** Every pushable destination — plain state-based navigation for v1. */
sealed interface Route {
    data class Detail(val archiveID: String) : Route
    data class Series(val slug: String) : Route
    data class Player(val spec: PlaySpec) : Route
    data class Filtered(val title: String, val contentType: String? = null,
                        val decade: Int? = null) : Route
    data class Playlist(val playlistID: String) : Route
    data object Surprise : Route
    data object Settings : Route
}

/** Selected tab + one shared back stack; BackHandler pops. */
class Nav {
    var tab by mutableStateOf(Tab.Home)
    val stack = mutableStateListOf<Route>()

    fun push(route: Route) {
        stack.add(route)
    }

    fun pop() {
        stack.removeLastOrNull()
    }

    fun openItem(archiveID: String, seriesID: String? = null, contentType: String? = null) {
        if (contentType == "tv-series") push(Route.Series(seriesID ?: archiveID))
        else push(Route.Detail(archiveID))
    }
}

/** archivewatch://item/{id} hand-off from MainActivity to AppRoot. */
object DeepLinks {
    val pendingItem = MutableStateFlow<String?>(null)
}
