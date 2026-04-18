import Foundation

// MARK: - ArchiveClient
//
// Read-only wrapper around the public Internet Archive APIs. Three
// operations — scrape (paginated browse), metadata (item detail),
// downloadURL (direct file access). No auth, no CORS to worry about on
// a native client.
//
// Identifier format: lowercase alphanumeric + underscore. We don't
// sanitize inputs here — callers are expected to pass valid IDs
// sourced from scrape results or curated lists.

actor ArchiveClient {

    static let shared = ArchiveClient()

    private let http = HTTPClient.shared

    private let scrapeBase = URL(string: "https://archive.org/services/search/v1/scrape")!
    private let metadataBase = URL(string: "https://archive.org/metadata/")!
    private let thumbnailBase = URL(string: "https://archive.org/services/img/")!

    // MARK: Browse — scrape API (cursor-paginated, no 10k cap)

    struct ScrapeQuery: Sendable {
        var q: String                 // Lucene-like: `mediatype:movies AND collection:feature_films`
        var fields: [String] = [
            "identifier", "title", "creator", "date", "year",
            "mediatype", "collection", "subject", "downloads",
            "description", "runtime"
        ]
        var sorts: [String] = []      // e.g. ["-downloads", "-week"]
        var count: Int = 100          // min 100 per API
        var cursor: String? = nil
    }

    /// Paginated browse. Returns items + next cursor (nil when exhausted).
    func scrape(_ query: ScrapeQuery) async throws -> (items: [ArchiveScrapeItem], nextCursor: String?) {
        var components = URLComponents(url: scrapeBase, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query.q),
            URLQueryItem(name: "fields", value: query.fields.joined(separator: ",")),
            URLQueryItem(name: "count", value: String(max(query.count, 100)))
        ]
        if !query.sorts.isEmpty {
            items.append(URLQueryItem(name: "sorts", value: query.sorts.joined(separator: ",")))
        }
        if let cursor = query.cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        guard let url = components.url else { throw HTTPError.nonHTTPResponse }

        let response: ArchiveScrapeResponse = try await http.getJSON(url)
        return (response.items ?? [], response.cursor)
    }

    // MARK: Detail — metadata API

    /// Fetch the full metadata blob for a single Archive identifier.
    func metadata(for identifier: String) async throws -> ArchiveMetadataResponse {
        let url = metadataBase.appendingPathComponent(identifier)
        return try await http.getJSON(url)
    }

    // MARK: Files

    /// Build a download URL for a named file belonging to an identifier.
    /// Prefers the server + dir from a fresh metadata response, falls back
    /// to the canonical /download/ path.
    func downloadURL(for identifier: String, file: String, using metadata: ArchiveMetadataResponse? = nil) -> URL? {
        if let metadata, let url = metadata.downloadURL(for: file) {
            return url
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "archive.org"
        components.path = "/download/\(identifier)/\(file)"
        return components.url
    }

    /// Built-in thumbnail — the bottom of the artwork cascade.
    nonisolated func thumbnailURL(for identifier: String) -> URL {
        thumbnailBase.appendingPathComponent(identifier)
    }
}
