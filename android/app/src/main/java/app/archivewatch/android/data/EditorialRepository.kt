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
    private val seriesCache = ConcurrentHashMap<String, SeriesDetail>()

    suspend fun featured(): Featured? {
        featuredCache?.let { return it }
        return withContext(Dispatchers.IO) {
            val fetched = fetch("$RAW_BASE/featured.json")
                ?: runCatching {
                    context.assets.open("featured.json").bufferedReader().readText()
                }.getOrNull()
            fetched?.let {
                runCatching { json.decodeFromString<Featured>(it) }.getOrNull()
            }?.also { featuredCache = it }
        }
    }

    /**
     * seriesID slugs can contain non-ASCII — percent-encode the path
     * component or the fetch 404s (contract §6.3, real iOS bug).
     */
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
