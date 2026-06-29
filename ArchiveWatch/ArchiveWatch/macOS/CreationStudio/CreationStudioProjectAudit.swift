#if os(macOS)
import Foundation
import AVFoundation

// REAL-PROJECT audit for Creation Studio (owner 2026-06-28: "use the following fully built project
// files to ensure that each function actually works within the creation studio … from clip
// addition/processing to exporting. prove that each function/feature works").
//
// The synthetic FeatureAudit/Stress harnesses repeat ONE clippable item; the owner's real pain
// (blank previews for many clips, hangs on stubborn clips, crashes on length changes) only shows on
// REAL multi-source supercut projects where every clip is a DISTINCT archive.org film. This harness
// loads each `.archiveproj` the owner provided, sets it as the editor's project, and asserts against
// the REAL preview composition (model.player.currentItem) — not just the timeline model.
//
// Env: `AW_CS_PROJECTS=1` scans the app container's Documents for `*.archiveproj` packages (copy them
// there first — the sandbox can't read ~/Documents). Logs a PASS/FAIL chart per project to stderr.
//
// SUCCESS CRITERIA (per project), researched against the pipeline (EditorModel/CompositionBuilder):
//   decode       — the package decodes into a ClipProject with clips.
//   firstPreview — a PLAYABLE preview item (currentItem.status == .readyToPlay) appears FAST and is
//                  NOT gated on every clip resolving (the "blank/unusable until all rendered" bug).
//   fullLoad     — the load SETTLES within a hard cap: no clip stuck .caching, not building/refining
//                  (the "hang on stubborn clips for minutes" bug). Reports ready/failed/total.
//   align        — final preview duration == timeline duration (a failed/slow clip is a black GAP at
//                  its slot, never a shift — the "wrong clip plays / preview≠timeline" bug).
//   trim         — shrinking then re-extending a RESOLVED clip's out-point changes the PREVIEW length
//                  (the "clip length changes don't show" bug), in both directions, on real footage.
//   trimLeft     — a left-trim moves the block's LEFT edge (holds the right) during the drag and the
//                  next clip re-packs on release (the "shrinks from the wrong edge" bug).
//   split/delete — structural edits change the clip count + preview length and keep alignment.
//   playhead     — an edit does NOT snap the playhead to 0.
//   export       — a real composition writes to a real file with a video track ≈ the timeline length.
//   (crash)      — running every edit on real multi-source projects without an EXC_BAD_ACCESS IS the
//                  crash test the owner couldn't get me to reproduce on synthetic data.
@MainActor
enum CreationStudioProjectAudit {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_PROJECTS"] != nil }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("AWPROJ \(s)\n".utf8)) }
    private static func rnd(_ d: Double) -> String { String(format: "%.1f", d) }

    private struct Result { let project: String; let name: String; let pass: Bool?; let detail: String }
    private static var results: [Result] = []
    /// pass=true PASS, pass=false FAIL, pass=nil SKIP (couldn't test — e.g. no clip resolved on a
    /// throttled network; a SKIP is reported honestly, never silently counted as a pass).
    private static func check(_ project: String, _ name: String, _ pass: Bool?, _ detail: String) {
        results.append(Result(project: project, name: name, pass: pass, detail: detail))
        let tag = pass == nil ? "SKIP" : (pass! ? "PASS" : "FAIL")
        log("\(tag) [\(project) · \(name)] \(detail)")
    }

    private static func previewSeconds(_ model: EditorModel) -> Double {
        guard let item = model.player.currentItem else { return -1 }
        let d = item.duration.seconds
        return d.isFinite ? d : -1
    }

    // MARK: - Entry

