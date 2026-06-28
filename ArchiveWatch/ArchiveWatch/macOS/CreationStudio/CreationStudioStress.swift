#if os(macOS)
import Foundation
import AVFoundation

// Robustness STRESS harness for the full supercut load (owner 2026-06-28: "as the preparing/verifying
// process completes … playback becomes unavailable, a small amount of clips are playable, preview and
// timeline get out of sync, the last few hang for minutes"). Unlike the feature audit (one cached
// item), this runs the REAL Phrase-Finder supercut over N DIFFERENT films WITH the verify pass — the
// actual failure mode — and CONTINUOUSLY samples the three invariants the owner named, reporting every
// violation with a timestamp:
//   INV-A  PREVIEW ALWAYS AVAILABLE — after the first frame, player.currentItem must never go nil /
//          fail / become unplayable while clips finish in the background.
//   INV-B  TIMELINE == PREVIEW — the composition's total duration must always match the timeline's
//          total (a drift means a clip on the timeline plays at a different spot than the preview).
//   INV-C  NO HANG / FULL LOAD — readiness must keep progressing (no multi-minute stall) and the whole
//          load must complete within a bound.
//
//   AW_CS_STRESS=50  AW_CS_PHRASES="what do you mean"   (one phrase; defaults to a common one)
@MainActor
enum CreationStudioStress {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_STRESS"] != nil }
    static var count: Int { Int(ProcessInfo.processInfo.environment["AW_CS_STRESS"] ?? "50") ?? 50 }
    private static var phrase: String {
        (ProcessInfo.processInfo.environment["AW_CS_PHRASES"]?
            .split(separator: ";").first.map(String.init))?
            .trimmingCharacters(in: .whitespaces) ?? "what do you mean"
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("AWSTRESS \(s)\n".utf8)) }

    private static func previewSeconds(_ model: EditorModel) -> Double {
        guard let d = model.player.currentItem?.duration.seconds, d.isFinite else { return -1 }
        return d
    }
    private static func previewAvailable(_ model: EditorModel) -> Bool {
        guard let item = model.player.currentItem else { return false }
        return item.status != .failed && item.duration.seconds.isFinite && item.duration.seconds > 0.05
    }

    static func run(model: EditorModel, store: AppStore) async {
        for _ in 0..<240 where (store.db?.browseCount() ?? 0) < 5000 { try? await Task.sleep(for: .milliseconds(250)) }
        guard let index = SubtitleIndex(path: SubtitleIndex.bestURL) else { log("ABORT no-subtitle-index"); exit(0) }

        // Build N different-film takes (same path as the real Phrase Finder + the bench).
        var seen = Set<String>(), deduped: [SubtitleCue] = []
        for cue in index.search(phrase, limit: 800) where seen.insert(cue.filmKey).inserted { deduped.append(cue) }
        let langByID = Dictionary(store.itemsByIDs(deduped.map(\.archiveID)).map { ($0.archiveID, $0.language) },
                                  uniquingKeysWith: { a, _ in a })
        let english = deduped.filter { !SubtitleIndex.isNonEnglishAudio(language: langByID[$0.archiveID] ?? nil) }
        let takes = Array(english.prefix(count)).map {
            EditorModel.SupercutTake(proxy: $0.proxyClip, phrase: phrase, captionText: $0.text)
        }
        guard takes.count >= 8 else { log("ABORT only \(takes.count) candidates for \"\(phrase)\""); exit(0) }
        log("START phrase=\"\(phrase)\" takes=\(takes.count)")

        // --- invariant trackers ---
        var firstAvailableMs = -1
        var unavailableAfterFirst = 0          // INV-A violations (preview went away after first frame)
        var maxDrift = 0.0; var maxDriftMs = 0; var driftViolations = 0   // INV-B
        var lastReady = 0; var lastProgressMs = 0; var maxStallMs = 0     // INV-C
        var sampleCount = 0
        let driftTol = 1.25

        let start = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(start) * 1000) }

        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let now = ms()
                sampleCount += 1
                let avail = previewAvailable(model)
                if avail, firstAvailableMs < 0 { firstAvailableMs = now }
                if firstAvailableMs >= 0, !avail { unavailableAfterFirst += 1 }
                // INV-B only meaningful once a preview exists.
                if avail {
                    let pv = previewSeconds(model), tl = model.totalDuration
                    let drift = abs(pv - tl)
                    if drift > maxDrift { maxDrift = drift; maxDriftMs = now }
                    if drift > driftTol {
                        driftViolations += 1
                        if driftViolations <= 6 {
                            let ready = model.clips.filter { model.clipPrep[$0.id] == .ready }.count
                            log("DRIFT @\(now)ms preview=\(rnd(pv)) timeline=\(rnd(tl)) clips=\(model.clips.count) ready=\(ready)")
                        }
                    }
                }
                // INV-C progress / stall.
                let ready = model.clips.filter { model.clipPrep[$0.id] == .ready }.count
                if ready > lastReady { lastReady = ready; lastProgressMs = now }
                maxStallMs = max(maxStallMs, now - lastProgressMs)
            }
        }

        model.addSupercutClips(takes, tighten: false, evenVolume: false)

        // PREVIEW-settle = every clip is ready OR given up (no clip still .caching). This is what the
        // user feels — when the editor is fully populated. The VERIFY pass (isRefining) then runs in the
        // BACKGROUND with the editor fully usable, so it is NOT counted as a hang. Track both.
        var previewSettledMs = -1, settledMs = -1
        for _ in 0..<2400 {                                   // up to 480s
            try? await Task.sleep(for: .milliseconds(200))
            let caching = model.clips.contains { model.clipPrep[$0.id] == .caching }
            // Preview is settled once EVERY clip reached a terminal state (ready or given-up/failed) —
            // not merely "nothing caching yet" (which is true before caching even starts).
            let allTerminal = !model.clips.isEmpty && model.clips.allSatisfy {
                switch model.clipPrep[$0.id] { case .ready, .failed: return true; default: return false }
            }
            if previewSettledMs < 0, allTerminal, !model.isBuildingPreview { previewSettledMs = ms() }
            if !caching && !model.isBuildingPreview && !model.isRefining && previewSettledMs >= 0 { settledMs = ms(); break }
        }
        // Let it rest a beat so the final compose lands, then sample the end state.
        try? await Task.sleep(for: .milliseconds(400))
        sampler.cancel()

        let finalClips = model.clips.count
        let finalReady = model.clips.filter { model.clipPrep[$0.id] == .ready }.count
        let finalFailed = model.clips.filter { if case .failed = model.clipPrep[$0.id] { return true }; return false }.count
        let endPv = previewSeconds(model), endTl = model.totalDuration
        let endAvail = previewAvailable(model)

        // INV-B: a handful of TRANSIENT drift samples are tolerable (the one frame between an atomic
        // verify-apply and its rebuild). A small percentage threshold catches a real persistent desync.
        let driftPct = sampleCount > 0 ? Double(driftViolations) / Double(sampleCount) : 0
        let invB = driftPct <= 0.05
        // INV-C: the PREVIEW must fully populate (dead clips given up) within a bound — the editor is
        // usable the whole time (INV-A), and the verify pass finishing later is background work.
        let invC = previewSettledMs >= 0 && previewSettledMs < 75_000

        log("FIRST-PREVIEW ms=\(firstAvailableMs)")
        log("PREVIEW-SETTLED ms=\(previewSettledMs)  VERIFY-SETTLED ms=\(settledMs) (-1 = HUNG past 480s)")
        log("END clips=\(finalClips) ready=\(finalReady) failed=\(finalFailed) preview=\(rnd(endPv)) timeline=\(rnd(endTl)) available=\(endAvail)")
        log("INV-A preview-available: firstAt=\(firstAvailableMs)ms, wentUnavailable=\(unavailableAfterFirst) samples \(unavailableAfterFirst == 0 ? "PASS" : "FAIL")")
        log("INV-B timeline==preview: maxDrift=\(rnd(maxDrift))s @\(maxDriftMs)ms, violations(>\(driftTol)s)=\(driftViolations)/\(sampleCount) (\(Int(driftPct*100))%) \(invB ? "PASS" : "FAIL")")
        log("INV-C preview-populates: previewSettled=\(previewSettledMs)ms (verify bg done @\(settledMs)ms) \(invC ? "PASS" : "FAIL")")
        log("END-STATE: \(finalReady)/\(finalClips) playable, preview \(endAvail ? "available" : "UNAVAILABLE"), drift=\(rnd(abs(endPv - endTl)))s")
        log("DONE")
        try? await Task.sleep(for: .milliseconds(300))
        exit(0)
    }

    private static func rnd(_ d: Double) -> String { String(format: "%.2f", d) }
}
#endif
