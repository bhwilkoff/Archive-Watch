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

        // Additive fields from the federated pipeline (tools/export_catalog.py).
        // All optional so old catalog.json files still decode without a migration.
        let rightsStatus: String?
        let qualityScore: Int?
        let popularityScore: Int?
        let bestSourceType: String?
        // Authoritative silent-film flag. When present and true, overrides the
        // contentType-based check — the pipeline's multi-signal classifier
        // (collection membership + director whitelist + audio absence + year)
        // is far more accurate than a year threshold on the app side.
        let isSilentFilm: Bool?

        // TV series card additions. For contentType == "tv-series", the
        // `archiveID` acts as the series slug ("bonanza-1960") and the
        // full episode list is lazy-loaded from /series/{seriesID}.json.
        // These are nil for every non-series item.
        let seriesID: String?
        let yearEnd: Int?
        let seasonsCount: Int?
        let episodesCount: Int?
        let networks: [String]?
        let creator: String?

        var id: String { archiveID }
        var posterURLParsed: URL? { posterURL.flatMap(URL.init(string:)) }
        var backdropURLParsed: URL? { backdropURL.flatMap(URL.init(string:)) }
        var videoURLParsed: URL? { downloadURL.flatMap(URL.init(string:)) }

        /// True when the poster is a real designed artwork (TMDb, Wikidata, Commons, TVmaze),
        /// false when it's just the Archive first-frame thumbnail.
        var hasDesignedArtwork: Bool {
            hasRealArtwork ?? (artworkSource != "archive")
        }

        /// Authoritative silent-film predicate. Prefers the pipeline's
        /// multi-signal flag; falls back to the legacy contentType check
        /// for catalogs generated before the pipeline switchover.
        var isSilent: Bool {
            isSilentFilm ?? (contentType == "silent-film")
        }

        /// Display-safe synopsis: HTML stripped, entities decoded, normalised whitespace.
        /// The builder strips most of this; this is belt-and-braces for old catalogs.
        var displaySynopsis: String? {
            guard let raw = synopsis, !raw.isEmpty else { return nil }
            return HTMLStripper.strip(raw)
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


// ---------------------------------------------------------------------------
// TV series (lazy-loaded from /series/{seriesID}.json)
// ---------------------------------------------------------------------------
// The main catalog carries a compact SeriesCard per show (as a
// Catalog.Item with contentType="tv-series"). When the user opens a
// series, SeriesStore fetches the per-series JSON on demand — that's
// where the full episode list + per-episode metadata lives. Keeping
// episode detail out of the main catalog keeps the main download
// small even for shows with 100+ episodes.

struct Series: Decodable, Sendable, Hashable, Identifiable {
    let version: Int
    let seriesID: String
    let title: String
    let yearStart: Int?
    let yearEnd: Int?
    let overview: String?
    let posterURL: String?
    let backdropURL: String?
    let genres: [String]
    let networks: [String]
    let creator: String?
    let seasons: [Season]
    let episodesCount: Int?

    var id: String { seriesID }
    var posterURLParsed: URL? { posterURL.flatMap(URL.init(string:)) }
    var backdropURLParsed: URL? { backdropURL.flatMap(URL.init(string:)) }

    /// A flattened list of episodes in season+episode order. Useful
    /// for the player's prev/next logic.
    var flatEpisodes: [Episode] {
        seasons.flatMap { $0.episodes }
    }

    func episode(after current: Episode) -> Episode? {
        let all = flatEpisodes
        guard let idx = all.firstIndex(of: current), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    func episode(before current: Episode) -> Episode? {
        let all = flatEpisodes
        guard let idx = all.firstIndex(of: current), idx > 0 else { return nil }
        return all[idx - 1]
    }

    static func == (lhs: Series, rhs: Series) -> Bool { lhs.seriesID == rhs.seriesID }
    func hash(into hasher: inout Hasher) { hasher.combine(seriesID) }
}

struct Season: Decodable, Sendable, Hashable {
    /// `nil` means the episodes couldn't be confidently assigned to a
    /// season number (Archive singletons, anthology one-offs); render
    /// them under an "Unassigned" / "More Episodes" group.
    let seasonNumber: Int?
    let episodes: [Episode]

    var displayTitle: String {
        if let n = seasonNumber { return "Season \(n)" }
        return "More Episodes"
    }
}

struct Episode: Decodable, Sendable, Hashable, Identifiable {
    let archiveID: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let title: String
    let overview: String?
    let stillURL: String?
    let airDate: String?
    let year: Int?
    let runtimeSeconds: Int?
    let videoFile: Catalog.VideoFile?
    let downloadURL: String?

    var id: String { archiveID }
    var stillURLParsed: URL? { stillURL.flatMap(URL.init(string:)) }
    var videoURLParsed: URL? { downloadURL.flatMap(URL.init(string:)) }

    /// Compact label like "S1 · E2" or "Ep. 12" when season is unknown.
    var numberLabel: String? {
        if let s = seasonNumber, let e = episodeNumber {
            return "S\(s) · E\(e)"
        }
        if let e = episodeNumber { return "Ep. \(e)" }
        return nil
    }

    static func == (lhs: Episode, rhs: Episode) -> Bool { lhs.archiveID == rhs.archiveID }
    func hash(into hasher: inout Hasher) { hasher.combine(archiveID) }
}


// ---------------------------------------------------------------------------
// Carriers for navigating to an Episode
// ---------------------------------------------------------------------------
// We push this struct (rather than the raw Episode) onto the navigation
// path so the destination has both the Episode and its parent Series.
// That lets the player compute prev/next without a second fetch.

struct EpisodeContext: Hashable, Sendable {
    let series: Series
    let episode: Episode
}

