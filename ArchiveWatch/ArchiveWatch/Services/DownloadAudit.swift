#if os(iOS) || os(macOS)
import Foundation
import SwiftData
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// The offline-downloads feature, exercised END TO END on the device
// (`AW_DOWNLOAD_AUDIT=1`), reported on stdout for `devicectl … --console`.
//
// Same tier and same discipline as `FunctionalAudit` on tvOS: between a
// compile and a human with the device in their hand, assert what the code
// actually DID — a real transfer from archive.org, a real file on disk, a real
// AVPlayer decoding it — never what it reported about itself.
//
// WHY this exists rather than a UI walkthrough: a physical iPhone cannot be put
// into airplane mode from here, so "it plays offline" cannot be demonstrated by
// severing the network on device. It can be PROVEN a better way — assert that
// the asset the player is handed is a `file://` URL and that AVFoundation
// decodes it. A file URL cannot reach the network by construction, so playing
// one is offline playback whatever the radio is doing. The genuinely-severed
// run happens on the Mac, where the Wi-Fi can be switched off
// (`tools/download_audit.py --mac`).
//
// The audit MUTATES: it downloads a film and then removes it. It deliberately
// picks a vintage commercial (a few MB, Decision "commercials" pool) so a run
// costs seconds, and it cleans up after itself — including on failure.
@MainActor
enum DownloadAudit {

    private static var passed = 0
    private static var failed = 0

    /// `AW_DOWNLOAD_AUDIT` — `1` (download, verify, remove), `prepare`
    /// (download and LEAVE it), `offline` (assert against what is on disk,
    /// with the network genuinely severed), `cleanup`.
    static var mode: String? {
        ProcessInfo.processInfo.environment["AW_DOWNLOAD_AUDIT"]
    }

    static var enabled: Bool { mode != nil }

