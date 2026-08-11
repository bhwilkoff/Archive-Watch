// Find published subtitle files that are out of sync with their own film.
//
// The app checks this per viewer, per playback, on Apple platforms only
// (Decision 062). Fixing it in the FILE fixes it once, for everyone — web and
// Android included, neither of which can transcribe on device. That is the only
// route by which those platforms get correct subtitles at all.
//
// It has to run on a machine that HAS the speech models. A hosted GitHub runner
// does not and cannot get them (Decision 060: supportedLocales 0,
// status(forModules:) unsupported), so this is a local tool, resumable, working
// through the catalogue popularity-first.
//
// Compiled against the SHIPPED `SubtitleAgreement` and `LiveCaptions`, so what
// this decides is exactly what the app decides — a divergence here would mean
// correcting files by one rule while the players judge them by another.
//
// Build:
//   xcrun swiftc -O -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleAgreement.swift \
//     tools/subtitle_sync_main.swift -o /tmp/subsync
//   /tmp/subsync work.json verdicts.jsonl [listenSeconds]

import AVFoundation
import Foundation

struct Job: Decodable {
    let id: String
    let mp4: String
    let vtt: String
}

@main
struct SyncAudit {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 2 else {
            print("usage: subsync <work.json> <verdicts.jsonl> [listenSeconds]"); exit(2)
        }
        let listen = args.count > 3 ? (Double(args[3]) ?? 240) : 240

        guard let data = FileManager.default.contents(atPath: args[1]),
              let jobs = try? JSONDecoder().decode([Job].self, from: data) else {
            print("could not read the work list"); exit(2)
        }
        guard await LiveCaptions.isSupported,
              await CaptionCapability.shared.resolved() else {
            print("this machine has no speech models — see Decision 060"); exit(1)
        }

        // Resume: never re-listen to a film already decided.
        var done = Set<String>()
        if let existing = try? String(contentsOfFile: args[2], encoding: .utf8) {
            for line in existing.split(separator: "\n") {
                if let d = line.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let id = o["id"] as? String { done.insert(id) }
            }
        }
        let todo = jobs.filter { !done.contains($0.id) }
        print("\(jobs.count) films · \(done.count) already decided · \(todo.count) to do\n")

        var counts: [String: Int] = [:]
        for (i, job) in todo.enumerated() {
            let started = Date()
            let verdict = await audit(job, listenFor: listen)
            let elapsed = Date().timeIntervalSince(started)
            counts[verdict["choice"] as? String ?? "?", default: 0] += 1
            append(verdict, to: args[2])
            let note = verdict["note"] as? String ?? ""
            print(String(format: "[%d/%d] %-42@ %-9@ %@ (%.0fs)",
                         i + 1, todo.count, job.id as NSString,
                         (verdict["choice"] as? String ?? "?") as NSString, note, elapsed))
        }
        print("\nsummary: " + counts.map { "\($0.key) \($0.value)" }.sorted().joined(separator: " · "))
    }

    static func audit(_ job: Job, listenFor: Double) async -> [String: Any] {
        guard let mp4 = URL(string: job.mp4), let vttURL = URL(string: job.vtt) else {
            return ["id": job.id, "choice": "error", "note": "bad url"]
        }
        guard let body = await fetchText(vttURL) else {
            return ["id": job.id, "choice": "error", "note": "vtt unreachable"]
        }
        let published = SubtitleAgreement.parseVTT(body)
        guard published.count >= 10 else {
            return ["id": job.id, "choice": "error", "note": "only \(published.count) cues"]
        }

        let captions = await LiveCaptions()
        await captions.start(url: mp4, from: .zero)
        let deadline = Date().addingTimeInterval(listenFor * 1.4 + 90)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await captions.leadSeconds(over: .zero) > listenFor { break }
            if await !captions.isRunning { break }
        }
        let transcript = await captions.transcript().map {
            SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
        }
        let failure = await captions.failure
        await captions.stop()

        guard transcript.count >= 5 else {
            // A film we could not hear is NOT a film with bad subtitles. Saying
            // so explicitly keeps silence out of the "mismatch" bucket, where it
            // would delete a perfectly good file.
            return ["id": job.id, "choice": "unheard",
                    "note": failure ?? "\(transcript.count) cues transcribed"]
        }
        guard let verdict = SubtitleAgreement.judge(published: published,
                                                    transcript: transcript) else {
            return ["id": job.id, "choice": "no-verdict",
                    "note": "\(transcript.count) cues, not enough overlap"]
        }

        var out: [String: Any] = [
            "id": job.id,
            "agreement": round(verdict.agreement * 1000) / 1000,
            "agreementAtZero": round(verdict.agreementAtZero * 1000) / 1000,
            "offset": round(verdict.offset * 10) / 10,
            "comparedCues": verdict.comparedCues,
            "transcriptCues": transcript.count,
        ]
        switch verdict.choice {
        case .keepPublished:
            out["choice"] = "keep"
            out["note"] = String(format: "%.0f%%", verdict.agreement * 100)
        case .shiftPublished(let by):
            out["choice"] = "shift"
            out["shift"] = round(by * 10) / 10
            out["note"] = String(format: "%+.1fs → %.0f%% (was %.0f%%)", by,
                                 verdict.agreement * 100, verdict.agreementAtZero * 100)
        case .preferLive:
            out["choice"] = "mismatch"
            out["note"] = String(format: "%.0f%%", verdict.agreement * 100)
        }
        return out
    }

    static func append(_ object: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    static func fetchText(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
