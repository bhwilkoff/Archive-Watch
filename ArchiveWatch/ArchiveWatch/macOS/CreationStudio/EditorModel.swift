#if os(macOS)
import Foundation
import AVFoundation
import Observation
import CoreImage
import ImageIO

// The editor's live state + edit operations (docs/macOS-DESIGN.md §3, §7). Owns the
// rebuild-and-swap preview (Rule 3b), the playhead, selection, zoom, filmstrip thumbnails,
// and the magnetic single-track edit model (Phase 1 — Rule 7c CapCut-approachable). The
// AppKit timeline (TimelineView_macOS) reads/writes through this; the SwiftUI editor binds
// to its @Observable properties. Mutations write through to `document.project` so SwiftUI
// autosaves the .archiveproj.
@MainActor
@Observable
final class EditorModel {
    private let document: ClipProjectDocument

    let player = AVPlayer()
    var playheadSeconds: Double = 0
    var isPlaying = false
    var selectedClipID: UUID?
    /// Timeline zoom — points per second. Clamped; ⌘-scroll / pinch drive it.
    var pointsPerSecond: Double = 60
    var thumbnails: [UUID: [CGImage]] = [:]
    var isBuildingPreview = false
    /// Per-clip media-prep state for the timeline UI: caching the local window / ready / failed.
    var clipPrep: [UUID: ClipPrep] = [:]
    enum ClipPrep: Equatable { case caching, ready, failed }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let thumbGen = ThumbnailGenerator()

    /// A locally-cached GENEROUS source window (clip ± handles). Trimming within
    /// [sourceStart, sourceEnd] reuses this file — only the composition's insert range
    /// changes, so no re-cache and no "Preparing clips" per trim.
    struct CachedWindow { let url: URL; let sourceStart: Double; let sourceEnd: Double }
    @ObservationIgnored private var clipCache: [UUID: CachedWindow] = [:]
    /// Extra source footage cached on each side of a clip so small trims are free.
    static let cacheHandle = 12.0

    // archive.org's per-~60s thumbnail strip (ArchiveThumbnails) is the timeline filmstrip
    // source: it's tiny + already-served, so a clip shows frames INSTANTLY without waiting for
    // the (slow) window cache + AVAssetImageGenerator. Cached per item + per image so trimming
    // re-derives the strip with no new network.
    @ObservationIgnored private var archiveStrips: [String: [ArchiveThumb]] = [:]
    @ObservationIgnored private var thumbImageCache: [URL: CGImage] = [:]

    static let minPPS = 6.0, maxPPS = 600.0

    init(document: ClipProjectDocument) {
        self.document = document
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, t.isNumeric else { return }
                self.playheadSeconds = t.seconds
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    var project: ClipProject { document.project }
    var clips: [TimelineClip] { document.project.timeline.clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds } }
    var totalDuration: Double { document.project.timeline.durationSeconds }

    // MARK: - Edits (magnetic single track → relayout after every change)

    func addClip(catalogItemID: String, sourceURL: URL, title: String,
                 inSeconds: Double = 3, durationSeconds: Double = 8) {
        let clip = TimelineClip(
            catalogItemID: catalogItemID, sourceURL: sourceURL,
            sourceRange: TimeRange(startSeconds: inSeconds, durationSeconds: durationSeconds),
            timelineStart: .zero, track: 0, label: title)
        document.project.timeline.clips.append(clip)
        relayout()
        selectedClipID = clip.id
        loadFilmstrip(for: clip)   // instant archive.org-thumbnail filmstrip (no wait on the cache)
        scheduleRebuild()          // window caching for preview/export happens in the rebuild
    }

    var selectedClip: TimelineClip? { clips.first { $0.id == selectedClipID } }

