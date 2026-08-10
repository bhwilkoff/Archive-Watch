import Foundation

// Is the subtitle file we shipped actually right for this film?
//
// A published track is preferred over a machine transcript on the reasoning that
// a human wrote it — and usually that is correct. But the owner's report is that
// "many times the automatic captions are far better than the subtitles file",
// and the two ways a subtitle file goes wrong are both invisible to us until
// someone watches:
//
//   1. It is for a DIFFERENT CUT, print, or film entirely. Archive uploads are
//      re-cuts, restorations, and re-releases; a file matched by title (the
//      failure Decision 026 exists for) can be coherent English that has nothing
//      to do with what is on screen.
//   2. It is RIGHT BUT OUT OF SYNC — the commonest fault by far, from a
//      different framerate, a missing reel, or a distributor's card at the head.
//      The words are perfect and land seconds from the mouths saying them.
//
// Neither can be judged from the file alone; both are obvious the moment you
// have an independent estimate of what is being said, which `LiveCaptions`
// produces on device for free. So this compares the two.
//
// The distinction between the two faults matters, because the remedies differ.
// A mismatched file should be abandoned for the transcript. A shifted file
// should be SHIFTED — human words with corrected timing beat a machine
// transcript on both counts, and throwing it away would lose the better text.
enum SubtitleAgreement {

    struct Cue: Sendable {
        let start: Double
        let end: Double
        let text: String
        init(start: Double, end: Double, text: String) {
            self.start = start; self.end = end; self.text = text
        }
    }

    enum Choice: Equatable, Sendable {
        /// The file matches; show it as published.
        case keepPublished
        /// The file matches, once this many seconds are ADDED to every cue
        /// time. Negative means the file runs late and must be pulled earlier.
        /// Stated as "what to add" rather than "how wrong it is" because the
        /// other phrasing invites exactly the sign error that made the first
        /// version of this move a 27s-late file further out of sync.
        case shiftPublished(by: Double)
        /// The file does not describe this film; transcribe instead.
        case preferLive
    }

    struct Verdict: Sendable {
        let choice: Choice
        /// Fraction of published words the transcript also heard, at `offset`.
        let agreement: Double
        /// Agreement with no shift applied, for comparison.
        let agreementAtZero: Double
        /// Seconds to ADD to every published cue time. Same convention as
        /// `shiftPublished(by:)`.
        let offset: Double
        let comparedCues: Int

        var summary: String {
            switch choice {
            case .keepPublished:
                return String(format: "subtitles match (%.0f%% agreement)", agreement * 100)
            case .shiftPublished(let by):
                return String(format: "subtitles ran %.1fs %@; corrected",
                              abs(by), by < 0 ? "late" : "early")
            case .preferLive:
                return String(format: "subtitles don't match this film (%.0f%%) — "
                              + "captioning instead", agreement * 100)
            }
        }
    }

    // How far out of sync a file can be and still be recognisably the same film.
    // Half a minute covers the usual causes (a distributor's card, a missing
    // reel head); beyond that a "match" is more likely coincidence.
    static let maxOffset: Double = 30
    static let coarseStep: Double = 1.0
    static let fineStep: Double = 0.1
    // Calibrated against real files rather than guessed, because a machine
    // transcript never agrees with a human one word-for-word. Measured on The
    // Day the Earth Caught Fire against a 300s transcript: its OWN published
    // track scores 44% at the right offset and 3% at the wrong one, and an
    // unrelated film's track scores 3% at every offset. The separation is wide;
    // the absolute numbers are low, and an earlier 0.55 threshold — picked from
    // intuition — classified a genuinely-matching file as unmatched.
    /// Below this, the file is not describing what is being said.
    static let mismatchBelow = 0.18
    /// Above this, it plainly is.
    static let matchAbove = 0.30
    /// A shift worth correcting. Under a second is within cue-boundary noise.
    static let worthShifting: Double = 1.0
    /// Fewer published words than this and the sample cannot settle anything.
    static let minPublishedWords = 60

