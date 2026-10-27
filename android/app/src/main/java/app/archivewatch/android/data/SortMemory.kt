package app.archivewatch.android.data

import android.content.Context
import androidx.core.content.edit

/**
 * The sort a viewer chose for a grid, remembered per KIND of grid (Apple
 * `SortMemory`, the same keys: `browseSort.<surface>`). A viewer, 2026-10-25:
 * "Sorting Menu resets to first menu item, not keeping what we previously
 * chose." The owner, 2026-10-27: A–Z by default for television, "with the
 * ability to change and have it remember."
 *
 * SharedPreferences rather than the DataStore settings: a grid reads its sort
 * while composing, and an asynchronous read would run the first query in the
 * wrong order and then run it again.
 */
object SortMemory {
    /** Television grids: series cards and TV Specials. */
    const val TV = "tv"
    /** Browse's own grid (the scope chips). */
    const val BROWSE = "browse"
    /** A category, genre, decade or facet grid of films. */
    const val CATEGORY = "category"
    /** A collection's own grid. */
    const val COLLECTION = "collection"

    private const val PREFS = "aw_sort"

    fun defaultSort(surface: String): BrowseSort =
        if (surface == TV) BrowseSort.ALPHABETICAL else BrowseSort.POPULAR

    fun key(surface: String): String = "browseSort.$surface"

    /** The surface a category grid belongs to. */
    fun surface(contentType: String?): String =
        if (contentType == "tv-series" || contentType == "tv-special") TV else CATEGORY

    fun sort(context: Context, surface: String): BrowseSort =
        BrowseSort.fromKey(prefs(context).getString(key(surface), null)) ?: defaultSort(surface)

    fun remember(context: Context, sort: BrowseSort, surface: String) {
        prefs(context).edit { putString(key(surface), sort.key) }
    }

    internal fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
