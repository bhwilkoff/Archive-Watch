package app.archivewatch.android.ui

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.listSaver
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
                        val decade: Int? = null, val year: Int? = null,
                        // Public Domain Day explorer (iOS parity): year CHIPS
                        // for recent PD-entry years ride the filtered grid.
                        val pdExplorer: Boolean = false) : Route
    data class Playlist(val playlistID: String) : Route
    data class Collection(val id: String, val title: String, val blurb: String? = null) : Route
    data class Person(val name: String, val tmdbPersonID: Int? = null) : Route
    data class ClipStudio(val archiveID: String) : Route
    data object Collections : Route
    data object Cartoon : Route
    data object Party : Route
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

    companion object {
        // Survive process death: persist the tab + the pushable stack (a low-memory
        // kill otherwise dumps the user back to Home). The Player route is NOT
        // restored — reviving a mid-playback session is worse than landing on the
        // title. A control char is the field separator (titles never contain it).
        private const val SEP = "\u0001"

        val Saver = listSaver<Nav, String>(
            save = { nav ->
                buildList {
                    add("tab$SEP${nav.tab.name}")
                    nav.stack.forEach { encode(it)?.let(::add) }
                }
            },
            restore = { entries ->
                Nav().apply {
                    entries.forEach { entry ->
                        val p = entry.split(SEP)
                        if (p[0] == "tab") runCatching { tab = Tab.valueOf(p[1]) }
                        else decode(p)?.let { stack.add(it) }
                    }
                }
            },
        )

        private fun encode(r: Route): String? = when (r) {
            is Route.Detail -> "detail$SEP${r.archiveID}"
            is Route.Series -> "series$SEP${r.slug}"
            is Route.Filtered -> "filtered$SEP${r.title}$SEP${r.contentType ?: ""}$SEP${r.decade ?: ""}$SEP${r.year ?: ""}$SEP${if (r.pdExplorer) "1" else ""}"
            is Route.Playlist -> "playlist$SEP${r.playlistID}"
            is Route.Collection -> "collection$SEP${r.id}$SEP${r.title}$SEP${r.blurb ?: ""}"
            is Route.Person -> "person$SEP${r.name}$SEP${r.tmdbPersonID ?: ""}"
            is Route.ClipStudio -> "clip$SEP${r.archiveID}"
            Route.Collections -> "collections"
            Route.Cartoon -> "cartoon"
            Route.Party -> "party"
            Route.Surprise -> "surprise"
            Route.Settings -> "settings"
            is Route.Player -> null
        }

        private fun decode(p: List<String>): Route? = when (p[0]) {
            "detail" -> Route.Detail(p[1])
            "series" -> Route.Series(p[1])
            "filtered" -> Route.Filtered(p[1], p[2].ifEmpty { null }, p[3].toIntOrNull(),
                p.getOrNull(4)?.toIntOrNull(), p.getOrNull(5) == "1")
            "playlist" -> Route.Playlist(p[1])
            "collection" -> Route.Collection(p[1], p[2], p[3].ifEmpty { null })
            "person" -> Route.Person(p[1], p.getOrNull(2)?.toIntOrNull())
            "clip" -> Route.ClipStudio(p[1])
            "collections" -> Route.Collections
            "cartoon" -> Route.Cartoon
            "party" -> Route.Party
            "surprise" -> Route.Surprise
            "settings" -> Route.Settings
            else -> null
        }
    }
}

/** archivewatch://item/{id} (+ /surprise, /channels) hand-off from
    MainActivity to AppRoot. */
object DeepLinks {
    val pendingItem = MutableStateFlow<String?>(null)
    val pendingAction = MutableStateFlow<String?>(null)   // "surprise" | "channels"
    /** Verification hook only (`--es aw_start_tab <name>`); never set in normal use. */
    val pendingTab = MutableStateFlow<String?>(null)
    /** Verification hook only (`--es aw_start_route <name>`); never set in normal use. */
    val pendingRoute = MutableStateFlow<String?>(null)
}

/** The player publishes here so MainActivity can auto-enter Picture-in-Picture when the user
    leaves the app mid-playback, sized to the real video aspect. */
object PlaybackPresence {
    val active = MutableStateFlow(false)
    /** True while the Activity is in Picture-in-Picture. The player hides its
     *  chrome (title overlay + transport controller) in that window: a PiP
     *  tile is ~150dp wide, and chrome drawn over it covered the film. */
    val inPip = MutableStateFlow(false)
    @Volatile var aspectWidth = 16
    @Volatile var aspectHeight = 9
}