    private static func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { passed += 1 } else { failed += 1 }
        print("[AWDLAUDIT] \(ok ? "PASS" : "FAIL") \(name) — \(detail)")
    }

    static func run(store: AppStore, container: ModelContainer) async {
        // Swift's `print` is BLOCK-buffered when stdout is not a tty, so a Mac
        // run piped into a harness produced nothing at all for nine minutes
        // while the verdicts sat in the buffer. `devicectl --console` on a
        // phone is unbuffered, which is exactly why iOS looked fine and macOS
        // looked hung. Unbuffer it before the first line is written.
        setvbuf(stdout, nil, _IONBF, 0)
        passed = 0; failed = 0
        // `configure` is a SIBLING .task on the same view, and SwiftUI gives no
        // ordering between siblings — so the audit cannot assume the manager is
        // wired. configure() is idempotent; calling it here removes the race.
        DownloadManager.shared.configure(container: container)
        let mode = Self.mode ?? "1"
        print("[AWDLAUDIT] BEGIN mode=\(mode)")

        if mode == "cleanup" {
            DownloadManager.shared.removeAll()
            check("cleanup", OfflineLibrary.bytesUsed() == 0,
                  OfflineLibrary.byteText(OfflineLibrary.bytesUsed()) + " left")
            print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
            return
        }
        if mode == "offline" {
            await runOffline(store: store, container: container)
            print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
            return
        }

        // The FULL catalog: the commercials pool is not in the bundled seed.
        for _ in 0..<120 {
            if (store.db?.itemCount ?? 0) > 10_000 { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard let db = store.db else {
            print("[AWDLAUDIT] FAIL catalog — no DB open; nothing else can run")
            print("[AWDLAUDIT] SUMMARY passed=0 failed=1")
            return
        }
        check("catalog", db.itemCount > 10_000, "\(db.itemCount) items open")

        // MARK: pick something small and real

        let override = ProcessInfo.processInfo.environment["AW_DOWNLOAD_AUDIT_ID"]
        var target: Catalog.Item?
        var versions: [ArchiveVersions.Version] = []
        if let override, let item = store.item(override) {
            target = item
            versions = await ArchiveVersions.list(itemID: item.archiveID)
        } else {
            // Vintage commercials are a few MB each — a real archive.org
            // transfer that finishes inside an audit rather than a coffee break.
            for candidate in store.randomCommercials(limit: 8)
                where candidate.videoURLParsed != nil {
                let list = await ArchiveVersions.list(itemID: candidate.archiveID)
                // 40 MB, not 120: a 101.6 MB "commercial" (Randall Parker's
                // additional footage) was still transferring when the budget
                // ran out and reported as a FAILURE of the feature, which it
                // was not. An audit's candidate has to fit its own clock.
                guard let smallest = list.min(by: { $0.sizeBytes < $1.sizeBytes }),
                      smallest.sizeBytes < 40_000_000 else { continue }
                target = candidate
                versions = list
                break
            }
        }
        guard let item = target else {
            check("candidate", false, "no small downloadable title found")
            print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
            return
        }
        let pick = versions.min(by: { $0.sizeBytes < $1.sizeBytes })
        check("candidate", true,
              "\(item.archiveID) — \(item.title) · "
              + (pick.map { "\($0.compactLabel)" } ?? "catalog default copy"))

        // Never audit on top of a real download the owner made.
        if OfflineLibrary.isDownloaded(item.archiveID) {
            DownloadManager.shared.remove(item.archiveID)
        }

        // MARK: space

        let free = OfflineLibrary.availableBytes()
        check("space.reported", free != nil,
              free.map { "\(OfflineLibrary.byteText($0)) free" } ?? "capacity unknown")
        if let size = pick?.sizeBytes {
            check("space.hasRoom", OfflineLibrary.hasRoom(for: size),
                  "needs \(OfflineLibrary.byteText(size)) + 1 GB reserve")
        }

        // MARK: the transfer

        let err = DownloadManager.shared.start(item: item, version: pick)
        check("start", err == nil, err ?? "accepted")
        guard err == nil else { return finish(item.archiveID) }

        let ctx = container.mainContext
        func row() -> DownloadedFilm? { DownloadManager.shared.row(for: item.archiveID) }
        check("row.created", row() != nil, "DownloadedFilm inserted, state=\(row()?.stateRaw ?? "-")")

        var sawProgress = false
        var partialHidden = true
        // A check that never had the chance to fail is not a passing check —
        // this repo has shipped a tautology before. A few-MB commercial can
        // finish between polls, so record whether an in-flight state was ever
        // actually OBSERVED and report SKIP rather than a hollow PASS.
        var sawActive = false
        var completed = false
        for _ in 0..<300 {                       // up to 5 minutes
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let p = DownloadManager.shared.progress(for: item.archiveID), p.received > 0 {
                sawProgress = true
            }
            // THE invariant that keeps a half-file away from the player: while
            // the transfer runs, the finished name must not exist.
            if let r = row(), r.state.isActive {
                sawActive = true
                if OfflineLibrary.isDownloaded(item.archiveID) { partialHidden = false }
            }
            if row()?.state == .completed { completed = true; break }
            if row()?.state == .failed { break }
        }
        check("progress.observed", sawProgress, "bytes were reported while transferring")
        if sawActive {
            check("partial.hidden", partialHidden,
                  "videoURL stayed nil until the rename (no half-file reaches the player)")
        } else {
            print("[AWDLAUDIT] SKIP partial.hidden — the transfer finished between polls, "
                  + "so the in-flight state was never observed")
        }
        check("complete", completed,
              "state=\(row()?.stateRaw ?? "-") \(row()?.errorText ?? "")")
        guard completed else { return finish(item.archiveID) }

        // MARK: the file

        guard let local = OfflineLibrary.videoURL(for: item.archiveID) else {
            check("file.exists", false, "no file at the expected path")
            return finish(item.archiveID)
        }
        let size = OfflineLibrary.bytesUsed(by: item.archiveID)
        check("file.exists", size > 1_000_000, "\(OfflineLibrary.byteText(size)) on disk")
        check("file.location", local.path.contains("Application Support"),
              // Caches is purgeable — the whole reason downloads are n/a on
              // tvOS. Landing there would silently break the airplane case.
              local.deletingLastPathComponent().path)
        let excluded = (try? OfflineLibrary.directory?
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? nil
        check("file.excludedFromBackup", excluded == true,
              "isExcludedFromBackup=\(String(describing: excluded))")
        if let expected = pick?.sizeBytes {
            let delta = abs(size - expected)
            check("file.completeBytes", delta < max(2_000_000, expected / 100),
                  "\(size) on disk vs \(expected) advertised")
        }

        // MARK: the thing the player will actually do

        // This is the offline proof: the URL handed to AVFoundation is a local
        // file, so no network can be involved in decoding it.
        check("asset.isLocalFile", local.isFileURL, local.scheme ?? "nil scheme")

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let asset = AVURLAsset(url: local)
        let duration = try? await asset.load(.duration)
        let seconds = duration.map(CMTimeGetSeconds) ?? 0
        check("asset.readable", seconds > 1,
              "AVFoundation read \(String(format: "%.1fs", seconds)) of duration from disk")

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.play()
        var advanced = 0.0
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            advanced = player.currentTime().seconds
            if advanced > 0.4 { break }
        }
        check("playback.advances", advanced > 0.4,
              "playhead reached \(String(format: "%.2fs", advanced)) decoding the local file")
        check("playback.noError", playerItem.error == nil,
              playerItem.error?.localizedDescription ?? "no item error")
        player.pause()

        // MARK: companions

        if item.posterURL != nil {
            check("poster.cached", OfflineLibrary.posterURL(for: item.archiveID) != nil,
                  "local poster for the Downloads list with no network")
        }
        if row()?.hasSubtitles == true {
            let subs = OfflineSubtitles(archiveID: item.archiveID)
            check("subtitles.parsed", subs != nil && !(subs?.isEmpty ?? true),
                  "downloaded WebVTT parsed into cues")
        } else {
            print("[AWDLAUDIT] SKIP subtitles — this title publishes none")
        }
        check("storage.counted", OfflineLibrary.bytesUsed() > 0,
              OfflineLibrary.byteText(OfflineLibrary.bytesUsed()))

        // MARK: removal — the owner's "easily removed from there as well"

        if mode == "prepare" {
            print("[AWDLAUDIT] KEPT \(item.archiveID) | \(item.title) | "
                  + "\(pick?.compactLabel ?? "") — left on disk for the offline run")
            print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
            return
        }
        DownloadManager.shared.remove(item.archiveID)
        try? ctx.save()
        check("remove.file", OfflineLibrary.videoURL(for: item.archiveID) == nil,
              "video gone")
        check("remove.allFiles", OfflineLibrary.bytesUsed(by: item.archiveID) == 0,
              "poster, subtitles and resume data gone too")
        check("remove.row", DownloadManager.shared.row(for: item.archiveID) == nil,
              "DownloadedFilm deleted (device-local: no tombstone, §9.7)")

        print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
    }

    /// The pass that runs with the network actually switched off.
    ///
    /// Carries its own NEGATIVE CONTROL: a remote URL must FAIL to load. Without
    /// it, "the film played" is not evidence — it is equally consistent with the
    /// Wi-Fi never having gone down, which is exactly the kind of false pass
    /// this project has been bitten by before (a tautological check, a spoofed
    /// UA drawing 429s, a probe reading a previous player's leftover track).
    private static func runOffline(store: AppStore, container: ModelContainer) async {
        // 1. Is the network REALLY down? Ask the OS, then PROVE it.
        //
        // `AW_OFFLINE_KIND=sockets` means the harness denied this process the
        // network rather than switching the interface off (the Mac's Wi-Fi
        // carries the session driving the test, so switching it off would be
        // one-way). NWPathMonitor watches the INTERFACE, which is still up, so
        // its answer is reported and not judged in that mode — the negative
        // control below is what establishes the severing either way.
        let kind = ProcessInfo.processInfo.environment["AW_OFFLINE_KIND"] ?? "interface"
        NetworkMonitor.shared.start()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if kind == "sockets" {
            print("[AWDLAUDIT] NOTE offline.detected — not judged under socket-level "
                  + "denial (NWPathMonitor watches the interface, which is up); "
                  + "isOnline=\(NetworkMonitor.shared.isOnline)")
        } else {
            check("offline.detected", !NetworkMonitor.shared.isOnline,
                  "NWPathMonitor reports isOnline=\(NetworkMonitor.shared.isOnline)")
        }

        var req = URLRequest(url: URL(string: "https://archive.org/metadata/nasa")!)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        var reachedNetwork = false
        do {
            _ = try await URLSession(configuration: .ephemeral).data(for: req)
            reachedNetwork = true
        } catch {
            check("offline.control", true, "archive.org unreachable: \(error.localizedDescription)")
        }
        if reachedNetwork {
            check("offline.control", false,
                  "archive.org ANSWERED — the network is up, so nothing below is offline evidence")
        }

        // 2. The app itself is usable: the catalog is a local SQLite file.
        for _ in 0..<60 {
            if (store.db?.itemCount ?? 0) > 10_000 { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let count = store.db?.itemCount ?? 0
        check("offline.catalog", count > 10_000, "\(count) items browsable with no network")
        let found = store.db?.search("chaplin", limit: 5).count ?? 0
        check("offline.search", found > 0, "FTS5 search returned \(found) results offline")

        // 3. The Library holds a real, playable film.
        let ctx = container.mainContext
        let rows = (try? ctx.fetch(FetchDescriptor<DownloadedFilm>())) ?? []
        let ready = rows.filter { $0.isPlayableOffline }
        check("offline.library", !ready.isEmpty,
              "\(ready.count) of \(rows.count) downloads present on disk")
        guard let row = ready.first, let local = row.localURL else { return }

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let asset = AVURLAsset(url: local)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        check("offline.assetReadable", seconds > 1,
              "\(row.title): \(String(format: "%.1fs", seconds)) read from disk")
        let pItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: pItem)
        player.isMuted = true
        player.play()
        var advanced = 0.0
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            advanced = player.currentTime().seconds
            if advanced > 0.5 { break }
        }
        check("offline.playback", advanced > 0.5,
              "playhead reached \(String(format: "%.2fs", advanced)) WITH THE NETWORK DOWN")
        check("offline.noError", pItem.error == nil,
              pItem.error?.localizedDescription ?? "no item error")
        player.pause()

        if OfflineSubtitles(archiveID: row.archiveID) != nil {
            check("offline.subtitles", true, "downloaded cues available with no network")
        }
    }

    /// Leave nothing behind on a device the owner uses.
    private static func finish(_ archiveID: String) {
        DownloadManager.shared.remove(archiveID)
        print("[AWDLAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
    }
}
#endif
