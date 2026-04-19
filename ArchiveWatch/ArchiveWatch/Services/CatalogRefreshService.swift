import Foundation

// Fetches the latest catalog.json from GitHub Pages on launch. Falls
// back to the bundled copy if the network is unreachable. Caches the
// downloaded copy in Application Support for use on the next launch
// (before a fresh fetch completes).
//
// Usage (called once at launch from AppStore.loadBundledData):
//   Task { await CatalogRefreshService.shared.refresh() }
//
// The refreshed catalog is published back via the AppStore, which the
// UI observes through @Observable.

actor CatalogRefreshService {

    static let shared = CatalogRefreshService()

    /// Override the URL for tests / local mirrors. Defaults to the
    /// expected GitHub Pages location; the host must set this in the
    /// GitHub Pages settings for the repo.
    private let remoteURL = URL(string: "https://bhwilkoff.github.io/Archive-Watch/catalog.json")!

    private var cacheURL: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("catalog.json")
    }

    /// Load the freshest catalog available: cache → bundle.
    func loadLatest() -> Catalog? {
        if let cached = tryDecode(url: cacheURL) { return cached }
        if let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json") {
            return tryDecode(url: bundled)
        }
        return nil
    }

    /// Fetch a fresh copy from GitHub Pages and cache it. Safe to call
    /// repeatedly; uses If-Modified-Since so we only download on change.
    @discardableResult
    func refresh() async -> Catalog? {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            request.setValue(formatter.string(from: modified), forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 304 { return tryDecode(url: cacheURL) }
            guard http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Catalog.self, from: data)
            try? data.write(to: cacheURL, options: .atomic)
            return decoded
        } catch {
            return nil
        }
    }

    private func tryDecode(url: URL) -> Catalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }
}
