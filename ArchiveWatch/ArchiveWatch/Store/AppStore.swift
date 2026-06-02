import SwiftUI

@MainActor
@Observable
final class AppStore {

    var catalog: Catalog? {
        didSet { rebuildDerived() }
    }
    var featured: Featured?
    var loadError: String?

    /// Read-only SQLite catalog (Decision 017). Opened from the bundled
    /// seed.sqlite for instant first paint, then swapped to the downloaded
    /// full DB. The view layer migrates to querying this instead of holding
    /// the whole catalog in `visibleItems`.
    private(set) var db: CatalogDB?
    /// Bumped whenever `db` is swapped (seed → downloaded), so views relying
    /// on it can refresh via `.task(id:)`.
    private(set) var dbGeneration = 0

    // Decision 012: items in adult-content collections are filtered out by
    // default on this shared 10-foot device; a Settings toggle opts back
    // in. Persisted so the choice survives launches. Flipping it re-derives
    // every shelf/grid through the same single chokepoint (rebuildDerived)
    // as a catalog assignment, so the filter can never be half-applied.
    var hideAdultContent: Bool = AppStore.loadHideAdultDefault() {
        didSet {
            UserDefaults.standard.set(hideAdultContent, forKey: Self.hideAdultKey)
            db?.hideAdult = hideAdultContent
            dbGeneration += 1            // nudge db-backed views to re-query
            rebuildDerived()
        }
    }
    private static let hideAdultKey = "hideAdultContent"
    private static func loadHideAdultDefault() -> Bool {
        // First launch (no stored value) → ON. Default-deny for a TV.
        guard UserDefaults.standard.object(forKey: hideAdultKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hideAdultKey)
    }

    /// The catalog's items with the adult filter already applied. THIS is
    /// what every view should read instead of `catalog.items` directly, so
    /// the Decision 012 filter cannot be bypassed by a view that forgets.
    private(set) var visibleItems: [Catalog.Item] = []

    // Derived structures, rebuilt once per catalog assignment so
    // downstream views never re-filter 31k items on body recompute.
    // The old pattern — computed `items(forShelf:)` scanning catalog
    // items per call — cost 670k iterations per HomeView render (21
    // shelves × 31k items). Now it's an O(1) dict lookup.
    private(set) var shelfMembers: [String: [Catalog.Item]] = [:]
    private(set) var availableDecades: [Int] = []
    private(set) var decadeCounts: [Int: Int] = [:]
    private(set) var topGenres: [String] = []
    /// Everything except tv-series cards — what Browse's grid shows.
    private(set) var browseableItems: [Catalog.Item] = []
    /// Just the series cards — for future series-specific entry points.
    private(set) var seriesCards: [Catalog.Item] = []

    private func rebuildDerived() {
        guard let allItems = catalog?.items else {
            shelfMembers = [:]; availableDecades = []; decadeCounts = [:]
            topGenres = []; browseableItems = []; seriesCards = []
            visibleItems = []
            return
        }

        // Apply the Decision 012 adult filter ONCE, here, so every derived
        // structure below — and `visibleItems` that views read — is built
        // from the same already-filtered set.
        let markers = adultMarkers
        let filtered: [Catalog.Item] = (hideAdultContent && !markers.isEmpty)
            ? allItems.filter { !Self.isAdult($0, markers: markers) }
            : allItems
        // Collapse duplicate uploads of the same film — Archive often has the
        // same title 3-5x (original, colorized, HD, iPod...). They share an
        // IMDb id, so we surface the single best copy and hide the rest from
        // every derived list at once. Catalog data is untouched (the alternate
        // uploads remain available); only the displayed set is deduped.
        let items = Self.dedupedByIMDb(filtered)
        self.visibleItems = items

        // Split series cards from everything else — they have different
        // semantics (no direct playable URL, route to SeriesDetailView).
        var series: [Catalog.Item] = []
        var regular: [Catalog.Item] = []
        var decadeTally: [Int: Int] = [:]
        var genreCounts: [String: Int] = [:]
        var shelves: [String: [Catalog.Item]] = [:]

        for it in items {
            // A real series card has a seriesID set by the exporter.
            // Items with contentType == "tv-series" but no seriesID
            // are individual TV-episode uploads that didn't pass
            // clustering (singletons, uncertain titles); those belong
            // in the regular pool so they appear in browse/search as
            // single playable items rather than empty "series".
            if it.contentType == "tv-series", it.seriesID != nil {
                series.append(it)
            } else {
                regular.append(it)
            }
            if let d = it.decade { decadeTally[d, default: 0] += 1 }
            for g in it.genres where !g.isEmpty {
                genreCounts[g, default: 0] += 1
            }
            for s in it.shelves {
                shelves[s, default: []].append(it)
            }
        }

        self.seriesCards = series
        self.browseableItems = regular
        self.decadeCounts = decadeTally
        self.availableDecades = decadeTally.keys.sorted()
        self.topGenres = genreCounts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(24)
            .map { $0.key }
        self.shelfMembers = shelves
    }

