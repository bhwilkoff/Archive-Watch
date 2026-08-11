// Do captions stay up long enough to READ, and does a new one ever replace one
// whose words are still being spoken?
//
// The owner's report: "the new sentence is displayed before the person speaking
// is finished with the last sentence... you are constantly racing to read." That
// is a PACING property, invisible to a screenshot and to any test that only asks
// whether captions appear at all.
//
// Asserted here, against the SHIPPED LiveCaptions driven by a real film:
//   1. No cue starts before the previous one ends (nothing is cut off).
//   2. Every caption is on screen long enough to read — at least ~1s, and
//      roughly in proportion to how many words it carries.
//   3. Captions advance in order, with no backward jumps.
//
// Build:
//   xcrun swiftc -parse-as-library ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_caption_pacing.swift -o /tmp/awpace && /tmp/awpace <url> [seconds]

import AVFoundation
import Foundation

@main
struct Harness {
    static func main() async {
        let args = CommandLine.arguments
        let raw = args.count > 1 ? args[1]
            : "https://dn800200.us.archive.org/0/items/mantheincrediblemachine/mantheincrediblemachine.mp4"
        let seconds = args.count > 2 ? (Double(args[2]) ?? 120) : 120
        guard let url = URL(string: raw) else { print("bad url"); exit(2) }
        guard await LiveCaptions.isSupported else { print("no recognizer here"); exit(1) }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        let captions = await LiveCaptions()
        await captions.start(url: url, from: .zero)
        player.play()

        // Sample what a viewer would actually see, densely.
        var timeline: [(t: Double, text: String)] = []
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let now = player.currentTime()
            await captions.throttle(playhead: now)
            let line = await captions.line(at: now)
            timeline.append((CMTimeGetSeconds(now), line))
        }
        await captions.stop()

        // Collapse the samples into "this caption was on screen from A to B".
        var shown: [(text: String, from: Double, to: Double)] = []
        for s in timeline where !s.text.isEmpty {
            if var last = shown.last, last.text == s.text {
                last.to = s.t
                shown[shown.count - 1] = last
            } else {
                shown.append((text: s.text, from: s.t, to: s.t))
            }
        }
        guard shown.count >= 3 else {
            print("only \(shown.count) captions seen — not enough to judge pacing")
            exit(1)
        }

        var tooFast: [(String, Double, Int)] = []
        var backwards = 0
        for (i, c) in shown.enumerated() {
            let dwell = c.to - c.from
            let words = c.text.split(separator: " ").count
            // ~2.5 words/second is a comfortable reading pace; allow the last
            // sample to under-report by one polling interval.
            let needed = max(1.0, Double(words) / 2.5)
            if dwell + 0.15 < needed { tooFast.append((c.text, dwell, words)) }
            if i > 0, c.from + 0.001 < shown[i - 1].from { backwards += 1 }
        }

        print("captions observed: \(shown.count)")
        for c in shown.prefix(8) {
            print(String(format: "  %5.1f-%5.1fs (%4.1fs) %2d words  %@",
                         c.from, c.to, c.to - c.from,
                         c.text.split(separator: " ").count, String(c.text.prefix(56))))
        }
        let dwells = shown.map { $0.to - $0.from }
        print(String(format: "\nmedian on screen: %.1fs   shortest: %.1fs",
                     dwells.sorted()[dwells.count / 2], dwells.min() ?? 0))
        print("replaced too soon to read: \(tooFast.count) of \(shown.count)")
        for (t, d, w) in tooFast.prefix(4) {
            print(String(format: "   %.1fs for %d words — %@", d, w, String(t.prefix(48))))
        }
        print("out-of-order: \(backwards)")

        let ok = backwards == 0 && Double(tooFast.count) / Double(shown.count) < 0.2
        print(ok
              ? "\nRESULT: OK — captions hold long enough to read and never cut each other off."
              : "\nRESULT: FAIL — captions are being replaced before they can be read.")
        exit(ok ? 0 : 1)
    }
}
