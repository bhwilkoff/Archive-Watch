// Shared by iOS and macOS (pointer/AppKit sibling of UIKit; tvOS has its own variant).
#if os(iOS) || os(macOS)
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
    /// True once the FULL catalog DB (not just the bundled seed) is loaded. The seed has no
    /// tv-episode items and only a slice of the catalog, so Creation Studio's "Add a Clip" (TV
    /// Episodes filter, live stock-shot generation) is empty/tiny until this flips.
    private(set) var hasFullCatalog = false
    private var loadTask: Task<Void, Never>?
    var loadError: String?

    /// A title queued to open in Creation Studio's mark-in/out editor — set by Detail's
    /// "Open in Creation Studio" share action, consumed once by a freshly-opened editor window.
    var pendingClipItem: Catalog.Item?

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

    /// Idempotent + coalescing: once the full catalog is loaded this returns immediately; concurrent
    /// callers (the main window AND the Creation Studio editor both kick this) share one in-flight
    /// load; and if the full DB hasn't landed yet (e.g. a slow/failed download) the task is cleared
    /// so the next caller retries instead of being stuck on the seed forever.
    func load() async {
        if hasFullCatalog { return }
        if let t = loadTask { await t.value; return }
        let t = Task { await self.performLoad() }
        loadTask = t
        await t.value
        if !hasFullCatalog { loadTask = nil }   // allow a retry until the full DB is in
    }

    private func performLoad() async {
        do { featured = try CatalogLoader.loadFeatured() }
        catch { /* featured is optional chrome; keep going */ }

        // FIRST PAINT: prefer the CACHED full catalog over the bundled seed.
        //
        // Opening either is `sqlite3_open_v2` plus one `itemCount` query — the
        // 165 MB is paged in on demand, never read up front — so the cached DB
        // is no slower to open. Painting the seed first and swapping a moment
        // later is the "double loading" the owner reported: the hero row and
        // Continue Watching render from the seed's 2,797 items, then re-render
        // from ~27k, and a recently-watched film absent from the seed pops in on
        // the second pass. The seed is for the FIRST launch, before any cache.
        if db == nil, let cached = await CatalogRefreshService.shared.cachedDatabasePath(),
           let full = CatalogDB(path: cached) {
            swap(full, path: cached)
            isReady = true
            hasFullCatalog = true
            print("[AppStore] first paint from cached full DB: \(full.itemCount) items")
        }
        if db == nil, let seed = Bundle.main.path(forResource: "seed", ofType: "sqlite"),
           let seedDB = CatalogDB(path: seed) {
            swap(seedDB, path: seed)
            isReady = true
            print("[AppStore] first paint from bundled seed: \(seedDB.itemCount) items")
        }
        // `onlyIfChanged: true` — the plain call returns the CACHED path on a
        // 304, i.e. the file already open above, so this swapped a THIRD time
        // and bumped dbVersion for content that had not changed at all.
        if let path = await CatalogRefreshService.shared.downloadDatabase(onlyIfChanged: true),
           let full = CatalogDB(path: path) {
            swap(full, path: path)
            isReady = true
            hasFullCatalog = true
            print("[AppStore] swapped to downloaded DB: \(full.itemCount) items")
        }
        if db == nil { loadError = "Could not open the catalog." }
    }

    /// Re-check the release for a newer catalog and swap it in. `load()` is
    /// memoized behind `loadTask` and short-circuits once `hasFullCatalog` is
    /// true, so it runs exactly once per process — without this, an app
    /// resumed after days serves its cold-launch catalog forever. Throttled by
    /// the service's TTL and a no-op when the release is unchanged.
    func refreshCatalogIfStale() async {
        guard hasFullCatalog else { return }
        // Editorial config first — swap() reads `featured` for demotedIDs.
        if let fresh = await CatalogLoader.refreshFeatured() {
            featured = fresh
            if let db {                       // no new DB? re-apply to the live one
                db.demotedIDs = Set(fresh.deprioritizedSeries ?? [])
                dbVersion += 1
            }
        }
        guard let path = await CatalogRefreshService.shared.refreshIfStale(),
              let full = CatalogDB(path: path) else { return }
        swap(full, path: path)
    }

    /// The file currently open as `db` — a swap to the SAME file is a no-op,
    /// since `dbVersion` re-queries every view and reshuffles the shelves for
    /// content that has not changed.
    private(set) var dbPath: String?

    private func swap(_ newDB: CatalogDB, path: String? = nil) {
        if let path, path == dbPath, db != nil { return }
        newDB.hideAdult = hideAdultContent
        newDB.hiddenTypes = Self.contentTypes(for: hiddenCategories)
        newDB.demotedIDs = Set(featured?.deprioritizedSeries ?? [])
        db = newDB
        dbPath = path
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
    func seriesCard(seriesID: String) -> Catalog.Item? { db?.seriesCard(slug: seriesID) }
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
    func topKeywords() -> [String] { db?.topKeywords() ?? [] }       // Decision 046
    func topStudios() -> [String] { db?.topStudios() ?? [] }         // Decision 046
    func byKeyword(_ keyword: String) -> [Catalog.Item] { db?.byKeyword(keyword) ?? [] }
    func byStudio(_ studio: String) -> [Catalog.Item] { db?.byStudio(studio) ?? [] }
    func randomPlayable(contentType: String? = nil) -> Catalog.Item? {
        db?.randomPlayable(contentType: contentType)
    }
    func randomFeatureFilm() -> Catalog.Item? { db?.randomFeatureFilm() }
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
    func items(forShelf shelfID: String, allowStandaloneTV: Bool = false) -> [Catalog.Item] {
        db?.shelf(shelfID, allowStandaloneTV: allowStandaloneTV) ?? []
    }

    /// Drop already-completed titles from a Home list (#17). No-op until a view
    /// populates `completedArchiveIDs` from SwiftData WatchProgress, or when the
    /// user turns the Settings toggle off.
    func filteringWatched(_ items: [Catalog.Item]) -> [Catalog.Item] {
        guard hideWatchedOnHome, !completedArchiveIDs.isEmpty else { return items }
        return items.filter { !completedArchiveIDs.contains($0.archiveID) }
    }

    // MARK: shared ContinuousPlayback engine surface (db*-prefixed, matches tvOS)
    func dbRandomPlayable() -> Catalog.Item? { db?.randomPlayable() }
    func dbRandomFeatureFilm() -> Catalog.Item? { db?.randomFeatureFilm() }
    func dbBrowse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                  sort: CatalogDB.Sort = .popular, limit: Int = 60,
                  homeOnly: Bool = false) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre,
                   sort: sort, limit: limit, homeOnly: homeOnly) ?? []
    }
}

#endif