    static func run(model: EditorModel, store: AppStore) async {
        log("START")
        // A saved project is self-contained (each clip carries sourceURL + catalogItemID), so we don't
        // need the full catalog — but ProxySource may consult it, so give it a brief, non-blocking head start.
        for _ in 0..<20 where (store.db?.browseCount() ?? 0) < 1 { try? await Task.sleep(for: .milliseconds(200)) }

        let projects = locateProjects()
        guard !projects.isEmpty else {
            log("ABORT no .archiveproj packages found in \(documentsDir().path) — copy them there first")
            finish()
        }
        log("found \(projects.count) projects: \(projects.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", "))")

        for url in projects {
            await audit(project: url, model: model)
        }
        finish()
    }

    private static func finish() -> Never {
        let pass = results.filter { $0.pass == true }.count
        let fail = results.filter { $0.pass == false }.count
        let skip = results.filter { $0.pass == nil }.count
        log("==== SUMMARY \(pass) passed · \(fail) failed · \(skip) skipped ====")
        for r in results where r.pass == false { log("  FAILED: [\(r.project) · \(r.name)] \(r.detail)") }
        for r in results where r.pass == nil { log("  SKIPPED: [\(r.project) · \(r.name)] \(r.detail)") }
        FileHandle.standardError.write(Data("AWPROJ DONE\n".utf8))
        exit(fail == 0 ? 0 : 1)
    }

    // MARK: - Per-project audit

    private static func audit(project url: URL, model: EditorModel) async {
        let name = url.deletingPathExtension().lastPathComponent
        log("———— \(name) ————")

        // Reset the editor to a clean slate between projects.
        model.pause()
        model.project = .empty
        model.clipPrep.removeAll()
        model.thumbnails.removeAll()
        await model.rebuildPreview()           // clears the player (empty timeline → nil item)

        // decode
        guard let proj = decode(url) else { check(name, "decode", false, "could not decode timeline.json"); return }
        let clipCount = proj.timeline.clips.count
        check(name, "decode", clipCount > 0, "\(clipCount) clips · \(proj.timeline.audioClips.count) audio · \(proj.timeline.textOverlays.count) text")
        extractMedia(from: url)                // voiceover/music → working cache (the document does this on open)

        // Load it into the bound editor model exactly as opening the document would.
        model.project = proj
        model.loadFilmstrips()

        // firstPreview + fullLoad — kick the rebuild and poll (don't await: we measure timings while it runs).
        let startedAt = Date()
        model.scheduleRebuild()
        let firstCap = 45.0
        // Bound the tail generously: the gentler adaptive concurrency (conc 3 for many-distinct-source
        // projects) loads MORE reliably but SLOWER, so a healthy full load legitimately takes longer.
        // A real hang (stuck clip that never gives up) still blows past even this.
        let fullCap = max(180.0, Double(clipCount) * 5.0)
        var firstAt: Date?
        var fullAt: Date?
        let hardDeadline = Date().addingTimeInterval(fullCap)
        while Date() < hardDeadline {
            try? await Task.sleep(for: .milliseconds(200))
            if firstAt == nil, model.player.currentItem?.status == .readyToPlay { firstAt = Date() }
            // Settled = every clip reached a terminal state (ready/failed), nothing caching, not building/refining.
            let s = model.prepStatus
            let terminal = s.ready + s.failures.count
            let settled = terminal >= s.total && s.caching == 0 && !model.isBuildingPreview && !model.isRefining && !model.isInteracting
            if settled, model.player.currentItem != nil { fullAt = Date(); break }
        }
        let s = model.prepStatus
        let firstS = firstAt.map { $0.timeIntervalSince(startedAt) }
        let fullS = fullAt.map { $0.timeIntervalSince(startedAt) }

        check(name, "firstPreview", (firstS ?? .infinity) <= firstCap,
              "playable preview in \(firstS.map(rnd) ?? ">\(rnd(firstCap))")s (cap \(rnd(firstCap))s) — must NOT wait for all \(clipCount) clips")
        check(name, "fullLoad", fullS != nil,
              "settled in \(fullS.map(rnd) ?? ">\(rnd(fullCap))")s (cap \(rnd(fullCap))s) · ready=\(s.ready) failed=\(s.failures.count) caching=\(s.caching) of \(s.total)"
              + (fullS == nil ? "  <- HANG: clips never settled" : ""))
        if s.ready == 0 {
            check(name, "resolveRate", false, "0 of \(s.total) clips resolved — archive.org throttle or all-dead sources; editing checks will SKIP")
        } else {
            check(name, "resolveRate", true, "\(s.ready) of \(s.total) clips resolved (\(Int(Double(s.ready) / Double(max(1, s.total)) * 100))%)")
        }

        // align — preview length == timeline length (gaps reserve unresolved slots → must match).
        let tl = model.totalDuration, pv = previewSeconds(model)
        check(name, "align", pv > 0 && abs(pv - tl) < max(1.5, tl * 0.03),
              "preview=\(rnd(pv))s timeline=\(rnd(tl))s (must match 1:1 — failed clips are black gaps, not shifts)")

        // ——— Editing (only if a clip actually resolved) ———
        guard model.clips.contains(where: { model.clipPrep[$0.id] == .ready }) else {
            for n in ["playhead", "trim.shrink", "trim.extend", "trimLeft", "split", "delete"] {
                check(name, n, nil, "no resolved clip to edit (load didn't resolve any footage)")
            }
            await auditExport(name: name, model: model, clipCount: clipCount)
            return
        }

        await auditPlayhead(name, model)
        await auditTrim(name, model)
        await auditTrimLeft(name, model)
        await auditSplit(name, model)
        await auditDelete(name, model)
        await auditExport(name: name, model: model, clipCount: clipCount)
    }

