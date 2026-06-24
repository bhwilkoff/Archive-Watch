#if os(macOS)
import Foundation
import CoreMedia

// Sentence Supercut (#9 v2, docs/research/creation-studio-sentence-supercut.md): type a line and
// assemble a supercut that SPEAKS it, using only clips that contain those words. The quality lever
// is LONGEST-MATCH coverage — cover the line with the fewest clips by preferring the longest
// contiguous run of words spoken in a single cue ("I love you" from one film, not three) — so the
// result is smooth, not jumpy. Word ranges within a cue are PROPORTIONAL by default (instant) and
// can be tightened to exact word boundaries with on-device speech (WordTiming, Rule 6b). Missing
// words become explicit gaps the user resolves (Rule 5a). Phase B replaces the per-cue lookups with
// a CI forced-aligned word index for instant whole-catalog composition.
@MainActor
enum SentenceComposer {
    struct Segment: Identifiable, Sendable {
        let id = UUID()
        let phrase: String              // the matched run of words, or a single unmatched word
        let cue: SubtitleCue?           // nil = no clip found (a gap)
        let sourceRange: TimeRange?     // proportional estimate in the source's own seconds
        var found: Bool { cue != nil }
    }

    /// Greedy longest-match plan: cover `sentence` with the fewest cues. Index-only (instant).
    static func plan(_ sentence: String, index: SubtitleIndex) -> [Segment] {
        let words = tokens(sentence)
        var segs: [Segment] = []
        var i = 0
        while i < words.count {
            var hit: (j: Int, cue: SubtitleCue, range: TimeRange?)?
            var j = words.count
            while j > i {                                   // try the LONGEST run first
                let run = Array(words[i..<j])
                if let cue = bestCue(run, index: index) {
                    hit = (j, cue, proportionalRange(cue, run)); break
                }
                j -= 1
            }
            if let h = hit {
                segs.append(Segment(phrase: words[i..<h.j].joined(separator: " "),
                                    cue: h.cue, sourceRange: h.range))
                i = h.j
            } else {
                segs.append(Segment(phrase: words[i], cue: nil, sourceRange: nil))   // a gap
                i += 1
            }
        }
        return segs
    }

    /// The shortest cue that contains `run` as a contiguous whole-word phrase (the word is most
    /// isolated there), among the index's matches.
    private static func bestCue(_ run: [String], index: SubtitleIndex) -> SubtitleCue? {
        let cues = index.search(run.joined(separator: " "), limit: 60)
        return cues
            .filter { contiguousIndex(tokens($0.text), run) != nil }
            .min { ($0.endSeconds - $0.startSeconds) < ($1.endSeconds - $1.startSeconds) }
    }

    /// Estimate the run's time window in the cue by word position (instant; speech tightens later).
    static func proportionalRange(_ cue: SubtitleCue, _ run: [String]) -> TimeRange? {
        let cueWords = tokens(cue.text)
        guard let start = contiguousIndex(cueWords, run), !cueWords.isEmpty else { return nil }
        let n = Double(cueWords.count)
        let dur = max(0.3, cue.endSeconds - cue.startSeconds)
        let s = cue.startSeconds + Double(start) / n * dur
        let e = cue.startSeconds + Double(start + run.count) / n * dur
        return TimeRange(startSeconds: max(0, s - 0.12), durationSeconds: (e - s) + 0.24)
    }

    /// The proxy clip for a found segment (its word window of the source).
    static func proxyClip(_ seg: Segment) -> ProxyClip? {
        guard let cue = seg.cue, let r = seg.sourceRange else { return nil }
        return ProxyClip(catalogItemID: cue.archiveID, sourceURL: cue.sourceURL, sourceRange: r,
                         label: seg.phrase, posterFrameSeconds: r.start.seconds, title: cue.title)
    }

    // MARK: tokens

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    /// Start index where `needle` appears as a contiguous run in `hay`, or nil.
    private static func contiguousIndex(_ hay: [String], _ needle: [String]) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        for s in 0...(hay.count - needle.count) where Array(hay[s..<s + needle.count]) == needle {
            return s
        }
        return nil
    }
}
#endif
