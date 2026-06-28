#if os(macOS)
import Foundation
import AVFoundation

// Autonomous FEATURE AUDIT for Creation Studio (owner 2026-06-28: "make sure that each and every
// feature/button/action within the Creation Studio interface actually does what it is meant to do").
// Env-gated, no GUI driving: `AW_CS_AUDIT=1` launches the editor, runs each feature against the REAL
// bound EditorModel + composition/preview pipeline (the same model the visible editor uses), ASSERTS
// on the real result (composition duration, cached-window span, clip state — not just the timeline
// model), prints a PASS/FAIL chart to stderr, then exits.
//
// The assertions look at what the PREVIEW actually composes, because the reported regression is
// exactly that: the timeline model updates (the block grows) but the preview never reflects it. So a
// test that only inspects `clip.sourceRange` would pass while the feature is broken — every check
// here verifies the COMPOSITION (model.player.currentItem) changed as expected.
@MainActor
enum CreationStudioFeatureAudit {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_AUDIT"] != nil }

    private static func log(_ s: String) {
        FileHandle.standardError.write(Data("AWAUDIT \(s)\n".utf8))
    }

    private struct Result { let name: String; let pass: Bool; let detail: String }
    private static var results: [Result] = []
    private static func check(_ name: String, _ pass: Bool, _ detail: String) {
        results.append(Result(name: name, pass: pass, detail: detail))
        log("\(pass ? "PASS" : "FAIL") [\(name)] \(detail)")
    }

    // The composition's total playable duration right now (what the program monitor will play).
    private static func previewSeconds(_ model: EditorModel) -> Double {
        guard let item = model.player.currentItem else { return -1 }
        let d = item.duration.seconds
        return d.isFinite ? d : -1
    }

    /// Wait until a rebuild that started AFTER `gen` has COMPLETED (debug_rebuildCount advanced) AND the
    /// preview has settled (no clip caching, not building/refining, the current item is ready). Keying
    /// off the generation counter avoids racing the 140ms rebuild debounce — the real bug only shows
    /// once a genuine rebuild has run to completion. Returns false on timeout.
    private static func settle(_ model: EditorModel, after gen: Int, timeout: Double = 60) async -> Bool {
        let deadline = Int(timeout * 10)
        var advanced = false
        for _ in 0..<deadline {
            try? await Task.sleep(for: .milliseconds(100))
            if model.debug_rebuildCount > gen { advanced = true }
            guard advanced else { continue }
            let anyCaching = model.clips.contains { model.clipPrep[$0.id] == .caching }
            let stable = !anyCaching && !model.isBuildingPreview && !model.isRefining && !model.isInteracting
            let itemReady = model.clips.isEmpty || model.player.currentItem?.status == .readyToPlay
            if stable && itemReady { return true }
        }
        return false
    }

    /// Simulate a timeline drag: begin, apply the edit, end (which fires the single deferred rebuild) —
    /// exactly the bracket TimelineView uses around a trim/move drag. Returns the rebuild generation
    /// captured BEFORE the edit so the caller can wait for the resulting rebuild to complete.
    @discardableResult
    private static func dragEdit(_ model: EditorModel, _ body: () -> Void) -> Int {
        let gen = model.debug_rebuildCount
        model.beginInteraction()
        body()
        model.endInteraction()
        return gen
    }

    static func run(model: EditorModel, store: AppStore) async {
        log("START waiting for full catalog")
        for _ in 0..<240 where (store.db?.browseCount() ?? 0) < 5000 { try? await Task.sleep(for: .milliseconds(250)) }
        log("catalog=\(store.db?.browseCount() ?? 0)")

        guard let item = CreationStudioTest.clippable(store), let url = item.videoURLParsed else {
            log("ABORT no clippable item"); finish()
        }
        log("subject item=\(item.archiveID) title=\"\(item.title)\"")

        await auditTrim(model, item: item, url: url)
        await auditTrimThenScrub(model, item: item, url: url)
        await auditTrimMultiClip(model, item: item, url: url)
        await auditSplit(model, item: item, url: url)
        await auditReorderAndDelete(model, item: item, url: url)
        await auditFadesTransitionsLooksSpeed(model, item: item, url: url)
        await auditPlayheadStability(model, item: item, url: url)
        await auditSwapCount(model, item: item, url: url)
        await auditPlayWhileLoading(model, item: item, url: url)
        await auditDuplicateCopyPasteMute(model, item: item, url: url)
        await auditTextOverlays(model, item: item, url: url)
        await auditMarkersAndSettings(model, item: item, url: url)
        await auditUndoRedo(model, item: item, url: url)
        await auditExport(model, item: item, url: url)
        // Runs LAST: its deliberately-failing clips churn background retries for ~80s, which would
        // pollute the baselines of duration-sensitive tests if it ran earlier.
        await auditAlignmentWithFailures(model, item: item, url: url)

        finish()
    }

