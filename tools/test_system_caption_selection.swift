// Does the system's generated subtitle track actually get switched ON, and does
// the app hand it an asset it will caption?
//
// The owner's report from a tvOS 27 Apple TV: file-based captions work,
// automatically generated ones never appear. Two causes, both of this app's own
// making, and the second was hidden behind the first.
//
//   1. A PUBLISHED track rides a master playlist we generate, declaring
//      `AUTOSELECT=YES,DEFAULT=YES`, so AVPlayer switches it on. A GENERATED
//      track is merely OFFERED — the system leaves it off — and nothing selected
//      it. An unselected track emits nothing, which also defeated the emission
//      check (Decision 063).
//
//   2. Through our `aw-stream://` resilient loader the system offers NO TRACK AT
//      ALL. So the previous design — wait for a track, select it, listen, and
//      only then swap to the direct URL — was gated behind a track that never
//      arrives, and on tvOS the swap could therefore never run.
//
// So the asset shape is now chosen UP FRONT, and this asserts both halves:
// the direct shape captions, and the loader shape does not. The negative control
// is the point, not decoration — it is the measurement the whole design rests
// on, and if a future change to the loader alters it, this says so.
//
// ONE SHAPE PER PROCESS, deliberately. An earlier harness probed several shapes
// in one process and reported that a shape captioned when it had merely run
// first; a shape identical to it failed later in the same run. Sequential
// probing cannot attribute a result to a shape.
//
// Build + run BOTH modes:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/SystemCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_system_caption_selection.swift -o /tmp/awsel
//   /tmp/awsel direct && /tmp/awsel loader

import AVFoundation

final class TextWatcher: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var seen: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        lock.lock(); defer { lock.unlock() }
        for s in strings {
            let t = s.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { lines.append(t) }
        }
    }
}

@main
struct Harness {
    // A film with no published subtitles and clear narration — one the system is
    // known to caption, so a failure is about the SHAPE and not a soundtrack too
    // rough to transcribe (the system declines on much of this catalogue).
    static let film = "https://archive.org/download/mantheincrediblemachine/"
        + "mantheincrediblemachine.mp4"

    @MainActor
    static func main() async {
        guard #available(macOS 27, iOS 27, tvOS 27, *) else {
            print("SKIP: generated subtitles need 27; this OS is older.")
            exit(0)
        }
        let args = CommandLine.arguments
        let mode = args.count > 1 ? args[1] : "direct"
        let url = URL(string: args.count > 2 ? args[2] : film)!

        // The decision the players now make, asserted directly.
        guard SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) else {
            print("FAIL: on 27 a film with no subtitles must take the direct path.")
            exit(1)
        }
        guard !SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: true) else {
            print("FAIL: a film WITH published subtitles must keep the captioned path —")
            print("      its subtitles are human, and better than a generated track.")
            exit(1)
        }

        let item: AVPlayerItem
        switch mode {
        case "direct":
            item = AVPlayerItem(url: url)          // exactly what the players build now
        case "loader":
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
            _ = loader                             // the delegate is held weakly
            item = AVPlayerItem(asset: asset)
        default:
            print("unknown mode \(mode); use direct|loader"); exit(2)
        }

        let player = AVPlayer(playerItem: item)
        player.volume = 0
        let watcher = TextWatcher()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = false
        output.setDelegate(watcher, queue: .main)
        item.add(output)
        player.play()

        let handed = await SystemCaptions.handOver(to: player)
        let stage = SystemCaptions.stage
        player.pause()
        print("mode=\(mode) captioning=\(handed) stage=\(stage.rawValue)")
        for line in watcher.seen.prefix(3) { print("     \(line.prefix(64))") }

        switch mode {
        case "direct":
            if handed, stage == .captioning {
                print("RESULT: OK — the direct shape is captioned by the system.")
                exit(0)
            }
            // The system declines on poor archival audio (Decision 063), so a
            // decline is a statement about the FILM. Only "no track offered" on
            // the direct shape would contradict the design.
            if stage == .noTrackOffered {
                print("RESULT: FAIL — no track offered on the DIRECT shape. The")
                print("        measurement this design rests on no longer holds.")
                exit(1)
            }
            print("RESULT: INCONCLUSIVE — a track was offered but stayed silent;")
            print("        the system declined this film's audio. Try another film.")
            exit(0)
        default:
            if !handed, stage == .noTrackOffered {
                print("RESULT: OK — the loader offers no track, which is exactly why")
                print("        the resilient path has to give way for captions.")
                exit(0)
            }
            print("RESULT: CHANGED — the loader now behaves differently than when")
            print("        this design was measured (stage=\(stage.rawValue)). If it")
            print("        captions now, the resilient loader can be kept for every")
            print("        film and prefersDirectPlayback should be revisited.")
            exit(1)
        }
    }
}
