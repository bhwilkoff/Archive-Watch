#if os(macOS)
import Foundation
import AVFoundation
import CoreImage

// Env-gated end-to-end validation of the Creation Studio engine (de-risk spike #3,
// docs/macOS-DESIGN.md §9.3 / Rule 4b) — the macOS analogue of the project's
// AW_PLAYBACK_DIAG diagnostics. Set AW_CS_SELFTEST=1 to run, on launch, the full
// cache-then-export pipeline on TWO real archive.org titles and print the result. No-op
// otherwise. Output goes to Library/Caches so it needs no user-selected file scope.
@MainActor
enum CreationStudioSelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_CS_SELFTEST"] == "1" }
    private static var started = false   // one-shot: RootView and the editor both try to kick it

    /// A short silent .m4a in the project cache, for verifying the music-bed mix path.
    static func makeSilentAudio() -> URL? {
        let url = ProjectMediaCache.directory.appendingPathComponent("test-music.m4a")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                        AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100 * 3) else { return nil }
        buf.frameLength = 44100 * 3                    // 3s of silence
        try? file.write(from: buf)
        return url
    }

    /// Average luma (0…1) of the exported video frame at `seconds` — used to prove the opacity
    /// fade ramps actually render (black at the fade extremes, bright in the middle).
    static func avgBrightness(_ url: URL, at seconds: Double) async -> Double? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        guard let cg = try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        else { return nil }
        let ci = CIImage(cgImage: cg)
        let avg = ci.applyingFilter("CIAreaAverage",
                                    parameters: [kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(avg, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
        return (Double(px[0]) + Double(px[1]) + Double(px[2])) / 3.0 / 255.0
    }

    /// Average (R,G,B) (each 0…1) of the exported frame at `seconds` — used to prove a color Look
    /// landed (e.g. sepia → R clearly above B).
    static func avgRGB(_ url: URL, at seconds: Double) async -> (Double, Double, Double)? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        guard let cg = try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        else { return nil }
        let ci = CIImage(cgImage: cg)
        let avg = ci.applyingFilter("CIAreaAverage",
                                    parameters: [kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(avg, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
        return (Double(px[0]) / 255.0, Double(px[1]) / 255.0, Double(px[2]) / 255.0)
    }

    static func run(store: AppStore) async {
        guard !started else { return }
        started = true
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
        // Prefer commercials — short AND they always have audio (so the #4 mute test is
        // meaningful; the catalog is otherwise heavy on silent-era films).
        guard let a = store.randomPlayable(contentType: "commercial") ?? store.randomPlayable(),
              let aURL = a.videoURLParsed else {
            log("FAIL — no playable catalog item after \(tries)s"); return
        }
        let b = store.randomPlayable(contentType: "commercial") ?? store.randomPlayable() ?? a
        let bURL = b.videoURLParsed ?? aURL

        // PREVIEW PIPELINE CHECK (cache-first): a real EditorModel builds a 2-clip preview from
        // LOCAL cached windows; its AVPlayerItem must reach .readyToPlay (1) with the full
        // 2-clip duration — proving the timeline preview shows video and plays through, not black.
        let editDoc = ClipProjectDocument()
        let editor = EditorModel(document: editDoc)
        editor.addClip(catalogItemID: a.archiveID, sourceURL: aURL, title: a.title)
        editor.addClip(catalogItemID: b.archiveID, sourceURL: bURL, title: b.title)
        let cacheT0 = Date()
        await editor.rebuildPreview()                      // cold cache of both generous windows
        let coldMs = Int(Date().timeIntervalSince(cacheT0) * 1000)
        var pst = 0
        for _ in 0..<80 {
            pst = editor.player.currentItem?.status.rawValue ?? -1
            if pst != 0 { break }                  // 0 unknown · 1 ready · 2 failed
            try? await Task.sleep(for: .milliseconds(500))
        }
        let pdur = editor.player.currentItem?.duration.seconds ?? 0
        let prep = editor.clipPrep.values.map { "\($0)" }.sorted().joined(separator: ",")
        log("PREVIEW itemStatus=\(pst) duration=\(String(format: "%.1f", pdur))s clips=\(editor.clips.count) coldCacheMs=\(coldMs) prep=[\(prep)]")

        // FILMSTRIP CHECK: a clip's timeline filmstrip should come from archive.org thumbnails
        // (instant) — counts > 0 well before / independent of the slow window cache.
        try? await Task.sleep(for: .seconds(4))
        let fcounts = editor.clips.map { editor.thumbnails[$0.id]?.count ?? 0 }
        log("FILMSTRIP archive-thumbnail frames per clip = \(fcounts)")

        // REUSE-ON-TRIM CHECK: nudge clip 0's in-point +1.5s (inside the ±12s handle) and rebuild.
        // It must REUSE the cached generous window (rebuild in well under a second), NOT re-cache.
        if let c0 = editor.clips.first {
            editor.trim(c0.id, newInSeconds: c0.sourceRange.start.seconds + 1.5)
            let trimT0 = Date()
            await editor.rebuildPreview()
            let trimMs = Int(Date().timeIntervalSince(trimT0) * 1000)
            log("TRIM-REUSE rebuild=\(trimMs)ms (reused cache if « coldCacheMs) status=\(editor.player.currentItem?.status.rawValue ?? -1)")
        }

        // REORDER + TEXT model checks (drag-reorder, context split, Add Text).
        let order0 = editor.clips.map { String($0.label.prefix(5)) }.joined(separator: "|")
        if editor.clips.count >= 2 { editor.moveClip(editor.clips[0].id, toIndex: 1) }
        let order1 = editor.clips.map { String($0.label.prefix(5)) }.joined(separator: "|")
        editor.playheadSeconds = 1
        editor.addTextOverlay()
        log("REORDER [\(order0)] -> [\(order1)] · textOverlays=\(editor.textOverlays.count) selectedOverlay=\(editor.selectedOverlayID != nil)")

        // A 2-clip cross-title timeline: an 8s window from each title, back to back.
        var timeline = Timeline()
        timeline.clips = [
            // Fade up from black over the first 1.5s; SILENT (sepia) color grade.
            TimelineClip(catalogItemID: a.archiveID, sourceURL: aURL,
                         sourceRange: TimeRange(startSeconds: 3, durationSeconds: 8),
                         timelineStart: .zero, track: 0, label: a.title, audioVolume: 1.0,
                         fadeInSeconds: 1.5, lookRaw: "silent"),
            // #4: clip B is MUTED. 2s cross-DISSOLVE from clip A; fade to black over the last 1.5s.
            // Total timeline = 8 + 8 - 2 = 14s.
            TimelineClip(catalogItemID: b.archiveID, sourceURL: bURL,
                         sourceRange: TimeRange(startSeconds: 3, durationSeconds: 8),
                         timelineStart: TimeStamp(seconds: 8), track: 0, label: b.title, audioVolume: 0.0,
                         fadeOutSeconds: 1.5, transitionInSeconds: 2.0),
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
                log("DONE[\(variant)] in \(dt)s — \(out.lastPathComponent) (\(size / 1024) KB)")
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

        // FADES (video opacity ramps): verify the CLEAN export (no credit confound) fades up
        // from black at the start and down to black at the end — brightness near-zero at the
        // fade extremes, bright in the middle.
        let cleanOut = ProjectMediaCache.directory.appendingPathComponent("selftest-clean.mp4")
        if FileManager.default.fileExists(atPath: cleanOut.path) {
            // CROSS-DISSOLVE: total timeline should be 14s (8+8 minus the 2s overlap), not 16.
            let dur = (try? await AVURLAsset(url: cleanOut).load(.duration).seconds) ?? -1
            log(String(format: "DISSOLVE duration=%.1fs (expected ~14.0 = 16 − 2s overlap)", dur))
            // FADES: black at the fade-in head and the fade-out tail, bright in the middle.
            let b0 = await Self.avgBrightness(cleanOut, at: 0.05)     // fade-in start ≈ black
            let bMid = await Self.avgBrightness(cleanOut, at: 3.0)    // clip A full ≈ bright
            let bEnd = await Self.avgBrightness(cleanOut, at: 13.95)  // fade-out end ≈ black
            log(String(format: "FADES brightness t=0:%.3f t=3:%.3f t=14:%.3f (fade ok if ends « mid)",
                       b0 ?? -1, bMid ?? -1, bEnd ?? -1))
            // DISSOLVE blend: mid-overlap (t≈7) both clips contribute → non-black.
            let bBlend = await Self.avgBrightness(cleanOut, at: 7.0)
            log(String(format: "DISSOLVE blend t=7:%.3f (should be > 0, both clips visible)", bBlend ?? -1))
            // LOOK (silent/sepia on clip A): at t=3 the red channel should clearly exceed blue.
            if let rgb = await Self.avgRGB(cleanOut, at: 3.0) {
                log(String(format: "LOOK silent/sepia t=3 R=%.3f G=%.3f B=%.3f (sepia if R > B)",
                           rgb.0, rgb.1, rgb.2))
            }
        }

        // MUSIC BED (#4): build the composition with an imported music track and confirm it adds
        // a third audio track (2 clips on A/B + 1 music) and a mix input for it.
        if let musicURL = Self.makeSilentAudio() {
            var resolved: [CompositionBuilder.ResolvedClip] = []
            for clip in timeline.clips {
                guard let url = try? await ClipCacheService.cachedURL(for: clip) else { continue }   // warm from the export
                let asset = AVURLAsset(url: url)
                let dur = (try? await asset.load(.duration)) ?? CMTime(seconds: 5, preferredTimescale: 600)
                resolved.append(.init(asset: asset, insertRange: CMTimeRange(start: .zero, duration: dur)))
            }
            let music = CompositionBuilder.ResolvedMusic(asset: AVURLAsset(url: musicURL), volume: 0.5, startSeconds: 0)
            if let built = try? await CompositionBuilder.build(resolved: resolved, timeline: timeline,
                                                               creditLine: nil, bakeOverlays: false, music: music) {
                let aTracks = built.composition.tracks(withMediaType: .audio).count
                let mixParams = (built.audioMix as? AVMutableAudioMix)?.inputParameters.count ?? 0
                log("MUSIC audio tracks=\(aTracks) (expect 3: clipsA/B + music)  mixParams=\(mixParams)")
            }
        }

        // #5: a ProRes .mov export (reuses the warm cache) to confirm the format path.
        let proURL = ProjectMediaCache.directory.appendingPathComponent("selftest-prores.mov")
        let proExporter = ExportService()
        await proExporter.export(ClipProject(title: "SelfTest", timeline: timeline, burnAttribution: false),
                                 to: proURL, format: .proRes422)
        if case .done = proExporter.phase { log("DONE[prores] — \(proURL.lastPathComponent)") }
        else if case .failed(let m) = proExporter.phase { log("FAIL[prores] — \(m)") }
    }
}
#endif
