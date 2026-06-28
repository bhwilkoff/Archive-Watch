#if os(macOS)
import Foundation
import AVFoundation

// Autonomous supercut benchmark (owner tasks 2026-06-26 / 2026-06-27). Env-gated, no GUI driving
// needed: `AW_CS_BENCH=50` launches the editor, runs the REAL Phrase Finder path (subtitle search →
// dedup → addSupercutClips with the verify pass) for a set of phrases, and writes per-run metrics to
// stderr + /tmp/aw_bench.log, then exits. Measures the FOUR things the owner cares about:
//   • STARTUP  — ms until the FIRST clip is ready (time-to-first-frame)
//   • THROUGHPUT — ms until all clips resolved
//   • RETENTION — how many of N survive (verify removes/replaces) — must NOT lose ~half
//   • ACCURACY — verify verdict distribution (confirmed / contradicted / unverifiable) as a proxy
//     for false-positive (unverifiable kept) and false-negative (contradicted dropped) rates.
//
// Earlier the bench added RANDOM clips with a fixed time range, so it measured render speed only and
// never exercised the phrase match or the verify pass — exactly the things the owner reported broken.
/// Overridable per-trial config the pipeline reads (one launch can sweep configs — GUI relaunch is
/// flaky due to macOS state restoration). Falls back to env, then the shipped default.
enum BenchConfig {
    nonisolated(unsafe) static var concurrency: Int?
    nonisolated(unsafe) static var handle: Double?
}

enum CreationStudioBench {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_BENCH"] != nil }
    static var count: Int { Int(ProcessInfo.processInfo.environment["AW_CS_BENCH"] ?? "50") ?? 50 }

    nonisolated(unsafe) static var benchStart = Date()
    private static let logURL = URL(fileURLWithPath: "/tmp/aw_bench.log")
    private static let testedURL = URL(fileURLWithPath: "/tmp/aw_bench_phrases.json")

    // --- live metrics for the run in progress (reset per phrase trial). Touched only from the
    // MainActor (EditorModel is @MainActor; the bench is @MainActor), so no lock is needed. ---
    @MainActor private static var firstReadyMs: Int?
    @MainActor private static var vConfirmed = 0, vContradicted = 0, vUnverifiable = 0

    static func mark(_ event: String) {
        let ms = Int(Date().timeIntervalSince(benchStart) * 1000)
        let line = "AWBENCH \(ms) \(event)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: logURL) }
    }

    /// Called (gated) the first time a clip reaches .ready in a trial → time-to-first-frame.
    @MainActor static func noteReady() {
        guard isEnabled else { return }
        if firstReadyMs == nil { firstReadyMs = Int(Date().timeIntervalSince(benchStart) * 1000) }
    }
    /// Called (gated) from the verify pass with each clip's verdict + detail → accuracy distribution.
    @MainActor static func noteVerdict(_ kind: String, phrase: String, detail: String) {
        guard isEnabled else { return }
        switch kind { case "confirmed": vConfirmed += 1; case "contradicted": vContradicted += 1; default: vUnverifiable += 1 }
        mark("VERDICT \(kind) phrase=\"\(phrase)\" \(detail)")
    }

