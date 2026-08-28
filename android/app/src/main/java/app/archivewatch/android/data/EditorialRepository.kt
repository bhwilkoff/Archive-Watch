package app.archivewatch.android.data

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.ConcurrentHashMap

/**
 * Editorial JSON (docs/CATALOG-CONTRACT.md §6): featured.json + the lazy
 * per-show series spines. Network-first with the bundled featured.json as
 * fallback; in-memory cache only (the files are tiny and refresh daily).
 */
class EditorialRepository(
    private val context: Context,
    private val okHttp: OkHttpClient,
    private val json: Json,
) {
    companion object {
        private const val RAW_BASE = "https://raw.githubusercontent.com/bhwilkoff/Archive-Watch/main"
    }

    @Volatile private var featuredCache: Featured? = null
    @Volatile private var collectionsCache: List<CollectionMeta>? = null
    private val seriesCache = ConcurrentHashMap<String, SeriesDetail>()

    /** Curated collections (collection_metadata.json, bundled at build). */
    suspend fun collections(): List<CollectionMeta> {
        collectionsCache?.let { return it }
        return try {
            val text = context.assets.open("collection_metadata.json")
                .bufferedReader().readText()
            json.decodeFromString<CollectionMetadataFile>(text).collections
        } catch (_: Throwable) {
            emptyList()
        }.also { collectionsCache = it }
    }

    suspend fun featured(): Featured? {
        featuredCache?.let { return it }
        return withContext(Dispatchers.IO) {
            val fetched = fetch("$RAW_BASE/featured.json")
                ?: runCatching {
                    context.assets.open("featured.json").bufferedReader().readText()
                }.getOrNull()
            fetched?.let {
                runCatching { json.decodeFromString<Featured>(it) }.getOrNull()
            }?.also {
                featuredCache = it
                CatalogDatabase.demotedIDs = it.deprioritizedSeries.toSet()
            }
        }
    }

    /**
     * seriesID slugs can contain non-ASCII — percent-encode the path
     * component or the fetch 404s (contract §6.3, real iOS bug).
     */
    /**
     * The season binge queue for an episode (auto-advance + manual next/prev).
     * Rebuilt from the series spine at play time: the season's playable
     * episodes in order, with the pressed episode as the start index. Null
     * when the episode can't anchor a queue (not found, or alone) — the
     * caller then plays the single item exactly as before. Regression note:
     * PARITY recorded episode binge as shipped, but the Decision-045 move to
     * Detail-first episode routing dropped the queue on EVERY Android play
     * path (measured on the Google TV, 2026-08-27) — this restores it for
     * phone and TV both.
     */
    suspend fun episodeBingeQueue(
        seriesSlug: String,
        episodeArchiveID: String,
    ): Pair<List<QueueEntry>, Int>? {
        val s = series(seriesSlug) ?: return null
        val season = s.seasons.find { se ->
            se.episodes.any { it.archiveID == episodeArchiveID }
        } ?: return null
        val entries = season.episodes.filter { it.downloadURL != null }.map { e ->
            val label = listOfNotNull(
                e.seasonNumber?.let { sn ->
                    e.episodeNumber?.let { en -> "S%02dE%02d".format(sn, en) }
                },
                e.title,
            ).joinToString(" · ").ifBlank { s.title }
            QueueEntry(
                id = e.archiveID ?: e.downloadURL!!,
                title = s.title,
                subtitle = label,
                url = e.downloadURL!!,
            )
        }
        val idx = entries.indexOfFirst { it.id == episodeArchiveID }
        return if (idx >= 0 && entries.size > 1) entries to idx else null
    }

    suspend fun series(slug: String): SeriesDetail? {
        seriesCache[slug]?.let { return it }
        return withContext(Dispatchers.IO) {
            fetch("$RAW_BASE/series/${Uri.encode(slug)}.json")?.let {
                runCatching { json.decodeFromString<SeriesDetail>(it) }.getOrNull()
            }?.also { seriesCache[slug] = it }
        }
    }

    private fun fetch(url: String): String? = try {
        okHttp.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (response.isSuccessful) response.body?.string() else null
        }
    } catch (_: Throwable) {
        null
    }
}