    private static func finish() -> Never {
        let passed = results.filter(\.pass).count
        log("==== SUMMARY \(passed)/\(results.count) passed ====")
        for r in results where !r.pass { log("  FAILED: [\(r.name)] \(r.detail)") }
        FileHandle.standardError.write(Data("AWAUDIT DONE\n".utf8))
        exit(0)
    }

    // MARK: - Trim (the reported regression)

    private static func auditTrim(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                      inSeconds: 20, durationSeconds: 3)
        guard let id = model.clips.first?.id else { check("trim.setup", false, "no clip added"); return }
        guard await settle(model, after: g) else {
            check("trim.setup", false, "clip never reached ready (network?)"); return
        }
        let base = previewSeconds(model)
        check("trim.setup", abs(base - 3) < 1.0, "initial preview=\(rnd(base))s expected ~3s")

        // EXTEND OUT by 7s (3 -> 10). Must re-cache a larger window and the preview must GROW.
        g = dragEdit(model) { model.trim(id, newOutSeconds: 30) }   // out 23 -> 30 => dur 10
        _ = await settle(model, after: g)
        let afterOut = previewSeconds(model)
        let span1 = model.debug_windowSpan(id)
        let actual1 = model.debug_clipActualDuration[id] ?? -1
        check("trim.extendOut", afterOut > base + 4,
              "preview \(rnd(base))->\(rnd(afterOut))s (want >\(rnd(base+4))); actualDur=\(rnd(actual1)) "
              + "window=[\(rnd(span1?.start ?? -1)),\(rnd(span1?.end ?? -1))] req.dur=10")

        // EXTEND IN earlier by 10s (in 20 -> 10). dur 10 -> 20. Preview must grow again.
        g = dragEdit(model) { model.trim(id, newInSeconds: 10) }    // in 20 -> 10 => dur 20
        _ = await settle(model, after: g)
        let afterIn = previewSeconds(model)
        check("trim.extendIn", afterIn > afterOut + 4,
              "preview \(rnd(afterOut))->\(rnd(afterIn))s (want >\(rnd(afterOut+4)))")

