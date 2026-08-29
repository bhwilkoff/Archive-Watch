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
        private const val liteCols =
            "i.archiveID,i.title,i.year,i.decade,i.contentType,i.posterURL," +
            "i.hasRealArtwork,i.artworkSource,i.runtimeSeconds,i.popularityScore," +
            "i.isSilentFilm,i.seriesID,i.episodesCount,i.imdbRating," +
            "i.director,i.numFavorites,i.avgRating"
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

    /** Restricts the most PROMINENT surfaces to titles whose bytes were verified
        playable (tools/check_liveness.py), so the app never showcases something
        that turns out not to play. Browse/Search stay ungated — the full catalog
        remains reachable while probe coverage climbs (iOS/tvOS parity).

        Empty when the column is absent: `playable` postdates shipped builds, and
        a new APK reading a still-cached older catalog.sqlite would otherwise
        throw on every one of these queries. */
    private val verifiedAnd: String get() = if (hasPlayableColumn) " AND i.playable = 1" else ""

    private val hasPlayableColumn: Boolean = try {
        queryRaw("PRAGMA table_info(items)") { it.getText(1) }.contains("playable")
    } catch (_: Throwable) {
        false
    }

    private val hasHiddenGemColumn: Boolean = try {
        queryRaw("PRAGMA table_info(items)") { it.getText(1) }.contains("hiddenGem")
    } catch (_: Throwable) {
        false
    }
    // Standalone TV (tv-special) never appears on film surfaces — Home shelves,
    // discovery rows, Random Film (owner directive 2026-06-18: "TV shows should
    // never appear in Movies"). Surfaced only via the TV scope's TV Specials grid.
    // tv-special AND tv-episode (first-class episode items, Decision 045) stay off
    // every film surface; episodes remain in `search` (which applies no TV exclusion).
    private val notStandaloneTV = " AND i.contentType NOT IN ('tv-special','tv-episode')"

    private val itemSelect =
        "SELECT $liteCols FROM items i"

    // --- verbs ---

    /**
     * `allowStandaloneTV` comes from a shelf whose featured.json category IS
     * television (Decision 086). Without it `notStandaloneTV` excluded
     * `tv-special` from EVERY shelf — including the four Classic TV shelves,
     * whose entire membership is tv-special, so they returned nothing and were
     * dropped for being too short. tvOS/iOS/macOS shipped the fix first; this
     * is the same conditional on the same shared DB.
     *
     * `tv-episode` stays excluded either way: a loose episode belongs to its
     * series and should be reached through it (Decision 045).
     */
    suspend fun shelf(
        shelfID: String,
        limit: Int = 80,
        allowStandaloneTV: Boolean = false,
    ): List<CatalogItem> {
        val tvClause =
            if (allowStandaloneTV) " AND i.contentType != 'tv-episode'" else notStandaloneTV
        return itemsLite(
            """SELECT $liteCols FROM item_shelves s
               JOIN items i ON i.archiveID = s.archiveID
               WHERE s.shelfID = ?$adultAnd$homeAnd$notCommercial$tvClause$typeAnd$verifiedAnd
               ORDER BY i.hasRealArtwork DESC, s.position LIMIT ?""",
            listOf(shelfID, limit),
        )
    }

    /** Curated lists bypass filters; result reordered to the requested order. */
    suspend fun itemsByIDs(ids: List<String>): List<CatalogItem> {
        if (ids.isEmpty()) return emptyList()
        val found = itemsByIDsDirect(ids).associateBy { it.archiveID }.toMutableMap()
        val missing = ids.filter { !found.containsKey(it) }
        if (missing.isNotEmpty()) {
            for ((old, item) in resolveAliases(missing)) found[old] = item
        }
        return ids.mapNotNull { found[it] }
    }

    suspend fun item(archiveID: String): CatalogItem? =
        itemsByIDs(listOf(archiveID)).firstOrNull()

    /**
     * Follow merged-away ids to the card that replaced them (Decision 085).
     *
     * Favorites, playlists and watch progress are keyed by archiveID, and the
     * build drops thousands of duplicate copies every publish — 5,363 rows in
     * the current DB. Android downloaded that table but never queried it, so a
     * saved id that lost dedup simply disappeared from the library while the
     * film sat one row away under the survivor's id.
     *
     * Each call is its own dbCall and they run SEQUENTIALLY: the mutex in
     * dbCall is not reentrant, so nesting these would deadlock.
     */
    private suspend fun resolveAliases(ids: List<String>): List<Pair<String, CatalogItem>> {
        if (ids.isEmpty()) return emptyList()
        val marks = ids.joinToString(",") { "?" }
        // A cached DB published before the table existed simply has no aliases;
        // that is not an error, it is an older catalog.
        val pairs = dbCall {
            runCatching {
                queryRaw(
                    "SELECT oldID, newID FROM item_aliases WHERE oldID IN ($marks)",
                    ids,
                ) { it.getText(0) to it.getText(1) }
            }.getOrDefault(emptyList())
        }
        if (pairs.isEmpty()) return emptyList()
        val byNew = itemsByIDsDirect(pairs.map { it.second }).associateBy { it.archiveID }
        return pairs.mapNotNull { (old, new) -> byNew[new]?.let { old to it } }
    }

    /** The un-aliased lookup, so alias resolution cannot recurse. */
    private suspend fun itemsByIDsDirect(ids: List<String>): List<CatalogItem> {
        if (ids.isEmpty()) return emptyList()
        val marks = ids.joinToString(",") { "?" }
        return items("SELECT json FROM item_json WHERE archiveID IN ($marks)", ids)
    }

    suspend fun browse(
        contentType: String? = null,
        decade: Int? = null,
        genre: String? = null,
        keyword: String? = null,
        studio: String? = null,
        year: Int? = null,
        sort: BrowseSort = BrowseSort.POPULAR,
        limit: Int = 60,
        offset: Int = 0,
        homeOnly: Boolean = false,
        full: Boolean = false,
    ): List<CatalogItem> {
        val (ct, gn, docAnd) = docCategory(contentType, genre)
        val (where0, binds) = browseWhere(ct, decade, gn, year, homeOnly)
        val where = where0 + docAnd
        val (joins, joinBinds) = facetJoins(gn, keyword, studio)
        // Popular = demoted ids last, designed (professional) artwork first,
        // then popularity; series cards have NULL popularityScore, so
        // episodesCount breaks their ties (iOS/tvOS parity).
        val order = if (sort == BrowseSort.POPULAR) {
            demoteOrder +
                "(i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC, " +
                "COALESCE(i.popularityScore, 0) DESC, " +
                "COALESCE(i.episodesCount, 0) DESC, COALESCE(i.imdbVotes, 0) DESC, i.archiveID"
        } else sort.sql
        // `full` decodes the per-item blob: only for callers that need fields a
        // list row does not carry (downloadURL, colorMode, synopsis) — Party
        // Play and Cartoon Mode build PLAYABLE lineups and filter on colour, so
        // a lite row would silently give them an empty lineup. Everything on
        // the launch path stays lite; this is a screen the viewer chose to open.
        return if (full) items(
            "SELECT j.json FROM items i$joins JOIN item_json j ON j.archiveID = i.archiveID" +
                " WHERE $where ORDER BY $order LIMIT ? OFFSET ?",
            joinBinds + binds + listOf(limit, offset),
        ) else itemsLite(
            "SELECT $liteCols FROM items i$joins" +
                " WHERE $where ORDER BY $order LIMIT ? OFFSET ?",
            joinBinds + binds + listOf(limit, offset),
        )
    }

    suspend fun browseCount(
        contentType: String? = null,
        decade: Int? = null,
        genre: String? = null,
        keyword: String? = null,
        studio: String? = null,
        year: Int? = null,
        homeOnly: Boolean = false,
    ): Int {
        val (ct, gn, docAnd) = docCategory(contentType, genre)
        val (where0, binds) = browseWhere(ct, decade, gn, year, homeOnly)
        val where = where0 + docAnd
        val (joins, joinBinds) = facetJoins(gn, keyword, studio)
        return dbCall {
            queryRaw("SELECT COUNT(*) FROM items i$joins WHERE $where", joinBinds + binds) {
                it.getLong(0).toInt()
            }.firstOrNull() ?: 0
        }
    }

    /** Value-filter joins onto `items i` for the facet tables — genre, plus the
        metadata-expansion keyword + studio tables (Decision 046). Each mirrors the
        `item_genres` join exactly: `(archiveID, value)` indexed on value, so the
        join is only paid when that filter is active. */
    private fun facetJoins(
        genre: String?, keyword: String?, studio: String?,
    ): Pair<String, List<Any?>> {
        val sb = StringBuilder()
        val binds = mutableListOf<Any?>()
        if (genre != null) {
            sb.append(" JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?"); binds.add(genre)
        }
        if (keyword != null) {
            sb.append(" JOIN item_keywords k ON k.archiveID = i.archiveID AND k.keyword = ?"); binds.add(keyword)
        }
        if (studio != null) {
            sb.append(" JOIN item_studios st ON st.archiveID = i.archiveID AND st.studio = ?"); binds.add(studio)
        }
        return sb.toString() to binds
    }

    /** The Documentary CATEGORY resolves by GENRE, not contentType (Apple
        parity). contentType is a FORM axis (silent/short/feature) while
        "documentary" is a SUBJECT: only 8 items were ever typed `documentary`
        while 1,109 carry the Documentary genre, so the tile was effectively
        empty. Resolving by genre is ADDITIVE — a silent documentary stays in
        Silent Era AND appears here — whereas re-typing would fill one category
        by gutting three. Applied at the call sites because `genre` also feeds
        facetJoins(). */
    private fun docCategory(contentType: String?, genre: String?): Triple<String?, String?, String> =
        if (contentType == "documentary")
            Triple(null, genre ?: "Documentary", " AND i.contentType != 'animation'")
        else Triple(contentType, genre, "")

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
            val b = StringBuilder("i.contentType NOT IN ('tv-series','tv-special','tv-episode')")
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
        return itemsLite(
            """SELECT $liteCols FROM items_fts f
               JOIN items i ON i.archiveID = f.archiveID
               WHERE items_fts MATCH ?$adultAnd$notCommercial$typeAnd
               ORDER BY rank LIMIT ?""",
            listOf(match, limit),
        )
    }

    /** Query hygiene per contract §5: quote each token + `*` suffix. */
    private fun ftsQuery(raw: String): String? {
        val tokens = raw.lowercase()
            .split(Regex("[^a-z0-9]+"))
            .filter { it.length >= 2 }
        if (tokens.isEmpty()) return null
        return tokens.joinToString(" ") { "\"$it\"*" }
    }

    suspend fun byCollection(collection: String, limit: Int = 240): List<CatalogItem> = itemsLite(
        """SELECT $liteCols FROM item_collections c
           JOIN items i ON i.archiveID = c.archiveID
           WHERE c.collection = ?$adultAnd
           ORDER BY i.popularityScore DESC LIMIT ?""",
        listOf(collection, limit),
    )

    /** Metadata-expansion facet filters (Decision 046) — parallel to the genre
        filter, querying the value-indexed `item_keywords` / `item_studios` join
        tables exactly like `byCollection` queries `item_collections`. */
    suspend fun byKeyword(keyword: String, limit: Int = 240): List<CatalogItem> = itemsLite(
        """SELECT $liteCols FROM item_keywords k
           JOIN items i ON i.archiveID = k.archiveID
           WHERE k.keyword = ?$adultAnd$notCommercial$typeAnd
           ORDER BY COALESCE(i.popularityScore, 0) DESC LIMIT ?""",
        listOf(keyword, limit),
    )

    suspend fun byStudio(studio: String, limit: Int = 240): List<CatalogItem> = itemsLite(
        """SELECT $liteCols FROM item_studios s
           JOIN items i ON i.archiveID = s.archiveID
           WHERE s.studio = ?$adultAnd$notCommercial$typeAnd
           ORDER BY COALESCE(i.popularityScore, 0) DESC LIMIT ?""",
        listOf(studio, limit),
    )

    /** Top keyword / studio facets for the filter UI — the value→count listing
        the Browse facet menus offer, gated by a film-count floor so the menu shows
        meaningful buckets (mirrors `topDirectors` / `decadeCounts`). */
    suspend fun topKeywords(minFilms: Int = 12, limit: Int = 80): List<String> = dbCall {
        queryRaw(
            """SELECT k.keyword, COUNT(*) AS c FROM item_keywords k
               JOIN items i ON i.archiveID = k.archiveID
               WHERE 1 = 1$adultAnd$notCommercial$typeAnd
               GROUP BY k.keyword HAVING c >= ? ORDER BY c DESC, k.keyword LIMIT ?""",
            listOf(minFilms, limit),
        ) { it.getText(0) }
    }

    suspend fun topStudios(minFilms: Int = 6, limit: Int = 80): List<String> = dbCall {
        queryRaw(
            """SELECT s.studio, COUNT(*) AS c FROM item_studios s
               JOIN items i ON i.archiveID = s.archiveID
               WHERE 1 = 1$adultAnd$notCommercial$typeAnd
               GROUP BY s.studio HAVING c >= ? ORDER BY c DESC, s.studio LIMIT ?""",
            listOf(minFilms, limit),
        ) { it.getText(0) }
    }

    suspend fun seriesCards(limit: Int = 500): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE i.contentType = 'tv-series'$adultAnd$typeAnd" +
            " ORDER BY $demoteOrder" +
            "(i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC," +
            " i.episodesCount DESC LIMIT ?",
        listOf(limit),
    )

    /** Standalone TV specials/episodes not folded into a series spine — the TV
        scope's "TV Specials" grid. Kept OFF every film surface (notStandaloneTV). */
    suspend fun tvSpecials(limit: Int = 500): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE i.contentType = 'tv-special'$adultAnd$typeAnd" +
            " ORDER BY (i.hasRealArtwork = 1) DESC, i.popularityScore DESC LIMIT ?",
        listOf(limit),
    )

    suspend fun tvSpecialsCount(): Int = dbCall {
        queryRaw(
            "SELECT COUNT(*) FROM items i WHERE i.contentType = 'tv-special'$adultAnd$typeAnd",
        ) { it.getLong(0).toInt() }.firstOrNull() ?: 0
    }

    /** "More Like This": same category, then year proximity (±10y), then popularity; finally
     *  prefer the SAME B&W-vs-color as the subject (colorMode is JSON-only, so ranked in Kotlin). */
    suspend fun related(to: CatalogItem, limit: Int = 20): List<CatalogItem> {
        val yearKey = to.year?.let {
            "(CASE WHEN i.year IS NOT NULL AND ABS(i.year - $it) <= 10 THEN 1 ELSE 0 END) DESC, "
        } ?: ""
        val pool = itemsLite(
            "$itemSelect WHERE i.contentType = ? AND i.archiveID != ?$adultAnd$typeAnd" +
                " ORDER BY ${yearKey}COALESCE(i.popularityScore,0) DESC, i.imdbVotes DESC LIMIT ?",
            listOf(to.contentType, to.archiveID, limit * 3),
        )
        val subjColor = to.colorMode ?: return pool.take(limit)
        return (pool.filter { it.colorMode == subjColor } + pool.filter { it.colorMode != subjColor }).take(limit)
    }

    /** "Top Rated" — IMDb favorites; the votes floor keeps tiny-sample
        curios from outranking the classics (iOS/tvOS parity). */
    suspend fun topRated(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE i.imdbRating IS NOT NULL AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd$verifiedAnd" +
            " ORDER BY i.imdbRating DESC, i.imdbVotes DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    /** Community shelves (archive.org usage signals). Vote-floored to recognized
        films — raw counts are dominated by un-IMDb'd foreign edge cases the metadata
        adult filter can't catch, but those have no votes (iOS/tvOS parity). */
    suspend fun watchingNow(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE COALESCE(i.views30d, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd$verifiedAnd" +
            " ORDER BY i.views30d DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    suspend fun communityFavorites(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE COALESCE(i.numFavorites, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd$verifiedAnd" +
            " ORDER BY i.numFavorites DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    suspend fun mostDiscussed(limit: Int = 24, minVotes: Int = 1000): List<CatalogItem> = itemsLite(
        "$itemSelect WHERE COALESCE(i.numReviews, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= ?" +
            " AND i.hasRealArtwork = 1$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd$verifiedAnd" +
            " ORDER BY i.numReviews DESC LIMIT ?",
        listOf(minVotes, limit),
    )

    /** "Hidden Gems" — high craft, low traffic.
     *
     *  Membership is the `hiddenGem` column COMPUTED by
     *  tools/build_sqlite.py::_mark_hidden_gems, not a predicate written here.
     *  This shelf used to ask for `qualityScore >= 60 AND popularityScore <= 40`,
     *  written in June against a popularityScore that ran 0-89; when _pop_score
     *  was rescaled on 2026-06-29 so every scored item is >= 100, that could no
     *  longer match anything and the shelf was silently empty on every platform
     *  for five weeks. A threshold against a scale the PIPELINE owns does not
     *  belong in a client.
     *
     *  Fallback for a DB predating the column: the scale-free part of the same
     *  idea — well-rated, not famous. */
    suspend fun hiddenGems(limit: Int = 20): List<CatalogItem> {
        val gemAnd = if (hasHiddenGemColumn) "i.hiddenGem = 1"
            else "i.imdbRating >= 7.0 AND i.imdbVotes BETWEEN 100 AND 5000 AND i.year IS NOT NULL"
        return itemsLite(
            "$itemSelect WHERE $gemAnd AND i.hasRealArtwork = 1" +
                "$adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd$verifiedAnd" +
                " ORDER BY i.imdbRating DESC, i.imdbVotes DESC LIMIT ?",
            listOf(limit),
        )
    }

    suspend fun topDirectors(minFilms: Int = 3, limit: Int = 4): List<String> = dbCall {
        queryRaw(
            """SELECT i.director, COUNT(*) AS c FROM items i
               WHERE i.director IS NOT NULL AND i.director != '' AND i.hasRealArtwork = 1
               $adultAnd$homeAnd$notCommercial$notStandaloneTV$typeAnd
               GROUP BY i.director HAVING c >= ? ORDER BY c DESC, i.director LIMIT ?""",
            listOf(minFilms, limit),
        ) { it.getText(0) }
    }

    suspend fun byDirector(name: String, limit: Int = 20, homeOnly: Boolean = false): List<CatalogItem> = itemsLite(
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
        var where = "i.contentType NOT IN ('tv-series','tv-special','tv-episode')"
        if (contentType != null) { where += " AND i.contentType = ?"; binds.add(contentType) }
        where += adultAnd + typeAnd
        if (contentType != "commercial") where += notCommercial
        return itemsLite("$itemSelect WHERE $where ORDER BY RANDOM() LIMIT 20", binds)
            .firstOrNull { it.downloadURL != null }
    }

    /** A random FULL-LENGTH film (Random Film). Feature/silent FEATURES with a runtime floor, so it
     *  never lands on a short / cartoon / newsreel (the old randomPlayable(null) admitted those). */
    suspend fun randomFeatureFilm(): CatalogItem? {
        var where = "i.contentType IN ('feature-film','silent-film') AND " +
            "(i.runtimeSeconds IS NULL OR i.runtimeSeconds >= 2400)"
        where += adultAnd + typeAnd
        return itemsLite("$itemSelect WHERE $where ORDER BY RANDOM() LIMIT 20", emptyList())
            .firstOrNull { it.downloadURL != null }
    }

    suspend fun randomSeries(): CatalogItem? = itemsLite(
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

    private val UNUSED_liteCols = "i.archiveID,i.title,i.year,i.decade,i.contentType,i.posterURL,i.hasRealArtwork,i.artworkSource,i.runtimeSeconds,i.popularityScore,i.isSilentFilm,i.seriesID,i.episodesCount,i.imdbRating,i.imdbVotes,i.director,i.numFavorites,i.avgRating"

    /**
     * A list row built from the `items` COLUMNS — no JSON decode.
     *
     * Every shelf and grid query used to `JOIN item_json` and decode the full
     * per-item blob, and Home alone builds 21 shelves of 32 plus a 120-item
     * row: over a thousand blobs, each ~4 KB with 76 fields, parsed on a
     * television's CPU before anything could be drawn. Measured on the Google
     * TV: the Home producer took 17.6s, 14s of it before the payload was even
     * assembled — far more than the 14s download it was blamed on.
     *
     * Nothing a list shows needs the blob: title, year, artwork, runtime and
     * rating are all columns, and every derived predicate the shelves rely on
     * (dedupKey, hasProfessionalArtwork, isSilent) is computed from those.
     * Detail still decodes the full item — that is one row, when asked for.
     */
    private fun liteFromRow(st: SQLiteStatement): CatalogItem = CatalogItem(
        archiveID = st.getText(0),
        title = if (st.isNull(1)) "" else st.getText(1),
        year = if (st.isNull(2)) null else st.getInt(2),
        decade = if (st.isNull(3)) null else st.getInt(3),
        contentType = if (st.isNull(4)) "" else st.getText(4),
        posterURL = if (st.isNull(5)) null else st.getText(5),
        hasRealArtwork = if (st.isNull(6)) null else st.getInt(6) != 0,
        artworkSource = if (st.isNull(7)) null else st.getText(7),
        runtimeSeconds = if (st.isNull(8)) null else st.getInt(8),
        popularityScore = if (st.isNull(9)) null else st.getInt(9),
        isSilentFilm = if (st.isNull(10)) null else st.getInt(10) != 0,
        seriesID = if (st.isNull(11)) null else st.getText(11),
        episodesCount = if (st.isNull(12)) null else st.getInt(12),
        imdbRating = if (st.isNull(13)) null else st.getDouble(13),
        director = if (st.isNull(14)) null else st.getText(14),
        numFavorites = if (st.isNull(15)) null else st.getInt(15),
        avgRating = if (st.isNull(16)) null else st.getDouble(16),
    )

    private suspend fun itemsLite(sql: String, binds: List<Any?>): List<CatalogItem> = dbCall {
        queryRaw(sql, binds) { liteFromRow(it) }
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
    // Same rich order the browse() path builds for POPULAR (designed-art-first + deterministic
    // tiebreak), so every code path that sorts by Popular agrees (owner 2026-06-29).
    POPULAR("Popular", "(i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC, " +
        "COALESCE(i.popularityScore, 0) DESC, COALESCE(i.imdbVotes, 0) DESC, i.archiveID"),
    RATING("Top Rated", "i.imdbRating IS NULL, i.imdbRating DESC, COALESCE(i.imdbVotes, 0) DESC"),
    ALPHABETICAL("A–Z", "i.title COLLATE NOCASE ASC"),
    NEWEST("Newest", "i.year DESC"),
    OLDEST("Oldest", "i.year ASC"),
}
