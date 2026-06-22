#if os(iOS)
import SwiftUI
import Observation

// iOS app store — the catalog/source-of-truth layer. Mirrors the tvOS AppStore's
// load sequence but only the platform-neutral parts: load featured.json, open the
// bundled seed.sqlite for instant first paint, then swap in the downloaded full DB
// (Decision 017). All catalog reads go through the shared Core `CatalogDB`.
// Exposes the `db*`-prefixed surface the shared ContinuousPlayback engine calls,
// so the F4 queue works on iOS unchanged (resolves `AppStore` to this type).
@MainActor
@Observable
final class AppStore {
    private(set) var db: CatalogDB?
    private(set) var featured: Featured?
    /// Bumped on every DB swap (seed → full) so views re-query.
    private(set) var dbVersion = 0
    private(set) var isReady = false
    var loadError: String?

    // Filters (settings-controlled). Default-deny mature content (Decision 012).
    var hideAdultContent: Bool = {
        UserDefaults.standard.object(forKey: "hideAdultContent") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(hideAdultContent, forKey: "hideAdultContent")
            db?.hideAdult = hideAdultContent
            dbVersion += 1
        }
    }

    // #4: content categories the user has hidden in Settings. Same UserDefaults
    // key + type mapping as tvOS, so the preference carries the same meaning on
    // both platforms (the value itself is per-device).
    var hiddenCategories: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "hiddenCategories") ?? [])
    }() {
        didSet {
            UserDefaults.standard.set(Array(hiddenCategories), forKey: "hiddenCategories")
            db?.hiddenTypes = Self.contentTypes(for: hiddenCategories)
            dbVersion += 1
        }
    }
    /// A hidden "tv-series" category covers both series cards and tv-specials.
    static func contentTypes(for categories: Set<String>) -> Set<String> {
        var types = categories
        if categories.contains("tv-series") { types.insert("tv-special") }
        return types
    }

    /// #17: completed titles are hidden from Home shelves + hero by default;
    /// a Settings toggle shows them again. Search/Browse/Library are unaffected.
    var hideWatchedOnHome: Bool = {
        UserDefaults.standard.object(forKey: "hideWatchedOnHome") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(hideWatchedOnHome, forKey: "hideWatchedOnHome")
            dbVersion += 1
        }
    }

    /// Completed titles (≥95%), set from SwiftData WatchProgress by the views that
    /// own the model context. Feeds Continue-Watching hiding + the F4 engine.
    var completedArchiveIDs: Set<String> = []

    /// Movie autoplay (#10): what plays after a movie ends. Default off; the
    /// player's MovieAutoplayQueue reads this. Episodes binge-advance regardless.
    var autoplayMode: AutoplayMode = {
        AutoplayMode(rawValue: UserDefaults.standard.string(forKey: "autoplayMode") ?? "") ?? .off
    }() {
        didSet { UserDefaults.standard.set(autoplayMode.rawValue, forKey: "autoplayMode") }
    }

    // Channels: vintage commercials between programs (tvOS parity; the
    // per-ad length CAP remains tvOS-only — see PARITY notes).
    var channelCommercialBreaks: Bool = UserDefaults.standard.object(
        forKey: "channelCommercialBreaks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(channelCommercialBreaks,
                                           forKey: "channelCommercialBreaks") }
    }

    // MARK: load

    func load() async {
        do { featured = try CatalogLoader.loadFeatured() }
        catch { /* featured is optional chrome; keep going */ }

        if let seed = Bundle.main.path(forResource: "seed", ofType: "sqlite"),
           let seedDB = CatalogDB(path: seed) {
            swap(seedDB)
            isReady = true
        }
        // Upgrade to a cached/downloaded full DB off the first paint.
        if let cached = await CatalogRefreshService.shared.cachedDatabasePath(),
           let full = CatalogDB(path: cached) {
            swap(full)
            isReady = true
        }
        if let path = await CatalogRefreshService.shared.downloadDatabase(),
           let full = CatalogDB(path: path) {
            swap(full)
            isReady = true
        }
        if db == nil { loadError = "Could not open the catalog." }
    }

    private func swap(_ newDB: CatalogDB) {
        newDB.hideAdult = hideAdultContent
        newDB.hiddenTypes = Self.contentTypes(for: hiddenCategories)
        newDB.demotedIDs = Set(featured?.deprioritizedSeries ?? [])
        db = newDB
        dbVersion += 1
    }

    // MARK: catalog reads (thin pass-throughs to Core)

    func browse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                year: Int? = nil, sort: CatalogDB.Sort = .popular,
                limit: Int = 60, offset: Int = 0) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre, year: year,
                   sort: sort, limit: limit, offset: offset) ?? []
    }
    func browseCount(contentType: String? = nil, decade: Int? = nil,
                     genre: String? = nil, year: Int? = nil) -> Int {
        db?.browseCount(contentType: contentType, decade: decade, genre: genre, year: year) ?? 0
    }
    func search(_ q: String) -> [Catalog.Item] { db?.search(q) ?? [] }
    func byPerson(_ name: String) -> [Catalog.Item] { db?.byPerson(name) ?? [] }
    func item(_ id: String) -> Catalog.Item? { db?.item(id) }
    func itemsByIDs(_ ids: [String]) -> [Catalog.Item] { db?.itemsByIDs(ids) ?? [] }
    func related(to item: Catalog.Item) -> [Catalog.Item] { db?.related(to: item) ?? [] }
    func seriesCards() -> [Catalog.Item] { db?.seriesCards() ?? [] }
    func tvSpecialsCount() -> Int { db?.tvSpecialsCount() ?? 0 }
    func hiddenGems() -> [Catalog.Item] { db?.hiddenGems() ?? [] }
    func topRated() -> [Catalog.Item] { db?.topRated() ?? [] }
    func mostDiscussed() -> [Catalog.Item] { db?.mostDiscussed() ?? [] }
    func communityFavorites() -> [Catalog.Item] { db?.communityFavorites() ?? [] }
    func watchingNow() -> [Catalog.Item] { db?.watchingNow() ?? [] }
    func byCollection(_ id: String) -> [Catalog.Item] { db?.byCollection(id) ?? [] }
    func decadeCounts() -> [Int: Int] { db?.decadeCounts() ?? [:] }
    func topDirectors() -> [(name: String, count: Int)] { db?.topDirectors() ?? [] }
    func byDirector(_ name: String) -> [Catalog.Item] { db?.byDirector(name, homeOnly: true) ?? [] }
    func topGenres() -> [String] { db?.topGenres() ?? [] }
    func randomPlayable(contentType: String? = nil) -> Catalog.Item? {
        db?.randomPlayable(contentType: contentType)
    }
    func randomSeries() -> Catalog.Item? { db?.randomSeries() }
    func randomCommercials(limit: Int = 12) -> [Catalog.Item] {
        db?.randomCommercials(limit: limit) ?? []
    }
    func randomByGenre(_ genres: [String]) -> Catalog.Item? { db?.randomByGenre(genres) }

    /// Items for a Home shelf, resolved through the prebuilt `item_shelves`
    /// mapping (Decision 017) by the shelf's id — the build assigns each shelf
    /// its real Archive-collection / curated members. The old path browsed by
    /// `contentType`, which made every "feature-film" shelf return the SAME
    /// popular list (the duplicate-shelf bug on iOS Home).
    func items(forShelf shelfID: String) -> [Catalog.Item] { db?.shelf(shelfID) ?? [] }

    /// Drop already-completed titles from a Home list (#17). No-op until a view
    /// populates `completedArchiveIDs` from SwiftData WatchProgress, or when the
    /// user turns the Settings toggle off.
    func filteringWatched(_ items: [Catalog.Item]) -> [Catalog.Item] {
        guard hideWatchedOnHome, !completedArchiveIDs.isEmpty else { return items }
        return items.filter { !completedArchiveIDs.contains($0.archiveID) }
    }

    // MARK: shared ContinuousPlayback engine surface (db*-prefixed, matches tvOS)
    func dbRandomPlayable() -> Catalog.Item? { db?.randomPlayable() }
    func dbBrowse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                  sort: CatalogDB.Sort = .popular, limit: Int = 60,
                  homeOnly: Bool = false) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre,
                   sort: sort, limit: limit, homeOnly: homeOnly) ?? []
    }
}

#endif