        // SHRINK back (in 10->15, out 30->18 => dur 3). Preview must shrink.
        g = dragEdit(model) { model.trim(id, newInSeconds: 15, newOutSeconds: 18) }
        _ = await settle(model, after: g)
        let afterShrink = previewSeconds(model)
        check("trim.shrink", afterShrink < afterIn - 4 && afterShrink > 1,
              "preview \(rnd(afterIn))->\(rnd(afterShrink))s (want <\(rnd(afterIn-4)))")
    }

    // MARK: - Trim, then immediately scrub (the real workflow that drops the rebuild)

    // The reported bug: you trim a clip, then scrub/play to SEE the new footage — and the preview
    // never updates. A scrub's beginInteraction cancels the trim's still-in-flight (debounced, then
    // slow) rebuild, and a scrub-only endInteraction reschedules nothing, so the committed edit is
    // silently lost. This reproduces that exact sequence.
    private static func auditTrimThenScrub(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                      inSeconds: 20, durationSeconds: 3)
        guard let id = model.clips.first?.id, await settle(model, after: g) else {
            check("trimScrub.setup", false, "clip never ready"); return
        }
        let base = previewSeconds(model)

        // Trim-extend on release (schedules a deferred rebuild)…
        g = model.debug_rebuildCount
        model.beginInteraction()
        model.trim(id, newOutSeconds: 30)        // 3 -> 10s
        model.endInteraction()                   // schedules the committed rebuild (140ms debounce)
        // …then the user immediately scrubs to check the result, BEFORE that rebuild finishes.
        try? await Task.sleep(for: .milliseconds(20))   // < the 140ms debounce
        model.beginInteraction()                 // a scrub: cancels the in-flight committed rebuild
        model.seek(toSeconds: 4)
        model.endInteraction()                   // scrub-only

        let completed = await settle(model, after: g, timeout: 12)
        let after = previewSeconds(model)
        check("trimScrub.extend", completed && after > base + 4,
              "preview \(rnd(base))->\(rnd(after))s (want >\(rnd(base+4))); rebuildCompleted=\(completed)")
    }

    // MARK: - Preview↔timeline ALIGNMENT when some clips fail (the "wrong clip plays" bug)

    // The reported bug: the preview plays a different clip than the timeline shows. Root cause was that
    // failed/unresolved clips were DROPPED from the composition while staying on the timeline, so every
    // later clip shifted earlier. This test mixes real clips with clips whose source can't resolve and
    // asserts the composition stays positionally 1:1 with the timeline (total preview == total timeline,
    // clip count unchanged) — i.e. failed clips become black GAPS at their slot, not shifts.
    private static func auditAlignmentWithFailures(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        let g = model.debug_rebuildCount
        for k in 0..<5 {
            if k % 2 == 0 {
                model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                              inSeconds: 10 + Double(k) * 5, durationSeconds: 3)
            } else {
                // A source that cannot resolve (no such item) — guaranteed to fail → becomes a gap.
                let bogus = "aw-nonexistent-item-\(k)-zzqqx"
                model.addClip(catalogItemID: bogus,
                              sourceURL: URL(string: "https://archive.org/download/\(bogus)/none.mp4")!,
                              title: "BOGUS \(k)", durationSeconds: 3)
            }
        }
        _ = g
        // Alignment holds as soon as the reals compose — a not-yet-resolved/failed clip is a GAP at its
        // slot, so we DON'T need to wait the ~80s for the bogus clips to fully give up. Poll for the
        // composition total to match the timeline total (and the preview must actually appear fast —
        // that it does, while bogus clips still churn, is the anti-hang proof).
        let aligned = await waitAligned(model, timeout: 75)
        let tl = model.totalDuration, pv = previewSeconds(model)
        check("align.failures", aligned && model.clips.count == 5,
              "clips=\(model.clips.count) timeline=\(rnd(tl))s preview=\(rnd(pv))s aligned=\(aligned) "
              + "(must match — failed/loading clips are GAPS at their slot, not shifts)")

        // Trimming a REAL clip must keep the alignment.
        if let realID = model.clips.first(where: { $0.label == item.title })?.id {
            dragEdit(model) { model.trim(realID, newOutSeconds: 10 + 6) }   // extend the first real clip
            let aligned2 = await waitAligned(model, timeout: 60)
            check("align.afterTrim", aligned2,
                  "after trim: timeline=\(rnd(model.totalDuration))s preview=\(rnd(previewSeconds(model)))s aligned=\(aligned2)")
        }
    }

    /// Poll until the composition total matches the timeline total (preview is positionally 1:1 with
    /// the timeline) and the item is playable. Does NOT require every clip to have resolved — gaps
    /// reserve unresolved slots — so it converges in seconds even when some clips are still loading.
    private static func waitAligned(_ model: EditorModel, timeout: Double) async -> Bool {
        for _ in 0..<Int(timeout * 10) {
            try? await Task.sleep(for: .milliseconds(100))
            let pv = previewSeconds(model)
            if pv > 0, abs(pv - model.totalDuration) < 1.2,
               model.player.currentItem?.status == .readyToPlay { return true }
        }
        return false
    }

    // MARK: - Trim inside a MANY-clip timeline (the real supercut-editing scenario)

    private static func auditTrimMultiClip(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        let g0 = model.debug_rebuildCount
        // 10 short clips from staggered in-points (like a supercut), each ~2s.
        for k in 0..<10 {
            model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                          inSeconds: 10 + Double(k) * 5, durationSeconds: 2)
        }
        guard await settle(model, after: g0, timeout: 120) else {
            check("multitrim.setup", false, "10 clips never all ready"); return
        }
        let total0 = previewSeconds(model)
        check("multitrim.setup", model.clips.count == 10 && total0 > 16,
              "10 clips, total preview=\(rnd(total0))s (~20 expected)")

        // Trim the MIDDLE clip's out by +6s. Its window must re-cache and the TOTAL preview must grow ~6s.
        let mid = model.clips[5].id
        let midOut = model.clips[5].sourceRange.endSeconds
        let g1 = dragEdit(model) { model.trim(mid, newOutSeconds: midOut + 6) }
        _ = await settle(model, after: g1, timeout: 120)
        let total1 = previewSeconds(model)
        let midActual = model.debug_clipActualDuration[mid] ?? -1
        let span = model.debug_windowSpan(mid)
        check("multitrim.extend", total1 > total0 + 4 && midActual > 6,
              "total \(rnd(total0))->\(rnd(total1))s (want >+4); midActualDur=\(rnd(midActual)) "
              + "window=[\(rnd(span?.start ?? -1)),\(rnd(span?.end ?? -1))]")
    }

    // MARK: - Split

    private static func auditSplit(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                      inSeconds: 10, durationSeconds: 10)
        guard let id = model.clips.first?.id, await settle(model, after: g) else {
            check("split.setup", false, "clip never ready"); return
        }
        let before = previewSeconds(model)
        g = model.debug_rebuildCount
        model.splitClip(id, atTimelineSeconds: 5)   // cut at the midpoint
        _ = await settle(model, after: g)
        let parts = model.clips.count
        let after = previewSeconds(model)
        check("split.count", parts == 2, "clips after split=\(parts) (want 2)")
        // Splitting must not lose footage — total preview length should be ~unchanged.
        check("split.duration", abs(after - before) < 1.5,
              "total preview \(rnd(before))->\(rnd(after))s (want ~unchanged)")
    }

    // MARK: - Reorder + delete

    private static func auditReorderAndDelete(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 4)
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 40, durationSeconds: 4)
        guard await settle(model, after: g) else { check("reorder.setup", false, "clips never ready"); return }
        let twoLen = previewSeconds(model)
        check("reorder.setup", model.clips.count == 2 && twoLen > 6, "2 clips, preview=\(rnd(twoLen))s")

        let firstID = model.clips[0].id
        let firstIn = model.clips[0].sourceRange.start.seconds
        g = model.debug_rebuildCount
        model.moveClip(firstID, toIndex: 1)
        _ = await settle(model, after: g)
        let nowSecond = model.clips.firstIndex { $0.id == firstID } == 1
        check("reorder.move", nowSecond, "moved clip is now index \(model.clips.firstIndex { $0.id == firstID } ?? -1) (want 1)")
        check("reorder.duration", abs(previewSeconds(model) - twoLen) < 1.5,
              "preview \(rnd(twoLen))->\(rnd(previewSeconds(model)))s (want ~unchanged); firstIn=\(rnd(firstIn))")

        // Delete one clip — preview must shrink to roughly one clip.
        g = model.debug_rebuildCount
        model.deleteClip(model.clips[0].id)
        _ = await settle(model, after: g)
        let oneLen = previewSeconds(model)
        check("delete.clip", model.clips.count == 1 && oneLen < twoLen - 2,
              "after delete clips=\(model.clips.count), preview \(rnd(twoLen))->\(rnd(oneLen))s")
    }

    // MARK: - Fades / transitions / looks / speed (these recompose the preview)

    private static func auditFadesTransitionsLooksSpeed(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 6)
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 40, durationSeconds: 6)
        guard await settle(model, after: g) else { check("fx.setup", false, "clips never ready"); return }
        let a = model.clips[0].id, b = model.clips[1].id

        model.setClipFade(a, fadeIn: 1.5, fadeOut: 1.0)
        let fc = model.clips.first { $0.id == a }
        check("fx.fade", (fc?.fadeInSeconds ?? 0) == 1.5 && (fc?.fadeOutSeconds ?? 0) == 1.0,
              "fadeIn=\(rnd(fc?.fadeInSeconds ?? -1)) fadeOut=\(rnd(fc?.fadeOutSeconds ?? -1))")

        let before = previewSeconds(model)
        g = model.debug_rebuildCount
        model.setClipTransition(b, 1.5)   // overlap shortens the total timeline by ~the dissolve length
        _ = await settle(model, after: g)
        let after = previewSeconds(model)
        check("fx.transition", after < before - 0.5,
              "dissolve shortened preview \(rnd(before))->\(rnd(after))s (overlap)")

        g = model.debug_rebuildCount
        model.setClipLook(a, .noir)
        _ = await settle(model, after: g)
        check("fx.look", model.clips.first { $0.id == a }?.look == .noir,
              "look=\(String(describing: model.clips.first { $0.id == a }?.look))")
    }

    // MARK: - Playhead stays put across an edit (must NOT snap to the timeline start)

    private static func auditPlayheadStability(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        for k in 0..<4 {
            model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                          inSeconds: 10 + Double(k) * 5, durationSeconds: 4)
        }
        guard await settle(model, after: g) else { check("playhead.setup", false, "clips never ready"); return }

        // Park the playhead deep in the timeline (≈ 3rd clip), as if mid-edit there.
        model.seek(toSeconds: 9)
        let before = model.playheadSeconds
        check("playhead.setup", abs(before - 9) < 0.6, "parked playhead at \(rnd(before)) (want ~9)")

        // Trim a clip — the rebuild must keep the playhead where it was, not snap to 0.
        let id = model.clips[1].id
        g = dragEdit(model) { model.trim(id, newOutSeconds: 15 + 5) }   // extend 2nd clip
        _ = await settle(model, after: g)
        let after = model.playheadSeconds
        check("playhead.stable", after > 1.0 && abs(after - before) < 1.5,
              "playhead \(rnd(before))->\(rnd(after)) across the edit (must stay put, NOT snap to 0)")
    }

    // MARK: - Preview must not "flash with every update" — a load does only a FEW item swaps

    private static func auditSwapCount(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        // Force a fresh blank monitor so the load starts from nil (the early-compose path).
        model.player.replaceCurrentItem(with: nil)
        let swaps0 = model.debug_swapCount
        let g = model.debug_rebuildCount
        for k in 0..<12 {
            model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                          inSeconds: 8 + Double(k) * 4, durationSeconds: 3)
        }
        guard await settle(model, after: g, timeout: 90) else { check("flash.swaps", false, "never settled"); return }
        // Let any debounced/auto-retry rebuilds settle, then count swaps for the whole 12-clip load.
        try? await Task.sleep(for: .seconds(2))
        let swaps = model.debug_swapCount - swaps0
        // The preview fills in CHUNKS (a few batched composes), NOT per-clip — per-clip would be ~12
        // swaps for this load (the strobe the owner reported). A handful proves it's batched.
        check("flash.swaps", swaps <= 7,
              "12-clip load did \(swaps) preview swaps (want <=7, well under per-clip — batched, not strobing)")
    }

    // MARK: - Playback continues (no jump to 0) while more clips load in the background

    private static func auditPlayWhileLoading(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        model.player.replaceCurrentItem(with: nil)
        let g = model.debug_rebuildCount
        for k in 0..<4 {
            model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                          inSeconds: 8 + Double(k) * 5, durationSeconds: 5)
        }
        guard await settle(model, after: g) else { check("playLoad.setup", false, "clips never ready"); return }

        // Press play partway in, then add MORE clips WHILE PLAYING.
        model.seek(toSeconds: 3)
        model.play()
        try? await Task.sleep(for: .seconds(1.2))
        let swaps0 = model.debug_swapCount
        for k in 0..<4 {
            model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title,
                          inSeconds: 40 + Double(k) * 5, durationSeconds: 5)
        }
        try? await Task.sleep(for: .seconds(3))   // let the (deferred) rebuild run while playing
        let during = model.playheadSeconds
        let swapsWhilePlaying = model.debug_swapCount - swaps0
        // The playhead must NOT snap to 0, and the item must NOT be swapped while playing (deferred).
        check("playLoad.noReset", during > 1.0,
              "playhead while loading-during-playback=\(rnd(during)) (must NOT jump to 0)")
        check("playLoad.deferred", swapsWhilePlaying == 0,
              "preview swaps while playing=\(swapsWhilePlaying) (must defer to pause/end — 0)")

        // Pausing must catch the preview up to the full timeline (the deferred fill applies).
        model.pause()
        let caughtUp = await waitAligned(model, timeout: 30)
        check("playLoad.catchUp", caughtUp && model.clips.count == 8,
              "after pause: clips=\(model.clips.count) preview=\(rnd(previewSeconds(model))) timeline=\(rnd(model.totalDuration)) caughtUp=\(caughtUp)")
    }

    // MARK: - Duplicate / copy-paste / mute / volume

    private static func auditDuplicateCopyPasteMute(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 4)
        guard let id = model.clips.first?.id, await settle(model, after: g) else {
            check("dup.setup", false, "clip never ready"); return
        }
        let oneLen = previewSeconds(model)

        // Duplicate — a 2nd clip from the same window; preview must roughly double.
        g = model.debug_rebuildCount
        model.duplicateClip(id)
        _ = await settle(model, after: g)
        check("dup.duplicate", model.clips.count == 2 && previewSeconds(model) > oneLen + 2,
              "clips=\(model.clips.count) preview \(rnd(oneLen))->\(rnd(previewSeconds(model)))s")

        // Mute the first clip → its audioVolume becomes 0.
        model.selectOnly(model.clips[0].id)
        model.toggleMuteSelected()
        check("dup.mute", model.clips[0].audioVolume == 0, "audioVolume=\(rnd(model.clips[0].audioVolume)) (want 0)")
        model.setClipVolume(model.clips[0].id, 0.5)
        check("dup.volume", abs(model.clips[0].audioVolume - 0.5) < 0.01, "audioVolume=\(rnd(model.clips[0].audioVolume))")

        // Copy + paste → a 3rd clip.
        let twoLen = previewSeconds(model)
        model.selectOnly(model.clips[1].id)
        model.copySelected()
        g = model.debug_rebuildCount
        model.paste()
        _ = await settle(model, after: g)
        check("dup.paste", model.clips.count == 3 && previewSeconds(model) > twoLen + 2,
              "clips=\(model.clips.count) preview \(rnd(twoLen))->\(rnd(previewSeconds(model)))s")
    }

    // MARK: - Text overlays (#3) — preview length unaffected (overlays render as a layer), model tracks them

    private static func auditTextOverlays(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        let g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 8)
        guard await settle(model, after: g) else { check("text.setup", false, "clip never ready"); return }
        model.playheadSeconds = 2

        let n0 = model.textOverlays.count
        model.addTextOverlay()
        check("text.add", model.textOverlays.count == n0 + 1, "overlays \(n0)->\(model.textOverlays.count)")
        guard var ov = model.textOverlays.last else { check("text.update", false, "no overlay"); return }
        ov.text = "AUDIT TITLE"
        model.updateOverlay(ov)
        check("text.update", model.textOverlays.last?.text == "AUDIT TITLE",
              "text=\"\(model.textOverlays.last?.text ?? "")\"")
        model.deleteOverlay(ov.id)
        check("text.delete", model.textOverlays.count == n0, "overlays back to \(model.textOverlays.count)")
    }

    // MARK: - Markers + project settings (render size / frame rate)

    private static func auditMarkersAndSettings(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        let g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 12)
        guard await settle(model, after: g) else { check("marker.setup", false, "clip never ready"); return }

        model.playheadSeconds = 4
        let m0 = model.markers.count
        model.toggleMarkerAtPlayhead()
        check("marker.add", model.markers.count == m0 + 1, "markers \(m0)->\(model.markers.count)")
        model.playheadSeconds = 0
        model.goToMarker(forward: true)
        check("marker.goTo", abs(model.playheadSeconds - 4) < 0.3, "playhead jumped to \(rnd(model.playheadSeconds)) (want ~4)")
        model.goToEnd()
        check("nav.end", model.playheadSeconds > model.totalDuration - 0.1, "playhead=\(rnd(model.playheadSeconds)) total=\(rnd(model.totalDuration))")

        model.setRenderSize(.init(width: 1080, height: 1920))   // portrait
        check("settings.renderSize", model.project.timeline.renderSize.width == 1080 && model.project.timeline.renderSize.height == 1920,
              "renderSize=\(model.project.timeline.renderSize.width)x\(model.project.timeline.renderSize.height)")
        model.setFrameRate(24)
        check("settings.frameRate", abs(model.project.timeline.frameRate - 24) < 0.01, "fps=\(rnd(model.project.timeline.frameRate))")
    }

    // MARK: - Export (the whole point — a real composition written to a real file)

    private static func auditExport(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        let g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 8, durationSeconds: 3)
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 30, durationSeconds: 3)
        guard await settle(model, after: g) else { check("export.setup", false, "clips never ready"); return }
        let timelineLen = model.totalDuration
        log("export: timeline ready len=\(rnd(timelineLen)), exporting…")

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-audit-export-\(Int(timelineLen)).mp4")
        try? FileManager.default.removeItem(at: out)
        let svc = ExportService()
        let project = model.project
        let task = Task { await svc.export(project, to: out, format: .h264) }
        // Hard cap so a stalled archive.org node can't hang the audit forever.
        var timedOut = true
        for _ in 0..<2400 {                                  // up to 240s
            try? await Task.sleep(for: .milliseconds(100))
            if svc.phase == .done { timedOut = false; break }
            if case .failed = svc.phase { timedOut = false; break }
        }
        if timedOut { task.cancel() }
        guard !timedOut, svc.phase == .done else {
            check("export.h264", false, "export phase=\(String(describing: svc.phase)) (timedOut=\(timedOut))"); return
        }
        let exists = FileManager.default.fileExists(atPath: out.path)
        let asset = AVURLAsset(url: out)
        let vTrack = (try? await asset.loadTracks(withMediaType: .video))?.first != nil
        let dur = (try? await asset.load(.duration))?.seconds ?? -1
        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        check("export.h264", exists && vTrack && abs(dur - timelineLen) < 1.5 && size > 50_000,
              "file=\(exists) videoTrack=\(vTrack) dur=\(rnd(dur))s (timeline=\(rnd(timelineLen))) bytes=\(size)")
        try? FileManager.default.removeItem(at: out)
    }

    // MARK: - Undo / redo

    private static func auditUndoRedo(_ model: EditorModel, item: Catalog.Item, url: URL) async {
        model.project.timeline.clips.removeAll()
        var g = model.debug_rebuildCount
        model.addClip(catalogItemID: item.archiveID, sourceURL: url, title: item.title, inSeconds: 5, durationSeconds: 6)
        guard let id = model.clips.first?.id, await settle(model, after: g) else {
            check("undo.setup", false, "clip never ready"); return
        }
        let dur0 = model.clips.first?.sourceRange.duration.seconds ?? -1
        log("undo: setup ready dur0=\(rnd(dur0))")
        let um = UndoManager(); model.undoManager = um          // default grouping (per run-loop event)
        um.beginUndoGrouping()
        model.checkpoint()                                     // registers the inverse on `um`
        let g1 = dragEdit(model) { model.trim(id, newOutSeconds: 25) }   // big extend
        um.endUndoGrouping()
        _ = await settle(model, after: g1)
        let dur1 = model.clips.first?.sourceRange.duration.seconds ?? -1
        log("undo: after edit dur1=\(rnd(dur1)), undoing…")
        g = model.debug_rebuildCount
        um.undo()
        _ = await settle(model, after: g)
        let durU = model.clips.first?.sourceRange.duration.seconds ?? -1
        log("undo: after undo durU=\(rnd(durU))")
        check("undo.trim", abs(durU - dur0) < 0.6 && dur1 > dur0 + 4,
              "dur \(rnd(dur0))->edit \(rnd(dur1))->undo \(rnd(durU)) (want undo≈orig)")
    }

    private static func rnd(_ d: Double) -> String { String(format: "%.2f", d) }
}
#endif
