// Does the SYSTEM caption our films for us, and does it survive our own loader?
//
// From 27, Apple generates subtitles on device for video that carries none. Two
// things had to be true before the app could rely on that, and neither was
// answerable from documentation:
//
//   1. Does it work for a PROGRESSIVE MP4? The WWDC session names HLS and
//      file-based content; archive.org serves neither.
//   2. Does it survive a custom `AVAssetResourceLoaderDelegate`? Every playback
//      path here is loader-backed (Decisions 021/031/034), and that is exactly
//      what disqualifies us from video AirPlay (Decision 051) — so it was a real
//      possibility that captions would be disqualified the same way.
//
// Measured on macOS 27.0 (26A5388g) against a live archive.org film, both
// answers YES, within a second:
//
//     t=1s assetOptions=1  selectableOnItem=1
//          - English (US) Transcribed [sbtl]
//
// This runs the SHIPPED ResilientStreamLoader, so it will notice if a change to
// the loader ever costs us the system's captions.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     ArchiveWatch/ArchiveWatch/Services/SystemCaptions.swift \
//     tools/test_system_generated_subtitles.swift -o /tmp/awsysub && /tmp/awsysub

import AVFoundation

@main
struct Harness {
    static let film = "https://archive.org/download/mantheincrediblemachine/"
        + "mantheincrediblemachine.mp4"

    static func main() async {
        guard #available(macOS 27, iOS 27, tvOS 27, *) else {
            print("SKIP: system-generated subtitles need 27; this OS is older.")
            exit(0)
        }
        let url = URL(string: CommandLine.arguments.count > 1
                      ? CommandLine.arguments[1] : film)!

        let direct = await probe("plain https MP4", AVPlayerItem(url: url))
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        _ = loader                       // the delegate is held weakly
        let viaLoader = await probe("through ResilientStreamLoader",
                                    AVPlayerItem(asset: asset))

        let ok = direct && viaLoader
        print(ok
              ? "\nRESULT: OK — the system captions our films, loader and all."
              : "\nRESULT: FAIL — direct=\(direct) loader=\(viaLoader). If only the "
                + "loader path failed, our playback stack is disqualifying the "
                + "system's captions the way it disqualifies AirPlay.")
        exit(ok ? 0 : 1)
    }

    /// Play briefly and report whether a subtitle option shows up.
    @available(macOS 27, iOS 27, tvOS 27, *)
    static func probe(_ label: String, _ item: AVPlayerItem) async -> Bool {
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.play()
        defer { player.pause() }

        for second in 1...20 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let group = try? await item.asset
                .loadMediaSelectionGroup(for: .legible) else { continue }
            let selectable = item.selectableMediaSelectionOptions(in: group)
            guard !selectable.isEmpty || !group.options.isEmpty else { continue }
            let names = selectable.map(\.displayName).joined(separator: ", ")
            print("\(label): \(second)s — \(selectable.count) option(s): \(names)")
            return true
        }
        print("\(label): no subtitle option after 20s")
        return false
    }
}
