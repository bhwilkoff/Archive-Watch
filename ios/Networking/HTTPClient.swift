import Foundation

// MARK: - HTTPClient
//
// Shared HTTP core for Archive Watch. Every provider (ArchiveClient,
// TMDbClient, WikidataClient) wraps this actor instead of talking to
// URLSession directly — this is where rate-limit handling, retry, and
// User-Agent enforcement live.
//
// Why an actor: Archive.org and TMDb both return 429 + Retry-After when
// we push too hard, and Wikidata's SPARQL endpoint is grumpy about
// bursts. An actor-serialized gate with per-host minimum spacing and
// exponential backoff is the simplest correct answer.

actor HTTPClient {

    // MARK: Shared instance

    static let shared = HTTPClient()

    // MARK: Configuration

    struct HostPolicy: Sendable {
        /// Minimum interval between requests to this host.
        let minInterval: TimeInterval
        /// Maximum attempts on retryable failures (429, 5xx).
        let maxAttempts: Int
    }

    /// Default per-host policy; providers may override via `register(host:policy:)`.
    private let defaultPolicy = HostPolicy(minInterval: 0.1, maxAttempts: 4)

    private var policies: [String: HostPolicy] = [
        "archive.org":             HostPolicy(minInterval: 0.15, maxAttempts: 4),
        "api.themoviedb.org":      HostPolicy(minInterval: 0.08, maxAttempts: 3),
        "image.tmdb.org":          HostPolicy(minInterval: 0.02, maxAttempts: 3),
        "query.wikidata.org":      HostPolicy(minInterval: 1.0,  maxAttempts: 3),
        "commons.wikimedia.org":   HostPolicy(minInterval: 0.25, maxAttempts: 3),
        "www.loc.gov":             HostPolicy(minInterval: 0.25, maxAttempts: 3)
    ]

    private var lastRequestAt: [String: Date] = [:]

    // MARK: Session

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "User-Agent": "ArchiveWatch/1.0 (tvOS; +https://github.com/bhwilkoff/Archive-Watch)",
            "Accept": "application/json"
        ]
        // Use the app-wide URLCache configured at launch (500 MB disk, 100 MB RAM).
        config.urlCache = URLCache.shared
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    // MARK: Public API

    /// Perform a GET request and decode JSON.
    func getJSON<T: Decodable>(
        _ url: URL,
        headers: [String: String] = [:],
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        let data = try await get(url, headers: headers)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(underlying: error, url: url)
        }
    }

    /// Perform a GET request and return the raw response body.
    func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        let host = url.host ?? ""
        let policy = policies[host] ?? defaultPolicy

        var attempt = 0
        while true {
            attempt += 1
            try await respectSpacing(for: host, policy: policy)

            var request = URLRequest(url: url)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

            do {
                let (data, response) = try await session.data(for: request)
                lastRequestAt[host] = Date()

                guard let http = response as? HTTPURLResponse else {
                    throw HTTPError.nonHTTPResponse
                }

                switch http.statusCode {
                case 200...299:
                    return data
                case 429, 500, 502, 503, 504:
                    guard attempt < policy.maxAttempts else {
                        throw HTTPError.httpStatus(http.statusCode, url: url)
                    }
                    try await Task.sleep(nanoseconds: backoffNanos(attempt: attempt, response: http))
                    continue
                case 404:
                    throw HTTPError.notFound(url: url)
                default:
                    throw HTTPError.httpStatus(http.statusCode, url: url)
                }
            } catch let error as HTTPError {
                throw error
            } catch {
                guard attempt < policy.maxAttempts else {
                    throw HTTPError.transport(underlying: error, url: url)
                }
                try await Task.sleep(nanoseconds: backoffNanos(attempt: attempt, response: nil))
                continue
            }
        }
    }

    // MARK: Spacing + backoff

    private func respectSpacing(for host: String, policy: HostPolicy) async throws {
        guard let last = lastRequestAt[host] else { return }
        let elapsed = Date().timeIntervalSince(last)
        let wait = policy.minInterval - elapsed
        guard wait > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }

    private func backoffNanos(attempt: Int, response: HTTPURLResponse?) -> UInt64 {
        // Honor Retry-After when the server specifies it (seconds or HTTP date).
        if let header = response?.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
            return UInt64(min(seconds, 30) * 1_000_000_000)
        }
        // Exponential: 0.5s, 1s, 2s, 4s, 8s (capped), with ±25% jitter.
        let base = min(pow(2.0, Double(attempt - 1)) * 0.5, 8.0)
        let jitter = Double.random(in: 0.75...1.25)
        return UInt64(base * jitter * 1_000_000_000)
    }
}

// MARK: - Errors

enum HTTPError: Error, CustomStringConvertible {
    case notFound(url: URL)
    case httpStatus(Int, url: URL)
    case nonHTTPResponse
    case transport(underlying: Error, url: URL)
    case decoding(underlying: Error, url: URL)

    var description: String {
        switch self {
        case .notFound(let url): return "404 Not Found: \(url.absoluteString)"
        case .httpStatus(let code, let url): return "HTTP \(code): \(url.absoluteString)"
        case .nonHTTPResponse: return "Non-HTTP response"
        case .transport(let underlying, let url): return "Transport error at \(url.absoluteString): \(underlying.localizedDescription)"
        case .decoding(let underlying, let url): return "Decode error at \(url.absoluteString): \(underlying)"
        }
    }
}

// MARK: - Flexible JSON helpers
//
// Archive.org's metadata endpoint famously returns fields that are
// sometimes a string, sometimes an array of strings, sometimes absent.
// These helpers let us decode that without scattering if-let ladders.

/// A value that may arrive as `T` or `[T]` in JSON.
struct OneOrMany<T: Codable & Sendable>: Codable, Sendable {
    let values: [T]

    init(_ values: [T]) { self.values = values }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let one = try? container.decode(T.self) {
            values = [one]
        } else if let many = try? container.decode([T].self) {
            values = many
        } else {
            values = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// A value that may arrive as `Int` or numeric `String`.
struct FlexibleInt: Codable, Sendable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int.self) { value = n; return }
        if let s = try? container.decode(String.self), let n = Int(s) { value = n; return }
        if let d = try? container.decode(Double.self) { value = Int(d); return }
        value = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
