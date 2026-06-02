import Foundation

// Downloads the prebuilt SQLite catalog DB and caches it for the app to query
// on disk (Decision 017, docs/architecture/catalog-delivery.md). The DB is
// hosted as a GitHub Release asset (off the Pages bandwidth budget; release
// CDN). First paint uses the bundled seed.sqlite; this fetches the full DB in
// the background and AppStore swaps it in.

actor CatalogRefreshService {

    static let shared = CatalogRefreshService()

    /// Raw prebuilt DB hosted as a GitHub Release asset. URLSession follows the
    /// redirect to the asset CDN automatically.
    private let dbURL = URL(string: "https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite")!
    private static let dbETagKey = "catalogDBETag"

    // tvOS only permits writes to Caches / tmp — never Application Support.
    private var dbCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("catalog.sqlite")
    }

    /// Path to the already-downloaded DB, if present.
    func cachedDatabasePath() -> String? {
        FileManager.default.fileExists(atPath: dbCacheURL.path) ? dbCacheURL.path : nil
    }

    /// Download the full catalog DB to Caches (ETag-conditional so an unchanged
    /// DB isn't re-fetched). Returns the local path, or the cached path on
    /// 304/failure. Validated by the caller opening it via CatalogDB.
    func downloadDatabase() async -> String? {
        var request = URLRequest(url: dbURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        if let etag = UserDefaults.standard.string(forKey: Self.dbETagKey),
           FileManager.default.fileExists(atPath: dbCacheURL.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (tmp, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse else { return cachedDatabasePath() }
            if http.statusCode == 304 { return cachedDatabasePath() }
            guard http.statusCode == 200 else { return cachedDatabasePath() }
            try? FileManager.default.removeItem(at: dbCacheURL)
            try FileManager.default.moveItem(at: tmp, to: dbCacheURL)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: Self.dbETagKey)
            }
            return dbCacheURL.path
        } catch {
            return cachedDatabasePath()
        }
    }
}
