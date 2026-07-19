import Foundation

enum CatalogLoader {

    enum LoadError: Error {
        case bundleMissing(String)
        case decodeFailed(String, Error)
    }

    /// Editorial config (curated shelves, category tiles, `deprioritizedSeries`,
    /// the adult-collection list) published alongside the site.
    private static let featuredURL = URL(string: "https://archivewatch.org/featured.json")!
    private static let featuredETagKey = "featuredETag"
    private static let featuredCheckedKey = "featuredLastCheckedAt"

    private static var featuredCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("featured.json")
    }

    // The catalog itself is no longer loaded from JSON — it lives in the
    // SQLite DB (Decision 017). Only featured.json (small) stays JSON.
    //
    // Prefers the cached remote copy, falling back to the bundled one. Curated
    // shelves and editorial demotions were previously frozen at build time, so a
    // curation fix could not reach users without an App Store release — the
    // catalog refreshed daily while the editorial layer on top of it could not.
    static func loadFeatured() throws -> Featured {
        if let cached = try? loadCachedFeatured() { return cached }
        return try loadBundled("featured", as: Featured.self)
    }

    private static func loadCachedFeatured() throws -> Featured {
        let data = try Data(contentsOf: featuredCacheURL)
        return try JSONDecoder().decode(Featured.self, from: data)
    }

    /// Fetch a newer editorial config. Returns nil when unchanged, unreachable,
    /// or when the payload fails to decode — the caller keeps what it has.
    /// Throttled by `ttl` so a foreground resume isn't a network call every time.
    static func refreshFeatured(ttl: TimeInterval = 6 * 3600) async -> Featured? {
        let last = UserDefaults.standard.double(forKey: featuredCheckedKey)
        if last > 0, Date().timeIntervalSince1970 - last < ttl { return nil }

        var request = URLRequest(url: featuredURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        if let etag = UserDefaults.standard.string(forKey: featuredETagKey),
           FileManager.default.fileExists(atPath: featuredCacheURL.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: featuredCheckedKey)
        guard http.statusCode == 200 else { return nil }   // 304 == nothing new

        // Decode BEFORE caching: a malformed or truncated payload must never
        // replace a good local copy, or the app would boot with no editorial
        // config until the next successful fetch.
        guard let featured = try? JSONDecoder().decode(Featured.self, from: data) else { return nil }
        try? data.write(to: featuredCacheURL, options: .atomic)
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: featuredETagKey)
        }
        return featured
    }

    private static func loadBundled<T: Decodable>(_ resource: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw LoadError.bundleMissing(resource + ".json")
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoadError.decodeFailed(resource, error)
        }
    }
}
