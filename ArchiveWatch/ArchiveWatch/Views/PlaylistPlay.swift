import Foundation

/// How a playlist plays, on every Apple platform (iOS-DESIGN §4.3b). Pure, so the
/// rule is one rule and can be tested without a player.
enum PlaylistPlay {
    /// What can actually play, in the order given. A series card has no file.
    static func playable(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter { $0.videoURLParsed != nil }
    }

    /// The first title not yet watched, or the top if all of them are.
    static func startIndex(_ items: [Catalog.Item], watched: (String) -> Bool) -> Int {
        items.firstIndex { !watched($0.archiveID) } ?? 0
    }

    static func position(_ index: Int, of count: Int) -> String { "\(index + 1) of \(count)" }
}
