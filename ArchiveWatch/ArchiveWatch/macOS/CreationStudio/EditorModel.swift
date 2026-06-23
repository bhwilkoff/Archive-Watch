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

    @ObservationIgnored private var preview: PreviewComposer.Preview?   // retains loaders
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
        generateThumbnails(for: clip)
        scheduleRebuild()
    }

    /// Add a clip from a saved proxy (dragged from the Library, or just-marked).
    func addClip(from proxy: ProxyClip) {
        let clip = TimelineClip.from(proxy, at: .zero)
        document.project.timeline.clips.append(clip)
        relayout()
        selectedClipID = clip.id
        generateThumbnails(for: clip)
        scheduleRebuild()
    }

    func deleteClip(_ id: UUID) {
        document.project.timeline.clips.removeAll { $0.id == id }
        thumbnails[id] = nil
        if selectedClipID == id { selectedClipID = nil }
        relayout(); scheduleRebuild()
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
        var right = TimelineClip(
            proxyClipID: clip.proxyClipID, catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
            sourceRange: TimeRange(startSeconds: cutSource, durationSeconds: clip.sourceRange.endSeconds - cutSource),
            timelineStart: .zero, track: 0, label: clip.label)
        document.project.timeline.clips[i] = left
        document.project.timeline.clips.insert(right, at: i + 1)
        generateThumbnails(for: right)
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

    func rebuildPreview() async {
        guard !document.project.timeline.clips.isEmpty else {
            player.replaceCurrentItem(with: nil); preview = nil; return
        }
        isBuildingPreview = true
        defer { isBuildingPreview = false }
        let credit = document.project.burnAttribution ? ExportService.defaultCredit : nil
        do {
            let built = try await PreviewComposer.build(timeline: document.project.timeline, creditLine: credit)
            guard !Task.isCancelled else { return }
            preview = built                                   // retains loaders
            player.replaceCurrentItem(with: built.playerItem)
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

    private func generateThumbnails(for clip: TimelineClip) {
        Task { [weak self] in
            let imgs = await self?.thumbGen.thumbnails(
                url: clip.sourceURL, startSeconds: clip.sourceRange.start.seconds,
                endSeconds: clip.sourceRange.endSeconds, count: 10) ?? []
            await MainActor.run { self?.thumbnails[clip.id] = imgs }
        }
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        rebuildTask?.cancel()
    }
}

// Off-main filmstrip thumbnail generation over the resilient remote asset.
actor ThumbnailGenerator {
    func thumbnails(url: URL, startSeconds: Double, endSeconds: Double, count: Int) async -> [CGImage] {
        let (asset, loader) = await MainActor.run { ResilientStreamLoader.makeAsset(for: url) }
        defer { withExtendedLifetime(loader) {} }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)   // small — speed over fidelity
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        let span = max(0.1, endSeconds - startSeconds)
        let times = (0..<max(1, count)).map { i -> NSValue in
            let t = startSeconds + span * (Double(i) + 0.5) / Double(count)
            return NSValue(time: CMTime(seconds: t, preferredTimescale: 600))
        }
        var out: [CGImage] = []
        for t in times {
            if let (img, _) = try? await gen.image(at: t.timeValue) { out.append(img) }
        }
        return out
    }
}
#endif