    /// Compare a published track against our own transcript of the same film.
    ///
    /// Returns nil when there is not enough evidence — silence, a sparse
    /// transcript, an intertitle-only stretch. NO OPINION is a valid answer and
    /// is very different from "they disagree": the caller keeps what it has.
    static func judge(published: [Cue], transcript: [Cue]) -> Verdict? {
        guard !published.isEmpty, !transcript.isEmpty else { return nil }

        // Only compare where we actually listened. The scout covers the opening
        // minutes, so the rest of the file has no evidence either way.
        let heardFrom = transcript.map(\.start).min() ?? 0
        let heardTo = transcript.map(\.end).max() ?? 0
        guard heardTo - heardFrom > 30 else { return nil }

        let window = published.filter {
            $0.start >= heardFrom - maxOffset && $0.start <= heardTo + maxOffset
        }
        let publishedWords = window.reduce(0) { $0 + tokens($1.text).count }
        guard publishedWords >= minPublishedWords else { return nil }

        // Index the transcript once: word -> the times it was heard.
        var heard: [String: [Double]] = [:]
        for cue in transcript {
            let ws = tokens(cue.text)
            guard !ws.isEmpty else { continue }
            let span = max(cue.end - cue.start, 0.5)
            for (i, w) in ws.enumerated() {
                let at = cue.start + span * (Double(i) + 0.5) / Double(ws.count)
                heard[w, default: []].append(at)
            }
        }

        var best = (score: -1.0, offset: 0.0)
        var atZero = 0.0
        var offset = -maxOffset
        while offset <= maxOffset {
            let s = score(window, heard: heard, offset: offset)
            if offset == 0 { atZero = s }
            if s > best.score { best = (s, offset) }
            offset += coarseStep
        }
        // Refine around the winner so a reported shift is worth applying.
        var fine = best.offset - coarseStep
        while fine <= best.offset + coarseStep {
            let s = score(window, heard: heard, offset: fine)
            if s > best.score { best = (s, fine) }
            fine += fineStep
        }
        if abs(best.offset) < fineStep { atZero = best.score }

        let choice: Choice
        if best.score < mismatchBelow {
            choice = .preferLive
        } else if abs(best.offset) >= worthShifting, best.score >= matchAbove,
                  best.score - atZero > 0.15 {
            // Only claim a shift when correcting it is what made it agree.
            choice = .shiftPublished(by: best.offset)
        } else {
            choice = .keepPublished
        }

        return Verdict(choice: choice, agreement: best.score, agreementAtZero: atZero,
                       offset: best.offset, comparedCues: window.count)
    }

    /// Fraction of published words heard near where the file says they are said.
    ///
    /// Word PRESENCE near the right time, not sequence alignment: a transcript
    /// mishears individual words constantly, and demanding order would score a
    /// good match as a bad one. Tolerance is generous because cue boundaries and
    /// speech boundaries never coincide exactly.
    private static func score(_ cues: [Cue], heard: [String: [Double]],
                              offset: Double) -> Double {
        var hits = 0, total = 0
        for cue in cues {
            let ws = tokens(cue.text)
            guard !ws.isEmpty else { continue }
            let from = cue.start + offset - 2.5
            let to = cue.end + offset + 2.5
            for w in ws {
                total += 1
                if let times = heard[w], times.contains(where: { $0 >= from && $0 <= to }) {
                    hits += 1
                }
            }
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    /// Words worth matching on.
    ///
    /// Very short words are dropped: "a", "of" and "the" appear so often that a
    /// completely unrelated subtitle file scores well on them alone, which is
    /// exactly the false match this is built to catch.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
    }

    /// Parse WebVTT.
    ///
    /// Both `HH:MM:SS.mmm` and `MM:SS.mmm` are legal, and assuming the first is
    /// how an earlier audit reported perfectly healthy files as empty
    /// (Decision 055) — so both are handled here.
    static func parseVTT(_ body: String) -> [Cue] {
        var cues: [Cue] = []
        var start: Double?
        var end: Double?
        var text = ""

        func flush() {
            if let s = start, !text.isEmpty {
                cues.append(Cue(start: s, end: end ?? s + 3, text: text))
            }
            start = nil; end = nil; text = ""
        }

        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                flush()
                let parts = line.components(separatedBy: "-->")
                start = seconds(parts.first ?? "")
                end = seconds(parts.count > 1 ? parts[1] : "")
            } else if line.isEmpty {
                flush()
            } else if start != nil, Int(line) == nil, !line.hasPrefix("WEBVTT") {
                text += (text.isEmpty ? "" : " ") + line
            }
        }
        flush()
        return cues
    }

    static func seconds(_ stamp: String) -> Double? {
        let field = stamp.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""
        let parts = field.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        let nums = parts.compactMap { Double($0) }
        guard nums.count == parts.count, !nums.isEmpty else { return nil }
        switch nums.count {
        case 3: return nums[0] * 3600 + nums[1] * 60 + nums[2]
        case 2: return nums[0] * 60 + nums[1]
        default: return nums[0]
        }
    }
}
