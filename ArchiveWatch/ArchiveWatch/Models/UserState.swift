import Foundation
import SwiftData

// User state lives in SwiftData (Decision 009 — no accounts, no cloud).
// WatchProgress tracks resume positions; Favorite is a thumbs-up set.
// Both key on archiveID so they survive catalog refreshes.

@Model
final class WatchProgress {
    @Attribute(.unique) var archiveID: String
    var positionSeconds: Double
    var durationSeconds: Double
    var lastWatchedAt: Date
    // When the archiveID belongs to a TV episode, `seriesID` is set so
    // Continue Watching can surface the parent series card (episodes
    // don't appear in the main catalog by themselves). Nil for films.
    var seriesID: String?
    var episodeTitle: String?

    // WATCH HISTORY (owner, 2026-08-15: "a full record of every movie/video
    // you have ever watched"). All optional so existing stores migrate
    // lightweight and older sync payloads decode unchanged.
    /// When this title was FIRST watched on any device (min across devices).
    var firstWatchedAt: Date?
    /// Distinct viewing sessions (a new session = >6h since the last write;
    /// max across devices).
    var playCount: Int?
    /// Once true, always true — a rewatch resets positionSeconds but must
    /// never take away "you have watched this" (OR across devices).
    var everCompleted: Bool?
    var completedAt: Date?

    init(archiveID: String, positionSeconds: Double = 0, durationSeconds: Double = 0,
         seriesID: String? = nil, episodeTitle: String? = nil) {
        self.archiveID = archiveID
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.lastWatchedAt = Date()
        self.seriesID = seriesID
        self.episodeTitle = episodeTitle
    }

    /// 0–1. Zero when we don't know duration yet.
    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, positionSeconds / durationSeconds)
    }

    /// Treat anything past 95% as finished — hide from Continue Watching.
    var isComplete: Bool {
        guard durationSeconds > 0 else { return false }
        return positionSeconds / durationSeconds >= 0.95
    }

    /// "Have I watched this?" — durable across rewatches. The Watched shelf
    /// and per-title badges read THIS, not isComplete: before everCompleted
    /// existed, resuming a finished film from the start silently erased its
    /// watched status everywhere.
    var isWatched: Bool { everCompleted == true || isComplete }

    /// THE one write path for playback progress + watch history, shared by
    /// every platform's player (tvOS DetailView, iOS PlayerView, macOS
    /// PlayerWindow). History semantics live here once: first-watch date,
    /// session counting (>6h gap = new session), and the durable
    /// everCompleted flag. `historyOnly` records THAT a title was watched
    /// (channel tune-ins) without touching the resume position, so Continue
    /// Watching never sees channel programs — the invariant that predates
    /// this history work.
    @MainActor
    static func record(in ctx: ModelContext, archiveID: String,
                       position: Double, duration: Double?,
                       historyOnly: Bool = false) {
        guard position.isFinite, position > 0 else { return }
        if historyOnly, position < 60 { return }   // a channel-surf is not "watched"
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID })
        let now = Date()
        do {
            if let w = try ctx.fetch(descriptor).first {
                if now.timeIntervalSince(w.lastWatchedAt) > 6 * 3600 {
                    w.playCount = (w.playCount ?? 1) + 1
                }
                if w.firstWatchedAt == nil {
                    w.firstWatchedAt = min(w.lastWatchedAt, now)
                }
                if !historyOnly {
                    w.positionSeconds = position
                    if let d = duration, d.isFinite, d > 0 { w.durationSeconds = d }
                    if w.isComplete, w.everCompleted != true {
                        w.everCompleted = true
                        w.completedAt = now
                    }
                }
                w.lastWatchedAt = now
            } else {
                let w = WatchProgress(
                    archiveID: archiveID,
                    positionSeconds: historyOnly ? 0 : position,
                    durationSeconds: historyOnly ? 0
                        : ((duration?.isFinite == true) ? (duration ?? 0) : 0))
                w.firstWatchedAt = now
                w.playCount = 1
                if w.isComplete { w.everCompleted = true; w.completedAt = now }
                ctx.insert(w)
            }
            try ctx.save()
        } catch {
            // Progress persistence must never take down playback.
        }
    }

    /// Mark a title watched, or un-mark it, by the viewer's own choice.
    ///
    /// Playback infers completion, but inference is not always right — a film
    /// abandoned at 92% reads as finished, and one seen elsewhere never
    /// registers at all. Since "watched" is now shown as a badge rather than a
    /// separate list (owner, 2026-08-17), the viewer needs a way to correct it,
    /// so this is the same durable `everCompleted` flag the sync merges as a
    /// union — never a second source of truth.
    @discardableResult
    static func setWatched(_ watched: Bool, in ctx: ModelContext,
                           archiveID: String) -> Bool {
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID })
        do {
            let now = Date()
            let record = try ctx.fetch(descriptor).first ?? {
                let w = WatchProgress(archiveID: archiveID,
                                      positionSeconds: 0, durationSeconds: 0)
                w.firstWatchedAt = now
                w.playCount = 1
                ctx.insert(w)
                return w
            }()
            record.everCompleted = watched
            record.completedAt = watched ? (record.completedAt ?? now) : nil
            // Un-marking must also clear a position that would otherwise put the
            // title straight back into Continue Watching at 99%.
            if !watched, record.isComplete { record.positionSeconds = 0 }
            record.lastWatchedAt = now
            try ctx.save()
            return true
        } catch {
            return false
        }
    }
}