    /// Set a clip's audio volume in the mix (#4).
    func setClipVolume(_ id: UUID, _ vol: Double) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        document.project.timeline.clips[i].audioVolume = max(0, min(1.5, vol))
        scheduleRebuild()
    }

    /// Add a clip from a saved proxy (dragged from the Library, or just-marked).
    func addClip(from proxy: ProxyClip) {
        let clip = TimelineClip.from(proxy, at: .zero)
        document.project.timeline.clips.append(clip)
        relayout()
        selectedClipID = clip.id
        loadFilmstrip(for: clip)
        scheduleRebuild()
    }

    func deleteClip(_ id: UUID) {
        document.project.timeline.clips.removeAll { $0.id == id }
        thumbnails[id] = nil; clipCache[id] = nil
        if selectedClipID == id { selectedClipID = nil }
        relayout(); scheduleRebuild()
    }

    /// Re-attempt caching a clip whose window failed to load (transient archive.org failure).
    func retryClip(_ id: UUID) {
        clipPrep[id] = nil
        thumbnails[id] = nil
        clipCache[id] = nil          // force a fresh cache attempt
        scheduleRebuild()
    }

    /// Set a clip's in/out (frame-exact handle drag). `newIn`/`newOut` are SOURCE seconds.
    func trim(_ id: UUID, newInSeconds: Double? = nil, newOutSeconds: Double? = nil) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = document.project.timeline.clips[i]
        var inS = clip.sourceRange.start.seconds
        var outS = clip.sourceRange.endSeconds
        if let newInSeconds { inS = min(max(0, newInSeconds), outS - 0.1) }
        if let newOutSeconds { outS = max(newOutSeconds, inS + 0.1) }
        clip.sourceRange = TimeRange(startSeconds: inS, durationSeconds: outS - inS)
        document.project.timeline.clips[i] = clip
        // Refresh the filmstrip for the new sub-range from cached thumbnails (instant, no flash);
        // the cached generous window is reused (no re-cache) while the trim stays inside it.
        loadFilmstrip(for: clip)
        relayout(); scheduleRebuild()
    }

    /// Split the clip under the playhead into two at the current position (⌘B).
    func splitAtPlayhead() {
        let t = playheadSeconds
        guard let clip = clips.first(where: { c in
            let s = c.timelineStart.seconds
            return t > s + 0.05 && t < s + c.sourceRange.duration.seconds - 0.05
        }) else { return }
        splitClip(clip.id, atTimelineSeconds: t)
    }

    /// Split a specific clip into two at a timeline position (context-menu "Split Here").
    func splitClip(_ id: UUID, atTimelineSeconds t: Double) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = document.project.timeline.clips[i]
        let offsetInClip = t - clip.timelineStart.seconds                   // seconds into the clip
        guard offsetInClip > 0.05, offsetInClip < clip.sourceRange.duration.seconds - 0.05 else { return }
        let cutSource = clip.sourceRange.start.seconds + offsetInClip
        var left = clip
        left.sourceRange = TimeRange(startSeconds: clip.sourceRange.start.seconds, durationSeconds: offsetInClip)
        let right = TimelineClip(
            proxyClipID: clip.proxyClipID, catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
            sourceRange: TimeRange(startSeconds: cutSource, durationSeconds: clip.sourceRange.endSeconds - cutSource),
            timelineStart: .zero, track: 0, label: clip.label)
        document.project.timeline.clips[i] = left
        document.project.timeline.clips.insert(right, at: i + 1)
        // Both halves come from the same source — share the cached generous window so neither
        // re-caches; just refresh each half's filmstrip for its new sub-range.
        if let w = clipCache[clip.id] { clipCache[right.id] = w }
        loadFilmstrip(for: left); loadFilmstrip(for: right)
        selectedClipID = right.id
        relayout(); scheduleRebuild()
    }

    /// Reorder a clip on the magnetic track by dragging (toIndex = desired slot).
    func moveClip(_ id: UUID, toIndex target: Int) {
        let original = document.project.timeline.clips
        guard let from = original.firstIndex(where: { $0.id == id }) else { return }
        var arr = original
        let clip = arr.remove(at: from)
        arr.insert(clip, at: min(max(0, target), arr.count))
        guard arr.map(\.id) != original.map(\.id) else { return }          // no order change
        document.project.timeline.clips = arr
        relayout(); scheduleRebuild()
    }

    /// Duplicate a clip immediately after itself (context menu).
    func duplicateClip(_ id: UUID) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let src = document.project.timeline.clips[i]
        let copy = TimelineClip(
            proxyClipID: src.proxyClipID, catalogItemID: src.catalogItemID, sourceURL: src.sourceURL,
            sourceRange: src.sourceRange, timelineStart: .zero, track: 0, label: src.label, audioVolume: src.audioVolume)
        document.project.timeline.clips.insert(copy, at: i + 1)
        if let w = clipCache[id] { clipCache[copy.id] = w }                 // same source window
        loadFilmstrip(for: copy)
        selectedClipID = copy.id
        relayout(); scheduleRebuild()
    }

    // MARK: - Text overlays (#3)

    var selectedOverlayID: UUID?
    var textOverlays: [TextOverlay] { document.project.timeline.textOverlays }

    func addTextOverlay() {
        let start = playheadSeconds
        let avail = max(0, totalDuration - start)
        let ov = TextOverlay(text: "Title",
                             timelineRange: TimeRange(startSeconds: start,
                                                      durationSeconds: avail > 1 ? min(3, avail) : 3))
        document.project.timeline.textOverlays.append(ov)
        selectedOverlayID = ov.id
        selectedClipID = nil
        // No preview rebuild: overlays aren't baked into the preview composition (the Core
        // Animation tool is export-only) — the live SwiftUI overlay shows them; export reads
        // them at export time. Skipping the rebuild keeps text editing/dragging instant.
    }

    func updateOverlay(_ ov: TextOverlay) {
        guard let i = document.project.timeline.textOverlays.firstIndex(where: { $0.id == ov.id }) else { return }
        document.project.timeline.textOverlays[i] = ov
    }

    func deleteOverlay(_ id: UUID) {
        document.project.timeline.textOverlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
    }

    /// Magnetic main track: clips lie end-to-end in ARRAY order, no gaps (Rule 7c). Array order
    /// IS the timeline order — reorder/insert in the array, then relayout assigns each clip's
    /// start. (Was sorting by timelineStart, which made a just-added clip at t=0 jump ahead and
    /// blocked drag-reordering.)
    private func relayout() {
        var cursor = 0.0
        var rebuilt: [TimelineClip] = []
        for var c in document.project.timeline.clips {
            c.timelineStart = TimeStamp(seconds: cursor)
            rebuilt.append(c)
            cursor += c.sourceRange.duration.seconds
        }
        document.project.timeline.clips = rebuilt
    }

    // MARK: - Preview (rebuild-and-swap, debounced)

    func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await self?.rebuildPreview()
        }
    }

    /// Rebuild the preview from LOCALLY-CACHED clip windows — never N concurrent remote streams
    /// (the Rule 4b reliability win). Each clip's in/out window is cached to a small local MP4
    /// once (reused across rebuilds AND shared with export), so the preview is fast, plays
    /// through every clip, and is frame-identical to the export.
    func rebuildPreview() async {
        let timelineClips = clips
        guard !timelineClips.isEmpty else {
            player.replaceCurrentItem(with: nil); return
        }
        // Show "Preparing clips…" only if the rebuild is actually slow (a cold cache). A rebuild
        // that reuses already-cached windows is near-instant and must not flash the overlay.
        let overlay = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { self?.isBuildingPreview = true }
        }
        defer { overlay.cancel(); isBuildingPreview = false }

        var resolved: [CompositionBuilder.ResolvedClip] = []
        for clip in timelineClips {
            do {
                let r = try await resolveLocal(clip)
                if Task.isCancelled { return }
                resolved.append(r)
            } catch {
                clipPrep[clip.id] = .failed                                 // skip a clip that won't cache
            }
        }
        guard !resolved.isEmpty, !Task.isCancelled else { return }

        // bakeOverlays:false — the Core Animation overlay tool is offline-only (crashes
        // AVPlayerItem). Same clip/reframe/audio recipe as export, so the preview frame matches.
        let credit = document.project.burnAttribution ? ExportService.defaultCredit : nil
        do {
            let built = try await CompositionBuilder.build(
                resolved: resolved, timeline: document.project.timeline,
                creditLine: credit, bakeOverlays: false)
            guard !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            player.replaceCurrentItem(with: item)
            seek(toSeconds: min(playheadSeconds, totalDuration))
        } catch {
            // Leave the previous preview in place on a transient build failure.
        }
    }

    /// Resolve a clip to a LOCAL asset + the insert range within it. Reuses a cached GENEROUS
    /// window whenever the trim falls inside it (instant — no re-cache); otherwise caches a new
    /// generous window (clip ± handles) so subsequent trims are free.
    private func resolveLocal(_ clip: TimelineClip) async throws -> CompositionBuilder.ResolvedClip {
        let inS = clip.sourceRange.start.seconds
        let outS = clip.sourceRange.endSeconds

        if let w = clipCache[clip.id], w.sourceStart <= inS + 0.05, w.sourceEnd + 0.05 >= outS,
           FileManager.default.fileExists(atPath: w.url.path) {
            clipPrep[clip.id] = .ready
            ensureThumbnails(clip, window: w)
            return makeResolved(clip, window: w)
        }

        if clipPrep[clip.id] != .ready { clipPrep[clip.id] = .caching }
        let cacheStart = max(0, inS - Self.cacheHandle)
        let cacheEnd = outS + Self.cacheHandle                     // clamped to source end by the cache service
        let url = try await CacheCoordinator.window(                // coalesces concurrent same-window caches
            catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
            startSeconds: cacheStart, endSeconds: cacheEnd)
        if Task.isCancelled { throw CancellationError() }
        let actualDur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? (cacheEnd - cacheStart)
        let window = CachedWindow(url: url, sourceStart: cacheStart, sourceEnd: cacheStart + actualDur)
        clipCache[clip.id] = window
        clipPrep[clip.id] = .ready
        ensureThumbnails(clip, window: window)   // fallback generator — no-op if loadFilmstrip set archive.org thumbnails
        return makeResolved(clip, window: window)
    }

    /// The clip's in/out expressed as an insert range INTO the cached window file (file t=0 is
    /// the window's source start), clamped to what the file actually holds.
    private func makeResolved(_ clip: TimelineClip, window: CachedWindow) -> CompositionBuilder.ResolvedClip {
        let inS = clip.sourceRange.start.seconds
        let startInFile = max(0, inS - window.sourceStart)
        let avail = max(0.05, window.sourceEnd - inS)
        let dur = min(clip.sourceRange.duration.seconds, avail)
        return .init(asset: AVURLAsset(url: window.url),
                     insertRange: CMTimeRange(start: CMTime(seconds: startInFile, preferredTimescale: 600),
                                              duration: CMTime(seconds: max(0.05, dur), preferredTimescale: 600)),
                     audioVolume: clip.audioVolume)
    }

    private func ensureThumbnails(_ clip: TimelineClip, window: CachedWindow) {
        guard thumbnails[clip.id] == nil else { return }
        let startInFile = max(0, clip.sourceRange.start.seconds - window.sourceStart)
        generateThumbnails(clip.id, url: window.url,
                           startSeconds: startInFile, durationSeconds: clip.sourceRange.duration.seconds)
    }

    // MARK: - Transport

    func togglePlay() { isPlaying ? pause() : play() }
    func play() { player.play(); isPlaying = true }
    func pause() { player.pause(); isPlaying = false }

    func seek(toSeconds s: Double) {
        let clamped = min(max(0, s), max(0, totalDuration))
        playheadSeconds = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func zoom(by factor: Double, focusSeconds: Double? = nil) {
        pointsPerSecond = min(Self.maxPPS, max(Self.minPPS, pointsPerSecond * factor))
    }

    // MARK: - Thumbnails (filmstrip)

    /// Generate the filmstrip for a clip's [start, start+duration] sub-range WITHIN the LOCAL
    /// cached window (fast + frame-accurate) — not the remote film.
    private func generateThumbnails(_ clipID: UUID, url: URL, startSeconds: Double, durationSeconds: Double) {
        Task { [weak self] in
            let imgs = await self?.thumbGen.thumbnails(
                url: url, startSeconds: startSeconds, durationSeconds: durationSeconds, count: 10) ?? []
            await MainActor.run { self?.thumbnails[clipID] = imgs }
        }
    }

    /// Set a clip's timeline filmstrip from archive.org's thumbnail strip — INSTANT (the images
    /// are a few KB, already served) and reused across clips/trims (strip + images cached), so a
    /// clip shows frames without waiting on the window cache. Leaves the filmstrip empty when the
    /// item has no thumbnails, so the cached-window generator (ensureThumbnails) fills in.
    /// Load archive.org-thumbnail filmstrips for EVERY current clip — called when the editor
    /// opens, so a SAVED project's clips get their instant filmstrips too (addClip only covers
    /// newly-added clips). No-op per clip once its thumbnails are set.
    func loadFilmstrips() { for c in clips where thumbnails[c.id] == nil { loadFilmstrip(for: c) } }

    private func loadFilmstrip(for clip: TimelineClip) {
        let id = clip.id, catID = clip.catalogItemID, url = clip.sourceURL
        let inS = clip.sourceRange.start.seconds, outS = clip.sourceRange.endSeconds
        Task { [weak self] in
            guard let self else { return }
            let strip: [ArchiveThumb]
            if let cached = self.archiveStrips[catID] { strip = cached }
            else { let s = await ArchiveThumbnails.strip(for: url); self.archiveStrips[catID] = s; strip = s }
            guard !strip.isEmpty else { return }
            var picks = strip.filter { $0.seconds >= inS - 1 && $0.seconds <= outS + 1 }
            if picks.isEmpty, let n = strip.min(by: { abs($0.seconds - inS) < abs($1.seconds - inS) }) { picks = [n] }
            if picks.count > 12 {                                  // cap a long clip's strip
                let step = Double(picks.count - 1) / 11
                picks = (0..<12).map { picks[min(picks.count - 1, Int((Double($0) * step).rounded()))] }
            }
            var imgs: [CGImage] = []
            for t in picks {
                if let c = self.thumbImageCache[t.url] { imgs.append(c) }
                else if let img = await Self.downloadThumb(t.url) { self.thumbImageCache[t.url] = img; imgs.append(img) }
            }
            if !imgs.isEmpty, !Task.isCancelled { self.thumbnails[id] = imgs }
        }
    }

    private nonisolated static func downloadThumb(_ url: URL) async -> CGImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // isolated deinit (SE-0371) so cleanup can touch the MainActor-isolated player/observer
    // natively under the Swift 6 language mode — no nonisolated(unsafe) escape hatch needed.
    isolated deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        rebuildTask?.cancel()
    }
}

// Off-main filmstrip thumbnails from a sub-range of a LOCAL cached window file (no remote stream).
actor ThumbnailGenerator {
    func thumbnails(url: URL, startSeconds: Double, durationSeconds: Double, count: Int) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)
        gen.requestedTimeToleranceBefore = .zero            // local file → exact is cheap + accurate
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let span = max(0.1, durationSeconds)
        let times = (0..<max(1, count)).map { i in
            CMTime(seconds: startSeconds + span * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var out: [CGImage] = []
        for t in times { if let (img, _) = try? await gen.image(at: t) { out.append(img) } }
        return out
    }
}
#endif
