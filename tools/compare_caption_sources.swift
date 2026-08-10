// Which captions are actually better — ours, or the system's?
//
// From 27 there are two machine transcripts available for the same film: the
// scout-ahead engine in `LiveCaptions` (Decision 058) and the system's own
// generated subtitles (Decision 061). We handed captioning to the system on the
// reasoning that a platform feature beats ours on integration — native menu,
// viewer's style, no second stream — but that says nothing about ACCURACY, and
// accuracy is the thing a viewer actually notices.
//
// This measures it, against a published human subtitle track as the reference,
// over the same window of the same film. Word error rate, both directions
// reported, plus how much of the window each source covered at all — a transcript
// that is accurate on the 10% it attempted is not better than one that attempted
// everything.
//
// The system's captions arrive in LATE BATCHES (measured: cues for playhead
// 28-46s were delivered at ~120s of wall clock), so this plays in real time and
// waits, rather than assuming they stream as they are spoken.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     tools/compare_caption_sources.swift -o /tmp/awcmp
//   /tmp/awcmp <mp4-url> <vtt-url> [windowSeconds]

import AVFoundation
import Foundation

final class LegibleSink: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _cues: [(start: Double, text: String)] = []
    var cues: [(start: Double, text: String)] {
        lock.lock(); defer { lock.unlock() }; return _cues
    }
    func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        let t = itemTime.seconds
        guard t.isFinite else { return }
        lock.lock(); defer { lock.unlock() }
        for s in strings {
            var txt = s.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // The first cue of a generated track is prefixed "Transcribed:".
            if txt.hasPrefix("Transcribed:") { txt = String(txt.dropFirst(12)) }
            if !txt.isEmpty { _cues.append((t, txt)) }
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
        let window = args.count > 3 ? (Double(args[3]) ?? 240) : 240

        guard let reference = await fetchVTT(vtt) else { print("could not read the VTT"); exit(2) }
        let refWords = words(in: reference, from: 0, to: window)
        guard refWords.count > 40 else {
            print("only \(refWords.count) reference words in the first \(Int(window))s — "
                  + "pick a film with dialogue earlier on"); exit(2)
        }
        print("reference: \(reference.count) cues, \(refWords.count) words in the first \(Int(window))s\n")

        async let system = captureSystem(mp4: mp4, window: window)
        let sysCues = await system
        let oursCues = await captureOurs(mp4: mp4, window: window)

        report("system (generated subtitles)", sysCues, reference: refWords, window: window)
        report("ours (LiveCaptions scout)", oursCues, reference: refWords, window: window)
    }

    static func report(_ label: String, _ cues: [(start: Double, text: String)],
                       reference: [String], window: Double) {
        let hyp = words(in: cues, from: 0, to: window)
        guard !hyp.isEmpty else { print("\(label): produced nothing\n"); return }
        let wer = errorRate(reference: reference, hypothesis: hyp)
        let spoken = cues.filter { $0.start <= window }.count
        print(String(format: "%@\n  cues %d · words %d (ref %d) · WER %.1f%%\n",
                     label, spoken, hyp.count, reference.count, wer * 100))
    }

    // MARK: sources

    static func captureSystem(mp4: URL, window: Double) async -> [(start: Double, text: String)] {
        let item = AVPlayerItem(url: mp4)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        let sink = LegibleSink()
        let out = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        out.setDelegate(sink, queue: .main)
        item.add(out)
        player.play()

        var selected = false
        let deadline = Date().addingTimeInterval(window * 1.6 + 60)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !selected,
               let g = try? await item.asset.loadMediaSelectionGroup(for: .legible),
               let opt = g.options.first {
                item.select(opt, in: g)
                selected = true
                print("system: selected \"\(opt.displayName)\"")
            }
            // Generated cues lag playback, so keep waiting after the playhead
            // passes the window until they stop arriving.
            if item.currentTime().seconds > window + 30 { break }
        }
        player.pause()
        return sink.cues
    }

    static func captureOurs(mp4: URL, window: Double) async -> [(start: Double, text: String)] {
        let captions = await LiveCaptions()
        await captions.start(url: mp4, from: .zero)
        let deadline = Date().addingTimeInterval(window * 1.2 + 60)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // The scout throttles against the playhead; feed it a synthetic one
            // that walks the window so it keeps transcribing.
            let lead = await captions.leadSeconds(over: .zero)
            if lead > window { break }
            if await !captions.isRunning { break }
        }
        let cues = await captions.transcript().map { (start: $0.start, text: $0.text) }
        await captions.stop()
        return cues
    }

    // MARK: scoring

    /// Word error rate — edit distance over words, normalised by reference length.
    static func errorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else { return 1 }
        var prev = Array(0...hypothesis.count)
        var cur = [Int](repeating: 0, count: hypothesis.count + 1)
        for i in 1...reference.count {
            cur[0] = i
            for j in 1...max(hypothesis.count, 1) where hypothesis.count > 0 {
                let cost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return Double(prev[hypothesis.count]) / Double(reference.count)
    }

    static func words(in cues: [(start: Double, text: String)],
                      from: Double, to: Double) -> [String] {
        cues.filter { $0.start >= from && $0.start <= to }
            .flatMap { normalise($0.text) }
    }

    static func normalise(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: WebVTT

    static func fetchVTT(_ url: URL) async -> [(start: Double, text: String)]? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let body = String(data: data, encoding: .utf8) else {
            print("vtt: fetch failed"); return nil
        }
        var cues: [(Double, String)] = []
        var pending: Double?
        var text = ""
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                if let p = pending, !text.isEmpty { cues.append((p, text)) }
                pending = seconds(fromStamp: String(line.split(separator: " ").first ?? ""))
                text = ""
            } else if line.isEmpty {
                if let p = pending, !text.isEmpty { cues.append((p, text)); pending = nil; text = "" }
            } else if pending != nil, !line.hasPrefix("WEBVTT"), Int(line) == nil {
                text += (text.isEmpty ? "" : " ") + line
            }
        }
        if let p = pending, !text.isEmpty { cues.append((p, text)) }
        if cues.isEmpty { print("vtt: parsed 0 cues from \(body.count) chars") }
        return cues.isEmpty ? nil : cues
    }

    /// WebVTT allows both HH:MM:SS.mmm and MM:SS.mmm — assuming the first is how
    /// an earlier audit reported healthy files as empty (Decision 055).
    static func seconds(fromStamp s: String) -> Double? {
        let parts = s.split(separator: ":").map(String.init)
        guard !parts.isEmpty else { return nil }
        let nums = parts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard nums.count == parts.count else { return nil }
        switch nums.count {
        case 3: return nums[0] * 3600 + nums[1] * 60 + nums[2]
        case 2: return nums[0] * 60 + nums[1]
        default: return nums[0]
        }
    }
}
