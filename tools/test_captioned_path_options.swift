// Does a film that ALREADY has subtitles still get the system's own options?
//
// Decision 067 moved uncaptioned films onto the plain URL because the resilient
// loader is never offered a generated track. Films WITH published subtitles took
// a different path and were deliberately left alone — but they are ALSO played
// through a custom `AVAssetResourceLoaderDelegate` (CaptionedHLSLoader, "Config
// C": playlists through a custom scheme, media segment a direct https URL).
//
// That matters for what comes next. From 27 the system can also TRANSLATE an
// existing subtitle track into other languages on iOS and macOS — the natural
// way to offer more languages without sourcing a single new file. If the custom
// scheme disqualifies that the way it disqualifies generation, then expanding
// into translated subtitles needs the same treatment as Decision 067, and it is
// better to know now than to build on the assumption.
//
// This lists the legible options the player ends up with, both ways, ONE MODE
// PER PROCESS (an earlier harness probed several shapes in one process and
// attributed a leftover track to the wrong shape).
//
// It reports rather than asserts a pass/fail: the set of translations offered
// depends on the languages configured on the device, so an empty translated set
// on a monolingual Mac is not evidence of a fault. What IS meaningful is a
// DIFFERENCE between the two modes on the same machine.
//
// Build + run BOTH modes:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/CaptionedHLSLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_captioned_path_options.swift -o /tmp/awcapopt
//   /tmp/awcapopt direct ; /tmp/awcapopt loader

import AVFoundation

@main
struct Harness {
    static let master = "https://archivewatch.org/subs/house_on_haunted_hill/master.m3u8"
    static let mp4 = "https://archive.org/download/house_on_haunted_hill/"
        + "house_on_haunted_hill.mp4"

    static func main() async {
        guard #available(macOS 27, iOS 27, tvOS 27, *) else {
            print("SKIP: needs 27."); exit(0)
        }
        let args = CommandLine.arguments
        let mode = args.count > 1 ? args[1] : "direct"
        let hls = URL(string: master)!

        let item: AVPlayerItem
        // The asset holds its resource-loader delegate WEAKLY, so this must
        // outlive the asset. Writing `_ = loader` releases it immediately and
        // every request then fails "unsupported URL" — which looks exactly like
        // the loader disqualifying the film, and is purely the harness's fault.
        // The players keep theirs in @State for the same reason.
        var retained: AnyObject?
        switch mode {
        case "direct":
            item = AVPlayerItem(url: hls)              // no loader at all
        case "loader":
            let (asset, l) = CaptionedHLSLoader.makeAsset(hls: hls,
                                                          downloadURL: URL(string: mp4)!)
            retained = l
            item = AVPlayerItem(asset: asset)
        default:
            print("unknown mode; use direct|loader"); exit(2)
        }
        defer { retained = nil }

        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.play()

        // Poll: a system-provided option appears a moment into playback, not at
        // item creation.
        var names: [String] = []
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if let g = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                let n = g.options.map(\.displayName)
                if n.count > names.count { names = n }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        player.pause()

        print("mode=\(mode) status=\(item.status.rawValue) options=\(names.count)")
        for n in names { print("   - \(n)") }
        if let e = item.error { print("   error: \(e.localizedDescription)") }
        print("Compare the two modes: a DIFFERENCE means the custom scheme is")
        print("costing this film system-provided options, as it does for generation.")
        exit(0)
    }
}
