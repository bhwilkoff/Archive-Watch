import Foundation

// The shared continuous-playback engine (roadmap F4 / #54): given the item that
// just finished and an autoplay mode, produce the next item to play. Its first
// consumer is movie autoplay (#10); channels (#1), party (#3), and cartoon (#2)
// will reuse it rather than each writing their own queue (tvOS-DESIGN §9.5).
//
// Episodes have their own "next" (the next episode — EpisodePlayerScreen already
// auto-advances), which is the "same show" autoplay; this engine covers the movie
// modes (more-like-this / same-era / surprise).

enum AutoplayMode: String, CaseIterable, Identifiable {
    case off, sameCategory, sameYear, surprise
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:          return "Off"
        case .sameCategory: return "More Like This"
        case .sameYear:     return "Same Era"
        case .surprise:     return "Surprise Me"
        }
    }
}

// Decoupled from any concrete app store (Decision 028): the engine lives in the
// shared Core and asks a small source protocol for items, so every platform's
// store (tvOS / iOS) conforms without the Core depending on platform UI state.
@MainActor
protocol ContinuousPlaybackSource: AnyObject {
    func randomPlayableItem() -> Catalog.Item?
    func browseItems(contentType: String?, decade: Int?, limit: Int) -> [Catalog.Item]
    var completedArchiveIDs: Set<String> { get }
}

@MainActor
enum ContinuousPlayback {
    /// The next item to autoplay after `item` under `mode`, or nil (mode off, or
    /// nothing playable/fresh fits). Honors the adult/hidden filters via the
    /// source's browse and skips the current item + already-watched titles.
    static func next(after item: Catalog.Item, mode: AutoplayMode,
                     source: ContinuousPlaybackSource) -> Catalog.Item? {
        switch mode {
        case .off:
            return nil
        case .surprise:
            for _ in 0..<5 {
                if let r = source.randomPlayableItem(),
                   r.archiveID != item.archiveID, r.videoURLParsed != nil {
                    return r
                }
            }
            return nil
        case .sameCategory:
            return pick(source.browseItems(contentType: item.contentType, decade: nil, limit: 80),
                        excluding: item, source: source)
        case .sameYear:
            guard item.decade != nil else { return nil }
            return pick(source.browseItems(contentType: nil, decade: item.decade, limit: 80),
                        excluding: item, source: source)
        }
    }

    private static func pick(_ pool: [Catalog.Item], excluding item: Catalog.Item,
                             source: ContinuousPlaybackSource) -> Catalog.Item? {
        pool.filter {
            $0.archiveID != item.archiveID &&
            $0.videoURLParsed != nil &&
            !source.completedArchiveIDs.contains($0.archiveID)
        }.randomElement()
    }
}
