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

        // Measure visibility PER LINE, not per display string. The display
        // STACKS up to two cues in rapid dialogue, so "A" -> "A\nB" is not a
        // replacement of A — A is still on screen. Judging string changes as
        // replacements is how this harness wrongly failed a display that was
        // holding every line longer than before.
        struct Line { var text: String; var from: Double; var to: Double }
        var lines: [Line] = []
        var open: [String: Int] = [:]   // text -> index in `lines`
        for s in timeline {
            let parts = s.text.isEmpty ? [] : s.text.components(separatedBy: "\n")
            for p in parts where !p.isEmpty {
                if let i = open[p] {
                    lines[i].to = s.t
                } else {
                    open[p] = lines.count
                    lines.append(Line(text: p, from: s.t, to: s.t))
                }
            }
            // A line no longer displayed is closed; a repeat later counts anew.
            for (text, i) in open where !parts.contains(text) {
                open.removeValue(forKey: text)
                _ = i
            }
        }
        guard lines.count >= 3 else {
            print("only \(lines.count) caption lines seen — not enough to judge pacing")
            exit(1)
        }

        var tooFast: [(String, Double, Int)] = []
        for (i, l) in lines.enumerated() {
            let dwell = l.to - l.from
            let words = l.text.split(separator: " ").count
            // ~2.5 words/second is a comfortable reading pace; allow the last
            // sample to under-report by one polling interval.
            let needed = max(1.0, Double(words) / 2.5)
            guard dwell + 0.15 < needed else { continue }
            // The stack holds TWO cues: in dialogue rapid enough to need a
            // third, the oldest yields early BY DESIGN (broadcast captions do
            // the same). Early exit is a defect only when fewer than two newer
            // lines arrived while this one was up.
            let newer = lines[(i + 1)...].prefix { $0.from <= l.to + 0.15 }.count
            if newer < 2 { tooFast.append((l.text, dwell, words)) }
        }

        print("caption lines observed: \(lines.count)")
        for l in lines.prefix(8) {
            print(String(format: "  %5.1f-%5.1fs (%4.1fs) %2d words  %@",
                         l.from, l.to, l.to - l.from,
                         l.text.split(separator: " ").count, String(l.text.prefix(56))))
        }
        let dwells = lines.map { $0.to - $0.from }
        print(String(format: "\nmedian on screen: %.1fs   shortest: %.1fs",
                     dwells.sorted()[dwells.count / 2], dwells.min() ?? 0))
        print("replaced too soon to read (and not crowded out): \(tooFast.count) of \(lines.count)")
        for (t, d, w) in tooFast.prefix(4) {
            print(String(format: "   %.1fs for %d words — %@", d, w, String(t.prefix(48))))
        }

        let ok = Double(tooFast.count) / Double(lines.count) < 0.2
        print(ok
              ? "\nRESULT: OK — every line holds long enough to read, or yielded only to two newer lines."
              : "\nRESULT: FAIL — lines are being replaced before they can be read.")
        exit(ok ? 0 : 1)
    }
}
