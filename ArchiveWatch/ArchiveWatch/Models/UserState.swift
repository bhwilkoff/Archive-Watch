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

    init(archiveID: String, positionSeconds: Double = 0, durationSeconds: Double = 0) {
        self.archiveID = archiveID
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.lastWatchedAt = Date()
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
