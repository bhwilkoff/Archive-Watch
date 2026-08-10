import AVFoundation
import CoreMedia
import Foundation
#if canImport(Speech)
import Speech
#endif

// On-device auto-captions (Apple 26+), and the gate that decides whether the
// result is fit to show.
//
// Decision 039b banned auto-captions after whisper.cpp produced fluent,
// plausible, WRONG dialogue on archival audio and fabricated speech over silent
// films — a wrong subtitle being worse than none. The owner has approved
// revisiting it, and three things make this attempt different:
//
//   1. `SpeechAnalyzer` / `SpeechTranscriber` (iOS/iPadOS/macOS/visionOS/tvOS
//      26) is a materially stronger, long-form, on-device engine — not
//      whisper-tiny — and it reports CONFIDENCE, which whisper.cpp effectively
//      did not. Confidence is the only signal that speaks to whether the AUDIO
//      was intelligible, as opposed to whether the TEXT looks tidy.
//   2. It runs per-viewer, on demand, opt-in, and the track is labelled
//      "auto-generated" — the viewer knows what they are reading.
//   3. `CaptionQuality` below refuses output that shows the recognizer failing.
//
// THE LIMIT, stated plainly so nobody mistakes this for a guarantee: a
// transcript that is FLUENT AND WRONG cannot be detected from its text. What is
// caught is the recognizer failing VISIBLY — going sparse, looping, or stopping
// early. Prevention for the silent-film case is refusal to run at all, not
// detection after the fact.
enum CaptionQuality {

    // Calibrated against real files, both directions — see
    // docs/SUBTITLE-COVERAGE-PLAN.md §4. An earlier gate scored unique/total
    // token ratio and rejected real human subtitles while accepting known-bad
    // ASR, because that ratio falls with LENGTH. Density is what separates:
    // a recognizer failing on poor audio goes sparse rather than inventing.
    //   White Zombie (bad ASR)  14 wpm   His Girl Friday (human) 187 wpm
    //   Carnival of Souls (bad) 49 wpm   The Stranger    (human) 102 wpm
    static let minWordsPerMinute = 65.0
    static let maxWordsPerMinute = 320.0
    static let minCuesPerMinute = 12.0
    static let minCoverage = 0.55

    struct Report { let ok: Bool; let reason: String; let wordsPerMinute: Double }

    static func assess(cues: [(start: Double, text: String)], runtime: Double) -> Report {
        guard cues.count >= 5, runtime > 0 else {
            return Report(ok: false, reason: "too few cues", wordsPerMinute: 0)
        }
        let words = cues.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let minutes = max(runtime / 60, 1)
        let wpm = Double(words) / minutes
        let cpm = Double(cues.count) / minutes
        let coverage = (cues.map(\.start).max() ?? 0) / runtime

        if wpm < minWordsPerMinute {
            return Report(ok: false, reason: "the recognizer produced very little speech "
                          + "(\(Int(wpm)) words/min) — the audio is probably too poor",
                          wordsPerMinute: wpm)
        }
        if wpm > maxWordsPerMinute {
            return Report(ok: false, reason: "runaway output", wordsPerMinute: wpm)
        }
        if cpm < minCuesPerMinute {
            return Report(ok: false, reason: "too few captions for the length", wordsPerMinute: wpm)
        }
        if coverage < minCoverage {
            return Report(ok: false, reason: "captions stop \(Int(coverage * 100))% in",
                          wordsPerMinute: wpm)
        }
        // Local degeneracy — the "ALRIGHT ALRIGHT ALRIGHT" class (Decision 043).
        let texts = cues.map { $0.text.lowercased() }
        let dup = zip(texts, texts.dropFirst()).filter { !$0.0.isEmpty && $0.0 == $0.1 }.count
        if Double(dup) / Double(texts.count) > 0.08 {
            return Report(ok: false, reason: "the transcript repeats itself", wordsPerMinute: wpm)
        }
        return Report(ok: true, reason: "\(cues.count) captions", wordsPerMinute: wpm)
    }

