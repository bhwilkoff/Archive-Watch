import Foundation

// MARK: - TMDbClient
//
// The Movie Database wrapper. Two entry points for enrichment:
//
//   1. `findByIMDb(_:)` — cheap. Given an IMDb tt-ID (which Archive
//      items often carry in `external-identifier`), return the TMDb
//      movie/TV match.
//   2. `movieDetail(id:)` — richer. Given a TMDb movie ID, fetch full
//      metadata with credits, images, and external IDs in one call via
//      `?append_to_response=credits,images,external_ids`.
//
// Auth: v4 bearer read token, stored in `Secrets.xcconfig` → Info.plist
// under `TMDB_BEARER_TOKEN`. The token is non-commercial per TMDb's
// free tier; see Decisions 007 and 010.

actor TMDbClient {

    static let shared = TMDbClient()

    private let http = HTTPClient.shared
    private let apiBase = URL(string: "https://api.themoviedb.org/3/")!
    private let imageBase = URL(string: "https://image.tmdb.org/t/p/")!

    private var bearerToken: String? {
        // Primary path: Info.plist key TMDB_BEARER_TOKEN, populated by xcconfig.
        if let token = Bundle.main.object(forInfoDictionaryKey: "TMDB_BEARER_TOKEN") as? String,
           !token.isEmpty, token != "$(TMDB_BEARER_TOKEN)" {
            return token
        }
        // Dev fallback: environment variable for Xcode scheme + Preview runs.
        if let env = ProcessInfo.processInfo.environment["TMDB_BEARER_TOKEN"], !env.isEmpty {
            return env
        }
        return nil
    }

    private var authHeaders: [String: String] {
        guard let token = bearerToken else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: Errors

    enum TMDbError: Error, CustomStringConvertible {
        case missingCredentials
        case noMatch(imdbID: String)

        var description: String {
            switch self {
            case .missingCredentials: return "TMDB_BEARER_TOKEN is not set (check Secrets.xcconfig and Info.plist)."
            case .noMatch(let id):     return "TMDb /find returned no results for \(id)."
            }
        }
    }

    // MARK: /find/{imdb_id}

    func findByIMDb(_ imdbID: String) async throws -> TMDbFindResponse {
        guard !authHeaders.isEmpty else { throw TMDbError.missingCredentials }

        var components = URLComponents(url: apiBase.appendingPathComponent("find/\(imdbID)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "external_source", value: "imdb_id"),
            URLQueryItem(name: "language", value: "en-US")
        ]
        guard let url = components.url else { throw HTTPError.nonHTTPResponse }

        let decoder = JSONDecoder()
        return try await http.getJSON(url, headers: authHeaders, decoder: decoder)
    }

    /// Convenience: return the first movie result or nil.
    func firstMovieMatch(forIMDb imdbID: String) async throws -> TMDbMovieSummary? {
        let response = try await findByIMDb(imdbID)
        return response.movieResults.first
    }

    // MARK: /movie/{id}

    func movieDetail(id: Int, appendCreditsImagesAndExternalIDs: Bool = true) async throws -> TMDbMovieDetail {
        guard !authHeaders.isEmpty else { throw TMDbError.missingCredentials }

        var components = URLComponents(url: apiBase.appendingPathComponent("movie/\(id)"),
                                       resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "language", value: "en-US")]
        if appendCreditsImagesAndExternalIDs {
            queryItems.append(URLQueryItem(name: "append_to_response",
                                           value: "credits,images,external_ids"))
            // Include imageless languages in the images bag — textless
            // posters are often the best picks.
            queryItems.append(URLQueryItem(name: "include_image_language", value: "en,null"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw HTTPError.nonHTTPResponse }

        return try await http.getJSON(url, headers: authHeaders)
    }

    // MARK: Image URL construction

    enum PosterSize: String, Sendable {
        case w342, w500, w780, original
    }

    enum BackdropSize: String, Sendable {
        case w780, w1280, original
    }

    nonisolated func posterURL(path: String, size: PosterSize = .w780) -> URL {
        imageBase.appendingPathComponent(size.rawValue).appendingPathComponent(path)
    }

    nonisolated func backdropURL(path: String, size: BackdropSize = .w1280) -> URL {
        imageBase.appendingPathComponent(size.rawValue).appendingPathComponent(path)
    }
}