    /// Keep the best single item per IMDb id; items without an IMDb id are all
    /// kept (we can't tell them apart). "Best" prefers a designed poster, full
    /// enrichment, a playable MP4, then vote count — with archiveID as a final
    /// stable tiebreak so the chosen copy never flickers between launches.
    static func dedupedByIMDb(_ items: [Catalog.Item]) -> [Catalog.Item] {
        func score(_ i: Catalog.Item) -> (Int, Int, String) {
            var r = 0
            if i.hasDesignedArtwork { r += 8 }
            if i.enrichmentTier == "fullyEnriched" { r += 4 }
            if (i.downloadURL ?? "").lowercased().hasSuffix(".mp4") { r += 2 }
            if i.runtimeSeconds != nil { r += 1 }
            return (r, i.imdbVotes ?? 0, i.archiveID)
        }
        var best: [String: Catalog.Item] = [:]
        for it in items {
            guard let id = it.imdbID, !id.isEmpty else { continue }
            if let cur = best[id] {
                if score(it) > score(cur) { best[id] = it }
            } else {
                best[id] = it
            }
        }
        let winners = Set(best.values.map(\.archiveID))
        return items.filter { it in
            guard let id = it.imdbID, !id.isEmpty else { return true }
            return winners.contains(it.archiveID)
        }
    }

    func loadBundledData() async {
        // STEP 1 — synchronous bundle load. Unblocks the UI within a
        // second; the user never sees "Loading catalog…" hang waiting
        // on the actor hop or a network fetch. Before this refactor,
        // an empty disk cache + slow JSON decode in the actor could
        // leave the spinner up indefinitely.
        //
        // IMPORTANT: featured is loaded FIRST so CategoryTilesRow +
        // accent colors are populated by the time Home first renders.
        // The catalog assignment triggers rebuildDerived() which can
        // take 100ms+ on the full catalog; if featured isn't set yet,
        // Home flashes with no categories during that blocking
        // rebuild and the user experiences "categories don't show
        // until catalog loads".
        let bundleStart = Date()
        do {
            // featured.json is small (categories + shelf metadata) and stays
            // JSON. The catalog ITSELF is no longer decoded into memory — the
            // SQLite DB (seed → downloaded full) is the source now (Decision
            // 017). This is the memory win: we never hold ~26k full items in RAM.
            featured = try CatalogLoader.loadFeatured()
            print("[AppStore] featured loaded in \(String(format: "%.2fs", Date().timeIntervalSince(bundleStart)))")
            // Open the bundled seed DB for instant first paint.
            if let seed = Bundle.main.path(forResource: "seed", ofType: "sqlite"),
               let seedDB = CatalogDB(path: seed) {
                swapDB(seedDB)
                print("[AppStore] seed.sqlite: \(seedDB.itemCount) items")
            } else {
                loadError = "Missing bundled seed.sqlite"
                return
            }
        } catch CatalogLoader.LoadError.bundleMissing(let name) {
            loadError = "Missing bundled resource: \(name)"
            return
        } catch CatalogLoader.LoadError.decodeFailed(let name, let err) {
            loadError = "Failed to decode \(name): \(err.localizedDescription)"
            return
        } catch {
            loadError = error.localizedDescription
            return
        }

        // Full SQLite catalog (Decision 017). Open the cached DB if we
        // already downloaded one (upgrades from the bundled seed), then fetch a
        // fresh copy from the release in the background and swap it in.
        Task { [weak self] in
            if let cached = await CatalogRefreshService.shared.cachedDatabasePath(),
               let fullDB = CatalogDB(path: cached) {
                await MainActor.run {
                    guard let self else { return }
                    if fullDB.itemCount >= (self.db?.itemCount ?? 0) { self.swapDB(fullDB) }
                }
            }
            if let path = await CatalogRefreshService.shared.downloadDatabase(),
               let fullDB = CatalogDB(path: path) {
                await MainActor.run {
                    guard let self else { return }
                    if fullDB.itemCount >= (self.db?.itemCount ?? 0) {
                        self.swapDB(fullDB)
                        print("[AppStore] swapped to full DB: \(fullDB.itemCount) items")
                    }
                }
            }
        }
    }

