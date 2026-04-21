import Foundation

// Lazy-loads per-series JSON from GitHub Pages on demand.
//
// The main catalog carries only SeriesCard-level data for each show.
// When a user opens a series, we fetch its full episode list from
// https://bhwilkoff.github.io/Archive-Watch/series/{seriesID}.json and
// cache the decoded Series in-memory for this session + on disk under
// Application Support for subsequent launches.
//
// Usage from SwiftUI:
//   let series = try await SeriesStore.shared.load(seriesID: "bonanza-1960")
//
// First call for a given seriesID performs the fetch; repeated calls
// return the in-memory cached copy. If the network is unreachable the
// store falls back to the last disk-cached copy.

actor SeriesStore {

    static let shared = SeriesStore()

    private let baseURL = URL(string: "https://bhwilkoff.github.io/Archive-Watch/series")!
    private var inMemory: [String: Series] = [:]

    private var cacheDir: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        let dir = appSupport.appendingPathComponent("series", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheURL(for seriesID: String) -> URL {
        cacheDir.appendingPathComponent("\(seriesID).json")
    }

    /// Fetch a series. Cache hits are free; misses go to network, fall
    /// back to disk cache on network failure.
    func load(seriesID: String) async -> Series? {
        if let cached = inMemory[seriesID] { return cached }

        let remote = baseURL.appendingPathComponent("\(seriesID).json")
        if let network = await fetchRemote(remote, seriesID: seriesID) {
            inMemory[seriesID] = network
            return network
        }

        // Disk fallback — last-known good copy from a prior session.
        if let disk = loadDisk(seriesID: seriesID) {
            inMemory[seriesID] = disk
            return disk
        }
        return nil
    }

    private func fetchRemote(_ url: URL, seriesID: String) async -> Series? {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadRevalidatingCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(Series.self, from: data)
            try? data.write(to: cacheURL(for: seriesID), options: .atomic)
            return decoded
        } catch {
            return nil
        }
    }

    private func loadDisk(seriesID: String) -> Series? {
        let url = cacheURL(for: seriesID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Series.self, from: data)
    }
}
