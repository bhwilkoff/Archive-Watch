#if os(macOS)
import Foundation
import AVFoundation
import Speech

// Per-WORD timing for the Text→Supercut (#9 refinement, Rule 6b). Given a clip's local audio and a
// target phrase, find the TIGHT time range of that phrase's words via macOS-26 SpeechTranscriber
// (on-device per-word `audioTimeRange`), VALIDATED against the caption text — the Decision-039b
// hallucination fix applied to *when*: the caption is ground truth for *what* was said, the
// recognizer only supplies *when*, so a hallucinated word that isn't in the caption is dropped.
//
// Graceful: if the speech model isn't installed (or the API/locale is unavailable), returns nil and
// the supercut stays line-level — never breaks the working flow.
enum WordTiming {
    struct Word: Sendable { let text: String; let range: CMTimeRange }

    /// The result of checking whether `phrase` is ACTUALLY SPOKEN in a window — independent of the
    /// (often spotty/hallucinated) subtitle that put the clip on screen.
    enum Verdict: Sendable {
        case confirmed(CMTimeRange)   // the phrase's words are in the recognized speech (tight bounds)
        case contradicted            // enough speech was recognized, but the phrase is absent — drop it
        case unverifiable            // too little speech recognized to judge (music / rough old audio) — keep
    }

    /// Verify the phrase is spoken in the cached window by listening to the AUDIO (not trusting the
    /// caption). This is the guard against subtitles that claim a phrase the clip doesn't contain
    /// (owner #1/#2). Returns `.contradicted` only when speech WAS recognized yet the phrase is
    /// missing, so a hard-to-recognize clip (music, old prints) is kept (`.unverifiable`), never
    /// wrongly dropped.
    static func verify(mediaURL: URL, phrase: String) async -> Verdict {
        let target = tokens(phrase)
        guard !target.isEmpty else { return .unverifiable }
        let words = await recognize(mediaURL: mediaURL)
        let recog = words.map { token($0.text) }
        // The recognizer is a WEAK oracle on the catalog's old/noisy/accented prints — the caption
        // is ground truth for WHAT was said (Decision 042/039b), so a `.contradicted` drop must
        // require STRONG counter-evidence: a substantial, clean transcript in which the phrase is
        // essentially ABSENT. Otherwise keep the caption-matched clip (`.unverifiable`). This is the
        // guard against the recognizer overruling a correct caption and dropping a good clip
        // (false negatives + the bulk of the "lost half my clips" — owner 2026-06-27).
        let need = max(6, target.count * 2)
        guard recog.count >= need else { return .unverifiable }

        // Single word: present (fuzzily) anywhere = confirmed; absent in a solid transcript = drop.
        if target.count == 1 {
            if let i = recog.firstIndex(where: { tokenMatch($0, target[0]) }) {
                return .confirmed(padded(words[i].range.start, words[i].range.end))
            }
            return .contradicted
        }
        // Multi-word: best in-order run with FUZZY token equality (absorbs recognizer slips:
        // plurals/tense, near-homophones, accent mangling) and gap tolerance. We KEEP the clip
        // unless the recognizer heard plenty yet almost NONE of the phrase is present — partial
        // recognition of an old print is expected, not proof the caption lied.
        var best: (lo: CMTime, hi: CMTime, matched: Int)?
        for start in recog.indices where tokenMatch(recog[start], target[0]) {
            var lo = words[start].range.start, hi = words[start].range.end
            var ti = 1, wi = start + 1, gaps = 0, matched = 1
            while ti < target.count && wi < recog.count {
                if tokenMatch(recog[wi], target[ti]) { hi = words[wi].range.end; ti += 1; gaps = 0; matched += 1 }
                else { gaps += 1; if gaps > 3 { break } }
                wi += 1
            }
            if best == nil || matched > best!.matched { best = (lo, hi, matched) }
            if matched >= target.count { break }
        }
        // Confirm when a majority (>=60%, min 2) of the phrase's words are heard in order — enough
        // to trust the caption put the right line on screen. Below that, with a solid transcript,
        // the phrase is genuinely absent -> contradicted.
        let threshold = max(2, Int((Double(target.count) * 0.6).rounded(.up)))
        let matched = best?.matched ?? 0
        if diag {
            log("VERIFY phrase=\(target.joined(separator: "+")) matched=\(matched)/\(target.count) "
              + "recog(\(recog.count))=\(recog.prefix(24).joined(separator: " "))")
        }
        if let b = best, b.matched >= threshold {
            return .confirmed(padded(b.lo, b.hi))
        }
        return .contradicted
    }

    // Diagnostic (AW_CS_DIAG=1): dump the recognized transcript vs the phrase so a `.contradicted`
    // can be judged TRUE (recognizer clearly heard other words) vs FALSE (recognizer failed on an old
    // print). stderr only (the app sandbox blocks /tmp writes).
    private static var diag: Bool { ProcessInfo.processInfo.environment["AW_CS_DIAG"] == "1" }
    private static func log(_ s: String) { FileHandle.standardError.write(Data(("AWVERIFY " + s + "\n").utf8)) }

