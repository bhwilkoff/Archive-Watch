import Foundation

// MARK: - ArtworkResolver
//
// Cascading poster + backdrop resolver. Every step is optional; we stop
// at the first success. The last-resort is Archive.org's own thumbnail,
// which is utilitarian but always available.
//
// The resolver is stateless — it takes the already-fetched TMDb detail
// (if any) and Wikidata match (if any), and returns URLs. Actual
// network fetches for Commons / LoC happen here.

struct ResolvedArtwork: Sendable {
    let posterURL: URL?
    let backdropURL: URL?
    let source: ArtworkSource
}

enum ArtworkSource: String, Sendable, Codable {
    case tmdb
    case wikidata
    case commons
    case loc
    case archive
    case none
}

actor ArtworkResolver {

    static let shared = ArtworkResolver()

    private let tmdb = TMDbClient.shared
    private let archive = ArchiveClient.shared
    private let http = HTTPClient.shared

    // MARK: Public API

    func resolve(
        archiveID: String,
        tmdbDetail: TMDbMovieDetail? = nil,
        wikidata: WikidataClient.WikidataMatch? = nil,
        title: String? = nil,
        year: Int? = nil
    ) async -> ResolvedArtwork {
        // 1. TMDb — best quality, best coverage when available.
        if let detail = tmdbDetail {
            let (poster, backdrop) = tmdbURLs(from: detail)
            if poster != nil || backdrop != nil {
                return ResolvedArtwork(posterURL: poster, backdropURL: backdrop, source: .tmdb)
            }
        }

        // 2. Wikidata's P18 image (usually Commons).
        if let wiki = wikidata, let image = wiki.imageURL {
            return ResolvedArtwork(posterURL: image, backdropURL: nil, source: .wikidata)
        }

        // 3. Wikimedia Commons search by title + year.
        if let title, let commons = try? await commonsSearch(title: title, year: year) {
            return ResolvedArtwork(posterURL: commons, backdropURL: nil, source: .commons)
        }

        // 4. Library of Congress search — strongest for pre-1950 American films.
        if let title, let year, year < 1960,
           let loc = try? await locSearch(title: title, year: year) {
            return ResolvedArtwork(posterURL: loc, backdropURL: nil, source: .loc)
        }

        // 5. Archive.org's own thumbnail — always works, never pretty.
        let thumb = archive.thumbnailURL(for: archiveID)
        return ResolvedArtwork(posterURL: thumb, backdropURL: nil, source: .archive)
    }

    // MARK: TMDb artwork pickers

    private nonisolated func tmdbURLs(from detail: TMDbMovieDetail) -> (URL?, URL?) {
        // Prefer highest-voted images from the /images bag, falling back
        // to the detail response's top-level paths.
        let posterPath = bestImage(from: detail.images?.posters, preferredLanguages: ["en", nil])
            ?? detail.posterPath
        let backdropPath = bestImage(from: detail.images?.backdrops, preferredLanguages: [nil, "en"])
            ?? detail.backdropPath

        let poster = posterPath.map { tmdb.posterURL(path: $0) }
        let backdrop = backdropPath.map { tmdb.backdropURL(path: $0) }
        return (poster, backdrop)
    }

    private nonisolated func bestImage(from pool: [TMDbImage]?, preferredLanguages: [String?]) -> String? {
        guard let pool, !pool.isEmpty else { return nil }
        // Try each language bucket in order, picking the highest-voted file.
        for lang in preferredLanguages {
            let bucket = pool.filter { $0.iso639_1 == lang }
            if let best = bucket.max(by: {
                ($0.voteAverage ?? 0, $0.voteCount ?? 0) < ($1.voteAverage ?? 0, $1.voteCount ?? 0)
            }) {
                return best.filePath
            }
        }
        return pool.first?.filePath
    }

    // MARK: Commons search

    private func commonsSearch(title: String, year: Int?) async throws -> URL? {
        let term: String = year.map { "\(title) (\($0) film)" } ?? "\(title) film poster"
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action",   value: "query"),
            URLQueryItem(name: "format",   value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: term),
            URLQueryItem(name: "gsrnamespace", value: "6"),   // File: namespace
            URLQueryItem(name: "gsrlimit", value: "5"),
            URLQueryItem(name: "prop",     value: "imageinfo"),
            URLQueryItem(name: "iiprop",   value: "url"),
            URLQueryItem(name: "iiurlwidth", value: "780")
        ]
        guard let url = components.url else { return nil }

        let response: CommonsSearchResponse = try await http.getJSON(url)
        // Pick the first result with a thumb URL.
        return response.query?.pages?.values
            .compactMap { $0.imageinfo?.first?.thumburl ?? $0.imageinfo?.first?.url }
            .compactMap { URL(string: $0) }
            .first
    }

    private struct CommonsSearchResponse: Decodable {
        struct Query: Decodable { let pages: [String: CommonsPage]? }
        struct CommonsPage: Decodable { let imageinfo: [CommonsImageInfo]? }
        struct CommonsImageInfo: Decodable {
            let url: String?
            let thumburl: String?
        }
        let query: Query?
    }

    // MARK: Library of Congress search

    private func locSearch(title: String, year: Int) async throws -> URL? {
        var components = URLComponents(string: "https://www.loc.gov/search/")!
        components.queryItems = [
            URLQueryItem(name: "q",   value: "\(title) \(year) film poster"),
            URLQueryItem(name: "fa",  value: "online-format:image"),
            URLQueryItem(name: "fo",  value: "json"),
            URLQueryItem(name: "c",   value: "5")
        ]
        guard let url = components.url else { return nil }

        let response: LOCSearchResponse = try await http.getJSON(url)
        return response.results?
            .compactMap { $0.image_url?.first }
            .compactMap { URL(string: $0) }
            .first
    }

    private struct LOCSearchResponse: Decodable {
        struct Hit: Decodable { let image_url: [String]? }
        let results: [Hit]?
    }
}
