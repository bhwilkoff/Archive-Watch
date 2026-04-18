import Foundation
import SwiftData

// MARK: - SeedCatalog
//
// On first launch, the app has no content in SwiftData and no network
// responses cached. The seed catalog (`catalog.json`, bundled with the
// app) is the bridge: a pre-computed set of enriched ContentItem
// records built by build-catalog.html and committed to the repo.
//
// Flow:
//   1. App launches. Main container is empty.
//   2. SeedCatalog.prime(into:) reads the bundled catalog.json.
//   3. For each entry, insert a ContentItem into the ModelContext
//      marked with enrichmentTier = .fullyEnriched if TMDb data was
//      present, .archiveOnly otherwise.
//   4. Home screens render immediately from SwiftData.
//   5. In the background, EnrichmentService refreshes items whose
//      lastEnrichedAt is older than the TTL (30 days for TMDb data).
//
// The seed catalog is not the source of truth once the app runs —
// it's a launch boost. SwiftData is mutable, so user actions and live
// refreshes overwrite it.
//
// Main-actor isolated because SwiftData's ModelContext is tied to
// the main actor in the common single-container setup used by this app.

@MainActor
enum SeedCatalog {

    private static let decoder = JSONDecoder()

    // MARK: Public API

    /// Load the bundled catalog and insert any items not already in
    /// the model context. Idempotent: safe to call on every launch.
    /// Returns the number of items inserted (0 if catalog was empty
    /// or all items already existed).
    @discardableResult
    static func prime(into context: ModelContext) -> Int {
        guard let catalog = loadBundledCatalog() else { return 0 }
        if catalog.items.isEmpty { return 0 }

        let existingSet = Set(fetchExistingIDs(context: context))

        var inserted = 0
        for entry in catalog.items {
            guard !existingSet.contains(entry.archiveID) else { continue }
            guard let item = makeContentItem(from: entry) else { continue }
            context.insert(item)
            inserted += 1
        }

        if inserted > 0 {
            do { try context.save() }
            catch { assertionFailure("SeedCatalog save failed: \(error)") }
        }
        return inserted
    }

    /// For diagnostic use. Returns the decoded catalog as-is.
    static func diagnosticLoad() -> SeedCatalogData? {
        loadBundledCatalog()
    }

    // MARK: Loading

    private static func loadBundledCatalog() -> SeedCatalogData? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SeedCatalogData.self, from: data)
        } catch {
            assertionFailure("Failed to decode catalog.json: \(error)")
            return nil
        }
    }

    private static func fetchExistingIDs(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<ContentItem>()
        guard let all = try? context.fetch(descriptor) else { return [] }
        return all.map(\.archiveID)
    }

    // MARK: Mapping

    private static func makeContentItem(from entry: SeedCatalogEntry) -> ContentItem? {
        // A playable video URL is non-negotiable; if the seed entry
        // doesn't have one, we skip rather than inserting a dead row.
        guard let videoFile = entry.videoFile,
              !videoFile.name.isEmpty else {
            return nil
        }

        let videoURL = "https://archive.org/download/\(entry.archiveID)/\(urlEncoded(videoFile.name))"
        let contentType = ContentType(rawValue: entry.contentType ?? "") ?? .featureFilm

        let item = ContentItem(
            archiveID: entry.archiveID,
            title: entry.title ?? entry.archiveID,
            videoURLString: videoURL,
            videoFormat: videoFile.format ?? "unknown",
            contentType: contentType
        )

        item.year = entry.year
        item.runtimeSeconds = entry.runtimeSeconds
        item.synopsis = entry.synopsis
        item.imdbID = entry.imdbID
        item.tmdbID = entry.tmdbID
        item.wikidataQID = entry.wikidataQID
        item.posterURLString = entry.posterURL
        item.backdropURLString = entry.backdropURL
        item.artworkSource = ArtworkSource(rawValue: entry.artworkSource ?? "archive") ?? .archive
        item.decade = entry.decade ?? entry.year.flatMap { Decade.from(year: $0)?.rawValue }
        item.runtimeBucket = entry.runtimeSeconds.map(RuntimeBucket.from(seconds:))
        item.genresRaw = entry.genres ?? []
        item.countries = entry.countries ?? []
        item.directorName = entry.director
        item.fileSizeBytes = videoFile.sizeBytes

        let cast = (entry.cast ?? []).map {
            CastSnapshot(name: $0.name, character: $0.character, order: $0.order ?? 0, profilePath: $0.profilePath)
        }
        item.cast = cast

        // Catalog fidelity determines enrichment tier.
        if entry.tmdbID != nil {
            item.enrichmentTier = .fullyEnriched
            item.sourceAttributionRaw = SourceAttribution.mixed.rawValue
        } else if entry.imdbID != nil {
            item.enrichmentTier = .identifierResolved
        } else {
            item.enrichmentTier = .archiveOnly
        }

        // Mark the seed time so the background refresh job knows when
        // this was last touched. Using the catalog's generatedAt if
        // present, otherwise distant past so it refreshes sooner.
        item.lastEnrichedAt = entry.lastEnrichedAtDate ?? Date(timeIntervalSince1970: 0)

        return item
    }

    private static func urlEncoded(_ filename: String) -> String {
        filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
    }
}

// MARK: - Catalog DTOs

struct SeedCatalogData: Codable, Sendable {
    let version: Int
    let generatedAt: String?
    let generator: String?
    let stats: SeedCatalogStats?
    let items: [SeedCatalogEntry]
}

struct SeedCatalogStats: Codable, Sendable {
    let totalItems: Int?
    let itemsWithIMDb: Int?
    let itemsWithTMDb: Int?
    let itemsWithPoster: Int?
    let itemsPlayable: Int?
}

struct SeedCatalogEntry: Codable, Sendable {
    let archiveID: String
    let title: String?
    let year: Int?
    let decade: Int?
    let runtimeSeconds: Int?
    let synopsis: String?
    let collections: [String]?
    let subjects: [String]?
    let mediatype: String?
    let imdbID: String?
    let tmdbID: Int?
    let wikidataQID: String?
    let videoFile: SeedCatalogVideoFile?
    let posterURL: String?
    let backdropURL: String?
    let artworkSource: String?
    let contentType: String?
    let genres: [String]?
    let countries: [String]?
    let cast: [SeedCatalogCast]?
    let director: String?
    let shelves: [String]?
    let generatedAt: String?

    var lastEnrichedAtDate: Date? {
        guard let s = generatedAt else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

struct SeedCatalogVideoFile: Codable, Sendable {
    let name: String
    let format: String?
    let size: String?
    let sizeBytes: Int64?
    let tier: Int?
    let reason: String?
}

struct SeedCatalogCast: Codable, Sendable {
    let name: String
    let character: String?
    let order: Int?
    let profilePath: String?
}
