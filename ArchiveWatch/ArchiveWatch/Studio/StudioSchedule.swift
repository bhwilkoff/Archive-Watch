// Watch-alongs scheduled ahead of time (macOS-DESIGN §D39).
//
// What the Mac remembers about a YouTube broadcast it scheduled: enough to go
// live on it later, and nothing that is a credential. The stream KEY is never
// here — go-live reads it again from the stream (`YouTubeLive.credentials
// (forScheduled:)`), exactly as a new broadcast reads it from a new stream.
//
// Foundation only: the §8.72 harness compiles this file without the app.

import Foundation

struct StudioScheduledShow: Codable, Sendable, Equatable, Identifiable {
    let broadcastID: String
    let streamID: String
    let archiveID: String
    /// The chosen file, `<item>/<file>` (Decision 143), so the show that was
    /// announced is the copy that plays.
    let copy: String?
    var title: String
    /// Exactly what was sent, because `liveBroadcasts.update` replaces the
    /// snippet and a reschedule that omitted it would erase it.
    var description: String
    var start: Date
    /// `YouTubePrivacy.rawValue`.
    let privacy: String

    var id: String { broadcastID }
}

/// The list, in `UserDefaults`. A schedule is a few rows; a database would be
/// a second store to keep honest for something this small.
enum StudioSchedule {
    static let defaultsKey = "studio.scheduledShows"
    /// A show this far past its start is over or abandoned. YouTube keeps an
    /// unstarted broadcast in Upcoming indefinitely, but the Mac stops offering
    /// it: a show twelve hours late is not the show that was announced.
    static let staleAfter: TimeInterval = 12 * 3600

    static func load(from defaults: UserDefaults = .standard) -> [StudioScheduledShow] {
        guard let data = defaults.data(forKey: defaultsKey),
              let shows = try? JSONDecoder().decode([StudioScheduledShow].self, from: data)
        else { return [] }
        return shows
    }

    static func save(_ shows: [StudioScheduledShow], to defaults: UserDefaults = .standard) {
        let sorted = shows.sorted { $0.start < $1.start }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Drops what is more than `staleAfter` past its start, and says what is
    /// left. Called when the Studio opens.
    @discardableResult
    static func prune(now: Date = Date(), defaults: UserDefaults = .standard) -> [StudioScheduledShow] {
        let kept = load(from: defaults).filter { now.timeIntervalSince($0.start) <= staleAfter }
        save(kept, to: defaults)
        return kept
    }

    static func upsert(_ show: StudioScheduledShow, defaults: UserDefaults = .standard) {
        var all = load(from: defaults).filter { $0.broadcastID != show.broadcastID }
        all.append(show)
        save(all, to: defaults)
    }

    static func remove(broadcastID: String, defaults: UserDefaults = .standard) {
        save(load(from: defaults).filter { $0.broadcastID != broadcastID }, to: defaults)
    }

    /// The scheduled shows Go Live may offer for this film. Go Live NEVER
    /// picks one on its own: exactly one is offered as the default choice,
    /// several are the host's to pick, none leaves today's path (§D39).
    static func matching(archiveID: String, in shows: [StudioScheduledShow],
                         now: Date = Date()) -> [StudioScheduledShow] {
        shows.filter { $0.archiveID == archiveID && now.timeIntervalSince($0.start) <= staleAfter }
            .sorted { $0.start < $1.start }
    }
}
