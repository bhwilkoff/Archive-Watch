import SwiftUI

@MainActor
@Observable
final class AppStore {

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

    // Decision 012: adult-content items are hidden by default on this shared
    // 10-foot device; a Settings toggle opts back in. The filter is an isAdult
    // column + WHERE clause in the DB (CatalogDB.hideAdult), computed at build
    // from featured.json.adultCollections — set on DB swap + toggle. Bumping
    // dbGeneration re-queries every db-backed view.
    var hideAdultContent: Bool = AppStore.loadHideAdultDefault() {
        didSet {
            UserDefaults.standard.set(hideAdultContent, forKey: Self.hideAdultKey)
            db?.hideAdult = hideAdultContent
            dbGeneration += 1
        }
    }
    // #4: content categories the user has hidden in Settings. Maps to the
    // CatalogDB type filter, applied app-wide. Persisted; re-queries on change.
    var hiddenCategories: Set<String> = AppStore.loadHiddenCategories() {
        didSet {
            UserDefaults.standard.set(Array(hiddenCategories), forKey: Self.hiddenCategoriesKey)
            db?.hiddenTypes = Self.contentTypes(for: hiddenCategories)
            dbGeneration += 1
        }
    }
    private static let hiddenCategoriesKey = "hiddenCategories"
    private static func loadHiddenCategories() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenCategoriesKey) ?? [])
    }
    /// A hidden "tv-series" category covers both series cards and tv-specials.
    static func contentTypes(for categories: Set<String>) -> Set<String> {
        var types = categories
        if categories.contains("tv-series") { types.insert("tv-special") }
        return types
    }

    private static let hideAdultKey = "hideAdultContent"
    private static func loadHideAdultDefault() -> Bool {
        // First launch (no stored value) → ON. Default-deny for a TV.
        guard UserDefaults.standard.object(forKey: hideAdultKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hideAdultKey)
    }

    // #17 (tvOS-DESIGN §10.3): completed titles are hidden from Home shelves +
    // hero by default; a Settings toggle shows them again. They stay everywhere
    // else (Search/Browse/Library). Continue Watching is exempt — it shows
    // in-progress, not completed (it filters !isComplete itself).
    //
    // Watched state lives in SwiftData (WatchProgress), separate from the SQLite
    // catalog, so the set of completed archiveIDs is fed in by an invisible
    // @Query-owning view (WatchedHomeSync) — keeping @Query out of HomeView to
    // avoid the macro cascade. Filtering happens app-side in HomeView.
    var hideWatchedOnHome: Bool = AppStore.loadHideWatchedDefault() {
        didSet { UserDefaults.standard.set(hideWatchedOnHome, forKey: Self.hideWatchedKey) }
    }
    /// archiveIDs the user has finished watching. Maintained by WatchedHomeSync.
    var completedArchiveIDs: Set<String> = []

    private static let hideWatchedKey = "hideWatchedOnHome"
    private static func loadHideWatchedDefault() -> Bool {
        guard UserDefaults.standard.object(forKey: hideWatchedKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hideWatchedKey)
    }

    // #10: global autoplay-next default for the movie player (off by default —
    // the user opts in). A per-video override lives in the player's transport.
    var autoplayMode: AutoplayMode = AppStore.loadAutoplayMode() {
        didSet { UserDefaults.standard.set(autoplayMode.rawValue, forKey: Self.autoplayKey) }
    }
    private static let autoplayKey = "autoplayMode"
    private static func loadAutoplayMode() -> AutoplayMode {
        AutoplayMode(rawValue: UserDefaults.standard.string(forKey: autoplayKey) ?? "") ?? .off
    }

    /// Drop completed titles from a Home list when the setting is on. No-op
    /// otherwise. Used by HomeView's hero + shelves.
    func filteringWatched(_ items: [Catalog.Item]) -> [Catalog.Item] {
        guard hideWatchedOnHome, !completedArchiveIDs.isEmpty else { return items }
        return items.filter { !completedArchiveIDs.contains($0.archiveID) }
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

    /// Items assigned to the given shelf id (SQLite, Decision 017).
    func items(forShelf shelfID: String) -> [Catalog.Item] {
        db?.shelf(shelfID) ?? []
    }

    // MARK: - SQLite-backed queries (Decision 017)
    // Thin wrappers so views call the store; the store owns the db + adult
    // state. Each returns [] when the db isn't open yet (first frames before
    // the seed loads), which views render as an empty state.

    func swapDB(_ newDB: CatalogDB) {
        newDB.hideAdult = hideAdultContent
        newDB.hiddenTypes = Self.contentTypes(for: hiddenCategories)
        db = newDB
        dbGeneration += 1
    }

    func dbBrowse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                  year: Int? = nil, sort: CatalogDB.Sort = .popular, limit: Int = 60,
                  offset: Int = 0, homeOnly: Bool = false) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre, year: year,
                   sort: sort, limit: limit, offset: offset, homeOnly: homeOnly) ?? []
    }
    func dbSearch(_ q: String) -> [Catalog.Item] { db?.search(q) ?? [] }
    func dbSeriesCards() -> [Catalog.Item] { db?.seriesCards() ?? [] }
    func dbItem(_ id: String) -> Catalog.Item? { db?.item(id) }
    func dbRelated(to item: Catalog.Item) -> [Catalog.Item] { db?.related(to: item) ?? [] }
    func dbDecadeCounts() -> [Int: Int] { db?.decadeCounts() ?? [:] }
    /// Live count of searchable titles in the loaded DB (tracks seed→full + rebuilds).
    var dbSearchableCount: Int { db?.searchableCount ?? 0 }
    func dbTopGenres() -> [String] { db?.topGenres() ?? [] }
    func dbItemsByIDs(_ ids: [String]) -> [Catalog.Item] { db?.itemsByIDs(ids) ?? [] }
    func dbHiddenGems() -> [Catalog.Item] { db?.hiddenGems() ?? [] }
    func dbTopDirectors() -> [(name: String, count: Int)] { db?.topDirectors() ?? [] }
    func dbByDirector(_ name: String, homeOnly: Bool = false) -> [Catalog.Item] { db?.byDirector(name, homeOnly: homeOnly) ?? [] }
    func dbByPerson(_ name: String) -> [Catalog.Item] { db?.byPerson(name) ?? [] }   // #4
    func dbByCollection(_ id: String, limit: Int = 2000) -> [Catalog.Item] { db?.byCollection(id, limit: limit) ?? [] }
    func dbCollectionCount(_ id: String) -> Int { db?.collectionCount(id) ?? 0 }
    func dbRandomPlayable(contentType: String? = nil) -> Catalog.Item? { db?.randomPlayable(contentType: contentType) }
    func dbRandomSeries() -> Catalog.Item? { db?.randomSeries() }
    func dbRandomByGenre(_ genres: [String]) -> Catalog.Item? { db?.randomByGenre(genres) }
    func dbSeriesCard(slug: String) -> Catalog.Item? { db?.seriesCard(slug: slug) }

    /// Catalog readiness: true once any DB (seed or full) is open. Replaces the
    /// old `catalog != nil` gate now that the JSON load is gone.
    var isReady: Bool { db != nil }

    /// Accent color for a category, parsed from `featured.json`.
    func accentColor(forCategory id: String?) -> Color {
        guard let id, let hex = featured?.category(id: id)?.accent else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
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
