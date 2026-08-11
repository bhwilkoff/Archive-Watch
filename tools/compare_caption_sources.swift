// Which captions are more accurate — ours, or the system's?
//
// From 27 there are two machine transcripts available for the same film: the
// scout-ahead engine in `LiveCaptions` (Decision 058) and the system's own
// generated subtitles (Decision 061). Captioning was handed to the system on
// INTEGRATION grounds — native menu, viewer's style, no second stream — which
// says nothing about accuracy, and accuracy is what a viewer notices.
//
// The reference is the film's published human subtitle track, ALIGNED FIRST.
// That step is not optional. The first version of this scored against the file
// as published and reported 67.7% WER for a transcript that was substantially
// correct, because that file runs 27 seconds late (Decision 062) and the
// compared windows therefore covered different parts of the film. A benchmark
// that measures the reference's sync error and calls it the engine's word error
// is worse than no benchmark.
//
// Both engines are scored over the SAME span — the overlap of what each covered
// — so a transcript that attempts less is not flattered by attempting less.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleAgreement.swift \
//     tools/compare_caption_sources.swift -o /tmp/awcmp
//   /tmp/awcmp <mp4-url> <vtt-url> [windowSeconds]

import AVFoundation
import Foundation

final class LegibleSink: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _cues: [SubtitleAgreement.Cue] = []
    var cues: [SubtitleAgreement.Cue] { lock.lock(); defer { lock.unlock() }; return _cues }

    func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        let t = itemTime.seconds
        guard t.isFinite else { return }
        lock.lock(); defer { lock.unlock() }
        for s in strings {
            var txt = s.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // A generated track labels its first cue.
            if txt.hasPrefix("Transcribed:") { txt = String(txt.dropFirst(12)) }
            guard !txt.isEmpty else { continue }
            _cues.append(SubtitleAgreement.Cue(start: t, end: t + 3, text: txt))
        }
    }
}

@main
struct Compare {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 2, let mp4 = URL(string: args[1]), let vtt = URL(string: args[2]) else {
            print("usage: awcmp <mp4-url> <vtt-url> [windowSeconds]"); exit(2)
        }
        let window = args.count > 3 ? (Double(args[3]) ?? 300) : 300

        guard let body = await fetchText(vtt) else { print("could not read the VTT"); exit(2) }
        let published = SubtitleAgreement.parseVTT(body)
        print("published reference: \(published.count) cues")

        print("\n— transcribing with our engine (scout, 2x) —")
        let ours = await captureOurs(mp4: mp4, window: window)
        print("ours: \(ours.count) cues covering "
              + String(format: "%.0f–%.0fs", ours.first?.start ?? 0, ours.last?.end ?? 0))
        guard ours.count > 5 else { print("our engine produced too little to compare"); exit(1) }

        // ALIGN the reference before scoring anything against it.
        guard let verdict = SubtitleAgreement.judge(published: published, transcript: ours) else {
            print("could not align the reference against our transcript"); exit(1)
        }
        let shift = verdict.offset
        let reference = published.map {
            SubtitleAgreement.Cue(start: $0.start + shift, end: $0.end + shift, text: $0.text)
        }
        print(String(format: "reference aligned by %+.1fs (agreement %.0f%%)",
                     shift, verdict.agreement * 100))

        print("\n— capturing the system's generated subtitles (1x, real time) —")
        let system = await captureSystem(mp4: mp4, window: window)
        print("system: \(system.count) cues covering "
              + String(format: "%.0f–%.0fs", system.first?.start ?? 0, system.last?.end ?? 0))

        guard !system.isEmpty else {
            print("\nthe system produced no captions here — reporting ours alone\n")
            report("ours (LiveCaptions scout)", ours, reference: reference,
                   from: ours.first?.start ?? 0, to: min(ours.last?.end ?? window, window))
            exit(1)
        }

        // Score both over the span BOTH attempted, so neither is flattered.
        let from = max(ours.first?.start ?? 0, system.first?.start ?? 0)
        let to = min(ours.last?.end ?? window, system.last?.end ?? window)
        guard to - from > 60 else {
            print(String(format: "\ncoverage barely overlaps (%.0f–%.0fs) — nothing fair to compare",
                         from, to))
            exit(1)
        }
        print(String(format: "\nscoring both over %.0f–%.0fs\n", from, to))
        report("system (generated subtitles)", system, reference: reference, from: from, to: to)
        report("ours (LiveCaptions scout)", ours, reference: reference, from: from, to: to)
    }

    static func report(_ label: String, _ cues: [SubtitleAgreement.Cue],
                       reference: [SubtitleAgreement.Cue], from: Double, to: Double) {
        let ref = words(reference, from: from, to: to)
        let hyp = words(cues, from: from, to: to)
        guard !ref.isEmpty else { print("\(label): no reference words in range\n"); return }
        guard !hyp.isEmpty else { print("\(label): produced nothing in range\n"); return }
        let wer = errorRate(reference: ref, hypothesis: hyp)
        let n = cues.filter { $0.start >= from && $0.start <= to }.count
        print(String(format: "%@\n  %d cues · %d words (reference %d) · WER %.1f%%\n",
                     label, n, hyp.count, ref.count, wer * 100))
    }

    // MARK: sources

    static func captureSystem(mp4: URL, window: Double) async -> [SubtitleAgreement.Cue] {
        let item = AVPlayerItem(url: mp4)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        let sink = LegibleSink()
        let out = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        out.setDelegate(sink, queue: .main)
        item.add(out)
        player.play()

        var selected = false
        var idleTicks = 0
        var lastCount = 0
        // Generated cues arrive in LATE BATCHES — measured ~75s behind the
        // playhead — so this keeps waiting after the playhead passes the window
        // until they stop arriving, rather than assuming they stream live.
        while true {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !selected,
               let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
               let option = group.options.first {
                item.select(option, in: group)
                selected = true
                print("  selected \"\(option.displayName)\"")
            }
            let n = sink.cues.count
            if n == lastCount { idleTicks += 1 } else { idleTicks = 0; lastCount = n }

            let playhead = item.currentTime().seconds
            if !selected, playhead > 90 {
                print("  no legible option after 90s — no generated subtitles here")
                break
            }
            if playhead > window, idleTicks >= 15 { break }   // backlog flushed
            if playhead > window + 240 { break }              // hard stop
        }
        player.pause()
        return sink.cues
    }

    static func captureOurs(mp4: URL, window: Double) async -> [SubtitleAgreement.Cue] {
        let captions = await LiveCaptions()
        await captions.start(url: mp4, from: .zero)
        let deadline = Date().addingTimeInterval(window * 1.3 + 90)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await captions.leadSeconds(over: .zero) > window { break }
            if await !captions.isRunning { break }
        }
        let cues = await captions.transcript().map {
            SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
        }
        await captions.stop()
        return cues
    }

    // MARK: scoring

    /// Word error rate — edit distance over words, normalised by reference length.
    static func errorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty, !hypothesis.isEmpty else { return 1 }
        var prev = Array(0...hypothesis.count)
        var cur = [Int](repeating: 0, count: hypothesis.count + 1)
        for i in 1...reference.count {
            cur[0] = i
            for j in 1...hypothesis.count {
                let cost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return Double(prev[hypothesis.count]) / Double(reference.count)
    }

    static func words(_ cues: [SubtitleAgreement.Cue], from: Double, to: Double) -> [String] {
        cues.filter { $0.start >= from && $0.start <= to }
            .sorted { $0.start < $1.start }
            .flatMap { normalise($0.text) }
    }

    static func normalise(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func fetchText(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
