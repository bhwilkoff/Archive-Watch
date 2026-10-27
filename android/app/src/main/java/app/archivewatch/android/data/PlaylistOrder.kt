package app.archivewatch.android.data

import android.content.Context
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

/** How a playlist's films, or the list of playlists, is shown. "My Order" is
 *  the viewer's own arrangement (a viewer, 2026-10-25: "Popular sorting by us
 *  users is our own rearrangement of the items being respected"). [key] is
 *  the persisted choice and the Apple `PlaylistSort` raw value. */
enum class PlaylistSort(val label: String, val key: String) {
    MY_ORDER("My Order", "myOrder"),
    ALPHABETICAL("A–Z", "alphabetical"),
    REVERSE_ALPHABETICAL("Z–A", "reverseAlphabetical"),
    NEWEST("Newest", "newest"),
    OLDEST("Oldest", "oldest");

    companion object {
        fun fromKey(key: String?): PlaylistSort? = entries.firstOrNull { it.key == key }
    }
}

object PlaylistOrder {
    const val LIST_KEY = "playlistSort.lists"
    fun contentsKey(playlistID: String) = "playlistSort.$playlistID"

    fun remembered(context: Context, key: String): PlaylistSort =
        PlaylistSort.fromKey(SortMemory.prefs(context).getString(key, null)) ?: PlaylistSort.MY_ORDER

    fun remember(context: Context, sort: PlaylistSort, key: String) {
        SortMemory.prefs(context).edit { putString(key, sort.key) }
    }

    /** The viewer's arrangement (Apple `Playlist.inMyOrder`): a list never
     *  placed — new here, or from a device that has not arranged — comes
     *  first, newest first; then the arranged ones by their place. */
    fun inMyOrder(lists: List<UserPlaylist>): List<UserPlaylist> =
        lists.sortedWith { a, b ->
            val x = a.sortIndex
            val y = b.sortIndex
            when {
                x == null && y == null -> b.createdAt.compareTo(a.createdAt)
                x == null -> -1
                y == null -> 1
                x != y -> x.compareTo(y)
                else -> b.createdAt.compareTo(a.createdAt)
            }
        }

    /** Places for `ordered`, already in the order the viewer arranged. Only a
     *  list whose place changed is returned (and stamped), so sync carries the
     *  move without rewriting every list. */
    fun arrange(ordered: List<UserPlaylist>, now: Long): List<UserPlaylist> =
        ordered.mapIndexedNotNull { i, p ->
            if (p.sortIndex == i) null else p.copy(sortIndex = i, modifiedAt = now)
        }

    /** `list` with the entry at `from` moved to `to`. */
    fun <T> moved(list: List<T>, from: Int, to: Int): List<T> {
        if (from !in list.indices || to !in list.indices || from == to) return list
        val out = list.toMutableList()
        out.add(to, out.removeAt(from))
        return out
    }

    fun sortedLists(lists: List<UserPlaylist>, sort: PlaylistSort): List<UserPlaylist> = when (sort) {
        PlaylistSort.MY_ORDER -> inMyOrder(lists)
        PlaylistSort.ALPHABETICAL -> lists.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
        PlaylistSort.REVERSE_ALPHABETICAL ->
            lists.sortedWith(compareByDescending(String.CASE_INSENSITIVE_ORDER) { it.name })
        PlaylistSort.NEWEST -> lists.sortedByDescending { it.createdAt }
        PlaylistSort.OLDEST -> lists.sortedBy { it.createdAt }
    }

    /** A playlist's films in `sort`; Newest/Oldest are the FILM's year, and a
     *  film with no year goes last either way. */
    fun <T> sortedFilms(films: List<T>, sort: PlaylistSort, item: (T) -> CatalogItem): List<T> = when (sort) {
        PlaylistSort.MY_ORDER -> films
        PlaylistSort.ALPHABETICAL -> films.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { item(it).title })
        PlaylistSort.REVERSE_ALPHABETICAL ->
            films.sortedWith(compareByDescending(String.CASE_INSENSITIVE_ORDER) { item(it).title })
        PlaylistSort.NEWEST -> films.sortedByDescending { item(it).year ?: Int.MIN_VALUE }
        PlaylistSort.OLDEST -> films.sortedBy { item(it).year ?: Int.MAX_VALUE }
    }

    // --- the Drive blob's playlist entry (shared with the web) ---

    /** Always writes `sortIndex`: a writer that drops it erases the viewer's
     *  order on every other device. */
    fun toJson(p: UserPlaylist): JSONObject = JSONObject()
        .put("id", p.id).put("name", p.name)
        .put("archiveIDs", JSONArray(p.archiveIDs))
        .put("createdAt", p.createdAt).put("modifiedAt", p.modifiedAt)
        .put("sortIndex", p.sortIndex ?: JSONObject.NULL)

    /** An entry from the cloud. Its own `createdAt` is kept; a missing
     *  `sortIndex` (a writer that does not know the field, such as the web
     *  today) keeps the place this device already has rather than erasing it. */
    fun fromJson(o: JSONObject, mine: UserPlaylist?): UserPlaylist? {
        val id = o.optString("id")
        if (id.isEmpty()) return null
        val mod = o.optLong("modifiedAt")
        val ids = o.optJSONArray("archiveIDs")?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?: emptyList()
        val sortIndex = when {
            !o.has("sortIndex") -> mine?.sortIndex
            o.isNull("sortIndex") -> null
            else -> o.optInt("sortIndex")
        }
        return UserPlaylist(
            id, o.optString("name"), ids.filter { it.isNotEmpty() },
            o.optLong("createdAt").takeIf { it > 0 } ?: mod, mod, sortIndex,
        )
    }
}
