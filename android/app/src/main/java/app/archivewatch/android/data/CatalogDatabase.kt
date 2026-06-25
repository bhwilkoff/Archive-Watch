package app.archivewatch.android.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * Read-only query layer over the published `catalog.sqlite` — the Kotlin
 * port of the tvOS/iOS `CatalogDB`, implementing the query verbs of
 * docs/CATALOG-CONTRACT.md §5 with the same SQL semantics. Never
 * materializes the whole catalog: every verb is LIMIT-bounded and decodes
 * only the rows a screen shows (Decision 017).
 */
class CatalogDatabase private constructor(
    private val connection: SQLiteConnection,
    private val json: Json,
) {
    /** Decision 012 — hide-adult default ON; set from Settings. */
    @Volatile var hideAdult: Boolean = true
    @Volatile var hiddenTypes: Set<String> = emptySet()

    // SQLiteConnection is not thread-safe — serialize all access.
    private val mutex = Mutex()

    companion object {
        /** Open + probe. A missing `meta.itemCount` means "not our DB". */
        fun open(path: String, json: Json): CatalogDatabase? = try {
            val db = CatalogDatabase(BundledSQLiteDriver().open(path), json)
            if (db.probeItemCount() == null) {
                db.close()
                null
            } else db
        } catch (_: Throwable) {
            null
        }

        /** Editorial demotion (featured.json `deprioritizedSeries`): these ids
            sort LAST in TV lists — still searchable/playable, never the
            marquee (iOS/tvOS parity). Set when featured.json decodes; static
            so it survives the seed→full DB swap. */
        var demotedIDs: Set<String> = emptySet()
    }

    private val demoteOrder: String
        get() = if (demotedIDs.isEmpty()) "" else
            "(i.archiveID IN (${demotedIDs.joinToString(",") { "'${it.replace("'", "''")}'" }})) ASC, "

    fun close() {
        try { connection.close() } catch (_: Throwable) {}
    }

    private fun probeItemCount(): Int? = try {
        queryRaw("SELECT value FROM meta WHERE key = 'itemCount'") { it.getText(0) }
            .firstOrNull()?.toIntOrNull()
    } catch (_: Throwable) {
        null
    }

    // --- the four standard filter clauses (contract §5) ---

    private val adultAnd: String get() = if (hideAdult) " AND i.isAdult = 0" else ""
    private val typeAnd: String
        get() = if (hiddenTypes.isEmpty()) "" else
            " AND i.contentType NOT IN (${hiddenTypes.joinToString(",") { "'${it.replace("'", "")}'" }})"
    private val homeAnd =
        " AND (i.rightsStatus IN ('public_domain','creative_commons')" +
            " OR (i.year >= 1888 AND i.year <= 1977))"
    private val notCommercial = " AND i.contentType != 'commercial'"
    // Standalone TV (tv-special) never appears on film surfaces — Home shelves,
    // discovery rows, Random Film (owner directive 2026-06-18: "TV shows should
    // never appear in Movies"). Surfaced only via the TV scope's TV Specials grid.
    private val notStandaloneTV = " AND i.contentType != 'tv-special'"

    private val itemSelect =
        "SELECT j.json FROM items i JOIN item_json j ON j.archiveID = i.archiveID"

    // --- verbs ---

    suspend fun shelf(shelfID: String, limit: Int = 80): List<CatalogItem> = items(
        """SELECT j.json FROM item_shelves s
           JOIN items i ON i.archiveID = s.archiveID
           JOIN item_json j ON j.archiveID = s.archiveID
           WHERE s.shelfID = ?$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd
           ORDER BY i.hasRealArtwork DESC, s.position LIMIT ?""",
        listOf(shelfID, limit),
    )

    /** Curated lists bypass filters; result reordered to the requested order. */
    suspend fun itemsByIDs(ids: List<String>): List<CatalogItem> {
        if (ids.isEmpty()) return emptyList()
        val marks = ids.joinToString(",") { "?" }
        val found = items(
            "SELECT json FROM item_json WHERE archiveID IN ($marks)",
            ids,
        ).associateBy { it.archiveID }
        return ids.mapNotNull { found[it] }
    }

    suspend fun item(archiveID: String): CatalogItem? =
        items("SELECT json FROM item_json WHERE archiveID = ?", listOf(archiveID)).firstOrNull()

    suspend fun browse(
        contentType: String? = null,
        decade: Int? = null,
        genre: String? = null,
        year: Int? = null,
        sort: BrowseSort = BrowseSort.POPULAR,
        limit: Int = 60,
        offset: Int = 0,
        homeOnly: Boolean = false,
    ): List<CatalogItem> {
        val (where, binds) = browseWhere(contentType, decade, genre, year, homeOnly)
        val genreJoin = if (genre != null) " JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?" else ""
        val genreBind = if (genre != null) listOf(genre) else emptyList()
        // Popular = demoted ids last, designed (professional) artwork first,
        // then popularity; series cards have NULL popularityScore, so
        // episodesCount breaks their ties (iOS/tvOS parity).
        val order = if (sort == BrowseSort.POPULAR) {
            demoteOrder +
                "(i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC, " +
                "COALESCE(i.popularityScore, 0) DESC, " +
                "COALESCE(i.episodesCount, 0) DESC, i.imdbVotes DESC"
        } else sort.sql
        return items(
            "SELECT j.json FROM items i$genreJoin JOIN item_json j ON j.archiveID = i.archiveID" +
                " WHERE $where ORDER BY $order LIMIT ? OFFSET ?",
            genreBind + binds + listOf(limit, offset),
        )
    }

    suspend fun browseCount(
        contentType: String? = null,
        decade: Int? = null,
        genre: String? = null,
        year: Int? = null,
        homeOnly: Boolean = false,
    ): Int {
        val (where, binds) = browseWhere(contentType, decade, genre, year, homeOnly)
        val genreJoin = if (genre != null) " JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?" else ""
        val genreBind = if (genre != null) listOf(genre) else emptyList()
        return dbCall {
            queryRaw("SELECT COUNT(*) FROM items i$genreJoin WHERE $where", genreBind + binds) {
                it.getLong(0).toInt()
            }.firstOrNull() ?: 0
        }
    }

    private fun browseWhere(
        contentType: String?,
        decade: Int?,
        genre: String?,
        year: Int?,
        homeOnly: Boolean,
    ): Pair<String, List<Any?>> {
        val binds = mutableListOf<Any?>()
        // An explicit tv-series request browses the SERIES CARDS (poster-gated:
        // a poster-less card in a curated category grid reads as broken);
        // otherwise series cards are excluded. The old unconditional exclusion
        // contradicted the explicit filter and returned zero rows — the same
        // bug that emptied Classic TV on iOS/tvOS (fixed there 2026-06-11).
        val sb = if (contentType == "tv-series") {
            StringBuilder("i.contentType = 'tv-series' AND i.hasRealArtwork = 1")
        } else if (contentType == "tv-special") {
            // The TV Specials grid (TV scope): standalone specials/episodes.
            StringBuilder("i.contentType = 'tv-special'")
        } else {
            // TV never appears in Movies — neither series cards NOR tv-specials.
            val b = StringBuilder("i.contentType NOT IN ('tv-series','tv-special')")
            if (contentType != null) { b.append(" AND i.contentType = ?"); binds.add(contentType) }
            b
        }
        if (decade != null) { sb.append(" AND i.decade = ?"); binds.add(decade) }
        if (year != null) { sb.append(" AND i.year = ?"); binds.add(year) }
        sb.append(adultAnd).append(typeAnd)
        if (contentType != "commercial") sb.append(notCommercial)
        if (homeOnly) sb.append(homeAnd)
        return sb.toString() to binds
    }

    suspend fun search(query: String, limit: Int = 200): List<CatalogItem> {
        val match = ftsQuery(query) ?: return emptyList()
        return items(
            """SELECT j.json FROM items_fts f
               JOIN items i ON i.archiveID = f.archiveID
               JOIN item_json j ON j.archiveID = f.archiveID
               WHERE items_fts MATCH ?$adultAnd$notCommercial$typeAnd
               ORDER BY rank LIMIT ?""",
            listOf(match, limit),
        )
    }

    /** Individual TV EPISODE search via `episodes_fts` (episode title + series title). Episodes
     *  aren't catalog items, so `search` never returns them — this powers the "Episodes" section. */
    suspend fun searchEpisodes(query: String, limit: Int = 60): List<EpisodeHit> {
        val match = ftsQuery(query) ?: return emptyList()
        return dbCall {
            queryRaw(
                """SELECT seriesID, seriesTitle, season, episode, archiveID, downloadURL,
                          stillURL, year, runtimeSeconds, title
                   FROM episodes_fts WHERE episodes_fts MATCH ? ORDER BY rank LIMIT ?""",
                listOf(match, limit),
            ) { s ->
                fun intOrNull(i: Int) = if (s.isNull(i)) null else s.getLong(i).toInt()
                fun textOrNull(i: Int) = if (s.isNull(i)) null else s.getText(i)
                EpisodeHit(
                    seriesID = s.getText(0), seriesTitle = s.getText(1),
                    season = intOrNull(2), episode = intOrNull(3), archiveID = s.getText(4),
                    downloadURL = textOrNull(5), stillURL = textOrNull(6),
                    year = intOrNull(7), runtimeSeconds = intOrNull(8), title = s.getText(9),
                )
            }
        }
    }

    /** Query hygiene per contract §5: quote each token + `*` suffix. */
    private fun ftsQuery(raw: String): String? {
        val tokens = raw.lowercase()
            .split(Regex("[^a-z0-9]+"))
            .filter { it.length >= 2 }
        if (tokens.isEmpty()) return null
        return tokens.joinToString(" ") { "\"$it\"*" }
    }

    suspend fun byCollection(collection: String, limit: Int = 240): List<CatalogItem> = items(
        """SELECT j.json FROM item_collections c
           JOIN item_json j ON j.archiveID = c.archiveID
           JOIN items i ON i.archiveID = c.archiveID
           WHERE c.collection = ?$adultAnd
           ORDER BY i.popularityScore DESC LIMIT ?""",
        listOf(collection, limit),
    )

    suspend fun seriesCards(limit: Int = 500): List<CatalogItem> = items(
        "$itemSelect WHERE i.contentType = 'tv-series'$adultAnd$typeAnd" +
            " ORDER BY $demoteOrder" +
            "(i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC," +
            " i.episodesCount DESC LIMIT ?",
        listOf(limit),
    )

    /** Standalone TV specials/episodes not folded into a series spine — the TV
        scope's "TV Specials" grid. Kept OFF every film surface (notStandaloneTV). */
    suspend fun tvSpecials(limit: Int = 500): List<CatalogItem> = items(
        "$itemSelect WHERE i.contentType = 'tv-special'$adultAnd$typeAnd" +
            " ORDER BY (i.hasRealArtwork = 1) DESC, i.popularityScore DESC LIMIT ?",
        listOf(limit),
    )

    suspend fun tvSpecialsCount(): Int = dbCall {
        queryRaw(
            "SELECT COUNT(*) FROM items i WHERE i.contentType = 'tv-special'$adultAnd$typeAnd",
        ) { it.getLong(0).toInt() }.firstOrNull() ?: 0
    }

    suspend fun related(to: CatalogItem, limit: Int = 20): List<CatalogItem> = items(
        "$itemSelect WHERE i.contentType = ? AND i.archiveID != ?$adultAnd$typeAnd" +
            " ORDER BY i.popularityScore DESC LIMIT ?",
        listOf(to.contentType, to.archiveID, limit),
    )

    /** "Top Rated" — IMDb favorites; the votes floor keeps tiny-sample
        curios from outranking the classics (iOS/tvOS parity). */
    suspend fun topRated(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = items(
        "$itemSelect WHERE i.imdbRating IS NOT NULL AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd" +
            " ORDER BY i.imdbRating DESC, i.imdbVotes DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    /** Community shelves (archive.org usage signals). Vote-floored to recognized
        films — raw counts are dominated by un-IMDb'd foreign edge cases the metadata
        adult filter can't catch, but those have no votes (iOS/tvOS parity). */
    suspend fun watchingNow(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = items(
        "$itemSelect WHERE COALESCE(i.views30d, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd" +
            " ORDER BY i.views30d DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    suspend fun communityFavorites(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = items(
        "$itemSelect WHERE COALESCE(i.numFavorites, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd" +
            " ORDER BY i.numFavorites DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    suspend fun mostDiscussed(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = items(
        "$itemSelect WHERE COALESCE(i.numReviews, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd" +
            " ORDER BY i.numReviews DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    suspend fun hiddenGems(limit: Int = 20): List<CatalogItem> = items(
        "$itemSelect WHERE i.hasRealArtwork = 1 AND i.qualityScore >= 60 AND i.popularityScore <= 40" +
            "$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd ORDER BY i.qualityScore DESC LIMIT ?",
        listOf(limit),
    )

    suspend fun topDirectors(minFilms: Int = 3, limit: Int = 4): List<String> = dbCall {
        queryRaw(
            """SELECT i.director, COUNT(*) AS c FROM items i
               WHERE i.director IS NOT NULL AND i.director != '' AND i.hasRealArtwork = 1
               $adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd
               GROUP BY i.director HAVING c >= ? ORDER BY c DESC, i.director LIMIT ?""",
            listOf(minFilms, limit),
        ) { it.getText(0) }
    }

    suspend fun byDirector(name: String, limit: Int = 20, homeOnly: Boolean = false): List<CatalogItem> = items(
        "$itemSelect WHERE i.director = ? AND i.hasRealArtwork = 1" +
            "$adultAnd$notCommercial$notStandaloneTV$typeAnd${if (homeOnly) homeAnd else ""}" +
            " ORDER BY i.popularityScore DESC LIMIT ?",
        listOf(name, limit),
    )

    /** Sanity clamp 1890–2029 per contract §5. */
    suspend fun decadeCounts(): List<Pair<Int, Int>> = dbCall {
        queryRaw(
            "SELECT i.decade, COUNT(*) FROM items i WHERE i.decade BETWEEN 1890 AND 2029" +
                "$adultAnd$notCommercial GROUP BY i.decade ORDER BY i.decade",
        ) { it.getLong(0).toInt() to it.getLong(1).toInt() }
    }

    suspend fun randomPlayable(contentType: String? = null): CatalogItem? {
        val binds = mutableListOf<Any?>()
        var where = "i.contentType NOT IN ('tv-series','tv-special')"
        if (contentType != null) { where += " AND i.contentType = ?"; binds.add(contentType) }
        where += adultAnd + typeAnd
        if (contentType != "commercial") where += notCommercial
        return items("$itemSelect WHERE $where ORDER BY RANDOM() LIMIT 20", binds)
            .firstOrNull { it.downloadURL != null }
    }

    suspend fun randomSeries(): CatalogItem? = items(
        "$itemSelect WHERE i.contentType = 'tv-series'$typeAnd ORDER BY RANDOM() LIMIT 1",
        emptyList(),
    ).firstOrNull()

    suspend fun metaString(key: String): String? = dbCall {
        queryRaw("SELECT value FROM meta WHERE key = ?", listOf(key)) { it.getText(0) }.firstOrNull()
    }

    suspend fun metaInt(key: String): Int? = metaString(key)?.toIntOrNull()

    // --- plumbing ---

    private suspend fun items(sql: String, binds: List<Any?>): List<CatalogItem> = dbCall {
        queryRaw(sql, binds) { it.getText(0) }
            .mapNotNull { row ->
                runCatching { json.decodeFromString<CatalogItem>(row) }.getOrNull()
            }
    }

    private suspend fun <T> dbCall(block: () -> T): T =
        withContext(Dispatchers.IO) { mutex.withLock { block() } }

    private fun <T> queryRaw(
        sql: String,
        binds: List<Any?> = emptyList(),
        map: (SQLiteStatement) -> T,
    ): List<T> {
        val out = mutableListOf<T>()
        val stmt = connection.prepare(sql)
        try {
            binds.forEachIndexed { i, value ->
                val idx = i + 1
                when (value) {
                    null -> stmt.bindNull(idx)
                    is String -> stmt.bindText(idx, value)
                    is Int -> stmt.bindLong(idx, value.toLong())
                    is Long -> stmt.bindLong(idx, value)
                    is Double -> stmt.bindDouble(idx, value)
                    is Boolean -> stmt.bindLong(idx, if (value) 1 else 0)
                    else -> stmt.bindText(idx, value.toString())
                }
            }
            while (stmt.step()) out.add(map(stmt))
        } finally {
            stmt.close()
        }
        return out
    }
}

enum class BrowseSort(val label: String, val sql: String) {
    POPULAR("Popular", "i.popularityScore DESC, i.imdbVotes DESC"),
    RATING("Top Rated", "i.imdbRating IS NULL, i.imdbRating DESC, COALESCE(i.imdbVotes, 0) DESC"),
    ALPHABETICAL("A–Z", "i.title COLLATE NOCASE ASC"),
    NEWEST("Newest", "i.year DESC"),
    OLDEST("Oldest", "i.year ASC"),
}