@Model
final class Favorite {
    @Attribute(.unique) var archiveID: String
    var addedAt: Date

    init(archiveID: String) {
        self.archiveID = archiveID
        self.addedAt = Date()
    }
}

// #12: a user-created playlist / custom collection. Ordered archiveIDs kept on
// the model (small lists); resolved to Catalog.Items at display time. CloudKit
// mirror lands with #11 (Decision 022).
@Model
final class Playlist {
    @Attribute(.unique) var id: String
    var name: String
    var archiveIDs: [String]
    var createdAt: Date
    // #11b: last local edit time. CloudKit sync merges playlists by RECENCY
    // (last-writer-wins) so a removal propagates — the old count-based merge
    // could never shrink a list. Defaulted for lightweight migration of stores
    // created before this field existed.
    var modifiedAt: Date = Date.distantPast

    init(id: String = UUID().uuidString, name: String, archiveIDs: [String] = []) {
        self.id = id
        self.name = name
        self.archiveIDs = archiveIDs
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    func contains(_ archiveID: String) -> Bool { archiveIDs.contains(archiveID) }

    /// Stamp an edit so sync treats this device's copy as the newest.
    func touch() { modifiedAt = Date() }
}

// #11b (Decision 022): a record that a synced item was DELETED, with when. Local
// SwiftData drops a deleted row entirely, so without this a deletion can't beat a
// stale cloud copy on pull — the item would resurrect. Tombstones are pushed to
// CloudKit so every device learns of the deletion; last-writer-wins by timestamp
// (a re-add newer than the tombstone clears it). Keyed "fav:<id>" / "pl:<id>" /
// "wp:<id>" / "ch:<id>".
@Model
final class Tombstone {
    @Attribute(.unique) var key: String
    var deletedAt: Date

    init(key: String, deletedAt: Date = Date()) {
        self.key = key
        self.deletedAt = deletedAt
    }
}

// #1b: a user-created 24-hour channel — a saved full-DB filter (any combination
// of genre / content type / decade) realized as a continuous lineup via the same
// engine as the preset channels. Syncs with #11 once enabled.
@Model
final class UserChannel {
    @Attribute(.unique) var id: String
    var name: String
    var genre: String?
    var contentType: String?
    var decade: Int?
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String,
         genre: String? = nil, contentType: String? = nil, decade: Int? = nil) {
        self.id = id
        self.name = name
        self.genre = genre
        self.contentType = contentType
        self.decade = decade
        self.createdAt = Date()
    }
}
