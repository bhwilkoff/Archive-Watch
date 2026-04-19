import Foundation

// The pre-built, bundled seed catalog — produced by tools/build-catalog.mjs
// and shipped inside the app bundle. First launch renders from this with
// zero network. SwiftData's ContentItem takes over once the app starts
// persisting user state (favorites, continue-watching, re-enrichments).

struct Catalog: Decodable, Sendable {
    let version: Int
    let generatedAt: String
    let generator: String?
    let stats: Stats
    let items: [Item]

    struct Stats: Decodable, Sendable {
        let totalItems: Int
        let itemsWithIMDb: Int?
        let itemsWithTMDb: Int?
        let itemsWithWikidata: Int?
        let fullyEnriched: Int?
        let itemsPlayable: Int?
    }

    struct Item: Decodable, Identifiable, Sendable, Hashable {
        let archiveID: String
        let title: String
        let year: Int?
        let decade: Int?
        let runtimeSeconds: Int?
        let synopsis: String?
        let collections: [String]
        let subjects: [String]
        let mediatype: String?
        let language: String?
        let imdbID: String?
        let tmdbID: Int?
        let wikidataQID: String?
        let tvmazeID: Int?
        let videoFile: VideoFile?
        let downloadURL: String?
        let posterURL: String?
        let backdropURL: String?
        let hasRealArtwork: Bool?
        let artworkSource: String
        let contentType: String
        let genres: [String]
        let countries: [String]
        let cast: [CastMember]
        let director: String?
        let producer: String?
        let seriesName: String?
        let network: String?
        let enrichmentTier: String?
        let shelves: [String]

        var id: String { archiveID }
        var posterURLParsed: URL? { posterURL.flatMap(URL.init(string:)) }
        var backdropURLParsed: URL? { backdropURL.flatMap(URL.init(string:)) }
        var videoURLParsed: URL? { downloadURL.flatMap(URL.init(string:)) }

        /// True when the poster is a real designed artwork (TMDb, Wikidata, Commons, TVmaze),
        /// false when it's just the Archive first-frame thumbnail.
        var hasDesignedArtwork: Bool {
            hasRealArtwork ?? (artworkSource != "archive")
        }

        /// Human byline for the Detail screen. For features: director. For TV: network.
        /// For ephemeral/PSA: producer/publisher/sponsor. Falls back to null.
        var byline: String? {
            if let director { return "Directed by \(director)" }
            if contentType == "tv-series", let network { return "Aired on \(network)" }
            if let producer { return "Produced by \(producer)" }
            return nil
        }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.archiveID == rhs.archiveID }
        func hash(into hasher: inout Hasher) { hasher.combine(archiveID) }
    }

    struct VideoFile: Decodable, Sendable, Hashable {
        let name: String
        let format: String
        let sizeBytes: Int?
        let tier: Int
    }

    struct CastMember: Decodable, Sendable, Hashable {
        let name: String
        let character: String?
        let order: Int
        let profilePath: String?
    }
}

// The curator-maintained shelves + category taxonomy. Lives alongside the
// catalog on disk; the app reads both to decide what shelves to build and
// how to tint them.

struct Featured: Decodable, Sendable {
    let version: Int
    let categories: [Category]
    let shelves: [Shelf]
    let adultCollections: [String]?

    struct Category: Decodable, Sendable, Identifiable {
        let id: String
        let displayName: String
        let shortName: String?
        let accent: String
        let posterAspect: String?
    }

    struct Shelf: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let category: String?
        let type: String
        // Only one of these is populated depending on `type`.
        let items: [CuratedItem]?
        let query: String?
        let sort: [String]?
        let limit: Int?
    }

    struct CuratedItem: Decodable, Sendable {
        let archiveID: String
        let note: String?
    }

    func category(id: String) -> Category? { categories.first(where: { $0.id == id }) }
}
