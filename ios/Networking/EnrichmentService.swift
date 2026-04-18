import Foundation

// MARK: - EnrichmentService
//
// Orchestrates the cascade described in DECISION 008:
//
//   Archive metadata
//     └─ extract IMDb from external-identifier
//         └─ else Wikidata P724 → IMDb
//             └─ TMDb /find → TMDb movie detail (+credits,+images,+external_ids)
//                 └─ ArtworkResolver cascade
//                     └─ Normalize to ContentItem
//
// Every step is best-effort. A failure in TMDb or Wikidata produces a
// degraded-but-usable ContentItem (tier = archiveOnly or
// identifierResolved). The one non-negotiable is the video URL —
// without a playable derivative, we return nil.
//
// This actor is stateless; call sites pass in the archive ID and we
// return a fully-populated ContentItem. Persistence (SwiftData) is the
// caller's responsibility.

actor EnrichmentService {

    static let shared = EnrichmentService()

    private let archive = ArchiveClient.shared
    private let tmdb = TMDbClient.shared
    private let wikidata = WikidataClient.shared
    private let artworkResolver = ArtworkResolver.shared

    // MARK: Errors

    enum EnrichmentError: Error, CustomStringConvertible {
        case noPlayableFile(archiveID: String)

        var description: String {
            switch self {
            case .noPlayableFile(let id): return "No playable video derivative for \(id)."
            }
        }
    }

    // MARK: Entry point

    /// Build a fully-populated ContentItem for the given Archive identifier.
    /// Returns nil if no playable video derivative exists.
    func enrich(archiveID: String) async throws -> ContentItem {

        // 1. Archive metadata + video file selection (non-negotiable).
        let metadataResponse = try await archive.metadata(for: archiveID)
        guard let files = metadataResponse.files,
              let pick = DerivativePicker.pick(from: files),
              let videoURL = archive.downloadURL(for: archiveID, file: pick.file.name ?? "", using: metadataResponse)
        else {
            throw EnrichmentError.noPlayableFile(archiveID: archiveID)
        }

        let meta = metadataResponse.metadata
        let title = meta?.title ?? archiveID
        let year = meta?.parsedYear
        let runtime = meta?.runtimeSeconds
        let subjects = meta?.subject?.values ?? []
        let collections = meta?.collection?.values ?? []

        let contentType = ContentTypeClassifier.classify(
            collections: collections,
            subjects: subjects,
            runtimeSeconds: runtime,
            year: year
        )

        let item = ContentItem(
            archiveID: archiveID,
            title: title,
            videoURLString: videoURL.absoluteString,
            videoFormat: pick.file.format ?? "unknown",
            contentType: contentType
        )
        item.originalTitle = meta?.title
        item.year = year
        item.runtimeSeconds = runtime
        item.synopsis = meta?.description?.values.first
        item.fileSizeBytes = pick.file.sizeBytes
        item.decade = year.flatMap { Decade.from(year: $0)?.rawValue }
        item.runtimeBucket = runtime.map(RuntimeBucket.from(seconds:))
        item.enrichmentTier = .archiveOnly
        item.sourceAttributionRaw = SourceAttribution.archive.rawValue

        // Seed genres from Archive subject tags. TMDb may overwrite these.
        item.genres = subjects.compactMap(Genre.fromSubject).uniqued()

        // 2. Resolve identifiers — IMDb ID, Wikidata QID.
        var imdbID = meta?.imdbID
        var wikidataMatch: WikidataClient.WikidataMatch?

        if imdbID == nil {
            wikidataMatch = try? await wikidata.lookup(archiveID: archiveID)
            imdbID = wikidataMatch?.imdbID
        }
        item.imdbID = imdbID
        item.wikidataQID = wikidataMatch?.qid
        if imdbID != nil || wikidataMatch != nil {
            item.enrichmentTier = .identifierResolved
        }

        // 3. TMDb enrichment, if we have an IMDb anchor.
        var tmdbDetail: TMDbMovieDetail?
        if let imdbID {
            tmdbDetail = try? await fetchTMDbDetail(for: imdbID)
            if let detail = tmdbDetail {
                applyTMDbDetail(detail, to: item)
                item.enrichmentTier = .fullyEnriched
                item.sourceAttributionRaw = SourceAttribution.mixed.rawValue
            }
        }

        // 4. Artwork cascade.
        let artwork = await artworkResolver.resolve(
            archiveID: archiveID,
            tmdbDetail: tmdbDetail,
            wikidata: wikidataMatch,
            title: title,
            year: year
        )
        item.posterURL = artwork.posterURL
        item.backdropURL = artwork.backdropURL
        item.artworkSource = artwork.source

        item.lastEnrichedAt = Date()
        return item
    }

    // MARK: TMDb step

    private func fetchTMDbDetail(for imdbID: String) async throws -> TMDbMovieDetail? {
        guard let summary = try await tmdb.firstMovieMatch(forIMDb: imdbID) else {
            return nil
        }
        return try await tmdb.movieDetail(id: summary.id)
    }

    private func applyTMDbDetail(_ detail: TMDbMovieDetail, to item: ContentItem) {
        item.tmdbID = detail.id
        if let t = detail.title { item.title = t }
        if let t = detail.originalTitle { item.originalTitle = t }
        if let overview = detail.overview, !overview.isEmpty { item.synopsis = overview }
        if let tagline = detail.tagline, !tagline.isEmpty { item.tagline = tagline }
        if let runtimeMinutes = detail.runtime { item.runtimeSeconds = runtimeMinutes * 60 }
        if let countries = detail.productionCountries {
            item.countries = countries.map(\.iso3166_1)
        }

        // Prefer TMDb's genre list over Archive subject-derived guesses.
        if let genres = detail.genres, !genres.isEmpty {
            item.genres = genres.compactMap { Genre.fromTMDb(id: $0.id) }.uniqued()
        }

        if let cast = detail.credits?.cast {
            item.cast = cast
                .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
                .prefix(15)
                .map { CastSnapshot(name: $0.name, character: $0.character, order: $0.order ?? 0, profilePath: $0.profilePath) }
        }

        if let director = detail.credits?.crew?.first(where: { ($0.job ?? "").lowercased() == "director" }) {
            item.directorName = director.name
        }

        if let external = detail.externalIDs {
            if item.wikidataQID == nil, let q = external.wikidataID, !q.isEmpty {
                item.wikidataQID = q
            }
            if item.imdbID == nil, let imdb = external.imdbID, !imdb.isEmpty {
                item.imdbID = imdb
            }
        }

        if detail.adult == true {
            item.isAdultContent = true
        }
    }
}

// MARK: - Small utilities

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
