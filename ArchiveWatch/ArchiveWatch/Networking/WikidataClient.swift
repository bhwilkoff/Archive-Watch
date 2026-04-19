import Foundation

// MARK: - WikidataClient
//
// Fallback identifier resolver. Used only when an Archive item lacks an
// `external-identifier` for IMDb. Wikidata stores the Internet Archive
// ID as property P724, IMDb as P345, and the primary image as P18.
//
// One SPARQL query closes the gap for any item notable enough to have a
// Wikidata entry.

actor WikidataClient {

    static let shared = WikidataClient()

    private let http = HTTPClient.shared
    private let sparqlEndpoint = URL(string: "https://query.wikidata.org/sparql")!

    struct WikidataMatch: Sendable {
        let qid: String           // e.g. "Q12345"
        let imdbID: String?       // "tt0032138"
        let imageURL: URL?        // Commons image, resolved
    }

    // MARK: Public API

    /// Look up an Archive identifier and return Wikidata cross-references.
    func lookup(archiveID: String) async throws -> WikidataMatch? {
        let query = sparqlQuery(archiveID: archiveID)
        let response: SPARQLResponse = try await fetchSPARQL(query: query)

        guard let binding = response.results.bindings.first else { return nil }

        let qid = binding.item?.value?.components(separatedBy: "/").last ?? ""
        let imdb = binding.imdb?.value
        let image: URL? = {
            guard let s = binding.image?.value else { return nil }
            return URL(string: s)
        }()

        return WikidataMatch(
            qid: qid,
            imdbID: imdb?.isEmpty == false ? imdb : nil,
            imageURL: image
        )
    }

    // MARK: SPARQL

    private func sparqlQuery(archiveID: String) -> String {
        // P724 = Internet Archive ID, P345 = IMDb ID, P18 = image.
        // Escape quotes defensively — identifiers are safe but belt + braces.
        let safeID = archiveID.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        SELECT ?item ?imdb ?image WHERE {
          ?item wdt:P724 "\(safeID)" .
          OPTIONAL { ?item wdt:P345 ?imdb. }
          OPTIONAL { ?item wdt:P18 ?image. }
        }
        LIMIT 1
        """
    }

    private func fetchSPARQL(query: String) async throws -> SPARQLResponse {
        var components = URLComponents(url: sparqlEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw HTTPError.nonHTTPResponse }

        // Wikidata requires a descriptive User-Agent; HTTPClient's default
        // satisfies this, but we specify Accept explicitly.
        return try await http.getJSON(url, headers: [
            "Accept": "application/sparql-results+json"
        ])
    }

    // MARK: SPARQL response types

    private struct SPARQLResponse: Decodable {
        let results: SPARQLResults
    }

    private struct SPARQLResults: Decodable {
        let bindings: [SPARQLBinding]
    }

    private struct SPARQLBinding: Decodable {
        let item: SPARQLValue?
        let imdb: SPARQLValue?
        let image: SPARQLValue?
    }

    private struct SPARQLValue: Decodable {
        let type: String?
        let value: String?
    }
}
