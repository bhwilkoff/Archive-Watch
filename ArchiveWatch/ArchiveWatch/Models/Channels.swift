import SwiftUI

// Channel presets + the guide's channel shape, shared by the tvOS EPG grid and
// the iOS touch guide (PARITY §5: same channels, same date-seeded schedule via
// ChannelScheduler — only the guide LAYOUT is per-platform).
struct Channel: Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let hex: String
    let icon: String
    var contentType: String? = nil
    var genre: String? = nil
    var accent: Color { Color(hex: hex) ?? .accentColor }

    static let all: [Channel] = [
        .init(id: "drama",   title: "Drama Theater",   tagline: "The big stories", hex: "#FF5C35", icon: "theatermasks.fill", genre: "Drama"),
        .init(id: "comedy",  title: "Comedy Hour",     tagline: "Laughs around the clock", hex: "#E8A317", icon: "face.smiling.fill", genre: "Comedy"),
        .init(id: "noir",    title: "Crime & Mystery", tagline: "Shadows and suspects", hex: "#2D5BFF", icon: "magnifyingglass", genre: "Crime"),
        .init(id: "thrill",  title: "Thriller",        tagline: "Edge of your seat", hex: "#0047FF", icon: "bolt.fill", genre: "Thriller"),
        .init(id: "horror",  title: "Horror",          tagline: "After dark", hex: "#7C5BBA", icon: "moon.stars.fill", genre: "Horror"),
        .init(id: "western", title: "Western Trail",   tagline: "The frontier rolls on", hex: "#C9A66B", icon: "hare.fill", genre: "Western"),
        .init(id: "scifi",   title: "Sci-Fi Theater",  tagline: "Worlds beyond", hex: "#3FA796", icon: "atom", genre: "Science Fiction"),
        .init(id: "silent",  title: "Silent Cinema",   tagline: "The age before sound", hex: "#C9A66B", icon: "film.stack.fill", contentType: "silent-film"),
        .init(id: "cartoon", title: "Cartoon Classics",tagline: "Animation all day", hex: "#FF4D8D", icon: "paintbrush.fill", contentType: "animation"),
        .init(id: "news",    title: "Newsreel Desk",   tagline: "History as it broke", hex: "#8A8F98", icon: "newspaper.fill", contentType: "newsreel"),
        .init(id: "docs",    title: "Documentary",     tagline: "Real stories", hex: "#3FA796", icon: "globe.americas.fill", contentType: "documentary"),
        // TV channels (not just movies) — built from playable classic-TV items.
        .init(id: "tv",        title: "Classic TV",   tagline: "Vintage television", hex: "#2D5BFF", icon: "tv.fill", contentType: "tv-special"),
        .init(id: "tv-comedy", title: "TV Comedy",    tagline: "Sitcoms & sketch", hex: "#E8A317", icon: "tv.fill", contentType: "tv-special", genre: "Comedy"),
        .init(id: "tv-drama",  title: "TV Drama",     tagline: "Series drama", hex: "#FF5C35", icon: "tv.fill", contentType: "tv-special", genre: "Drama"),
        .init(id: "tv-western",title: "TV Westerns",  tagline: "Saddle up, every hour", hex: "#C9A66B", icon: "tv.fill", contentType: "tv-special", genre: "Western"),
    ]
}

/// A channel as the guide sees it: identity + its program pool + its schedule.
struct GuideChannel: Identifiable {
    let id: String
    let number: Int
    let title: String
    let accent: Color
    let icon: String
    let slots: [ScheduledProgram]
}
