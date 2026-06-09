import SwiftUI
import Observation

// iOS app store — the catalog/source-of-truth layer. Mirrors the tvOS AppStore's
// load sequence but only the platform-neutral parts: load featured.json, open the
// bundled seed.sqlite for instant first paint, then swap in the downloaded full DB
// (Decision 017). All catalog reads go through the shared Core `CatalogDB`.
// Conforms to `ContinuousPlaybackSource` so the shared F4 engine works unchanged.
@MainActor
@Observable
final class AppStore: ContinuousPlaybackSource {
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

    /// Completed titles (≥95%), set from SwiftData WatchProgress by the views that
    /// own the model context. Feeds Continue-Watching hiding + the F4 engine.
    var completedArchiveIDs: Set<String> = []

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
        db = newDB
        dbVersion += 1
    }

    // MARK: catalog reads (thin pass-throughs to Core)

    func browse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                sort: CatalogDB.Sort = .popular, limit: Int = 60, offset: Int = 0) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre,
                   sort: sort, limit: limit, offset: offset) ?? []
    }
    func search(_ q: String) -> [Catalog.Item] { db?.search(q) ?? [] }
    func item(_ id: String) -> Catalog.Item? { db?.item(id) }
    func itemsByIDs(_ ids: [String]) -> [Catalog.Item] { db?.itemsByIDs(ids) ?? [] }
    func related(to item: Catalog.Item) -> [Catalog.Item] { db?.related(to: item) ?? [] }
    func seriesCards() -> [Catalog.Item] { db?.seriesCards() ?? [] }
    func hiddenGems() -> [Catalog.Item] { db?.hiddenGems() ?? [] }
    func byCollection(_ id: String) -> [Catalog.Item] { db?.byCollection(id) ?? [] }
    func decadeCounts() -> [Int: Int] { db?.decadeCounts() ?? [:] }

    /// Items for a Home shelf: explicit IDs (curated) or a category browse (dynamic).
    func shelfItems(_ shelf: Featured.Shelf, limit: Int = 24) -> [Catalog.Item] {
        if let curated = shelf.items, !curated.isEmpty {
            return itemsByIDs(curated.map(\.archiveID))
        }
        return browse(contentType: shelf.category, sort: .popular, limit: limit)
    }

    // MARK: ContinuousPlaybackSource
    func randomPlayableItem() -> Catalog.Item? { db?.randomPlayable() }
    func browseItems(contentType: String?, decade: Int?, limit: Int) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, sort: .popular, limit: limit) ?? []
    }
}
