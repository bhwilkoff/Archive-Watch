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
// Not @MainActor: `plan` runs OFF the main thread (the LIKE-scan queries it fires are slow), so the
// Supercut Search UI stays responsive and can show live progress. SubtitleIndex is thread-safe.
enum SentenceComposer {
    /// One source for a run of words: a cue + the word window within it.
    struct Candidate: Identifiable, Sendable {
        let id = UUID()
        let cue: SubtitleCue
        let range: TimeRange
    }
    struct Segment: Identifiable, Sendable {
        let id = UUID()
        let phrase: String              // the matched run of words, or a single unmatched word
        var candidates: [Candidate]     // ranked alternates ([] = a gap)
        var selected: Int = 0           // which alternate the user picked
        var found: Bool { !candidates.isEmpty }
        var chosen: Candidate? { candidates.indices.contains(selected) ? candidates[selected] : nil }
    }

    /// Greedy longest-match plan: cover `sentence` with the fewest runs, each carrying ranked
    /// ALTERNATE source clips the user can swap between. Runs OFF the main thread (slow LIKE scans);
    /// `onProgress(wordsDone, wordsTotal)` fires as each run resolves so the UI can show a live bar.
    static func plan(_ sentence: String, index: SubtitleIndex,
                     onProgress: (@Sendable (_ wordsDone: Int, _ wordsTotal: Int) -> Void)? = nil) -> [Segment] {
        let words = tokens(sentence)
        var segs: [Segment] = []
        var i = 0
        onProgress?(0, words.count)
        while i < words.count {
            var hit: (j: Int, cands: [Candidate])?
            var j = words.count
            while j > i {                                   // try the LONGEST run first
                let run = Array(words[i..<j])
                let cands = candidates(run, index: index)
                if !cands.isEmpty { hit = (j, cands); break }
                j -= 1
            }
            if let h = hit {
                segs.append(Segment(phrase: words[i..<h.j].joined(separator: " "), candidates: h.cands))
                i = h.j
            } else {
                segs.append(Segment(phrase: words[i], candidates: []))   // a gap
                i += 1
            }
            onProgress?(i, words.count)
        }
        return segs
    }

    /// Pick a different alternate for the segment at `index` (cycles); returns the updated plan.
    static func cycle(_ plan: [Segment], at index: Int, by delta: Int) -> [Segment] {
        var p = plan
        guard p.indices.contains(index), !p[index].candidates.isEmpty else { return p }
        let n = p[index].candidates.count
        p[index].selected = ((p[index].selected + delta) % n + n) % n
        return p
    }

    /// Randomize every segment's chosen take (variety — the charm of a cross-film word collage).
    static func shuffle(_ plan: [Segment]) -> [Segment] {
        plan.map { var s = $0; if !s.candidates.isEmpty { s.selected = Int.random(in: 0..<s.candidates.count) }; return s }
    }

    /// Resolve an arbitrary replacement phrase (for filling a gap) to ranked candidates.
    static func resolve(_ phrase: String, index: SubtitleIndex) -> [Candidate] {
        candidates(tokens(phrase), index: index)
    }

    /// Ranked candidate sources for a run: cues that contain it as a contiguous whole-word phrase,
    /// SHORTEST first (the word most isolated), each with its word window. Top few.
    private static func candidates(_ run: [String], index: SubtitleIndex, limit: Int = 6) -> [Candidate] {
        let cues = index.search(run.joined(separator: " "), limit: 80)
            .filter { contiguousIndex(tokens($0.text), run) != nil }
            .sorted { ($0.endSeconds - $0.startSeconds) < ($1.endSeconds - $1.startSeconds) }
            .prefix(limit)
        return cues.compactMap { cue in
            let range = index.wordRange(archiveID: cue.archiveID, run: run, nearSeconds: cue.startSeconds)
                ?? proportionalRange(cue, run)
            return range.map { Candidate(cue: cue, range: $0) }
        }
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

    /// The proxy clip for a found segment, using the user's chosen alternate (its word window).
    static func proxyClip(_ seg: Segment) -> ProxyClip? {
        guard let c = seg.chosen else { return nil }
        return proxy(for: c, phrase: seg.phrase)
    }

    /// The segment's OTHER candidates (not the chosen one) as ranked fallback proxies — the supercut
    /// verify pass swaps in the first that actually speaks the phrase if the chosen clip doesn't.
    static func alternateProxies(_ seg: Segment) -> [ProxyClip] {
        seg.candidates.enumerated()
            .filter { $0.offset != seg.selected }
            .map { proxy(for: $0.element, phrase: seg.phrase) }
    }

    private static func proxy(for c: Candidate, phrase: String) -> ProxyClip {
        ProxyClip(catalogItemID: c.cue.archiveID, sourceURL: c.cue.sourceURL, sourceRange: c.range,
                  label: phrase, posterFrameSeconds: c.range.start.seconds, title: c.cue.title)
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