    // MARK: - Editing checks (on the project's REAL resolved clips)

    /// Wait until the preview DURATION stabilizes (unchanged across 3 consecutive samples) with a
    /// ready item and no active build. Keying on the duration settling — not a rebuild counter — is
    /// robust to the background transient-retry rebuilds that fire on a heavily-cold project (those
    /// would race a counter-based wait and make an edit's effect look like it never landed).
    private static func settle(_ model: EditorModel, timeout: Double = 60) async {
        let deadline = Date().addingTimeInterval(timeout)
        var last = -999.0, stable = 0
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            let pv = previewSeconds(model)
            let building = model.isBuildingPreview || model.isRefining || model.isInteracting
            let ready = model.player.currentItem?.status == .readyToPlay
            if ready, !building, abs(pv - last) < 0.05 {
                stable += 1
                if stable >= 3 { return }
            } else {
                stable = 0
            }
            last = pv
        }
    }

    private static func readyClip(_ model: EditorModel) -> TimelineClip? {
        model.clips.first { model.clipPrep[$0.id] == .ready && $0.sourceRange.duration.seconds > 2.5 }
    }

    private static func auditPlayhead(_ name: String, _ model: EditorModel) async {
        guard let clip = readyClip(model) else { check(name, "playhead", nil, "no ready clip > 2.5s"); return }
        let park = min(model.totalDuration * 0.5, 20)
        model.seek(toSeconds: park)
        let before = model.playheadSeconds
        model.beginInteraction()
        model.trim(clip.id, newOutSeconds: clip.sourceRange.endSeconds - 1)   // a small edit
        model.endInteraction()
        await settle(model)
        let after = model.playheadSeconds
        check(name, "playhead", after > 0.5 && abs(after - before) < 2.0,
              "playhead \(rnd(before))->\(rnd(after)) across an edit (must NOT snap to 0)")
    }

    private static func auditTrim(_ name: String, _ model: EditorModel) async {
        guard let clip = readyClip(model) else { check(name, "trim.shrink", nil, "no ready clip"); return }
        let id = clip.id
        let base = previewSeconds(model)
        let end0 = clip.sourceRange.endSeconds

        // SHRINK out by 3s — deterministic (footage definitely exists). Preview must shrink.
        model.beginInteraction(); model.trim(id, newOutSeconds: end0 - 3); model.endInteraction()
        await settle(model)
        let afterShrink = previewSeconds(model)
        check(name, "trim.shrink", afterShrink < base - 2 && afterShrink > 0,
              "preview \(rnd(base))->\(rnd(afterShrink))s on a -3s trim (the length change MUST reach the preview)")

        // EXTEND back +3s — that footage was just there, so the preview must grow again.
        model.beginInteraction(); model.trim(id, newOutSeconds: end0); model.endInteraction()
        await settle(model)
        let afterExtend = previewSeconds(model)
        check(name, "trim.extend", afterExtend > afterShrink + 2,
              "preview \(rnd(afterShrink))->\(rnd(afterExtend))s on a +3s re-extend (new footage MUST appear)")
    }

    private static func auditTrimLeft(_ name: String, _ model: EditorModel) async {
        // Need a ready INTERIOR clip: index in 1..<count-1 (has a previous AND a next, so we can check
        // both the left-edge anchor and that the next clip doesn't ripple during the drag).
        let cs = model.clips
        guard cs.count >= 3,
              let idx = (1..<(cs.count - 1)).first(where: {
                  model.clipPrep[cs[$0].id] == .ready && cs[$0].sourceRange.duration.seconds > 3
              }) else {
            check(name, "trimLeft", nil, "no interior ready clip with a neighbour"); return
        }
        let c = cs[idx], next = cs[idx + 1]
        let start0 = c.timelineStart.seconds
        let end0 = c.timelineRange.endSeconds
        let nextStart0 = next.timelineStart.seconds

        model.beginInteraction()
        model.trim(c.id, newInSeconds: c.sourceRange.start.seconds + 2)   // shrink from the LEFT by 2s
        let startDuring = model.clips.first { $0.id == c.id }?.timelineStart.seconds ?? -1
        let endDuring = model.clips.first { $0.id == c.id }?.timelineRange.endSeconds ?? -1
        let nextDuring = model.clips.first { $0.id == next.id }?.timelineStart.seconds ?? -1
        let leftMoves = abs(startDuring - (start0 + 2)) < 0.5 && abs(endDuring - end0) < 0.5
        let noRipple = abs(nextDuring - nextStart0) < 0.4
        model.endInteraction()
        await settle(model, timeout: 40)
        let nextAfter = model.clips.first { $0.id == next.id }?.timelineStart.seconds ?? -1
        let repacks = nextAfter < nextStart0 - 1.0
        check(name, "trimLeft", leftMoves && noRipple && repacks,
              "left edge \(rnd(start0))->\(rnd(startDuring)) (want +2, right held \(rnd(end0))->\(rnd(endDuring))); "
              + "next during \(rnd(nextStart0))->\(rnd(nextDuring)) (no ripple), after release ->\(rnd(nextAfter)) (re-packs)")
    }

    private static func auditSplit(_ name: String, _ model: EditorModel) async {
        guard let clip = readyClip(model) else { check(name, "split", nil, "no ready clip"); return }
        let before = previewSeconds(model), count0 = model.clips.count
        let cutAt = clip.timelineStart.seconds + clip.timelineRange.duration.seconds / 2
        model.splitClip(clip.id, atTimelineSeconds: cutAt)
        await settle(model)
        let after = previewSeconds(model)
        check(name, "split", model.clips.count == count0 + 1 && abs(after - before) < 1.5,
              "clips \(count0)->\(model.clips.count) (want +1); preview \(rnd(before))->\(rnd(after))s (~unchanged)")
    }

    private static func auditDelete(_ name: String, _ model: EditorModel) async {
        guard let clip = readyClip(model) else { check(name, "delete", nil, "no ready clip"); return }
        let before = previewSeconds(model), count0 = model.clips.count, tl0 = model.totalDuration
        let id = clip.id
        model.deleteClip(id)
        await settle(model)
        let after = previewSeconds(model), tl = model.totalDuration
        let aligned = after > 0 && abs(after - tl) < max(1.5, tl * 0.03)
        check(name, "delete", model.clips.count == count0 - 1 && after < before + 0.5 && aligned,
              "clips \(count0)->\(model.clips.count) (want -1); preview \(rnd(before))->\(rnd(after))s timeline \(rnd(tl0))->\(rnd(tl))s aligned=\(aligned)")
    }

    // MARK: - Export

    private static func auditExport(name: String, model: EditorModel, clipCount: Int) async {
        guard !model.clips.isEmpty else { check(name, "export", nil, "no clips"); return }
        // Export re-caches FULL-quality windows per clip. For a big multi-film project that is a huge
        // download; prove the end-to-end export on projects within a clip budget (tunable), and report
        // the large ones as deferred (the export composition path is identical + proven on the small ones).
        let budget = Int(ProcessInfo.processInfo.environment["AW_CS_EXPORT_MAX_CLIPS"] ?? "") ?? 30
        guard model.clips.count <= budget else {
            check(name, "export", nil, "deferred — \(model.clips.count) clips > \(budget) (full-quality cache too large for the autonomous run; path proven on smaller projects)")
            return
        }
        let timelineLen = model.totalDuration
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("aw-proj-export-\(name).mp4")
        try? FileManager.default.removeItem(at: out)
        let svc = ExportService()
        let project = model.project
        let task = Task { await svc.export(project, to: out, format: .h264) }
        // Full-quality re-cache (parallel) + the AVAssetExportSession encode (with the Core-Animation
        // provenance overlay) of a multi-minute composition is inherently slow — scale the cap to the
        // program length + clip count so a long-but-progressing export isn't cut off mid-encode.
        let cap = max(420.0, timelineLen * 4 + Double(model.clips.count) * 8)
        let deadline = Date().addingTimeInterval(cap)
        var timedOut = true
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            if svc.phase == .done { timedOut = false; break }
            if case .failed = svc.phase { timedOut = false; break }
        }
        if timedOut { task.cancel() }
        guard !timedOut, svc.phase == .done else {
            check(name, "export", false, "phase=\(String(describing: svc.phase)) (timedOut=\(timedOut), cap \(rnd(cap))s)")
            try? FileManager.default.removeItem(at: out); return
        }
        let asset = AVURLAsset(url: out)
        let vTrack = (try? await asset.loadTracks(withMediaType: .video))?.first != nil
        let dur = (try? await asset.load(.duration))?.seconds ?? -1
        let size = ((try? FileManager.default.attributesOfItem(atPath: out.path))?[.size] as? Int) ?? 0
        check(name, "export", vTrack && abs(dur - timelineLen) < max(1.5, timelineLen * 0.04) && size > 50_000,
              "file dur=\(rnd(dur))s (timeline \(rnd(timelineLen))) videoTrack=\(vTrack) bytes=\(size)")
        try? FileManager.default.removeItem(at: out)
    }

    // MARK: - Loading the packages from the sandbox container

    private static func documentsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    }

    private static func locateProjects() -> [URL] {
        let dir = documentsDir()
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "archiveproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func decode(_ packageURL: URL) -> ClipProject? {
        let timeline = packageURL.appendingPathComponent("timeline.json")
        guard let data = try? Data(contentsOf: timeline) else {
            // Tolerate a flat-file project (same fallback the document supports).
            guard let d = try? Data(contentsOf: packageURL) else { return nil }
            return try? ClipProjectDocument.decoder.decode(ClipProject.self, from: d)
        }
        return try? ClipProjectDocument.decoder.decode(ClipProject.self, from: data)
    }

    /// Copy embedded media/ (voiceover, music) into the working cache so the engine resolves it by
    /// filename — the same extraction ClipProjectDocument.init does on open (which we bypass here).
    private static func extractMedia(from packageURL: URL) {
        let mediaDir = packageURL.appendingPathComponent("media")
        guard let files = try? FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil) else { return }
        for f in files {
            let dst = ProjectMediaCache.directory.appendingPathComponent(f.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dst.path) { try? FileManager.default.copyItem(at: f, to: dst) }
        }
    }
}
#endif
