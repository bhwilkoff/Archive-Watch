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

@MainActor
enum ContinuousPlayback {
    /// The next item to autoplay after `item` under `mode`, or nil (mode off, or
    /// nothing playable/fresh fits). Honors the adult/hidden filters via dbBrowse
    /// and skips the current item + already-watched titles.
    static func next(after item: Catalog.Item, mode: AutoplayMode, store: AppStore) -> Catalog.Item? {
        switch mode {
        case .off:
            return nil
        case .surprise:
            for _ in 0..<5 {
                if let r = store.dbRandomPlayable(),
                   r.archiveID != item.archiveID, r.videoURLParsed != nil {
                    return r
                }
            }
            return nil
        case .sameCategory:
            return pick(store.dbBrowse(contentType: item.contentType, sort: .popular, limit: 80),
                        excluding: item, store: store)
        case .sameYear:
            guard item.decade != nil else { return nil }
            return pick(store.dbBrowse(decade: item.decade, sort: .popular, limit: 80),
                        excluding: item, store: store)
        }
    }

    private static func pick(_ pool: [Catalog.Item], excluding item: Catalog.Item,
                             store: AppStore) -> Catalog.Item? {
        pool.filter {
            $0.archiveID != item.archiveID &&
            $0.videoURLParsed != nil &&
            !store.completedArchiveIDs.contains($0.archiveID)
        }.randomElement()
    }
}
