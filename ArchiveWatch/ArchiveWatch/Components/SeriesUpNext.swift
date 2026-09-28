import Foundation
import SwiftData

/// What a series page's primary action plays (tvOS-DESIGN §3.4b, iOS-DESIGN
/// §3.5d): the episode after the one most recently watched — that one again
/// when it was left partway, the next in order when it was finished, and the
/// first episode when nothing of the show has been watched. One rule for every
/// Apple platform.
struct SeriesUpNext: Equatable {
    enum Verb: String { case play = "Play", resume = "Resume", next = "Next" }
    let verb: Verb
    let episode: Episode

    var label: String {
        if let s = episode.seasonNumber, let e = episode.episodeNumber {
            return "\(verb.rawValue) S\(s), E\(e)"
        }
        if let e = episode.episodeNumber { return "\(verb.rawValue) Episode \(e)" }
        return verb.rawValue
    }

    @MainActor
    static func compute(for series: Series?, in context: ModelContext) -> SeriesUpNext? {
        let episodes = (series?.seasons ?? []).flatMap(\.episodes)
            .filter { $0.videoURLParsed != nil }
        guard let first = episodes.first else { return nil }
        let ids = episodes.map(\.archiveID)
        let seen = (try? context.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { ids.contains($0.archiveID) }))) ?? []
        guard let last = seen.max(by: { $0.lastWatchedAt < $1.lastWatchedAt }),
              let i = episodes.firstIndex(where: { $0.archiveID == last.archiveID })
        else { return SeriesUpNext(verb: .play, episode: first) }
        if !last.isComplete, last.positionSeconds > 10 {
            return SeriesUpNext(verb: .resume, episode: episodes[i])
        }
        if i + 1 < episodes.count { return SeriesUpNext(verb: .next, episode: episodes[i + 1]) }
        return SeriesUpNext(verb: .play, episode: first)
    }
}