    /// Cues → WebVTT.
    static func vtt(from cues: [(start: Double, text: String)], runtime: Double) -> String {
        func stamp(_ t: Double) -> String {
            let ms = Int((t - t.rounded(.down)) * 1000)
            let s = Int(t)
            return String(format: "%02d:%02d:%02d.%03d", s / 3600, (s % 3600) / 60, s % 60, ms)
        }
        var out = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n"
        for (i, c) in cues.enumerated() {
            let end = min(i + 1 < cues.count ? cues[i + 1].start : c.start + 4, runtime)
            guard end > c.start else { continue }
            out += "\(i + 1)\n\(stamp(c.start)) --> \(stamp(end))\n\(c.text)\n\n"
        }
        return out
    }
}

enum AutoCaptions {

    /// Whether on-device transcription is possible at all here.
    static var isSupported: Bool {
        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) { return true }
        #endif
        return false
    }

    enum Failure: Error, LocalizedError {
        case unsupported, silentFilm, noAudio, rejected(String), failed(String)
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Automatic captions need a newer system version."
            case .silentFilm:  return "This is a silent film — there is no dialogue to caption."
            case .noAudio:     return "This title has no usable audio track."
            case .rejected(let why): return "Automatic captions weren't good enough to show: \(why)"
            case .failed(let m): return m
            }
        }
    }

    /// Transcribe a LOCAL audio/video file to WebVTT, or throw with a reason.
    ///
    /// `isSilentFilm` is refused before any work: fabricating dialogue over a
    /// silent film is the single worst outcome here and is prevented by not
    /// running, never by inspecting the result.
    static func transcribe(fileURL: URL, runtime: Double,
                           isSilentFilm: Bool) async throws -> String {
        guard !isSilentFilm else { throw Failure.silentFilm }
        guard isSupported else { throw Failure.unsupported }
        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            let cues = try await runTranscriber(fileURL: fileURL)
            let report = CaptionQuality.assess(cues: cues, runtime: runtime)
            guard report.ok else { throw Failure.rejected(report.reason) }
            return CaptionQuality.vtt(from: cues, runtime: runtime)
        }
        #endif
        throw Failure.unsupported
    }

    /// Extract a plain audio file from a movie container.
    ///
    /// `AVAudioFile` reads AUDIO files; handed an .mp4 it fails. The film's audio
    /// is exported to m4a first — which also means we transcribe a few MB rather
    /// than a multi-GB video.
    static func extractAudio(from movie: URL) async throws -> URL {
        let asset = AVURLAsset(url: movie)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-transcribe-\(UUID().uuidString).m4a")
        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noAudio
        }
        export.outputURL = out
        export.outputFileType = .m4a
        try await export.export(to: out, as: .m4a)
        return out
    }

    #if canImport(Speech)
    /// Read `source` and yield its audio as `format` buffers for the analyzer.
    ///
    /// In memory, because the alternative — converting to a temp FILE — fails on
    /// the format the analyzer actually asks for (coreaudio 'fmt?': what
    /// `bestAvailableAudioFormat` returns is not necessarily something
    /// `AVAudioFile` will write).
    @available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
    private static func pcmStream(from source: AVAudioFile,
                                  as format: AVAudioFormat) throws -> AsyncStream<AnalyzerInput> {
        guard let converter = AVAudioConverter(from: source.processingFormat, to: format) else {
            throw Failure.failed("This device can't convert the audio for transcription.")
        }
        let inCap: AVAudioFrameCount = 16384
        let ratio = format.sampleRate / source.processingFormat.sampleRate
        return AsyncStream { continuation in
            do {
                // `read(into:frameCount:)` throws eofErr (-39) at the end rather
                // than returning zero frames, so drive the loop off the length.
                while source.framePosition < source.length {
                    let remaining = AVAudioFrameCount(min(Int64(inCap),
                                                          source.length - source.framePosition))
                    if remaining == 0 { break }
                    guard let inBuf = AVAudioPCMBuffer(pcmFormat: source.processingFormat,
                                                       frameCapacity: remaining) else { break }
                    try source.read(into: inBuf, frameCount: remaining)
                    if inBuf.frameLength == 0 { break }
                    let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1024
                    guard let outBuf = AVAudioPCMBuffer(pcmFormat: format,
                                                        frameCapacity: outCap) else { break }
                    var err: NSError?
                    var fed = false
                    converter.convert(to: outBuf, error: &err) { _, status in
                        if fed { status.pointee = .noDataNow; return nil }
                        fed = true
                        status.pointee = .haveData
                        return inBuf
                    }
                    if err != nil { break }
                    if outBuf.frameLength > 0 {
                        continuation.yield(AnalyzerInput(buffer: outBuf))
                    }
                }
            } catch {
                // Fall through: whatever was yielded still gets transcribed, and
                // CaptionQuality refuses a transcript that stops early.
            }
            continuation.finish()
        }
    }

    @available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
    private static func runTranscriber(fileURL: URL) async throws -> [(start: Double, text: String)] {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"),
                                            preset: .timeIndexedTranscriptionWithAlternatives)
        // Install the language model, and REPORT it when that fails.
        //
        // Both calls used to be `try?`. On a machine where the model is already
        // present (any Mac that has used dictation) that is invisible; on a
        // fresh CI runner it silently leaves no model installed, and every
        // subsequent failure surfaces as the misleading "No common audio format
        // among modules" — 1,096 films in one batch, none of them actually an
        // audio-format problem. A swallowed setup error is not a small thing:
        // it renamed the bug.
        let installed = await SpeechTranscriber.installedLocales
            .contains { $0.identifier(.bcp47) == "en-US" }
        if !installed {
            do {
                if let req = try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]) {
                    try await req.downloadAndInstall()
                }
            } catch {
                throw Failure.failed("Couldn't install the speech model: "
                                     + error.localizedDescription)
            }
        }
        // Deliberately NOT gated on `status == .installed`: measured on a Mac
        // where transcription demonstrably works, the status reads `.supported`,
        // so treating anything else as fatal would break the path that works.
        // The status is carried instead into the diagnosis below, where it is
        // the difference between a real answer and a misleading one.
        let status = await AssetInventory.status(forModules: [transcriber])
        // Hand the analyzer audio in a format it accepts, rather than whatever
        // the extractor happened to produce.
        //
        // This is not defensive tidying: feeding it a 16 kHz mono AAC file
        // worked on macOS 27 and failed on macOS 26 with SFSpeechErrorDomain
        // Code=5 "No common audio format among modules" — 24 of 24 films on the
        // first CI batch, a run that stayed green while producing nothing. The
        // supported format is whatever `bestAvailableAudioFormat` reports for
        // THESE modules on THIS OS, so ask, and convert when it differs.
        // Try the file as extracted FIRST, and convert only if the analyzer
        // refuses it. Converting unconditionally was measurably worse: the
        // as-extracted path transcribes a 29-minute film in 26s, while routing
        // the same audio through a conversion left the analyzer running for
        // 17+ minutes without finishing. So the fast path stays the default and
        // conversion is the fallback for the OS that needs it.
        //
        // `finishAfterFile: true` drives the whole file and finishes, so results
        // can be consumed on THIS task. Collecting them from a separate Task
        // instead is a Swift 6 data race on the accumulator.
        let source = try AVAudioFile(forReading: fileURL)
        do {
            _ = try await SpeechAnalyzer(inputAudioFile: source, modules: [transcriber],
                                         finishAfterFile: true)
        } catch {
            // SFSpeechErrorDomain Code=5 "No common audio format among modules".
            // macOS 27 accepts the 16 kHz mono file the extractor produces;
            // macOS 26 runners refuse it — 890 of 1096 films in one CI batch.
            //
            // Feed BUFFERS in the analyzer's own format rather than another
            // file. Writing a converted file was the first attempt and failed
            // its own way (coreaudio 'fmt?' — the format it asks for is not
            // necessarily one AVAudioFile will write), so the file is taken out
            // of the loop entirely.
            guard let want = await SpeechAnalyzer
                .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                // No available format means the MODEL is missing, not the audio.
                // Reporting the analyzer's original "No common audio format
                // among modules" here sent a whole batch chasing codecs.
                throw Failure.failed("No speech model is available for en-US "
                                     + "(asset status \(status)) — transcription "
                                     + "cannot run on this machine.")
            }
            let stream = try pcmStream(from: source, as: want)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            _ = try await analyzer.analyzeSequence(stream)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        var cues: [(start: Double, text: String)] = []
        for try await result in transcriber.results {
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append((start: CMTimeGetSeconds(result.range.start), text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }
    #endif
}
