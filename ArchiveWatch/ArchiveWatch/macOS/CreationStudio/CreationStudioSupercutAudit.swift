#if os(macOS)
import Foundation
import AVFoundation

// Supercut-path audit (owner 2026-06-29): "create tests where you generate new projects, search for
// 50 clips with the following phrases and ensure that the processing goes through and visually works
// to play through as soon as the processing is fully complete." Phrases: "I am here", "waiting on you",
// "build it", "safe now", "You're wrong".
//
// Env: AW_CS_SUPERCUT=1. This drives the REAL Phrase-Finder path (SubtitleIndex.search → SupercutTake
// → EditorModel.addSupercutClips → background verify + caching), then asserts the three reported bugs
// are fixed against the REAL preview composition:
//   overlay   — once processing completes, the "clips couldn't load" overlay is CLEAR (no .failed clips
//               linger, not building, not refining, no blocked reason).
//   noFailed  — clips that won't load are REMOVED from the timeline (not left as dead slots).
//   resolved  — EVERY surviving clip resolved (clipPrep == .ready) → no black gaps.
//   align     — preview duration == timeline duration (positionally 1:1 → plays through, no blanks).
//   playsThru — pressing Play actually advances the playhead through the composition (liveness).
@MainActor
enum CreationStudioSupercutAudit {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_SUPERCUT"] != nil }
    private static let phrases = ["I am here", "waiting on you", "build it", "safe now", "You're wrong"]
    private static var perPhrase: Int { Int(ProcessInfo.processInfo.environment["AW_CS_SUPERCUT_PER"] ?? "") ?? 10 }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("AWSUPER \(s)\n".utf8)) }
    private static func rnd(_ d: Double) -> String { String(format: "%.1f", d) }
    private struct R { let name: String; let pass: Bool; let detail: String }
    private static var results: [R] = []
    private static func check(_ name: String, _ pass: Bool, _ detail: String) {
        results.append(R(name: name, pass: pass, detail: detail))
        log("\(pass ? "PASS" : "FAIL") [\(name)] \(detail)")
    }
    private static func previewSeconds(_ m: EditorModel) -> Double {
        guard let d = m.player.currentItem?.duration.seconds, d.isFinite else { return -1 }; return d
    }

    static func run(model: EditorModel, store: AppStore) async {
        log("START — building subtitle index")
        for _ in 0..<240 where (store.db?.browseCount() ?? 0) < 5000 { try? await Task.sleep(for: .milliseconds(250)) }
        await SubtitleIndexBuilder.ensureIndex(store: store)
        guard let index = SubtitleIndex(path: SubtitleIndex.bestURL) else {
            check("index", false, "no subtitle index available"); finish()
        }
        log("index ready (\(index.cueCount) cues)")

        // Build a 50-clip supercut from the 5 phrases (perPhrase each), exactly as SupercutSheet does:
        // search → dedupe by film identity → drop non-English-audio films → SupercutTake.
        var takes: [EditorModel.SupercutTake] = []
        var seenFilms = Set<String>()
        for phrase in phrases {
            let cues = index.search(phrase, limit: 400)
            var kept = 0
            for cue in cues where seenFilms.insert(cue.filmKey).inserted {
                let lang = store.item(cue.archiveID)?.language
                if SubtitleIndex.isNonEnglishAudio(language: lang) { continue }
                takes.append(.init(proxy: cue.proxyClip, phrase: phrase, captionText: cue.text))
                kept += 1
                if kept >= perPhrase { break }
            }
            log("phrase \"\(phrase)\": \(kept) takes")
        }
        check("search", takes.count >= phrases.count, "assembled \(takes.count) takes across \(phrases.count) phrases")
        guard !takes.isEmpty else { finish() }

        // Reset the editor + add the whole batch at once (the real "add 50" path: instant add, then
        // background verify + caching). No tighten/even — the verify pass ALWAYS runs regardless.
        model.pause()
        model.project = .empty
        await model.rebuildPreview()
        let added = takes.count
        model.addSupercutClips(takes, tighten: false, evenVolume: false, addSubtitles: false)
        log("added \(added) clips; waiting for processing (cache + verify) to complete…")

        // Wait until processing is FULLY complete: not refining, not building, nothing caching, every
        // remaining clip resolved (.ready), item playable. The verify pass + caching of ~50 distinct
        // films is slow, so the cap is generous; a real hang exceeds it.
        let cap = Double(ProcessInfo.processInfo.environment["AW_CS_SUPERCUT_CAP"] ?? "") ?? 480
        let started = Date()
        var firstPreviewAt: Date?
        var completeAt: Date?
        let deadline = started.addingTimeInterval(cap)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            if firstPreviewAt == nil, model.player.currentItem?.status == .readyToPlay { firstPreviewAt = Date() }
            let caching = model.clips.contains { model.clipPrep[$0.id] == .caching }
            let anyNil  = model.clips.contains { model.clipPrep[$0.id] == nil }
            let complete = !model.isRefining && !model.isBuildingPreview && !caching && !anyNil
                && !model.clips.isEmpty && model.player.currentItem?.status == .readyToPlay
            if complete { completeAt = Date(); break }
        }

        let survived = model.clips.count
        let failures = model.prepStatus.failures
        let notReady = model.clips.filter { model.clipPrep[$0.id] != .ready }
        let tl = model.totalDuration, pv = previewSeconds(model)
        let firstS = firstPreviewAt.map { $0.timeIntervalSince(started) }
        let fullS = completeAt.map { $0.timeIntervalSince(started) }

        log("added=\(added) survived=\(survived) removed=\(added - survived) firstPreview=\(firstS.map(rnd) ?? "—")s complete=\(fullS.map(rnd) ?? ">\(rnd(cap))")s")

        check("complete", completeAt != nil,
              "processing settled in \(fullS.map(rnd) ?? ">\(rnd(cap))")s (cap \(rnd(cap))s)"
              + (completeAt == nil ? " — HANG: never reached a fully-processed state" : ""))
        // BUG 1 — the "couldn't load" overlay must be gone once processing completes.
        check("overlay.clear", failures.isEmpty && model.previewBlockedReason == nil && !model.isBuildingPreview && !model.isRefining,
              "failures=\(failures.count) blocked=\(model.previewBlockedReason ?? "nil") building=\(model.isBuildingPreview) refining=\(model.isRefining) (all must be empty/false)")
        // BUG 2 — clips that won't load are REMOVED, not left in the timeline.
        check("noFailedClips", notReady.isEmpty,
              "\(notReady.count) clips not .ready remain in the timeline (must be 0 — dead clips are removed)")
        // BUG 3 — every surviving clip resolved → composition is gap-free → plays through (no blanks).
        check("resolved", survived > 0 && notReady.isEmpty,
              "\(survived) clips, all resolved=\(notReady.isEmpty)")
        check("align", pv > 0 && abs(pv - tl) < max(1.5, tl * 0.03),
              "preview=\(rnd(pv))s timeline=\(rnd(tl))s (must match → no black gaps)")

        // Liveness: pressing Play advances the playhead through the composition at ~realtime, crossing
        // many clip boundaries without stalling. Sample each second so we can tell startup latency from
        // a steady-state stall (the owner's "didn't play through" was a stuck/sluggish player).
        if completeAt != nil, survived > 0 {
            model.seek(toSeconds: 0)
            try? await Task.sleep(for: .milliseconds(400))
            let p0 = model.playheadSeconds
            model.play()
            var samples: [Double] = []
            for _ in 0..<12 { try? await Task.sleep(for: .seconds(1)); samples.append(model.playheadSeconds) }
            let p1 = model.playheadSeconds
            model.pause()
            // Steady-state rate over the LAST 8s (excludes startup buffering): should be ~1s/s.
            let steady = samples.count >= 9 ? (samples[11] - samples[3]) / 8.0 : 0
            check("playsThrough", p1 > p0 + 8 && steady > 0.7 && model.player.currentItem?.status == .readyToPlay,
                  "playhead \(rnd(p0))->\(rnd(p1)) over 12s (want >+8); steady-state \(rnd(steady))×; samples=[\(samples.map { rnd($0) }.joined(separator: ","))]")
        } else {
            check("playsThrough", false, "skipped — processing never completed")
        }

        finish()
    }

    private static func finish() -> Never {
        let pass = results.filter(\.pass).count
        log("==== SUMMARY \(pass)/\(results.count) passed ====")
        for r in results where !r.pass { log("  FAILED: [\(r.name)] \(r.detail)") }
        FileHandle.standardError.write(Data("AWSUPER DONE\n".utf8))
        exit(results.allSatisfy(\.pass) ? 0 : 1)
    }
}
#endif
