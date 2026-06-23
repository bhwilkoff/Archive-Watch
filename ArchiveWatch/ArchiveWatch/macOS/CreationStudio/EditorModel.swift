#if os(macOS)
import Foundation
import AVFoundation
import Observation
import CoreImage

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
        scheduleRebuild()          // caching + thumbnails happen in the rebuild (from the local window)
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
        scheduleRebuild()
    }

    func deleteClip(_ id: UUID) {
        document.project.timeline.clips.removeAll { $0.id == id }
        thumbnails[id] = nil
        if selectedClipID == id { selectedClipID = nil }
        relayout(); scheduleRebuild()
    }

    /// Re-attempt caching a clip whose window failed to load (transient archive.org failure).
    func retryClip(_ id: UUID) {
        clipPrep[id] = nil
        thumbnails[id] = nil
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
        thumbnails[id] = nil          // range changed → regenerate from the new cached window
        clipPrep[id] = nil
        relayout(); scheduleRebuild()
    }

    /// Split the clip under the playhead into two at the current position (⌘B).
    func splitAtPlayhead() {
        let t = playheadSeconds
        guard let clip = clips.first(where: { c in
            let s = c.timelineStart.seconds
            return t > s + 0.05 && t < s + c.sourceRange.duration.seconds - 0.05
        }), let i = document.project.timeline.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let offsetInClip = t - clip.timelineStart.seconds          // seconds into the clip
        let cutSource = clip.sourceRange.start.seconds + offsetInClip
        var left = clip
        left.sourceRange = TimeRange(startSeconds: clip.sourceRange.start.seconds,
                                     durationSeconds: offsetInClip)
        let right = TimelineClip(
            proxyClipID: clip.proxyClipID, catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
            sourceRange: TimeRange(startSeconds: cutSource, durationSeconds: clip.sourceRange.endSeconds - cutSource),
            timelineStart: .zero, track: 0, label: clip.label)
        document.project.timeline.clips[i] = left
        document.project.timeline.clips.insert(right, at: i + 1)
        thumbnails[clip.id] = nil; clipPrep[clip.id] = nil   // both halves re-derive their windows
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
        scheduleRebuild()
    }

    func updateOverlay(_ ov: TextOverlay) {
        guard let i = document.project.timeline.textOverlays.firstIndex(where: { $0.id == ov.id }) else { return }
        document.project.timeline.textOverlays[i] = ov
        scheduleRebuild()
    }

    func deleteOverlay(_ id: UUID) {
        document.project.timeline.textOverlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
        scheduleRebuild()
    }

    /// Magnetic main track: clips lie end-to-end in their current order, no gaps (Rule 7c).
    private func relayout() {
        let ordered = document.project.timeline.clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds }
        var cursor = 0.0
        var rebuilt: [TimelineClip] = []
        for var c in ordered {
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
        isBuildingPreview = true
        defer { isBuildingPreview = false }

        var resolved: [CompositionBuilder.ResolvedClip] = []
        for clip in timelineClips {
            if clipPrep[clip.id] != .ready { clipPrep[clip.id] = .caching }
            do {
                let url = try await ClipCacheService.cachedURL(for: clip)   // fast if already cached
                if Task.isCancelled { return }
                clipPrep[clip.id] = .ready
                if thumbnails[clip.id] == nil { generateThumbnails(clip.id, localURL: url) }
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration)                   // the cached file IS the window
                resolved.append(.init(asset: asset,
                                      insertRange: CMTimeRange(start: .zero, duration: dur),
                                      audioVolume: clip.audioVolume))
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

    /// Generate the filmstrip from the LOCAL cached window (fast + frame-accurate) — not the
    /// remote film. The window file spans exactly the clip's in/out, so frames map directly.
    private func generateThumbnails(_ clipID: UUID, localURL: URL) {
        Task { [weak self] in
            let imgs = await self?.thumbGen.thumbnails(url: localURL, count: 10) ?? []
            await MainActor.run { self?.thumbnails[clipID] = imgs }
        }
    }

    // isolated deinit (SE-0371) so cleanup can touch the MainActor-isolated player/observer
    // natively under the Swift 6 language mode — no nonisolated(unsafe) escape hatch needed.
    isolated deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        rebuildTask?.cancel()
    }
}

// Off-main filmstrip thumbnails from a LOCAL cached window file (fast, no remote streaming).
actor ThumbnailGenerator {
    func thumbnails(url: URL, count: Int) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)
        gen.requestedTimeToleranceBefore = .zero            // local file → exact is cheap + accurate
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { return [] }
        let span = dur.seconds
        let times = (0..<max(1, count)).map { i in
            CMTime(seconds: span * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var out: [CGImage] = []
        for t in times { if let (img, _) = try? await gen.image(at: t) { out.append(img) } }
        return out
    }
}
#endif
