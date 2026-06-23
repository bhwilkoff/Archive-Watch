#if os(macOS)
import Foundation
import AVFoundation

// Env-gated end-to-end validation of the Creation Studio engine (de-risk spike #3,
// docs/macOS-DESIGN.md §9.3 / Rule 4b) — the macOS analogue of the project's
// AW_PLAYBACK_DIAG diagnostics. Set AW_CS_SELFTEST=1 to run, on launch, the full
// cache-then-export pipeline on TWO real archive.org titles and print the result. No-op
// otherwise. Output goes to Library/Caches so it needs no user-selected file scope.
@MainActor
enum CreationStudioSelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_SELFTEST"] == "1" }

    static func run(store: AppStore) async {
        // stderr is unbuffered (stdout block-buffers when redirected), and a result file
        // survives buffering entirely — read it directly.
        let resultFile = ProjectMediaCache.directory.appendingPathComponent("selftest-result.txt")
        func log(_ s: String) {
            let line = "AWCS SELFTEST: \(s)\n"
            FileHandle.standardError.write(Data(line.utf8))
            if let h = try? FileHandle(forWritingTo: resultFile) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.data(using: .utf8)?.write(to: resultFile)
            }
        }
        try? "".write(to: resultFile, atomically: true, encoding: .utf8)
        log("starting · cacheDir=\(ProjectMediaCache.directory.path)")

        // Wait for the catalog DB to swap in (randomPlayable needs it).
        var tries = 0
        while store.randomPlayable() == nil && tries < 60 {
            try? await Task.sleep(for: .seconds(1)); tries += 1
        }
        guard let a = store.randomPlayable(), let aURL = a.videoURLParsed else {
            log("FAIL — no playable catalog item after \(tries)s"); return
        }
        let b = store.randomPlayable() ?? a
        let bURL = b.videoURLParsed ?? aURL

        // A 2-clip cross-title timeline: an 8s window from each title, back to back.
        var timeline = Timeline()
        timeline.clips = [
            TimelineClip(catalogItemID: a.archiveID, sourceURL: aURL,
                         sourceRange: TimeRange(startSeconds: 3, durationSeconds: 8),
                         timelineStart: .zero, track: 0, label: a.title),
            TimelineClip(catalogItemID: b.archiveID, sourceURL: bURL,
                         sourceRange: TimeRange(startSeconds: 3, durationSeconds: 8),
                         timelineStart: TimeStamp(seconds: 8), track: 0, label: b.title),
        ]
        // Phase 2 #3: a timed text overlay (yellow, centered, t=2–9s).
        timeline.textOverlays = [
            TextOverlay(text: "ARCHIVE WATCH",
                        timelineRange: TimeRange(startSeconds: 2, durationSeconds: 7),
                        positionX: 0.5, positionY: 0.5, fontScale: 0.07, colorHex: "#FFD60A")
        ]
        log("clips: \(a.archiveID) + \(b.archiveID); + 1 text overlay; expected duration ~16s")

        // Export BOTH ways: with the attribution credit (default), then a CLEAN export
        // (owner decision — attribution is optional). The clean run reuses the cached
        // clip files, so only the first export pays the streaming cost.
        for (variant, burn) in [("credit", true), ("clean", false)] {
            let project = ClipProject(title: "SelfTest", timeline: timeline, burnAttribution: burn)
            let out = ProjectMediaCache.directory.appendingPathComponent("selftest-\(variant).mp4")
            let exporter = ExportService()
            let t0 = Date()
            await exporter.export(project, to: out)
            let dt = Int(Date().timeIntervalSince(t0))
            switch exporter.phase {
            case .done:
                let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                log("DONE[\(variant)] in \(dt)s — \(out.lastPathComponent) (\((size ?? 0) / 1024) KB)")
                // Read provenance metadata back via AVFoundation's COMMON view (maps the
                // format-specific atoms back to common identifiers — the right reader).
                let common = (try? await AVURLAsset(url: out).load(.commonMetadata)) ?? []
                let t = (try? await common.first { $0.identifier == .commonIdentifierTitle }?.load(.stringValue)) ?? nil
                let d = (try? await common.first { $0.identifier == .commonIdentifierDescription }?.load(.stringValue)) ?? nil
                log("metadata[\(variant)]: title=\(t ?? "nil") | desc=\(d ?? "nil")")
            case .failed(let m):
                log("FAIL[\(variant)] in \(dt)s — \(m)")
            default:
                log("ENDED[\(variant)] in unexpected phase")
            }
        }
    }
}
#endif
