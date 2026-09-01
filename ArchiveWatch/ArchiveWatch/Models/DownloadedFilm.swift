#if os(iOS) || os(macOS)
import Foundation
import SwiftData

// A film the viewer has asked to keep on THIS device (Decision 099).
//
// DEVICE-LOCAL, and deliberately NOT synced — the one user model that is not
// (iOS-DESIGN §9.7). Favorites and progress describe an intention, which is the
// same on every device; a download describes a FILE, which exists on exactly
// one. Syncing this row would put a title in the iPhone's Downloads that lives
// only on the Mac — a promise the app cannot keep, and precisely the failure
// mode Decision 085 had to repair for merged-away ids. So it never goes through
// `SyncNudge` and never appears in the CloudKit payload: a bare `ctx.delete` is
// CORRECT here, the single exception to §9.4.
//
// The row carries denormalised title/year/runtime/poster so the Downloads list
// renders with the catalog absent entirely — the point of the feature is that
// it works when nothing else can be reached.
@Model
final class DownloadedFilm {
    @Attribute(.unique) var archiveID: String
    var title: String
    var year: Int?
    var runtimeSeconds: Int?
    var posterURLString: String?
    /// The archive.org copy being fetched. Stored so a paused download resumes
    /// the SAME transfer the viewer chose, not whatever the pipeline now picks.
    var remoteURLString: String
    /// The `ArchiveVersions` label of the chosen copy — "480p · H.264 · 575 MB".
    /// Shown verbatim in the Downloads list: what is on this device is a
    /// specific transfer of a film, and saying so is the honest thing.
    var qualityLabel: String?
    var expectedBytes: Int64
    var receivedBytes: Int64
    var stateRaw: String
    var errorText: String?
    var addedAt: Date
    var completedAt: Date?
    /// Set when the published WebVTT came down with the film.
    var hasSubtitles: Bool

    init(archiveID: String, title: String, year: Int? = nil, runtimeSeconds: Int? = nil,
         posterURLString: String? = nil, remoteURLString: String,
         qualityLabel: String? = nil, expectedBytes: Int64 = 0) {
        self.archiveID = archiveID
        self.title = title
        self.year = year
        self.runtimeSeconds = runtimeSeconds
        self.posterURLString = posterURLString
        self.remoteURLString = remoteURLString
        self.qualityLabel = qualityLabel
        self.expectedBytes = expectedBytes
        self.receivedBytes = 0
        self.stateRaw = DownloadState.queued.rawValue
        self.addedAt = Date()
        self.hasSubtitles = false
    }

    var state: DownloadState {
        get { DownloadState(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    /// 0–1 from the persisted counters. The live figure while a transfer runs
    /// comes from `DownloadManager.progress(for:)`; this is what survives a
    /// relaunch, and what a paused row shows.
    var fraction: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }

    /// The finished film on disk, or nil. Asks the FILE SYSTEM, never the row:
    /// a row can say completed while the file was deleted from under it (a
    /// restore, a Mac user in Finder), and the player must never be handed a
    /// path that is not there.
    var localURL: URL? { OfflineLibrary.videoURL(for: archiveID) }

    var isPlayableOffline: Bool { localURL != nil }
}

enum DownloadState: String, Sendable {
    /// Accepted, waiting for the session to start the transfer.
    case queued
    case downloading
    /// Stopped by the viewer, or interrupted with resume data banked.
    case paused
    case completed
    case failed

    var isActive: Bool { self == .queued || self == .downloading }
}
#endif
