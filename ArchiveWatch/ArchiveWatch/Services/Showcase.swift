import Foundation

/// App Store screenshot mode: `AW_SHOWCASE=1`, DEBUG builds only.
///
/// Owner, 2026-10-08: *"the movies grid and even the home screen need better
/// screenshots. We need better filters and a better hero image that helped to
/// highlight just how professional the posters and backdrops are."*
///
/// It is a RULE over the catalog's own fields, never a hand-picked list (the
/// no-AI-lists rule): the hero tier's rights evidence, professional poster and
/// backdrop art, nothing tagged horror (store art must suit 4+), most-voted
/// first. It also hides the viewer's own rows (Continue Watching), which on a
/// shared container would be the developer's history, and holds the hero on
/// its first film instead of auto-advancing past it before the capture.
enum Showcase {
    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["AW_SHOWCASE"] == "1"
        #else
        false
        #endif
    }

    static func qualifies(_ item: Catalog.Item) -> Bool {
        item.isHeroRightsSafe
            && item.hasProfessionalArtwork
            && item.posterURLParsed != nil
            && !item.genres.contains { $0.localizedCaseInsensitiveContains("horror") }
    }

    static func ranked(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter(qualifies).sorted { ($0.imdbVotes ?? 0) > ($1.imdbVotes ?? 0) }
    }

    /// The marquee: the rule, plus a backdrop to fill it.
    static func hero(from items: [Catalog.Item], count: Int = 7) -> [Catalog.Item] {
        Array(ranked(items.filter { $0.backdropURLParsed != nil }).prefix(count))
    }
}
