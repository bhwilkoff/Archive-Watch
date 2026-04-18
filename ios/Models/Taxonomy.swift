import Foundation

// MARK: - Taxonomy
//
// Controlled vocabulary for Archive Watch. Every ContentItem is tagged
// into these facets so the Browse screen has predictable filters and
// Search results have a consistent chip set.
//
// Keep this file **small, flat, and hand-maintained.** Archive.org's
// `subject` field is free-text; we map it onto our closed set rather
// than trying to represent the whole infinite tag cloud.

enum ContentType: String, Codable, CaseIterable, Sendable {
    case featureFilm    = "feature-film"
    case shortFilm      = "short-film"
    case silentFilm     = "silent-film"
    case animation      = "animation"
    case tvSeries       = "tv-series"
    case tvSpecial      = "tv-special"
    case newsreel       = "newsreel"
    case documentary    = "documentary"
    case ephemeral      = "ephemeral"
    case homeMovie      = "home-movie"

    var displayName: String {
        switch self {
        case .featureFilm:  return "Feature Film"
        case .shortFilm:    return "Short Film"
        case .silentFilm:   return "Silent Film"
        case .animation:    return "Animation"
        case .tvSeries:     return "TV Series"
        case .tvSpecial:    return "TV Special"
        case .newsreel:     return "Newsreel"
        case .documentary:  return "Documentary"
        case .ephemeral:    return "Ephemeral Film"
        case .homeMovie:    return "Home Movie"
        }
    }

    /// Preferred aspect ratio for artwork in this bucket.
    var preferredPosterAspect: PosterAspect {
        switch self {
        case .featureFilm, .silentFilm, .shortFilm, .animation: return .poster2x3
        case .tvSeries, .tvSpecial:                              return .backdrop16x9
        case .newsreel, .documentary, .ephemeral, .homeMovie:    return .backdrop16x9
        }
    }
}

enum PosterAspect: Sendable {
    case poster2x3
    case backdrop16x9
}

// MARK: Genres (mapped from TMDb genre IDs, falling back to keyword match on Archive `subject`)

enum Genre: String, Codable, CaseIterable, Sendable {
    case action       = "action"
    case animation    = "animation"
    case comedy       = "comedy"
    case crime        = "crime"
    case documentary  = "documentary"
    case drama        = "drama"
    case family       = "family"
    case fantasy      = "fantasy"
    case horror       = "horror"
    case musical      = "musical"
    case mystery      = "mystery"
    case romance      = "romance"
    case sciFi        = "sci-fi"
    case thriller     = "thriller"
    case war          = "war"
    case western      = "western"

    var displayName: String {
        switch self {
        case .action: return "Action"
        case .animation: return "Animation"
        case .comedy: return "Comedy"
        case .crime: return "Crime"
        case .documentary: return "Documentary"
        case .drama: return "Drama"
        case .family: return "Family"
        case .fantasy: return "Fantasy"
        case .horror: return "Horror"
        case .musical: return "Musical"
        case .mystery: return "Mystery"
        case .romance: return "Romance"
        case .sciFi: return "Science Fiction"
        case .thriller: return "Thriller"
        case .war: return "War"
        case .western: return "Western"
        }
    }

    /// TMDb's canonical genre IDs (movies). Stable — unchanged since v3.
    static func fromTMDb(id: Int) -> Genre? {
        switch id {
        case 28:    return .action
        case 16:    return .animation
        case 35:    return .comedy
        case 80:    return .crime
        case 99:    return .documentary
        case 18:    return .drama
        case 10751: return .family
        case 14:    return .fantasy
        case 27:    return .horror
        case 10402: return .musical
        case 9648:  return .mystery
        case 10749: return .romance
        case 878:   return .sciFi
        case 53:    return .thriller
        case 10752: return .war
        case 37:    return .western
        default:    return nil
        }
    }