    /// Items assigned to the given shelf id. Prefers the SQLite DB (Decision
    /// 017) when available, falling back to the precomputed JSON dict during
    /// the migration.
    func items(forShelf shelfID: String) -> [Catalog.Item] {
        if let db { return db.shelf(shelfID) }
        return shelfMembers[shelfID] ?? []
    }

    // MARK: - SQLite-backed queries (Decision 017)
    // Thin wrappers so views call the store; the store owns the db + adult
    // state. Each returns [] when the db isn't open yet (first frames before
    // the seed loads), which views render as an empty state.

    func swapDB(_ newDB: CatalogDB) {
        newDB.hideAdult = hideAdultContent
        db = newDB
        dbGeneration += 1
    }

    func dbBrowse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                  sort: CatalogDB.Sort = .popular, limit: Int = 60, offset: Int = 0) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre,
                   sort: sort, limit: limit, offset: offset) ?? []
    }
    func dbSearch(_ q: String) -> [Catalog.Item] { db?.search(q) ?? [] }
    func dbSeriesCards() -> [Catalog.Item] { db?.seriesCards() ?? [] }
    func dbItem(_ id: String) -> Catalog.Item? { db?.item(id) }
    func dbRelated(to item: Catalog.Item) -> [Catalog.Item] { db?.related(to: item) ?? [] }
    func dbDecadeCounts() -> [Int: Int] { db?.decadeCounts() ?? [:] }
    func dbTopGenres() -> [String] { db?.topGenres() ?? [] }
    func dbItemsByIDs(_ ids: [String]) -> [Catalog.Item] { db?.itemsByIDs(ids) ?? [] }
    func dbHiddenGems() -> [Catalog.Item] { db?.hiddenGems() ?? [] }
    func dbTopDirectors() -> [(name: String, count: Int)] { db?.topDirectors() ?? [] }
    func dbByDirector(_ name: String) -> [Catalog.Item] { db?.byDirector(name) ?? [] }
    func dbByCollection(_ id: String, limit: Int = 2000) -> [Catalog.Item] { db?.byCollection(id, limit: limit) ?? [] }
    func dbCollectionCount(_ id: String) -> Int { db?.collectionCount(id) ?? 0 }
    func dbRandomPlayable(contentType: String? = nil) -> Catalog.Item? { db?.randomPlayable(contentType: contentType) }
    func dbSeriesCard(slug: String) -> Catalog.Item? { db?.seriesCard(slug: slug) }

    /// Catalog readiness: true once any DB (seed or full) is open. Replaces the
    /// old `catalog != nil` gate now that the JSON load is gone.
    var isReady: Bool { db != nil }

    /// Accent color for a category, parsed from `featured.json`.
    func accentColor(forCategory id: String?) -> Color {
        guard let id, let hex = featured?.category(id: id)?.accent else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }

    // MARK: - Adult-content filter (Decision 012)

    /// Adult-content markers from `featured.json.adultCollections`, lowercased.
    /// We deliberately drop the `"fav-"` entry: it's a per-user favorites
    /// prefix that nearly every popular title carries, not an adult signal —
    /// treating it as one would hide most of the catalog. Falls back to a
    /// built-in marker list if `featured.json` omits the field.
    private var adultMarkers: [String] {
        let raw = featured?.adultCollections
            ?? ["pron", "adult", "erotica", "sexploitation", "nudism", "mature-content"]
        return raw.map { $0.lowercased() }.filter { $0 != "fav-" }
    }

    /// True when any of the item's collection ids contains an adult marker.
    private static func isAdult(_ item: Catalog.Item, markers: [String]) -> Bool {
        item.collections.contains { col in
            let c = col.lowercased()
            return markers.contains { c.contains($0) }
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double( v        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
