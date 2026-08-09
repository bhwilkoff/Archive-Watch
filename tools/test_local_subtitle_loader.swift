// Proves the on-device subtitle path END TO END against the SHIPPED files:
// SubtitleStore writes a VTT + playlists, LocalSubtitleHLSLoader serves them
// through a custom scheme, and AVFoundation plays the remote film with a
// working CC menu.
//
// This exists because the shape it replaces — handing AVPlayer a `file://`
// master — was asserted throughout the code and never executed. It does not
// work (see test_local_master_playback.swift). A feature whose only proof is
// that it compiles is not proven.
//
// Compile the real sources, not copies:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleStore.swift \
//     ArchiveWatch/ArchiveWatch/Networking/LocalSubtitleHLSLoader.swift \
//     tools/test_local_subtitle_loader.swift -o /tmp/awsubs && /tmp/awsubs <mp4-url>

import AVFoundation
import Foundation

@main
struct Harness {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        print(ok ? "  PASS  \(what)" : "  FAIL  \(what) \(detail)")
        if !ok { failures += 1 }
    }

    static func main() async {
        let args = CommandLine.arguments
        let video = URL(string: args.count > 1 ? args[1]
                        : "https://archive.org/download/phantom_thunderbolt/phantom_thunderbolt.mp4")!
        let id = "aw-harness-\(UUID().uuidString.prefix(8))"

        let vtt = """
        WEBVTT
        X-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000

        1
        00:00:02.000 --> 00:00:06.000
        Archive Watch on-device subtitle probe.

        2
        00:00:08.000 --> 00:00:12.000
        Second cue, so the track is not degenerate.

        """

        print("on-device subtitle path — \(video.lastPathComponent)")

        guard let master = SubtitleStore.store(vtt: vtt, for: id, videoURL: video,
                                               runtime: 3270, label: "English") else {
            print("  FAIL  SubtitleStore.store returned nil"); exit(1)
        }
        check(FileManager.default.fileExists(atPath: master.path), "store writes a master playlist")
        check(SubtitleStore.cachedHLS(for: id) != nil, "cachedHLS finds it again")
        check(SubtitleStore.hasCaptions(for: id), "hasCaptions is true once stored")

        let dir = master.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The identity resolver keeps this test about the loader, not about
        // archive.org's node rotation.
        guard let (asset, loader) = LocalSubtitleHLSLoader.makeAsset(
            dir: dir, downloadURL: video, resolveNode: { $0 }) else {
            print("  FAIL  makeAsset returned nil"); exit(1)
        }
        _ = loader   // must outlive the asset; the delegate is held weakly
        check(asset.url.scheme == "aw-hls", "asset uses the custom scheme",
              "got \(asset.url.scheme ?? "nil")")

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let deadline = Date().addingTimeInterval(60)
        while item.status == .unknown && Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        check(item.status == .readyToPlay, "reaches .readyToPlay",
              item.status == .failed ? "— \(item.error.map(String.init(describing:)) ?? "?")"
                                     : "— still .unknown after 60s")
        guard item.status == .readyToPlay else { summarize(); return }

        if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
            let names = group.options.map(\.displayName)
            check(!names.isEmpty, "exposes a legible subtitle track", "options: \(names)")
            check(names.contains { $0.localizedCaseInsensitiveContains("english") },
                  "the track is labelled English", "options: \(names)")
        } else {
            check(false, "exposes a legible media selection group")
        }

        if let d = try? await asset.load(.duration) {
            check(CMTimeGetSeconds(d) > 60, "duration comes from the remote film",
                  "\(CMTimeGetSeconds(d))s")
        }

        player.play()
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        check(CMTimeGetSeconds(player.currentTime()) > 0, "playback advances")

        // Seeking is where a single-segment playlist historically broke — the
        // known limitation the published captioned path already carries.
        let ok = await player.seek(to: CMTime(seconds: 120, preferredTimescale: 600))
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let after = CMTimeGetSeconds(player.currentTime())
        check(ok && after > 100, "seeks into the film",
              "seek returned \(ok), landed at \(String(format: "%.1fs", after))")

        summarize()
    }

    static func summarize() {
        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
