// Does the system's generated subtitle track actually get switched ON?
//
// The owner's report from a tvOS 27 Apple TV: file-based captions work,
// automatically generated ones never appear. The cause is a difference this app
// created and then did not notice. A PUBLISHED track rides a master playlist we
// generate ourselves, which declares `AUTOSELECT=YES,DEFAULT=YES`, so AVPlayer
// switches it on. A GENERATED track is merely OFFERED by the system, and nothing
// selected it — so it sat in the subtitle menu, switched off, on every film that
// had no published file.
//
// That also silently defeated the emission check (Decision 063): a track that is
// off emits no text, so the app concluded the system had declined and fell back
// to an engine that has no models on an Apple TV at all.
//
// This drives the SHIPPED `SystemCaptions` against a real film with no published
// subtitles and asserts the whole sequence: an option appears, selecting it
// takes, and text then actually flows.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/SystemCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_system_caption_selection.swift -o /tmp/awsel && /tmp/awsel

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
    // A film with NO published subtitle track, so the only captions available
    // are the ones the system generates.
    static let film = "https://archive.org/download/mantheincrediblemachine/"
        + "mantheincrediblemachine.mp4"

    static func main() async {
        guard #available(macOS 27, iOS 27, tvOS 27, *) else {
            print("SKIP: generated subtitles need 27; this OS is older."); exit(0)
        }
        let url = URL(string: CommandLine.arguments.count > 1
                      ? CommandLine.arguments[1] : film)!

        // The SHIPPED playback path, so the resource loader is exercised too.
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        _ = loader
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 0

        let watcher = TextWatcher()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = false
        output.setDelegate(watcher, queue: .main)
        item.add(output)
        player.play()

        let offered = await SystemCaptions.waitForLegibleOption(on: player)
        print("1. system offers a subtitle option: \(offered)")
        guard offered else {
            print("\nRESULT: FAIL — no option was ever offered."); exit(1)
        }
        _ = watcher

        // The SHIPPED sequence, which must end with the system actually
        // speaking — including the swap off the resilient loader, without which
        // it is offered and mute forever.
        let handed = await SystemCaptions.handOver(to: player, directURL: url)
        print("2. system is genuinely captioning: \(handed)")
        for line in watcher.seen.prefix(4) { print("     \(line.prefix(64))") }
        player.pause()

        let ok = handed
        print(ok
              ? "\nRESULT: OK — the system's captions are switched on and speaking."
              : "\nRESULT: FAIL — the hand-over did not produce captions.")
        exit(ok ? 0 : 1)
    }
}
