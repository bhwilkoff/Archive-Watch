#if os(iOS) || os(macOS)
import Foundation

// Where a downloaded film lives on THIS device.
//
// Apple's data-storage guidelines put re-downloadable content the user expects
// offline in Application Support with `isExcludedFromBackup` — NOT in Caches.
// Caches is what tvOS gives an app (and the whole reason downloads are n/a
// there, PARITY §"Offline downloads"): the system may delete a Caches file
// between launches, which for this feature means the film you packed for a
// flight is gone at 30,000 feet. Application Support is never purged; the
// backup exclusion keeps a 900 MB public-domain film out of the viewer's
// iCloud backup, where Apple would reject it.
//
// The file NAME is derived from the archiveID alone, so `videoURL(for:)` is a
// synchronous file-exists check with no database round trip — the players call
// it on the way to building an AVPlayerItem. A download in flight writes to
// `.partial`, so the presence of the final name IS the completion signal and a
// half-downloaded film can never be handed to the player.
enum OfflineLibrary {

    /// Directory holding every downloaded film, poster and subtitle file.
    /// Created on first use and marked do-not-back-up.
    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
        else { return nil }
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            // On iOS Application Support does not exist until someone makes it.
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    /// archiveIDs are file-system safe in practice, but the catalog holds ids
    /// from an open upload system — never trust one as a path component.
    static func safeName(_ archiveID: String) -> String {
        let mapped = archiveID.unicodeScalars.map {
            (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_")
                ? Character($0) : "_"
        }
        return String(mapped)
    }

    // MARK: - Paths

    private static func path(_ archiveID: String, _ ext: String) -> URL? {
        directory?.appendingPathComponent("\(safeName(archiveID)).\(ext)")
    }

    /// The finished film, or nil when this title is not downloaded.
    /// THE lookup every player and every "is it downloaded?" check goes through.
    static func videoURL(for archiveID: String) -> URL? {
        guard let u = path(archiveID, "mp4"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    static func isDownloaded(_ archiveID: String) -> Bool { videoURL(for: archiveID) != nil }

    /// Where a download in flight lands. Renamed to `videoURL` only on success.
    static func partialURL(for archiveID: String) -> URL? { path(archiveID, "partial") }

    /// URLSession resume data for an interrupted or paused download.
    static func resumeDataURL(for archiveID: String) -> URL? { path(archiveID, "resume") }

    /// Locally cached poster, so the Downloads shelf has artwork with no network.
    static func posterURL(for archiveID: String) -> URL? {
        guard let u = path(archiveID, "jpg"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    static func posterWriteURL(for archiveID: String) -> URL? { path(archiveID, "jpg") }

    /// The published WebVTT, downloaded alongside the film so its human
    /// subtitles survive the flight (Decision 099).
    static func subtitleURL(for archiveID: String) -> URL? {
        guard let u = path(archiveID, "vtt"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    static func subtitleWriteURL(for archiveID: String) -> URL? { path(archiveID, "vtt") }

    // MARK: - Space

    /// Bytes this title occupies on disk (film + poster + subtitles).
    static func bytesUsed(by archiveID: String) -> Int64 {
        [videoURL(for: archiveID), posterURL(for: archiveID), subtitleURL(for: archiveID),
         partialURL(for: archiveID)]
            .compactMap { $0 }
            .reduce(Int64(0)) { $0 + fileSize($1) }
    }

    /// Bytes every download occupies, for the Settings storage line.
    static func bytesUsed() -> Int64 {
        guard let dir = directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return 0 }
        return names.reduce(Int64(0)) { $0 + fileSize(dir.appendingPathComponent($1)) }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    /// Free space the system will actually give us for a download.
    ///
    /// `volumeAvailableCapacityForImportantUsage` — not `...ForOpportunisticUsage`
    /// and not the raw capacity: it is the number that accounts for purgeable
    /// space the OS will free on demand, which is what a user-initiated download
    /// is entitled to. It reports 0 rather than throwing on a volume that cannot
    /// answer, so treat 0 as "unknown", never as "full".
    static func availableBytes() -> Int64? {
        guard let dir = directory,
              let v = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = v.volumeAvailableCapacityForImportantUsage, capacity > 0
        else { return nil }
        return capacity
    }

    /// Headroom kept free so a download can never be the thing that fills a
    /// phone — iOS starts behaving badly (and refuses OS updates) well before 0.
    static let reservedBytes: Int64 = 1_000_000_000

    /// Whether `bytes` fits, leaving the reserve intact. Unknown capacity → allow
    /// (the download itself will fail with a real error rather than a guess).
    static func hasRoom(for bytes: Int64) -> Bool {
        guard let free = availableBytes() else { return true }
        return free > bytes + reservedBytes
    }

    // MARK: - Removal

    /// Delete every file belonging to a title. Safe to call when nothing exists.
    static func removeFiles(for archiveID: String) {
        for ext in ["mp4", "partial", "resume", "jpg", "vtt"] {
            if let u = path(archiveID, ext) { try? FileManager.default.removeItem(at: u) }
        }
    }

    static func byteText(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
#endif
