#if os(macOS)
import Foundation
import AVFoundation

// Autonomous proxy-render benchmark (owner task 2026-06-26): measure + optimize how fast the
// preview pipeline renders N never-before-processed clips. Env-gated, NO macOS permissions needed
// (runs unattended): `AW_CS_BENCH=20` launches the editor, pulls N fresh random clippable items
// from the catalog, runs the REAL rebuildPreview path, writes precise per-stage timings to
// /tmp/aw_bench.log, and exits. Success criteria: 20 clips ready in <= 60s.
/// Overridable per-trial config the pipeline reads (so one app launch can sweep many configs —
/// GUI relaunch is flaky due to macOS state restoration). Falls back to env, then the shipped default.
enum BenchConfig {
    nonisolated(unsafe) static var concurrency: Int?
    nonisolated(unsafe) static var handle: Double?
}

enum CreationStudioBench {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_BENCH"] != nil }
    static var count: Int { Int(ProcessInfo.processInfo.environment["AW_CS_BENCH"] ?? "20") ?? 20 }

    nonisolated(unsafe) static var benchStart = Date()
    private static let logURL = URL(fileURLWithPath: "/tmp/aw_bench.log")
    private static let testedURL = URL(fileURLWithPath: "/tmp/aw_bench_tested.json")

    /// Timestamped (ms since bench start) event line → stderr + /tmp/aw_bench.log. Called from the
    /// pipeline stages (gated) so I can see EXACTLY what runs before the first byte is fetched.
    static func mark(_ event: String) {
        let ms = Int(Date().timeIntervalSince(benchStart) * 1000)
        let line = "AWBENCH \(ms) \(event)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: logURL) }
    }

    private static func loadTested() -> Set<String> {
        guard let d = try? Data(contentsOf: testedURL),
              let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(a)
    }
    private static func saveTested(_ s: Set<String>) {
        try? JSONEncoder().encode(Array(s)).write(to: testedURL)
    }

    /// The sweep plan: (concurrency, handleSeconds). One launch runs them all — reliable + comparable.
    /// `AW_CS_BENCH_PLAN="8:1,10:1"` overrides; default sweeps the promising range.
    private static var plan: [(Int, Double)] {
        if let s = ProcessInfo.processInfo.environment["AW_CS_BENCH_PLAN"] {
            return s.split(separator: ",").compactMap {
                let p = $0.split(separator: ":"); guard p.count == 2, let c = Int(p[0]), let h = Double(p[1]) else { return nil }
                return (c, h)
            }
        }
        return [(4, 1), (6, 1), (8, 1), (10, 1), (8, 0.5), (8, 2)]
    }

    @MainActor
    static func run(model: EditorModel, store: AppStore) async {
        // Wait for the FULL catalog (the seed has too few items + no variety for a fair benchmark).
        for _ in 0..<160 where (store.db?.browseCount() ?? 0) < 5000 { try? await Task.sleep(for: .milliseconds(250)) }
        mark("SWEEP catalog=\(store.db?.browseCount() ?? 0) plan=\(plan.map { "\($0.0):\($0.1)" }.joined(separator: ","))")
        var tested = loadTested()

        for (conc, handle) in plan {
            // Fresh, never-before-processed picks for THIS trial.
            var picks: [Catalog.Item] = []
            var tries = 0
            while picks.count < count && tries < count * 80 {
                tries += 1
                guard let it = store.db?.randomPlayable() else { break }
                if tested.contains(it.archiveID) || picks.contains(where: { $0.archiveID == it.archiveID }) { continue }
                guard it.isClippable, it.videoURLParsed != nil else { continue }
                picks.append(it)
            }
            guard !picks.isEmpty else { mark("ABORT no-fresh-items (tested=\(tested.count))"); break }
            for p in picks { tested.insert(p.archiveID) }
            saveTested(tested)

            BenchConfig.concurrency = conc
            BenchConfig.handle = handle
            model.project.timeline.clips.removeAll()
            for p in picks {
                model.project.timeline.clips.append(TimelineClip(
                    catalogItemID: p.archiveID, sourceURL: p.videoURLParsed!,
                    sourceRange: TimeRange(startSeconds: 8, durationSeconds: 4),
                    timelineStart: .zero, track: 0, label: p.title))
            }
            benchStart = Date()
            mark("TRIAL conc=\(conc) handle=\(handle) n=\(picks.count)")
            await model.rebuildPreview()
            let allMs = Int(Date().timeIntervalSince(benchStart) * 1000)
            let ready = model.clips.filter { model.clipPrep[$0.id] == .ready }.count
            mark("RESULT conc=\(conc) handle=\(handle) ready=\(ready)/\(picks.count) totalMs=\(allMs) projected20s=\(String(format: "%.1f", Double(allMs)/Double(max(1,ready))*20/1000))")
        }
        mark("DONE sweep complete")
        try? await Task.sleep(for: .milliseconds(300))
        exit(0)
    }
}
#endif
