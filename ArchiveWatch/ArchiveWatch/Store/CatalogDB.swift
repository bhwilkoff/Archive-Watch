import Foundation
import SQLite3   // system module on tvOS — no third-party package (Decision 017)

// Read-only query layer over the prebuilt catalog SQLite (Decision 017,
// docs/architecture/catalog-delivery.md). The app queries the DB on disk and
// decodes only the rows a screen needs — so resident memory is the visible
// rows, not the whole catalog. Rows come back as `Catalog.Item` decoded from
// the `item_json` blob, so the models are identical to the JSON path.
//
// Reads are fast (indexed, LIMIT-bounded) so they run synchronously on the
// main actor; downloading/swapping the DB file is async and lives in
// CatalogRefreshService.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CatalogDB {
    private let handle: OpaquePointer
    private let decoder = JSONDecoder()

    enum Sort { case popular, rating, alphabetical, newest, oldest }

    /// Opens the DB read-only. Returns nil if the file is missing/corrupt.
    init?(path: String) {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            if let h { sqlite3_close(h) }
            return nil
        }
        self.handle = h
        // mmap OFF: if the DB file is corrupted under disk pressure, an mmap'd read faults the process
        // (EXC_BAD_ACCESS) instead of returning a recoverable SQLITE_CORRUPT we can handle.
        sqlite3_exec(h, "PRAGMA mmap_size=0;", nil, nil, nil)
        // `playable` arrived after this app shipped, so a build running against a
        // still-cached older DB would hit "no such column" — and a failed prepare
        // returns [], silently EMPTYING the shelves that gate on it. Probe once
        // and drop the clause when it's absent; the shelf is merely ungated until
        // the next catalog refresh lands. Must be assigned before any method call
        // on self (metaInt below) — all stored properties initialized first.
        hasPlayableColumn = Self.columnExists(h, table: "items", column: "playable")
        hasHiddenGemColumn = Self.columnExists(h, table: "items", column: "hiddenGem")
        // Fail fast if it isn't actually our schema.
        guard metaInt("itemCount") != nil else {
            sqlite3_close(h); return nil
        }
    }

    /// True when `table` has `column` (PRAGMA table_info).
    private static func columnExists(_ h: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }

    private let hasPlayableColumn: Bool
    private let hasHiddenGemColumn: Bool

    /// Restricts a surface to titles whose bytes were verified playable
    /// (tools/check_liveness.py). Applied to the most PROMINENT surfaces only —
    /// the marquee and the community shelves — so the app never showcases a
    /// title that turns out not to play, while Browse/Search keep the full
    /// catalog available as coverage climbs. Empty (no-op) on an older DB.
    private var verifiedAnd: String { hasPlayableColumn ? "AND i.playable = 1" : "" }

    deinit { sqlite3_close(handle) }

    // MARK: - Decoding

    private func decode(_ json: String) -> Catalog.Item? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(Catalog.Item.self, from: data)
    }

    /// Run a query whose first column is an item_json blob → [Catalog.Item].
    private func items(_ sql: String, _ binds: [String] = []) -> [Catalog.Item] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), b, -1, SQLITE_TRANSIENT)
        }
        var out: [Catalog.Item] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0),
               let it = decode(String(cString: c)) {
                out.append(it)
            }
        }
        return out
    }

    private func scalarRows(_ sql: String, _ binds: [String] = []) -> [(String, Int)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), b, -1, SQLITE_TRANSIENT)
        }
        var out: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            out.append((key, Int(sqlite3_column_int64(stmt, 1))))
        }
        return out
    }

    // MARK: - Meta

    func metaInt(_ key: String) -> Int? {
        let r = scalarRows("SELECT value, 0 FROM meta WHERE key=?", [key])
        return r.first.flatMap { Int($0.0) }
    }
    func metaString(_ key: String) -> String? {
        scalarRows("SELECT value, 0 FROM meta WHERE key=?", [key]).first?.0
    }

    /// Decision 012 adult filter — set from AppStore.hideAdultContent. When
    /// true, queries exclude items the build flagged isAdult=1.
    var hideAdult = true
    private var adultAnd: String { hideAdult ? "AND i.isAdult = 0" : "" }

    /// Content-type categories the user has hidden in Settings (#4). Applied
    /// app-wide (Home + Browse + Search) like the adult filter. Values are
    /// app-defined contentType strings, so safe to inline.
    var hiddenTypes: Set<String> = []
    private var typeAnd: String {
        guard !hiddenTypes.isEmpty else { return "" }
        let list = hiddenTypes.map { "'\($0)'" }.joined(separator: ",")
        return "AND i.contentType NOT IN (\(list))"
    }

    /// Editorial demotion (featured.json `deprioritizedSeries`): series whose
    /// episode rights are uncertain sort to the END of TV lists instead of
    /// leading them — still searchable and playable, just never the marquee
    /// (owner direction 2026-06-11 re: SNL). Set from AppStore on DB swap.
    var demotedIDs: Set<String> = []
    private var demoteOrder: String {
        guard !demotedIDs.isEmpty else { return "" }
        let list = demotedIDs
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        return "(i.archiveID IN (\(list))) ASC, "
    }

    /// Home-advertising gate: keep modern, uncertain-rights movies OFF the home
    /// surfaces while still admitting everything that's confidently free to show.
    /// An item qualifies for Home if EITHER:
    ///   • its rights are explicitly public_domain / creative_commons (any year —
    ///     this is how post-1977 gov/PD content like NASA stays eligible), OR
    ///   • it has a known release year in the cinema-history window 1888–1977
    ///     (PD-by-age era; no rights tag needed).
    /// A post-1977 film with reserved/unknown rights — i.e. a modern movie we
    /// can't vouch for — fails both and is hidden from Home (measured: blocks
    /// ~230 items, drops ZERO items from any curated shelf). year-null + non-PD
    /// is also blocked (a wrong-match item whose year we nulled must not sneak
    /// back onto the marquee). NOT applied to Browse/Search — the full catalog
    /// stays available there.
    private let homeAnd =
        "AND (i.rightsStatus IN ('public_domain','creative_commons') " +
        "OR (i.year >= 1888 AND i.year <= 1977))"

    /// Commercials (contentType 'commercial') are interstitial + collection
    /// content (vintage ads — see docs/design/channels-tv-guide.md). They must
    /// NEVER clutter Home/Browse/Search/Surprise-by-film. They surface ONLY via
    /// the Commercials collection (byCollection), the Random Commercial action
    /// (randomPlayable(contentType:"commercial")), and channel breaks
    /// (randomCommercials). This clause is applied to every general surface;
    /// the three intentional surfaces omit it.
    private let notCommercial = "AND i.contentType != 'commercial'"

    /// Standalone/atomic TV — tv-special (specials + un-folded episodes) and
    /// tv-episode (first-class episode items, Decision 045) — must NEVER appear
    /// on film surfaces: Home discovery shelves, Random Film, director/quality
    /// rows (owner directive 2026-06-18: "TV shows should never appear in
    /// Movies"). tv-series cards are handled per-query (they DO lead TV shelves).
    /// tv-specials surface via the TV tab's TV Specials grid; tv-episodes via the
    /// series Detail + favorites/playlists/SEARCH (episodes ARE searchable — see
    /// `searchExclude`, which keeps them in the index while this drops them here).
    private let notStandaloneTV = "AND i.contentType NOT IN ('tv-special','tv-episode')"

    /// Search MAY return episode items (the whole point of making them items —
    /// Decision 045), so it drops only tv-special, not tv-episode.
    private let searchExclude = "AND i.contentType != 'tv-special'"

    // MARK: - Queries the views use

    /// One Home shelf. Items with real designed artwork lead (#7 — never put a
    /// poster-less tile ahead of one that has a real poster), then stored
    /// position order.
    ///
    /// `homeAnd` IS applied: a curated shelf must not surface a modern,
    /// uncertain-rights film. The gate is the year/rights one (1888–1977 OR
    /// PD/CC), NOT the old rights-required cap that starved NASA — measured to
    /// drop zero items from every current shelf while blocking modern strays.
    func shelf(_ shelfID: String, limit: Int = 80) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM item_shelves s
            JOIN item_json j USING(archiveID)
            JOIN items i USING(archiveID)
            WHERE s.shelfID = ?1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd)
            ORDER BY i.hasRealArtwork DESC, s.position
            LIMIT \(limit)
        """, [shelfID])
    }

    /// Curated/explicit list of archiveIDs (e.g. editor's picks from featured.json).
    func itemsByIDs(_ ids: [String]) -> [Catalog.Item] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = items("SELECT json FROM item_json WHERE archiveID IN (\(placeholders))", ids)
        // Preserve the requested order.
        let byID = Dictionary(rows.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    /// Shared WHERE/ORDER builder so browse() and the off-main paging path
    /// (browsePageJSON) stay in lockstep.
    private func browseSQL(contentType: String?, decade: Int?, genre: String?, year: Int?,
                           sort: Sort, limit: Int, offset: Int, homeOnly: Bool) -> (String, [String]) {
        // Series cards are excluded from general browse grids — but when the
        // caller EXPLICITLY asks for tv-series (the Classic TV category tile),
        // they ARE the result set. The old unconditional exclusion contradicted
        // the explicit filter and returned zero rows (owner report 2026-06-11:
        // "the Classic TV category contains no items").
        var where_: [String] = []
        var binds: [String] = []
        var contentType = contentType
        var genre = genre
        // The Documentary CATEGORY resolves by GENRE, not by contentType.
        //
        // contentType is a FORM axis (silent-film / short-film / feature-film);
        // "documentary" is a SUBJECT. Only 8 items were ever typed
        // `documentary`, while 1,109 carry the Documentary genre — so the
        // category tile was effectively empty and count-gated off Home while
        // the catalog held over a thousand documentaries (owner, 2026-07-19:
        // "There should be thousands of documentaries").
        //
        // Resolving by genre is ADDITIVE: a silent documentary stays in Silent
        // Era AND appears here. Re-typing them instead would have moved 396
        // silents, 297 shorts and 151 features out of their own categories —
        // filling one category by gutting three.
        //
        // `animation` is excluded: 29 genre-tagged items are cartoons (Betty
        // Boop), which are not documentaries whatever the tag says.
        if contentType == "documentary" {
            contentType = nil
            genre = genre ?? "Documentary"
            where_.append("i.contentType != 'animation'")
        }
        if contentType == "tv-series" {
            // The Classic TV category grid: series cards only, and only ones
            // with a real poster — a poster-less card in a curated category
            // tile reads as broken (owner direction 2026-06-11; the 28
            // poster-less series stay reachable via Browse→TV and Search).
            where_.append("i.contentType = 'tv-series'")
            where_.append("i.hasRealArtwork = 1")
        } else if contentType == "tv-special" {
            // The TV Specials grid (TV tab): standalone specials/episodes that
            // aren't (yet) folded into a series spine. Surfaced ONLY here.
            where_.append("i.contentType = 'tv-special'")
        } else if contentType == "tv-episode" {
            // Episode items are first-class (Decision 045); requestable explicitly
            // (the Clip Studio source browser) though never in general film browse.
            where_.append("i.contentType = 'tv-episode'")
        } else {
            // TV never appears in Movies/general browse — neither series cards
            // NOR tv-specials (owner directive 2026-06-18: "TV shows should
            // never appear in Movies"). Each has its own TV-tab surface.
            where_.append("i.contentType NOT IN ('tv-series','tv-special','tv-episode')")
            if let contentType { where_.append("i.contentType = ?"); binds.append(contentType) }
        }
        if hideAdult { where_.append("i.isAdult = 0") }
        // Commercials are never part of a general browse grid — only when the
        // caller explicitly asks for contentType == "commercial".
        if contentType != "commercial" { where_.append("i.contentType != 'commercial'") }
        if let decade { where_.append("i.decade = \(decade)") }
        if let year { where_.append("i.year = \(year)") }   // #15 Public Domain Day (exact year)
        var join = ""
        if let genre {
            join = "JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?"
            binds.append(genre)
        }
        let order: String
        switch sort {
        case .popular:
            // Demoted series last; designed (professional) artwork leads, then
            // popularity. Series cards have NULL popularityScore, so
            // episodesCount breaks their ties — the deepest shows surface first.
            order = """
                \(demoteOrder)\
                (i.hasRealArtwork = 1 AND COALESCE(i.artworkSource,'') != 'generated') DESC, \
                COALESCE(i.popularityScore, 0) DESC, \
                COALESCE(i.episodesCount, 0) DESC, COALESCE(i.imdbVotes, 0) DESC, i.archiveID
                """
        case .rating:
            // The IMDb community's verdict. Votes-floored ordering isn't
            // needed here (NULLS LAST keeps unrated items browsable at the
            // tail); the vote count only breaks rating ties.
            order = """
                \(demoteOrder)\
                i.imdbRating IS NULL, i.imdbRating DESC, \
                COALESCE(i.imdbVotes, 0) DESC
                """
        case .alphabetical: order = "i.title COLLATE NOCASE ASC"
        case .newest:       order = "i.year DESC"
        case .oldest:       order = "i.year ASC"
        }
        let sql = """
            SELECT j.json FROM items i
            JOIN item_json j USING(archiveID) \(join)
            WHERE \(where_.joined(separator: " AND ")) \(homeOnly ? homeAnd : "") \(typeAnd)
            ORDER BY \(order)
            LIMIT \(limit) OFFSET \(offset)
            """
        return (sql, binds)
    }

    /// Browse grid: filter by content type / decade / genre, sorted, paginated.
    func browse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                year: Int? = nil, sort: Sort = .popular, limit: Int = 60, offset: Int = 0,
                homeOnly: Bool = false) -> [Catalog.Item] {
        let (sql, binds) = browseSQL(contentType: contentType, decade: decade, genre: genre,
                                     year: year, sort: sort, limit: limit, offset: offset,
                                     homeOnly: homeOnly)
        return items(sql, binds)
    }

    /// Raw item_json strings for a browse page — the SQLite read ONLY (fast,
    /// main-confined, the single connection stays thread-safe). Hand the result
    /// to `CatalogDB.decodeItems(_:)` off the main thread so paging a big grid
    /// doesn't hitch fast scrolling (the JSON decode is the expensive part).
    func browsePageJSON(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                        sort: Sort = .popular, limit: Int = 300, offset: Int = 0) -> [String] {
        let (sql, binds) = browseSQL(contentType: contentType, decade: decade, genre: genre,
                                     year: nil, sort: sort, limit: limit, offset: offset,
                                     homeOnly: false)
        return rawColumn(sql, binds)
    }

    /// Run a query and return column-0 as raw strings (no decode).
    private func rawColumn(_ sql: String, _ binds: [String] = []) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), b, -1, SQLITE_TRANSIENT)
        }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    /// Decode item_json strings into items — pure + Sendable-safe, so it can run
    /// off the main thread (Task.detached) to keep scrolling smooth.
    static func decodeItems(_ jsons: [String]) -> [Catalog.Item] {
        let dec = JSONDecoder()
        return jsons.compactMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? dec.decode(Catalog.Item.self, from: data)
        }
    }

    /// True total matching a browse filter, ignoring the page limit — so the grid
    /// header can show the real catalog size ("36,944 titles") while only a page
    /// is loaded. Mirrors browse()'s WHERE exactly.
    func browseCount(contentType: String? = nil, decade: Int? = nil,
                     genre: String? = nil, year: Int? = nil) -> Int {
        // Same explicit-tv-series rule as browseSQL (see comment there).
        var where_: [String] = []
        var binds: [String] = []
        if contentType == "tv-series" {
            where_.append("i.contentType = 'tv-series'")
            where_.append("i.hasRealArtwork = 1")   // match browseSQL's poster gate
        } else if contentType == "tv-special" {
            where_.append("i.contentType = 'tv-special'")
        } else if contentType == "tv-episode" {
            where_.append("i.contentType = 'tv-episode'")
        } else {
            where_.append("i.contentType NOT IN ('tv-series','tv-special','tv-episode')")
            if let contentType { where_.append("i.contentType = ?"); binds.append(contentType) }
        }
        if hideAdult { where_.append("i.isAdult = 0") }
        if contentType != "commercial" { where_.append("i.contentType != 'commercial'") }
        if let decade { where_.append("i.decade = \(decade)") }
        if let year { where_.append("i.year = \(year)") }
        var join = ""
        if let genre {
            join = "JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?"
            binds.append(genre)
        }
        return scalarRows("""
            SELECT '', COUNT(*) FROM items i \(join)
            WHERE \(where_.joined(separator: " AND ")) \(typeAnd)
        """, binds).first?.1 ?? 0
    }

    /// Title/cast/director search via FTS5.
    func search(_ query: String, limit: Int = 200) -> [Catalog.Item] {
        let q = ftsQuery(query)
        guard !q.isEmpty else { return [] }
        return items("""
            SELECT j.json FROM items_fts f
            JOIN item_json j ON j.archiveID = f.archiveID
            JOIN items i ON i.archiveID = f.archiveID
            WHERE items_fts MATCH ? \(adultAnd) \(notCommercial) \(searchExclude) \(typeAnd)
            ORDER BY rank
            LIMIT \(limit)
        """, [q])
    }

    /// All TV series cards (small set — ~hundreds).
    func seriesCards() -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = 'tv-series' \(adultAnd) \(typeAnd)
            ORDER BY \(demoteOrder) i.episodesCount DESC
        """)
    }

    /// Standalone TV specials/episodes not (yet) folded into a series spine —
    /// the TV tab's "TV Specials" grid. Designed art first so the surface reads
    /// well; the long tail stays reachable by scroll. Kept OFF every film surface
    /// (see notStandaloneTV) so TV never appears in Movies.
    func tvSpecials(limit: Int = 2000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = 'tv-special' \(adultAnd) \(typeAnd)
            ORDER BY (i.hasRealArtwork = 1) DESC, i.popularityScore DESC
            LIMIT \(limit)
        """)
    }

    /// Count of standalone TV specials (TV tab card count / gating).
    func tvSpecialsCount() -> Int {
        scalarRows("""
            SELECT '', COUNT(*) FROM items i
            WHERE i.contentType = 'tv-special' \(adultAnd) \(typeAnd)
        """).first?.1 ?? 0
    }

    /// Full item by id (Detail screen).
    func item(_ archiveID: String) -> Catalog.Item? {
        items("SELECT json FROM item_json WHERE archiveID = ?", [archiveID]).first
    }

    /// Items related to one item, for "More Like This". Ranks by SAME category (contentType,
    /// so cartoons→cartoons), then closeness in YEAR (±10y), then overall POPULARITY in SQL;
    /// then prefers the SAME black-and-white-vs-color as the subject in Swift (colorMode lives
    /// in the item_json blob, not the scalar `items` table, so it can't be an ORDER BY key).
    /// Over-fetches so the color preference has room to reorder without starving the row.
    func related(to item: Catalog.Item, limit: Int = 20) -> [Catalog.Item] {
        let yearKey = item.year.map {
            "(CASE WHEN i.year IS NOT NULL AND ABS(i.year - \($0)) <= 10 THEN 1 ELSE 0 END) DESC,"
        } ?? ""
        let pool = items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = ? AND i.archiveID != ? \(adultAnd) \(typeAnd)
            ORDER BY \(yearKey) COALESCE(i.popularityScore,0) DESC, i.imdbVotes DESC
            LIMIT \(limit * 3)
        """, [item.contentType, item.archiveID])
        guard let subjectColor = item.isColor else { return Array(pool.prefix(limit)) }
        // Stable partition: same-color first, the rest after (preserves the year+popularity order).
        let same = pool.filter { $0.isColor == subjectColor }
        let other = pool.filter { $0.isColor != subjectColor }
        return Array((same + other).prefix(limit))
    }

    /// "Hidden Gems" — high craft, low traffic. Home surface → home-gated.
    ///
    /// The membership test is the `hiddenGem` column COMPUTED by
    /// `tools/build_sqlite.py::_mark_hidden_gems`, not a predicate written here.
    /// This shelf previously asked for `qualityScore >= 60 AND popularityScore
    /// <= 40`, written in June against a popularityScore that ran 0-89. When
    /// `_pop_score` was rescaled on 2026-06-29 so every scored item is >= 100,
    /// that predicate could no longer match anything, and the shelf was silently
    /// empty on every platform for five weeks — the query stayed valid, so
    /// nothing failed, it just returned zero rows. A threshold against a scale
    /// the PIPELINE owns does not belong in a client; the pipeline recomputes the
    /// cut per build (percentile) and hands us a boolean.
    ///
    /// Fallback for a DB predating the column (an app updated before its catalog
    /// refresh lands): the scale-free part of the same idea — well-rated, not
    /// famous. Deliberately omits the popularity condition rather than
    /// re-inventing a constant.
    func hiddenGems(limit: Int = 20) -> [Catalog.Item] {
        let gemAnd = hasHiddenGemColumn
            ? "i.hiddenGem = 1"
            : "i.imdbRating >= 7.0 AND i.imdbVotes BETWEEN 100 AND 5000 AND i.year IS NOT NULL"
        return items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE \(gemAnd) AND i.hasRealArtwork = 1
              \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd) \(verifiedAnd)
            ORDER BY i.imdbRating DESC, i.imdbVotes DESC LIMIT \(limit)
        """)
    }

    /// "Top Rated" — the IMDb crowd's favorites. A votes floor keeps a
    /// 9.8-with-a-dozen-votes curio from outranking a beloved classic.
    /// Home surface → home-gated, designed art only.
    func topRated(limit: Int = 24, minVotes: Int = 1000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.imdbRating IS NOT NULL AND COALESCE(i.imdbVotes, 0) >= \(minVotes)
              AND i.hasRealArtwork = 1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd) \(verifiedAnd)
            ORDER BY i.imdbRating DESC, i.imdbVotes DESC LIMIT \(limit)
        """)
    }

    // Community shelves (archive.org usage signals, tools/harvest_community_signals.py).
    // All vote-floored to RECOGNIZED films: raw community counts are dominated by
    // obscure foreign edge cases (un-IMDb'd softcore, "The Child Molester") that the
    // adult filter can't catch from metadata, but those have no IMDb votes — so the
    // same minVotes discipline as Top Rated keeps these curated shelves clean.

    /// "Most Discussed" — films the community wrote the most genuine reviews about.
    func mostDiscussed(limit: Int = 24, minVotes: Int = 1000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE COALESCE(i.numReviews, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= \(minVotes)
              AND i.hasRealArtwork = 1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd) \(verifiedAnd)
            ORDER BY i.numReviews DESC LIMIT \(limit)
        """)
    }

    /// "Community Favorites" — most-favorited on archive.org.
    func communityFavorites(limit: Int = 24, minVotes: Int = 1000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE COALESCE(i.numFavorites, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= \(minVotes)
              AND i.hasRealArtwork = 1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd) \(verifiedAnd)
            ORDER BY i.numFavorites DESC LIMIT \(limit)
        """)
    }

    /// "Watching Now" — most views in the last 30 days (current momentum).
    func watchingNow(limit: Int = 24, minVotes: Int = 1000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE COALESCE(i.views30d, 0) > 0 AND COALESCE(i.imdbVotes, 0) >= \(minVotes)
              AND i.hasRealArtwork = 1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd) \(verifiedAnd)
            ORDER BY i.views30d DESC LIMIT \(limit)
        """)
    }

    /// Most-prolific directors (≥ minFilms with designed art) → (name, count).
    /// Home surface → home-gated so we don't headline a director whose only
    /// shown films would be filtered off Home.
    func topDirectors(minFilms: Int = 3, limit: Int = 4) -> [(name: String, count: Int)] {
        scalarRows("""
            SELECT i.director, COUNT(*) c FROM items i
            WHERE i.director IS NOT NULL AND i.director != '' AND i.hasRealArtwork = 1 \(adultAnd) \(homeAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd)
            GROUP BY i.director HAVING c >= \(minFilms)
            ORDER BY c DESC, i.director LIMIT \(limit)
        """).map { (name: $0.0, count: $0.1) }
    }

    func byDirector(_ name: String, limit: Int = 20, homeOnly: Bool = false) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.director = ? AND i.hasRealArtwork = 1 \(adultAnd) \(homeOnly ? homeAnd : "") \(notCommercial) \(notStandaloneTV) \(typeAnd)
            ORDER BY i.popularityScore DESC LIMIT \(limit)
        """, [name])
    }

    /// Items featuring a person (cast OR director), via the FTS `names` column
    /// (#4). Matches all name tokens so "John Wayne" doesn't pull every John.
    func byPerson(_ name: String, limit: Int = 120) -> [Catalog.Item] {
        let tokens = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return [] }
        let q = tokens.map { "names:\"\($0)\"*" }.joined(separator: " ")
        return items("""
            SELECT j.json FROM items_fts f
            JOIN item_json j ON j.archiveID = f.archiveID
            JOIN items i ON i.archiveID = f.archiveID
            WHERE items_fts MATCH ? \(adultAnd) \(typeAnd)
            ORDER BY i.popularityScore DESC
            LIMIT \(limit)
        """, [q])
    }

    /// Items in a registered collection (CollectionsView / collection browse).
    func byCollection(_ collection: String, limit: Int = 2000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM item_collections c
            JOIN item_json j ON j.archiveID = c.archiveID
            JOIN items i ON i.archiveID = c.archiveID
            WHERE c.collection = ? \(adultAnd)
            ORDER BY i.popularityScore DESC LIMIT \(limit)
        """, [collection])
    }

    /// Items carrying a thematic keyword (Decision 046) — the keyword join
    /// table is value-indexed (idx_kw_keyword), mirroring item_genres. TV /
    /// commercials excluded so the grid matches the film-browse surfaces.
    func byKeyword(_ keyword: String, limit: Int = 2000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM item_keywords k
            JOIN item_json j ON j.archiveID = k.archiveID
            JOIN items i ON i.archiveID = k.archiveID
            WHERE k.keyword = ? \(adultAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd)
            ORDER BY i.popularityScore DESC LIMIT \(limit)
        """, [keyword])
    }

    /// Items from a studio / production company (Decision 046) — value-indexed
    /// (idx_studio_studio), mirroring byKeyword/item_genres.
    func byStudio(_ studio: String, limit: Int = 2000) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM item_studios s
            JOIN item_json j ON j.archiveID = s.archiveID
            JOIN items i ON i.archiveID = s.archiveID
            WHERE s.studio = ? \(adultAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd)
            ORDER BY i.popularityScore DESC LIMIT \(limit)
        """, [studio])
    }

    /// Count of items in a registered collection (CollectionsView card count).
    /// scalarRows returns (col0 text, col1 int) — put the count in col1.
    func collectionCount(_ collection: String) -> Int {
        scalarRows("""
            SELECT '', COUNT(*) FROM item_collections c JOIN items i USING(archiveID)
            WHERE c.collection = ? \(adultAnd)
        """, [collection]).first?.1 ?? 0
    }

    /// A random playable (non-series) item, optionally of a content type.
    func randomPlayable(contentType: String? = nil) -> Catalog.Item? {
        var where_ = ["i.contentType NOT IN ('tv-series','tv-special','tv-episode')"]
        if hideAdult { where_.append("i.isAdult = 0") }
        // Random Film must never land on a commercial; Random Commercial passes
        // contentType: "commercial" explicitly to opt back in.
        if contentType != "commercial" { where_.append("i.contentType != 'commercial'") }
        var binds: [String] = []
        if let ct = contentType { where_.append("i.contentType = ?"); binds.append(ct) }
        return items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE \(where_.joined(separator: " AND ")) \(typeAnd)
            ORDER BY RANDOM() LIMIT 1
        """, binds).first
    }

    /// A random FULL-LENGTH film (Surprise → Random Film). Restricted to feature + silent
    /// FEATURES with a runtime floor, so it never lands on a short / cartoon / newsreel / clip
    /// (the old `randomPlayable(nil)` admitted every non-TV type). Unknown-runtime features are
    /// kept (most carry a TMDb runtime; a null shouldn't exclude a real feature).
    func randomFeatureFilm() -> Catalog.Item? {
        var where_ = ["i.contentType IN ('feature-film','silent-film')",
                      "(i.runtimeSeconds IS NULL OR i.runtimeSeconds >= 2400)"]
        if hideAdult { where_.append("i.isAdult = 0") }
        return items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE \(where_.joined(separator: " AND ")) \(typeAnd)
            ORDER BY RANDOM() LIMIT 1
        """).first
    }

    /// A shuffled batch of playable commercials, for inserting as breaks between
    /// programs on a channel (docs/design/channels-tv-guide.md). Bypasses the
    /// notCommercial exclusion by querying contentType = 'commercial' directly.
    func randomCommercials(limit: Int = 12) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = 'commercial' \(adultAnd) \(typeAnd)
            ORDER BY RANDOM() LIMIT \(limit)
        """)
    }

    /// A random TV series card (Surprise → Random TV Episode lands on the show).
    func randomSeries() -> Catalog.Item? {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = 'tv-series' \(typeAnd)
            ORDER BY RANDOM() LIMIT 1
        """).first
    }

    /// A random playable (non-series) item carrying any of the given genres
    /// (Surprise → Random Sci-Fi & Horror).
    func randomByGenre(_ genres: [String]) -> Catalog.Item? {
        guard !genres.isEmpty else { return nil }
        let placeholders = genres.map { _ in "?" }.joined(separator: ",")
        return items("""
            SELECT j.json FROM items i
            JOIN item_json j USING(archiveID)
            JOIN item_genres g ON g.archiveID = i.archiveID
            WHERE g.genre IN (\(placeholders)) AND i.contentType != 'tv-series'
              \(adultAnd) \(notCommercial) \(notStandaloneTV) \(typeAnd)
            ORDER BY RANDOM() LIMIT 1
        """, genres).first
    }

    /// Resolve a TV series card by its raw slug (ContinueWatching episodes).
    func seriesCard(slug: String) -> Catalog.Item? {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.seriesID = ? AND i.contentType = 'tv-series' LIMIT 1
        """, [slug]).first
    }

    // MARK: - Facets

    func decadeCounts() -> [Int: Int] {
        var out: [Int: Int] = [:]
        // Clamp to plausible film history (cinema began ~1888; nothing
        // post-2029). Guards against bad source years surfacing nonsense eras
        // like "1060s" or future decades in the Browse-by-Era row (#8).
        for (k, v) in scalarRows("""
            SELECT i.decade, COUNT(*) FROM items i
            WHERE i.decade BETWEEN 1890 AND 2029 \(adultAnd) \(notCommercial)
            GROUP BY i.decade
        """) {
            if let d = Int(k) { out[d] = v }
        }
        return out
    }

    func topGenres(limit: Int = 24) -> [String] {
        scalarRows("""
            SELECT g.genre, COUNT(*) c FROM item_genres g
            JOIN items i USING(archiveID)
            WHERE 1=1 \(adultAnd)
            GROUP BY g.genre ORDER BY c DESC, g.genre LIMIT \(limit)
        """).map(\.0)
    }

    /// Most-used thematic keywords for the filter menu (Decision 046), mirroring
    /// topGenres. Ordered by how many films carry each.
    func topKeywords(limit: Int = 40) -> [String] {
        scalarRows("""
            SELECT k.keyword, COUNT(*) c FROM item_keywords k
            JOIN items i USING(archiveID)
            WHERE 1=1 \(adultAnd)
            GROUP BY k.keyword ORDER BY c DESC, k.keyword LIMIT \(limit)
        """).map(\.0)
    }

    /// Most-represented studios for the filter menu (Decision 046).
    func topStudios(limit: Int = 40) -> [String] {
        scalarRows("""
            SELECT s.studio, COUNT(*) c FROM item_studios s
            JOIN items i USING(archiveID)
            WHERE 1=1 \(adultAnd)
            GROUP BY s.studio ORDER BY c DESC, s.studio LIMIT \(limit)
        """).map(\.0)
    }

    var itemCount: Int { metaInt("itemCount") ?? 0 }
    var generatedAt: String? { metaString("generatedAt") }

    /// Exact number of searchable rows in the CURRENTLY-LOADED DB — a live
    /// COUNT over the FTS index, not the build-time `itemCount` meta value, so
    /// the Search screen always reflects the real database (seed vs full, and
    /// every rebuild as the catalog grows).
    var searchableCount: Int {
        scalarRows("SELECT '', COUNT(*) FROM items_fts").first?.1 ?? 0
    }

    // MARK: - FTS query hygiene

    /// Turn free user text into a safe FTS5 prefix query: keep alphanumerics,
    /// quote each token, append `*` for prefix matching.
    private func ftsQuery(_ raw: String) -> String {
        let tokens = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