    /// Phrases to exercise — common multi-word lines that recur across many films, so each yields
    /// dozens of distinct-film candidates. Override with AW_CS_PHRASES="a;b;c".
    private static var phrases: [String] {
        if let s = ProcessInfo.processInfo.environment["AW_CS_PHRASES"] {
            return s.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return ["i don't know", "what do you mean", "i love you", "come on",
                "wait a minute", "what's going on", "let's go", "i can't believe"]
    }

    private static func loadTested() -> Set<String> {
        guard let d = try? Data(contentsOf: testedURL),
              let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(a)
    }
    private static func saveTested(_ s: Set<String>) { try? JSONEncoder().encode(Array(s)).write(to: testedURL) }

    @MainActor
    static func run(model: EditorModel, store: AppStore) async {
        for _ in 0..<160 where (store.db?.browseCount() ?? 0) < 5000 { try? await Task.sleep(for: .milliseconds(250)) }
        guard let index = SubtitleIndex(path: SubtitleIndex.bestURL) else { mark("ABORT no-subtitle-index"); exit(0) }
        let conc = BenchConfig.concurrency ?? Int(ProcessInfo.processInfo.environment["AW_CS_CONC"] ?? "") ?? 6
        let handle = BenchConfig.handle ?? Double(ProcessInfo.processInfo.environment["AW_CS_HANDLE"] ?? "") ?? 1.5
        BenchConfig.concurrency = conc; BenchConfig.handle = handle
        mark("SWEEP catalog=\(store.db?.browseCount() ?? 0) cues=\(index.cueCount) conc=\(conc) handle=\(handle) n=\(count)")

        var tested = loadTested()
        for phrase in phrases where !tested.contains(phrase) {
            tested.insert(phrase); saveTested(tested)
            // Real Phrase Finder path: LIKE+whole-word+confidence search, dedup to one cue per film.
            var seen = Set<String>(), deduped: [SubtitleCue] = []
            for cue in index.search(phrase, limit: 600) where seen.insert(cue.filmKey).inserted { deduped.append(cue) }
            // Drop non-English films (English subs = translation, foreign audio) — same as runFind.
            let langByID = Dictionary(store.itemsByIDs(deduped.map(\.archiveID)).map { ($0.archiveID, $0.language) },
                                      uniquingKeysWith: { a, _ in a })
            let nonEng = deduped.filter { SubtitleIndex.isNonEnglishAudio(language: langByID[$0.archiveID] ?? nil) }.count
            let english = deduped.filter { !SubtitleIndex.isNonEnglishAudio(language: langByID[$0.archiveID] ?? nil) }
            let cues = Array(english.prefix(count))
            mark("LANG-FILTER phrase=\"\(phrase)\" deduped=\(deduped.count) droppedNonEnglish=\(nonEng) kept=\(english.count)")
            guard cues.count >= 4 else { mark("SKIP phrase=\"\(phrase)\" only \(cues.count) candidates"); continue }

            // reset trial metrics
            firstReadyMs = nil; vConfirmed = 0; vContradicted = 0; vUnverifiable = 0
            model.project.timeline.clips.removeAll()
            let takes = cues.map { EditorModel.SupercutTake(proxy: $0.proxyClip, phrase: phrase, captionText: $0.text) }
            benchStart = Date()
            mark("TRIAL phrase=\"\(phrase)\" candidates=\(takes.count)")

            model.addSupercutClips(takes, tighten: false, evenVolume: false)
            // Wait for the preview to settle (first/all ready) AND the verify pass to finish removing.
            var settledMs = 0
            for _ in 0..<2400 {                                   // up to 600s
                try? await Task.sleep(for: .milliseconds(250))
                let preparing = model.clips.contains { model.clipPrep[$0.id] == .caching }
                if !model.isRefining && !preparing { break }
                settledMs += 250
            }
            let totalMs = Int(Date().timeIntervalSince(benchStart) * 1000)
            let surviving = model.clips.count
            let ready = model.clips.filter { model.clipPrep[$0.id] == .ready }.count
            let first = firstReadyMs ?? -1, c = vConfirmed, k = vContradicted, u = vUnverifiable
            let retained = takes.isEmpty ? 0 : Int(Double(surviving) / Double(takes.count) * 100)
            mark("RESULT phrase=\"\(phrase)\" added=\(takes.count) surviving=\(surviving) ready=\(ready) retained=\(retained)% "
               + "firstReadyMs=\(first) totalMs=\(totalMs) verdicts[confirmed=\(c) contradicted=\(k) unverifiable=\(u)]")
        }
        mark("DONE sweep complete")
        try? await Task.sleep(for: .milliseconds(300))
        exit(0)
    }
}
#endif
