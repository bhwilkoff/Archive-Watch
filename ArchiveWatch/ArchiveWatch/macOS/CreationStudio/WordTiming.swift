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

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    private static func token(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
#endif
