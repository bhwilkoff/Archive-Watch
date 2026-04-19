import Foundation
import SwiftData

// MARK: - ContentItem
//
// The normalized, enriched record for a single Archive.org title.
// Everything displayed in the UI — Home shelves, Detail page, Search
// results — reads from this model. The EnrichmentService writes.
//
// Storage notes:
//   - URLs live as Strings to avoid SwiftData's URL-encoding quirks.
//   - Arrays of scalars are stored directly; SwiftData handles
//     `[String]` natively via Codable.
//   - Cast members are stored as JSON since they're a fixed-cap list
//     we rarely need to query individually.

@Model
final class ContentItem {

    // MARK: Identity
    @Attribute(.unique) var archiveID: String
    var title: String
    var originalTitle: String?

    // MARK: Time
    var year: Int?
    var runtimeSeconds: Int?

    // MARK: Text
    var synopsis: String?
    var tagline: String?

    // MARK: Cross-references
    var imdbID: String?
    var tmdbID: Int?
    var wikidataQID: String?

    // MARK: Artwork
    var posterURLString: String?
    var backdropURLString: String?
    var artworkSourceRaw: String = ArtworkSource.none.rawValue

    // MARK: Classification (denormalized for fast query)
    var contentTypeRaw: String
    var decade: Int?
    var genresRaw: [String] = []        // Genre.rawValue
    var countries: [String] = []        // ISO 3166-1 alpha-2
    var contentRating: String?
    var runtimeBucketRaw: String?

    // MARK: Cast + crew
    var directorName: String?
    var castJSON: String = "[]"         // JSON-encoded [CastSnapshot]

    // MARK: Playback
    var videoURLString: String
    var videoFormat: String
    var fileSizeBytes: Int64?

    // MARK: Enrichment state
    var enrichmentTierRaw: String = EnrichmentTier.archiveOnly.rawValue
    var lastEnrichedAt: Date?
    var lastEnrichmentError: String?

    // MARK: User state
    var isFavorite: Bool = false
    var playbackPositionSeconds: Double = 0
    var isAdultContent: Bool = false
    var addedAt: Date = Date()

    // MARK: Attribution
    var sourceAttributionRaw: String = SourceAttribution.archive.rawValue

    // MARK: Init

    init(
        archiveID: String,
        title: String,
        videoURLString: String,
        videoFormat: String,
        contentType: ContentType
    ) {
        self.archiveID = archiveID
        self.title = title
        self.videoURLString = videoURLString
        self.videoFormat = videoFormat
        self.contentTypeRaw = contentType.rawValue
    }

    // MARK: Computed accessors

    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .featureFilm }
        set { contentTypeRaw = newValue.rawValue }
    }

    var artworkSource: ArtworkSource {
        get { ArtworkSource(rawValue: artworkSourceRaw) ?? .none }
        set { artworkSourceRaw = newValue.rawValue }
    }

    var enrichmentTier: EnrichmentTier {
        get { EnrichmentTier(rawValue: enrichmentTierRaw) ?? .archiveOnly }
        set { enrichmentTierRaw = newValue.rawValue }
    }

    var runtimeBucket: RuntimeBucket? {
        get { runtimeBucketRaw.flatMap(RuntimeBucket.init(rawValue:)) }
        set { runtimeBucketRaw = newValue?.rawValue }
    }

    var genres: [Genre] {
        get { genresRaw.compactMap(Genre.init(rawValue:)) }
        set { genresRaw = newValue.map(\.rawValue) }
    }

    var posterURL: URL? {
        get { posterURLString.flatMap(URL.init(string:)) }
        set { posterURLString = newValue?.absoluteString }
    }

    var backdropURL: URL? {
        get { backdropURLString.flatMap(URL.init(string:)) }
        set { backdropURLString = newValue?.absoluteString }
    }

    var videoURL: URL? {
        URL(string: videoURLString)
    }

    var cast: [CastSnapshot] {
        get {
            guard let data = castJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([CastSnapshot].self, from: data)) ?? []
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8)
            castJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }
}

// MARK: - Supporting types

enum EnrichmentTier: String, Codable, Sendable {
    case archiveOnly          // only raw Archive metadata
    case identifierResolved   // IMDb or Wikidata QID known
    case fullyEnriched        // TMDb movie detail + artwork present
    case failed               // cascade exhausted without success
}

struct CastSnapshot: Codable, Sendable, Hashable {
    let name: String
    let character: String?
    let order: Int
    let profilePath: String?
}

enum SourceAttribution: String, Codable, Sendable {
    case tmdb
    case archive
    case mixed      // Archive + TMDb + others — the usual case post-enrichment
}
