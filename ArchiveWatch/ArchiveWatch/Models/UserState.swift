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
