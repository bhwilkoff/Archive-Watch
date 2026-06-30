import Foundation

// Decodes an array field that may be ABSENT from the JSON to an empty array instead of throwing.
// tv-episode items (Decision 045) are materialized with a minimal JSON that omits the film-only
// arrays (collections/subjects/genres/countries/cast/shelves); without this every episode row
// failed to decode and `browse()`/`search()` silently dropped ALL of them — episodes never
// appeared as items anywhere (Add-a-Clip, search, Detail). The KeyedDecodingContainer overload is
// what turns a MISSING key into the default (synthesized Decodable otherwise throws on absence).
@propertyWrapper
struct DefaultEmptyArray<Element: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    var wrappedValue: [Element]
    init(wrappedValue: [Element] = []) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = (try? c.decode([Element].self)) ?? []
    }
}

extension KeyedDecodingContainer {
    func decode<Element>(_ type: DefaultEmptyArray<Element>.Type,
                         forKey key: Key) throws -> DefaultEmptyArray<Element> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmptyArray()
    }
}

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
        @DefaultEmptyArray var collections: [String]
        @DefaultEmptyArray var subjects: [String]
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
        @DefaultEmptyArray var genres: [String]
        @DefaultEmptyArray var countries: [String]
        @DefaultEmptyArray var cast: [CastMember]
        let director: String?
        let directorProfilePath: String?   // TMDb photo path for the director (Detail's first chip)
        let producer: String?
        let seriesName: String?
        let network: String?
        let enrichmentTier: String?
        @DefaultEmptyArray var shelves: [String]

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
        // Build-time adult flag (Decision 012). Optional so older catalogs
        // decode unchanged; absent → not adult. Lets views that resolve items
        // by id (e.g. Continue Watching) honor the filter the same as the
        // CatalogDB WHERE-clause path.
        let isAdult: Bool?

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

        // Episode-item linkage (contentType == "tv-episode", Decision 045): a
        // playable episode materialized as a first-class catalog item, so it
        // gets the same favorite/playlist/share/Clip/Detail/search machinery as
        // a film. seriesID points at its spine; these carry the display byline.
        let seasonNumber: Int?
        let episodeNumber: Int?
        let seriesTitle: String?

        // OMDb rich fields (tools/omdb_backfill.py). Optional so old
        // catalogs decode unchanged. imdbRating/Votes feed shelf ranking
        // and a "Top Rated" surface; contentRating complements the
        // Decision-012 adult filter with a real MPAA/TV signal.
        let imdbRating: Double?
        let imdbVotes: Int?
        let contentRating: String?
        let synopsisSource: String?

        // Color vs black-and-white, classified from the actual video frames by
        // tools/classify_color.py (mean ffmpeg signalstats saturation). "color"
        // or "bw"; nil = not yet classified. Optional so old catalogs decode
        // unchanged.
        let colorMode: String?

        // Subtitle/caption tracks (tools/enrich_subtitles.py). Additive +
        // optional. Each is a side-loadable track the players attach to the
        // progressive MP4 (archive.org's own ASR captions, OpenSubtitles, or
        // generated). nil/absent = no captions known yet.
        let captions: [Caption]?

        // HLS master playlist (tools/build_subtitle_assets.py) that wraps the
        // MP4 + WebVTT subtitle tracks — the NATIVE way AVPlayerViewController
        // shows a CC menu (Decision 039). Present only once the Pages assets are
        // built. Apple players use this URL instead of the bare MP4.
        let subtitleHLS: String?

        // Community / usage signals harvested from archive.org
        // (tools/harvest_community_signals.py). Additive + optional. Power the
        // community-aware popularity sort and the Detail-page community stats.
        let downloads: Int?
        let numFavorites: Int?
        let avgRating: Double?
        let numReviews: Int?
        let viewsAllTime: Int?
        let views30d: Int?
        // Genuine reviews of the TITLE, filtered in the pipeline
        // (tools/comment_fit.py) so the app only ever shows reviews about the FILM
        // — never file-quality talk or inappropriate comments. nil = none kept.
        let reviews: [Review]?

        // Metadata expansion (Decision 046 / docs/METADATA-EXPANSION.md). All
        // additive + optional — only ~41% of films carry them and older catalogs
        // decode unchanged. Arrays MUST use @DefaultEmptyArray (a plain [String]
        // throws on absence and silently drops the whole item from every list).
        // The strings are detail-flavor; keywords/akaTitles are also in the FTS
        // index for search, and keywords/studios have value-indexed join tables
        // for filtering.
        @DefaultEmptyArray var keywords: [String]
        @DefaultEmptyArray var akaTitles: [String]
        @DefaultEmptyArray var studios: [String]
        let originalTitle: String?
        let writer: String?
        let composer: String?
        let cinematographer: String?
        let franchise: String?
        let tagline: String?
        let releaseDate: String?
        let awards: String?

        var id: String { archiveID }
        var subtitleHLSURL: URL? { subtitleHLS.flatMap(URL.init(string:)) }
        var posterURLParsed: URL? { posterURL.flatMap(URL.init(string:)) }
        var backdropURLParsed: URL? { backdropURL.flatMap(URL.init(string:)) }
        var videoURLParsed: URL? { downloadURL.flatMap(URL.init(string:)) }

        /// True when the poster is a real designed artwork (TMDb, Wikidata, Commons, TVmaze),
        /// false when it's just the Archive first-frame thumbnail.
        var hasDesignedArtwork: Bool {
            hasRealArtwork ?? (artworkSource != "archive")
        }

        /// Real *professional* poster art — excludes our frame-extracted
        /// ("generated") covers. The Home page uses this so the front page only
        /// shows true designed posters, never a screenshot-derived card.
        var hasProfessionalArtwork: Bool {
            hasDesignedArtwork && artworkSource != "generated"
        }

        /// Title-level identity for cross-shelf de-duplication on Home. Two
        /// archive.org uploads of the SAME film share an imdbID (and usually a
        /// title+year) but differ in archiveID, so an archiveID-only seen-set
        /// lets the same title repeat across shelves. Prefer the imdbID; fall
        /// back to a normalized title+year; finally the archiveID so two genuinely
        /// distinct yearless same-titled items don't collapse into one.
        var dedupKey: String {
            if let im = imdbID?.lowercased(), !im.isEmpty { return "imdb:" + im }
            let norm = title.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .filter { $0.isLetter || $0.isNumber }
            if !norm.isEmpty, let y = year { return "ty:\(norm)|\(y)" }
            return "id:" + archiveID
        }

        /// Known color status from frame analysis. nil when unclassified.
        var isColor: Bool? {
            switch colorMode { case "color": return true; case "bw": return false; default: return nil }
        }
        var isBlackAndWhite: Bool { colorMode == "bw" }

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

        /// "7.8" — IMDb rating formatted for display, or nil if unrated.
        var imdbRatingDisplay: String? {
            guard let r = imdbRating, r > 0 else { return nil }
            return String(format: "%.1f", r)
        }

        /// Compact vote count, e.g. "149K", "21K", "1.4K", "302".
        var imdbVotesDisplay: String? {
            guard let v = imdbVotes, v > 0 else { return nil }
            if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
            if v >= 1_000     { return "\(v / 1000)K" }
            return "\(v)"
        }

        /// Compact archive.org community counts for the Detail stats row.
        private static func compact(_ n: Int) -> String {
            if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
            if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
            return "\(n)"
        }
        /// "304K views" worth of all-time views, or nil.
        var viewsDisplay: String? {
            guard let v = viewsAllTime ?? downloads, v > 0 else { return nil }
            return Self.compact(v)
        }
        /// Favorite count, e.g. "730", or nil.
        var favoritesDisplay: String? {
            guard let f = numFavorites, f > 0 else { return nil }
            return Self.compact(f)
        }
        /// archive.org community star rating "4.8", or nil if unrated.
        var avgRatingDisplay: String? {
            guard let r = avgRating, r > 0 else { return nil }
            return String(format: "%.1f", r)
        }
        /// Genuine, pipeline-filtered reviews to show on Detail (already fit-checked).
        var displayReviews: [Review] {
            (reviews ?? []).filter { ($0.body?.isEmpty == false) || ($0.title?.isEmpty == false) }
        }

        /// Human byline for the Detail screen. For features: director. For TV: network.
        /// For ephemeral/PSA: producer/publisher/sponsor. Falls back to null.
        var byline: String? {
            if let director { return "Directed by \(director)" }
            if contentType == "tv-series", let network { return "Aired on \(network)" }
            if let producer { return "Produced by \(producer)" }
            return nil
        }

        /// A first-class episode item (Decision 045). Its `seriesID` points at
        /// the spine so Detail can offer "Part of <series>".
        var isEpisode: Bool { contentType == "tv-episode" }

        /// "S1 · E17" / "Ep. 17" byline for an episode item, else nil.
        var episodeNumberLabel: String? {
            if let s = seasonNumber, let e = episodeNumber { return "S\(s) · E\(e)" }
            if let e = episodeNumber { return "Ep. \(e)" }
            return nil
        }

        /// Whether Clip Studio (the Create feature) is offered for this item.
        /// Defense in depth on top of Decision 027 (copyrighted titles are
        /// already excluded from the catalog upstream): only offer clipping
        /// for content we can confidently call free. A playable video is
        /// required; rightsStatus must be PD/CC or absent (nil → "" → allowed,
        /// since the visible catalog is PD/CC-only post-027). An explicit
        /// "unknown" / rights-reserved status is NOT clippable.
        var isClippable: Bool {
            guard videoURLParsed != nil else { return false }
            switch (rightsStatus ?? "").lowercased() {
            case "", "public_domain", "publicdomain", "public-domain", "cc0", "creative_commons":
                return true
            case let s where s.hasPrefix("cc") || s.contains("public"):
                return true
            default:
                return false
            }
        }

        /// Canonical archive.org source page for provenance/attribution.
        var sourceDetailsURL: String { "https://archive.org/details/\(archiveID)" }

        /// The always-available archive.org item thumbnail (a real video frame for most playable
        /// items). The UNIVERSAL poster fallback so a tile is NEVER blank when the designed poster
        /// URL is dead/throttled — every platform's poster view layers this behind the real poster.
        var archiveThumbURL: URL? {
            let id = archiveID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? archiveID
            return URL(string: "https://archive.org/services/img/\(id)")
        }

        /// Burned-in provenance credit line for exported clips — the
        /// attribution wedge (CREATE-STUDIO-PLAN §1). Public domain by default;
        /// names a CC dedication when that's the right.
        var clipCreditLine: String {
            let rights = (rightsStatus ?? "").lowercased().contains("creative")
                ? "Creative Commons" : "Public Domain"
            return "archivewatch.org · \(rights)"
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
        // TMDb person id (Decision 046) — reliable "more by this actor" and the
        // Callsheet person deep-link (Decision 038, previously blocked on this).
        // Optional so older catalogs decode unchanged.
        let tmdbPersonID: Int?
    }

    /// A subtitle/caption track that players side-load onto the video.
    /// `format` is "srt" or "vtt"; web/Apple convert SRT→VTT, Android plays
    /// either natively. `source` records provenance (archive-asr, archive,
    /// opensubtitles, generated) for labeling + attribution.
    struct Caption: Decodable, Sendable, Hashable {
        let lang: String            // BCP-47-ish: "en", "es", "fr", …
        let label: String?          // display label, e.g. "English (auto)"
        let format: String          // "srt" | "vtt"
        let url: String             // archive.org source (Android side-loads this)
        let source: String?
        let vttURL: String?         // CORS-hosted VTT on Pages (web `<track>`)
        var urlParsed: URL? { URL(string: url) }
        var displayLabel: String { label ?? lang.uppercased() }
    }

    /// A genuine review of the title, already pipeline-filtered (comment_fit.py)
    /// — the app never has to judge fit at runtime, only display these.
    struct Review: Decodable, Sendable, Hashable, Identifiable {
        let reviewer: String?
        let title: String?
        let body: String?
        let stars: Int?             // 1...5, or nil for an unrated comment
        let date: String?           // "YYYY-MM-DD"
        var id: String { (reviewer ?? "") + "|" + (date ?? "") + "|" + (title ?? "") }
        var displayName: String { (reviewer?.isEmpty == false ? reviewer : nil) ?? "Archive viewer" }
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

    // The CANONICAL Home shelf order, replicated on every platform (owner 2026-06-29: "I prefer the
    // order and titles of the Apple TV app… replicated across all platforms"). featured.json file
    // order is NOT used for Home — this priority list is. Ids absent from the catalog are skipped.
    static let homeShelfPriority: [String] = [
        "popular-features", "wikidata-pd", "film-noir", "scifi-horror",
        "silent-hall-of-fame", "melies", "video-cellar", "comedy",
        "animation-all", "vintage-cartoons", "nasa", "classic-tv-1960s",
        "classic-tv-1950s", "classic-tv-1970s", "ephemera", "newsreels",
        "educational", "picfixer", "silent-era", "popular-classic-tv",
        "all-time-features",
    ]

    /// The featured shelves in canonical Home order (used by tvOS/iOS/macOS Home).
    var orderedHomeShelves: [Shelf] {
        Self.homeShelfPriority.compactMap { id in shelves.first { $0.id == id } }
    }
    // Editorial demotion: series whose episode RIGHTS are uncertain sort to
    // the END of TV lists instead of leading them (still searchable/playable;
    // owner direction 2026-06-11 re: Saturday Night Live).
    let deprioritizedSeries: [String]?

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
    let cast: [Catalog.CastMember]?   // from TVmaze (tools/enrich_tv_cast.py)
    let seasons: [Season]
    let episodesCount: Int?
    /// Total episodes in the canonical run (TVmaze), vs `episodesCount` which
    /// is how many we actually have playable. Drives the "X of Y" affordance.
    let canonicalEpisodesCount: Int?

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

struct EpisodeContext: Hashable, Sendable, Identifiable {
    let series: Series
    let episode: Episode
    var id: String { episode.archiveID }
}

