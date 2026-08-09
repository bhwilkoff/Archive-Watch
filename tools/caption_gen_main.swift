// Generate subtitles for a batch of films with Apple's on-device transcriber.
//
// This is the CENTRAL counterpart to the in-app "Get subtitles" action: same
// engine, same quality gate (it compiles the SHIPPED AutoCaptions.swift, so the
// gate can never drift between them), but run once on a macOS runner so every
// viewer on every platform gets the result — instead of each viewer downloading
// a whole film to transcribe it themselves.
//
// WHY THIS IS NOT DECISION 039a AGAIN. That was whisper.cpp, retired by 039b
// because it produced fluent, confident, WRONG dialogue on archival audio and
// fabricated speech over silent films. Three things differ: the engine is
// SpeechTranscriber (macOS 26), which is materially stronger on this material
// and measured at ~108x realtime; every result passes CaptionQuality, which
// rejects the sparse/looping/truncated output a failing recognizer produces; and
// silent films are REFUSED before any work rather than inspected after.
//
// THE LIMIT still stands and is stated in the output: a transcript that is
// fluent and WRONG cannot be detected from its text. These tracks are labelled
// auto-generated wherever they appear.
//
// Work list JSON: [{"id": "...", "url": "https://...", "runtime": 5400}, ...]
// Writes <out>/<id>/en.vtt for each film that passes, plus a report JSON.
//
// Build (compiles the shipped engine — no copy, no drift):
//   xcrun swiftc -O ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     tools/caption_gen_main.swift -o /tmp/captiongen
// Run:
//   /tmp/captiongen work.json out/ report.json [--max-minutes 240]

import AVFoundation
import Foundation

struct Film: Codable { let id: String; let url: String; let runtime: Double }

struct Result: Codable {
    let id: String
    let ok: Bool
    let reason: String
    let cues: Int
    let seconds: Double
}

@main
struct CaptionGen {

    /// Pull just the audio with ffmpeg. AVFoundation refuses to read a remote
    /// asset for anything but playback (AVAssetReader: "non-local URL";
    /// AVAssetExportSession: -11838), and ffmpeg streams the container and keeps
    /// only the audio, so this costs bandwidth but almost no disk.
    static func extractAudio(_ url: String, to dest: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["ffmpeg", "-nostdin", "-loglevel", "error", "-y",
                       "-i", url, "-vn", "-ac", "1", "-ar", "16000",
                       "-c:a", "aac", dest.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
            && (try? dest.checkResourceIsReachable()) == true
    }

    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            print("usage: captiongen <work.json> <outdir> <report.json> [--max-minutes N]")
            exit(2)
        }
        let workURL = URL(fileURLWithPath: args[1])
        let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
        let reportURL = URL(fileURLWithPath: args[3])
        var budget: Double = 0
        if let i = args.firstIndex(of: "--max-minutes"), i + 1 < args.count {
            budget = Double(args[i + 1]) ?? 0
        }

        guard AutoCaptions.isSupported else {
            print("ERROR: this runner's OS has no SpeechTranscriber (needs macOS 26+).")
            exit(1)
        }
        guard let data = try? Data(contentsOf: workURL),
              let films = try? JSONDecoder().decode([Film].self, from: data) else {
            print("ERROR: could not read \(workURL.path)"); exit(2)
        }

        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let deadline = budget > 0 ? Date().addingTimeInterval(budget * 60) : nil
        var results: [Result] = []
        var passed = 0, rejected = 0, failed = 0

        print("captiongen: \(films.count) films, budget \(budget > 0 ? "\(Int(budget))m" : "none")")

        for (n, film) in films.enumerated() {
            if let deadline, Date() > deadline {
                print("captiongen: STOPPED EARLY at the budget — \(n) of \(films.count) attempted; "
                      + "the rest are picked up next run.")
                break
            }
            let started = Date()
            let audio = FileManager.default.temporaryDirectory
                .appendingPathComponent("cg-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: audio) }

            guard extractAudio(film.url, to: audio) else {
                failed += 1
                results.append(.init(id: film.id, ok: false, reason: "audio extraction failed",
                                     cues: 0, seconds: -started.timeIntervalSinceNow))
                print("[\(n + 1)/\(films.count)] \(film.id): no audio")
                continue
            }

            do {
                // isSilentFilm is decided upstream by the selector; anything that
                // reaches here is sound-era. Refusal, not detection.
                let vtt = try await AutoCaptions.transcribe(fileURL: audio,
                                                            runtime: film.runtime,
                                                            isSilentFilm: false)
                let dir = outDir.appendingPathComponent(film.id, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try vtt.write(to: dir.appendingPathComponent("en.vtt"), atomically: true,
                              encoding: .utf8)
                let cues = vtt.components(separatedBy: "-->").count - 1
                passed += 1
                results.append(.init(id: film.id, ok: true, reason: "ok", cues: cues,
                                     seconds: -started.timeIntervalSinceNow))
                print("[\(n + 1)/\(films.count)] \(film.id): \(cues) cues "
                      + "(\(Int(-started.timeIntervalSinceNow))s)")
            } catch {
                rejected += 1
                let why = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                results.append(.init(id: film.id, ok: false, reason: why, cues: 0,
                                     seconds: -started.timeIntervalSinceNow))
                print("[\(n + 1)/\(films.count)] \(film.id): REJECTED — \(why)")
            }
        }

        let out = try? JSONEncoder().encode(results)
        try? out?.write(to: reportURL)
        print("\ncaptiongen: passed=\(passed) rejected=\(rejected) failed=\(failed)")
        // A rejection is a RESULT — the gate refusing output that would be worse
        // than nothing — so it must never read as a broken run.
        exit(0)
    }
}