    /// Best-effort keyword map for Archive.org's `subject` field.
    static func fromSubject(_ subject: String) -> Genre? {
        let s = subject.lowercased()
        if s.contains("western")                       { return .western }
        if s.contains("horror")                        { return .horror }
        if s.contains("sci-fi") || s.contains("science fiction") { return .sciFi }
        if s.contains("comedy")                        { return .comedy }
        if s.contains("drama")                         { return .drama }
        if s.contains("musical")                       { return .musical }
        if s.contains("war")                           { return .war }
        if s.contains("noir") || s.contains("crime")   { return .crime }
        if s.contains("cartoon") || s.contains("animat") { return .animation }
        if s.contains("romance")                       { return .romance }
        if s.contains("mystery")                       { return .mystery }
        if s.contains("thriller")                      { return .thriller }
        if s.contains("documentary")                   { return .documentary }
        if s.contains("fantasy")                       { return .fantasy }
        if s.contains("family")                        { return .family }
        if s.contains("action") || s.contains("adventure") { return .action }
        return nil
    }
}

// MARK: Runtime buckets (for Browse filtering)

enum RuntimeBucket: String, CaseIterable, Sendable {
    case under10   = "under-10"
    case ten30     = "10-30"
    case thirty60  = "30-60"
    case sixty90   = "60-90"
    case ninety120 = "90-120"
    case over120   = "120+"

    var displayName: String {
        switch self {
        case .under10:   return "Under 10 min"
        case .ten30:     return "10–30 min"
        case .thirty60:  return "30–60 min"
        case .sixty90:   return "60–90 min"
        case .ninety120: return "90–120 min"
        case .over120:   return "Over 2 hours"
        }
    }

    static func from(seconds: Int) -> RuntimeBucket {
        let minutes = seconds / 60
        switch minutes {
        case ..<10:   return .under10
        case 10..<30: return .ten30
        case 30..<60: return .thirty60
        case 60..<90: return .sixty90
        case 90..<120:return .ninety120
        default:      return .over120
        }
    }
}

// MARK: Decade (derived from year)

enum Decade: Int, CaseIterable, Sendable {
    case d1890 = 1890, d1900 = 1900, d1910 = 1910, d1920 = 1920, d1930 = 1930
    case d1940 = 1940, d1950 = 1950, d1960 = 1960, d1970 = 1970, d1980 = 1980
    case d1990 = 1990, d2000 = 2000, d2010 = 2010, d2020 = 2020

    var displayName: String { "\(rawValue)s" }

    static func from(year: Int) -> Decade? {
        let rounded = (year / 10) * 10
        return Decade(rawValue: rounded)
    }
}

// MARK: Content-type classification heuristic

enum ContentTypeClassifier {

    /// Infer a ContentType from Archive.org collection tags + subject + runtime.
    /// This runs once at enrichment time; the result is stored on the ContentItem.
    static func classify(
        collections: [String],
        subjects: [String],
        runtimeSeconds: Int?,
        year: Int?
    ) -> ContentType {
        // 1. Authoritative registry (docs/taxonomy/collections.json).
        //    The highest-weight collection with a known category wins.
        if let dominant = CollectionRegistry.dominantCollection(from: collections),
           let typed = ContentType(rawValue: dominant.info.category) {
            return typed
        }

        // 2. Fall back to string-contains heuristics for unregistered
        //    collections (still want to do the right thing for obscure
        //    tags that haven't been added to the registry yet).
        let cols = Set(collections.map { $0.lowercased() })
        let subs = subjects.map { $0.lowercased() }

        if cols.contains(where: { $0.contains("classic_tv") || $0.contains("classictv") }) {
            return .tvSeries
        }
        if cols.contains(where: { $0.contains("newsreel") || $0.contains("news-and-public") }) {
            return .newsreel
        }
        if cols.contains(where: { $0.contains("prelinger") || $0.contains("ephemeral") }) {
            return .ephemeral
        }
        if cols.contains(where: { $0.contains("cartoon") || $0.contains("animation") }) {
            return .animation
        }
        if cols.contains(where: { $0.contains("silent") }) {
            return .silentFilm
        }
        if cols.contains(where: { $0.contains("home_movie") || $0.contains("homemovie") }) {
            return .homeMovie
        }

        // 3. Year-based silent fallback.
        if let y = year, y < 1928 { return .silentFilm }

        // 4. Documentary via subject tags.
        if subs.contains(where: { $0.contains("documentary") }) { return .documentary }

        // 5. Runtime-based split for everything else.
        if let r = runtimeSeconds {
            if r < 40 * 60 { return .shortFilm }
            if r > 55 * 60 { return .featureFilm }
        }

        return .featureFilm
    }
}
