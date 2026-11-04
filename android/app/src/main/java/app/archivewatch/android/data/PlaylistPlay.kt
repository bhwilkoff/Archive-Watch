package app.archivewatch.android.data

import kotlin.random.Random

/** A playlist plays (iOS-DESIGN §4.3b): which titles, in what order, from
 *  where. Nothing here is stored; the place comes from watch history. */
object PlaylistPlay {

    /** Titles with a file of their own. A series card has none, whatever its
     *  row carries, and a merged-away id can repeat a card. */
    fun playable(titles: List<CatalogItem>): List<CatalogItem> =
        titles.filter { it.contentType != "tv-series" && !it.downloadURL.isNullOrBlank() }
            .distinctBy { it.archiveID }

    /** The first title not marked watched, or the top if all are. */
    fun startIndex(ids: List<String>, watched: Set<String>): Int =
        ids.indexOfFirst { it !in watched }.coerceAtLeast(0)

    /** "3 of 12"; a list of one has no place to name. */
    fun position(index: Int, count: Int): String? =
        if (count > 1 && index in 0 until count) "${index + 1} of $count" else null

    /** `shown` pairs each card with the id the playlist stores for it, in the
     *  order on screen: history saved under a merged-away id still counts. */
    fun play(shown: List<Pair<String, CatalogItem>>, watched: Set<String>): PlaySpec? {
        val titles = playable(shown.map { it.second })
        val seen = watched + shown.filter { it.first in watched }.map { it.second.archiveID }
        return spec(titles, startIndex(titles.map { it.archiveID }, seen))
    }

    fun shuffle(shown: List<Pair<String, CatalogItem>>, random: Random = Random.Default): PlaySpec? =
        spec(playable(shown.map { it.second }).shuffled(random), 0)

    private fun spec(titles: List<CatalogItem>, start: Int): PlaySpec? {
        val first = titles.getOrNull(start) ?: return null
        return PlaySpec(
            id = first.archiveID,
            title = first.title,
            description = first.synopsis,
            url = first.downloadURL!!,
            captions = first.captions ?: emptyList(),
            runtimeSeconds = first.runtimeSeconds,
            queue = titles.map {
                QueueEntry(
                    id = it.archiveID,
                    title = it.title,
                    url = it.downloadURL!!,
                    captions = it.captions ?: emptyList(),
                    description = it.synopsis,
                )
            },
            queueIndex = start,
            playlist = true,
        )
    }
}
