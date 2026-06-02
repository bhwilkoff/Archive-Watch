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

    enum Sort { case popular, alphabetical, newest, oldest }

    /// Opens the DB read-only. Returns nil if the file is missing/corrupt.
    init?(path: String) {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            if let h { sqlite3_close(h) }
            return nil
        }
        self.handle = h
        // Fail fast if it isn't actually our schema.
        guard metaInt("itemCount") != nil else {
            sqlite3_close(h); return nil
        }
    }

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

    // MARK: - Queries the views use

    /// One Home shelf, in stored position order.
    func shelf(_ shelfID: String, limit: Int = 60) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM item_shelves s
            JOIN item_json j USING(archiveID)
            JOIN items i USING(archiveID)
            WHERE s.shelfID = ?1
            ORDER BY s.position
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

    /// Browse grid: filter by content type / decade / genre, sorted, paginated.
    func browse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                sort: Sort = .popular, limit: Int = 60, offset: Int = 0) -> [Catalog.Item] {
        var where_ = ["i.contentType != 'tv-series'"]
        if hideAdult { where_.append("i.isAdult = 0") }
        var binds: [String] = []
        if let contentType { where_.append("i.contentType = ?"); binds.append(contentType) }
        if let decade { where_.append("i.decade = \(decade)") }
        var join = ""
        if let genre {
            join = "JOIN item_genres g ON g.archiveID = i.archiveID AND g.genre = ?"
            binds.append(genre)
        }
        let order: String
        switch sort {
        case .popular:      order = "i.popularityScore DESC, i.imdbVotes DESC"
        case .alphabetical: order = "i.title COLLATE NOCASE ASC"
        case .newest:       order = "i.year DESC"
        case .oldest:       order = "i.year ASC"
        }
        return items("""
            SELECT j.json FROM items i
            JOIN item_json j USING(archiveID) \(join)
            WHERE \(where_.joined(separator: " AND "))
            ORDER BY \(order)
            LIMIT \(limit) OFFSET \(offset)
        """, binds)
    }

    /// Title/cast/director search via FTS5.
    func search(_ query: String, limit: Int = 200) -> [Catalog.Item] {
        let q = ftsQuery(query)
        guard !q.isEmpty else { return [] }
        return items("""
            SELECT j.json FROM items_fts f
            JOIN item_json j ON j.archiveID = f.archiveID
            JOIN items i ON i.archiveID = f.archiveID
            WHERE items_fts MATCH ? \(adultAnd)
            ORDER BY rank
            LIMIT \(limit)
        """, [q])
    }

    /// All TV series cards (small set — ~hundreds).
    func seriesCards() -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = 'tv-series'
            ORDER BY i.episodesCount DESC
        """)
    }

    /// Full item by id (Detail screen).
    func item(_ archiveID: String) -> Catalog.Item? {
        items("SELECT json FROM item_json WHERE archiveID = ?", [archiveID]).first
    }

    /// Items related to one item (same content type), for "More Like This".
    func related(to item: Catalog.Item, limit: Int = 20) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.contentType = ? AND i.archiveID != ? \(adultAnd)
            ORDER BY i.popularityScore DESC
            LIMIT \(limit)
        """, [item.contentType, item.archiveID])
    }

    /// "Hidden Gems" — high craft, low traffic.
    func hiddenGems(limit: Int = 20) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.hasRealArtwork = 1 AND i.qualityScore >= 60
              AND i.popularityScore <= 40 \(adultAnd)
            ORDER BY i.qualityScore DESC LIMIT \(limit)
        """)
    }

    /// Most-prolific directors (≥ minFilms with designed art) → (name, count).
    func topDirectors(minFilms: Int = 3, limit: Int = 4) -> [(name: String, count: Int)] {
        scalarRows("""
            SELECT i.director, COUNT(*) c FROM items i
            WHERE i.director IS NOT NULL AND i.director != '' AND i.hasRealArtwork = 1 \(adultAnd)
            GROUP BY i.director HAVING c >= \(minFilms)
            ORDER BY c DESC, i.director LIMIT \(limit)
        """).map { (name: $0.0, count: $0.1) }
    }

    func byDirector(_ name: String, limit: Int = 20) -> [Catalog.Item] {
        items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE i.director = ? AND i.hasRealArtwork = 1 \(adultAnd)
            ORDER BY i.popularityScore DESC LIMIT \(limit)
        """, [name])
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
        var where_ = ["i.contentType != 'tv-series'"]
        if hideAdult { where_.append("i.isAdult = 0") }
        var binds: [String] = []
        if let ct = contentType { where_.append("i.contentType = ?"); binds.append(ct) }
        return items("""
            SELECT j.json FROM items i JOIN item_json j USING(archiveID)
            WHERE \(where_.joined(separator: " AND "))
            ORDER BY RANDOM() LIMIT 1
        """, binds).first
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
        for (k, v) in scalarRows("SELECT i.decade, COUNT(*) FROM items i WHERE i.decade IS NOT NULL \(adultAnd) GROUP BY i.decade") {
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

    var itemCount: Int { metaInt("itemCount") ?? 0 }
    var generatedAt: String? { metaString("generatedAt") }

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
