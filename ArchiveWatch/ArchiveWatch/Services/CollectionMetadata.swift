import SwiftUI

// Single source of truth for Archive collection display metadata.
// CollectionsView (rendering the tiles) and BrowseView (showing the
// filtered grid when a tile is tapped) both read from here, so a
// collection's display name / blurb / accent never drifts between
// screens — and so the user never sees the raw Archive slug.

enum CollectionMetadata {

    struct Entry: Identifiable {
        let id: String
        let title: String
        let blurb: String
        let accent: String   // hex
    }

    static let all: [Entry] = [
        // Marquee features
        .init(id: "Film_Noir",               title: "Film Noir",              blurb: "Shadows, second thoughts, venetian-blind lighting.",       accent: "#FF5C35"),
        .init(id: "SciFi_Horror",            title: "Sci-Fi & Horror",        blurb: "B-movies, creature features, postwar paranoia.",           accent: "#7C5BBA"),
        .init(id: "Comedy_Films",            title: "Comedy",                 blurb: "Pratfalls, quick wit, surreal cinema.",                    accent: "#FF4D8D"),
        .init(id: "TheVideoCellarCollection", title: "The Video Cellar",       blurb: "A curator's devoted private library.",                     accent: "#E8A317"),
        .init(id: "feature_films",           title: "Feature Films",          blurb: "The main library — thousands of public-domain features.", accent: "#FF5C35"),
        .init(id: "feature_films_picfixer",  title: "Picfixer Restorations",  blurb: "A collector's multi-year film restoration project.",       accent: "#FF5C35"),
        .init(id: "mid-century-german-film", title: "Mid-Century German Film", blurb: "Postwar to New German Cinema.",                            accent: "#8A8F98"),

        // Silent cinema
        .init(id: "silenthalloffame",        title: "Silent Hall of Fame",    blurb: "Curator-picked silents: Griffith, Chaplin, Keaton, Lang.", accent: "#C9A66B"),
        .init(id: "georgesmelies",           title: "Georges Méliès",         blurb: "The magician who invented cinema.",                        accent: "#C9A66B"),
        .init(id: "silent_films",            title: "Silent Cinema",          blurb: "The first thirty years of moving pictures.",               accent: "#C9A66B"),
        .init(id: "segundodechomon",         title: "Segundo de Chomón",      blurb: "Spanish Méliès-era trick cinema pioneer.",                 accent: "#C9A66B"),

        // Animation
        .init(id: "animationandcartoons",    title: "Animation",              blurb: "From Fleischer to Terrytoons to beyond.",                  accent: "#FF4D8D"),
        .init(id: "vintage_cartoons",        title: "Vintage Cartoons",       blurb: "Pre-1970 animation on 16mm and 35mm.",                     accent: "#FF4D8D"),
        .init(id: "classic_cartoons",        title: "Classic Cartoons",       blurb: "Early Disney, Fleischer, Terrytoons.",                     accent: "#FF4D8D"),

        // Classic TV
        .init(id: "classic_tv_1950s",        title: "1950s Television",       blurb: "Live broadcasts, rabbit-ears era.",                        accent: "#2D5BFF"),
        .init(id: "classic_tv_1960s",        title: "1960s Television",       blurb: "The golden age of network drama.",                         accent: "#2D5BFF"),
        .init(id: "classic_tv_1970s",        title: "1970s Television",       blurb: "Color, variety, sitcom reinvention.",                      accent: "#2D5BFF"),
        .init(id: "classic_tv_1980s",        title: "1980s Television",       blurb: "Cable arrives; the networks respond.",                     accent: "#2D5BFF"),
        .init(id: "classic_tv_1940s",        title: "1940s Television",       blurb: "The earliest surviving broadcasts.",                       accent: "#2D5BFF"),
        .init(id: "classic_tv",              title: "Classic Television",     blurb: "Vintage broadcasts across the 20th century.",              accent: "#2D5BFF"),

        // Government / ephemeral / educational
        .init(id: "prelinger",               title: "The Prelinger Archive",  blurb: "Industrial, educational, and ephemeral 20th-century film.", accent: "#7C5BBA"),
        .init(id: "nasa",                    title: "NASA Films",             blurb: "Earthrise, moonwalks, the long engineering story.",        accent: "#3FA796"),
        .init(id: "educationalfilms",        title: "Educational Shorts",     blurb: "Encyclopædia Britannica, Coronet, classroom filmstrips.",  accent: "#7C5BBA"),
        .init(id: "ephemera",                title: "Ephemera",               blurb: "Industrial, instructional, home, in-between.",             accent: "#7C5BBA"),
        .init(id: "newsandpublicaffairs",    title: "Newsreels",              blurb: "How the 20th century reported itself to itself.",          accent: "#8A8F98")
    ]

    /// Display title for a collection id. Never returns the raw slug —
    /// falls back to a de-slugged variant so even unknown collections
    /// are presentable.
    static func title(for id: String) -> String {
        if let entry = all.first(where: { $0.id == id }) { return entry.title }
        return id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func entry(for id: String) -> Entry? {
        all.first(where: { $0.id == id })
    }

    static func accent(for id: String) -> Color {
        guard let hex = entry(for: id)?.accent else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}