    /// Fuzzy token equality for the recognizer-vs-phrase comparison: exact, or (for words >=4 chars)
    /// a shared >=4-char prefix (plural/tense: run/running, color/colored) or edit-distance <=1
    /// (recognizer slip / accent: their/there, gonna/gunna). Stops the on-device recognizer's
    /// near-misses from contradicting a correct caption.
    private static func tokenMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let la = a.count, lb = b.count
        guard min(la, lb) >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return editDistanceAtMost1(Array(a), Array(b))
    }

    /// True iff Levenshtein(a,b) <= 1. O(max len) — bails fast on length gap > 1.
    private static func editDistanceAtMost1(_ a: [Character], _ b: [Character]) -> Bool {
        if abs(a.count - b.count) > 1 { return false }
        let (s, t) = a.count <= b.count ? (a, b) : (b, a)   // s is the shorter/equal
        var i = 0, j = 0, edits = 0
        while i < s.count && j < t.count {
            if s[i] == t[j] { i += 1; j += 1; continue }
            edits += 1; if edits > 1 { return false }
            if s.count == t.count { i += 1; j += 1 }        // substitution
            else { j += 1 }                                  // insertion in the longer string
        }
        if j < t.count { edits += t.count - j }              // trailing char in the longer
        return edits <= 1
    }

    private static func padded(_ lo: CMTime, _ hi: CMTime) -> CMTimeRange {
        let pad = CMTime(seconds: 0.2, preferredTimescale: 600)
        return CMTimeRange(start: CMTimeMaximum(.zero, lo - pad), end: hi + pad)
    }

    /// Find the tight time range of `phrase` WITHIN a cached line-window file (the returned range is
    /// relative to that file), via speech recognition validated against `caption`. nil = keep the
    /// whole line.
    static func tighten(mediaURL: URL, phrase: String, caption: String) async -> CMTimeRange? {
        let words = await recognize(mediaURL: mediaURL)
        guard !words.isEmpty else { return nil }
        // Validate against the caption (Rule 6b): keep recognizer words that the caption contains.
        let capTokens = Set(tokens(caption))
        let valid = words.filter { capTokens.contains(token($0.text)) }
        guard !valid.isEmpty else { return nil }
        // Find the contiguous run of valid words matching the phrase tokens.
        let target = tokens(phrase)
        guard let first = valid.firstIndex(where: { token($0.text) == target.first }) else { return nil }
        var lo = valid[first].range.start, hi = valid[first].range.end
        var ti = 1, wi = first + 1
        while ti < target.count && wi < valid.count {
            if token(valid[wi].text) == target[ti] { hi = valid[wi].range.end; ti += 1 }
            wi += 1
        }
        let pad = CMTime(seconds: 0.2, preferredTimescale: 600)
        let start = CMTimeMaximum(.zero, lo - pad)
        return CMTimeRange(start: start, end: hi + pad)
    }

    /// All recognized words (with timing) within `clamp`, or empty if speech is unavailable.
    static func recognize(mediaURL: URL, clamp: CMTimeRange? = nil) async -> [Word] {
        guard let audio = await extractAudio(mediaURL, range: clamp),
              let file = try? AVAudioFile(forReading: audio) else { return [] }
        defer { try? FileManager.default.removeItem(at: audio) }

        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"),
                                            transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
        } catch { return [] }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        var words: [Word] = []
        let collector = Task<[Word], Never> {
            var out: [Word] = []
            do {
                for try await result in transcriber.results {
                    let s = result.text
                    for run in s.runs {
                        guard let tr = run.audioTimeRange else { continue }
                        let w = String(s[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !w.isEmpty { out.append(Word(text: w, range: tr)) }
                    }
                }
            } catch { }
            return out
        }
        guard (try? await analyzer.start(inputAudioFile: file, finishAfterFile: true)) != nil else {
            collector.cancel(); return []
        }
        words = await collector.value
        return words
    }

    /// Extract the audio of a (clamped) media range to an m4a SpeechAnalyzer can read.
    private static func extractAudio(_ url: URL, range: CMTimeRange?) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        if let range { session.timeRange = range }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-\(UUID().uuidString.prefix(6)).m4a")
        try? FileManager.default.removeItem(at: out)
        do { try await session.export(to: out, as: .m4a); return out } catch { return nil }
    }

    // Word tokens with apostrophes STRIPPED (not split on) so a contraction is ONE token that
    // matches `token()` applied to a recognizer word: "don't" -> "dont" on both sides. Splitting on
    // the apostrophe (the old bug) made the phrase ["i","don","t","know"] while the recognizer gave
    // "dont" — so "i don't know" (and every contraction) could NEVER confirm and was always dropped.
    private static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "\u{2019}" }
            .map { token(String($0)) }
            .filter { !$0.isEmpty }
    }
    private static func token(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
#endif
