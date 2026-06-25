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

    /// What the inspector edits — the PRIMARY (focused) element. `.none` = the project itself.
    /// Multi-selection (⌘/⇧-click, marquee) lives in `selectedIDs`; `selection` is the primary the
    /// inspector shows (the most-recently-touched member).
    enum Selection: Equatable, Hashable {
        case none, clip(UUID), overlay(UUID), audio(UUID)
        var id: UUID? { switch self { case .clip(let i), .overlay(let i), .audio(let i): return i; case .none: return nil } }
    }
    var selection: Selection = .none
    /// The FULL multi-selection set (UUIDs across clips/overlays/audio — all globally unique). The
    /// primary `selection` is always one of these (or `.none` when empty).
    var selectedIDs: Set<UUID> = []

    /// Resolve an id to its element kind (which array holds it).
    func kindOf(_ id: UUID) -> Selection {
        if clips.contains(where: { $0.id == id }) { return .clip(id) }
        if textOverlays.contains(where: { $0.id == id }) { return .overlay(id) }
        if audioClips.contains(where: { $0.id == id }) { return .audio(id) }
        return .none
    }
    /// Single-select (replaces the whole selection) — also the path `addClip`/etc. use.
    func select(_ s: Selection) { selection = s; selectedIDs = s.id.map { [$0] } ?? [] }
    func selectOnly(_ id: UUID) { selectedIDs = [id]; selection = kindOf(id) }
    /// ⌘-click: toggle one element in/out of the selection.
    func toggleSelected(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if selection.id == id { selection = selectedIDs.first.map { kindOf($0) } ?? .none }
        } else { selectedIDs.insert(id); selection = kindOf(id) }
    }
    /// ⇧-click: add to the selection without removing.
    func addSelected(_ id: UUID) { selectedIDs.insert(id); selection = kindOf(id) }
    /// Marquee result — replace (or add when additive).
    func setSelectedIDs(_ ids: Set<UUID>, additive: Bool) {
        selectedIDs = additive ? selectedIDs.union(ids) : ids
        if let p = selection.id, selectedIDs.contains(p) { /* keep primary */ }
        else { selection = selectedIDs.first.map { kindOf($0) } ?? .none }
    }
    func clearSelection() { selectedIDs = []; selection = .none }
    func selectAll() {
        selectedIDs = Set(clips.map(\.id) + textOverlays.map(\.id) + audioClips.map(\.id))
        selection = selectedIDs.first.map { kindOf($0) } ?? .none
    }
    /// Delete every selected element (clips, overlays, audio), as one undo step.
    func deleteSelection() {
        guard !selectedIDs.isEmpty else { return }
        checkpoint()
        let ids = selectedIDs
        for id in ids {
            switch kindOf(id) {
            case .overlay: document.project.timeline.textOverlays.removeAll { $0.id == id }
            case .audio:
                if let i = audioIndex(id) {
                    try? FileManager.default.removeItem(at: ProjectMediaCache.directory
                        .appendingPathComponent(document.project.timeline.audioClips[i].fileName))
                    document.project.timeline.audioClips.remove(at: i)
                }
            case .clip: document.project.timeline.clips.removeAll { $0.id == id }
            case .none: break
            }
        }
        clearSelection()
        bumpOverlayRevision()
        relayout(); scheduleRebuild()
    }
    /// Multi-drag: set each selected FREE element (text overlay / audio clip) to its captured
    /// origin start + `delta`, in ONE rebuild. Magnetic video clips have no free time position, so
    /// they're not part of a time-delta drag (they reorder individually).
    func moveSelectedFreeElements(byDelta delta: Double, origins: [UUID: Double]) {
        for (id, origin) in origins {
            let target = max(0, origin + delta)
            switch kindOf(id) {
            case .overlay:
                if let i = document.project.timeline.textOverlays.firstIndex(where: { $0.id == id }) {
                    let dur = document.project.timeline.textOverlays[i].timelineRange.duration.seconds
                    document.project.timeline.textOverlays[i].timelineRange =
                        TimeRange(startSeconds: target, durationSeconds: dur)
                }
            case .audio:
                if let i = audioIndex(id) { document.project.timeline.audioClips[i].startSeconds = target }
            default: break
            }
        }
        bumpOverlayRevision()   // selected overlays may have moved → refresh the live preview
        scheduleRebuild()
    }
    var selectedClipID: UUID? { if case .clip(let id) = selection { return id }; return nil }
    var selectedOverlayID: UUID? { if case .overlay(let id) = selection { return id }; return nil }
    var selectedAudioID: UUID? { if case .audio(let id) = selection { return id }; return nil }
    /// Timeline zoom — points per second. Clamped; ⌘-scroll / pinch drive it.
    var pointsPerSecond: Double = 60
    var thumbnails: [UUID: [CGImage]] = [:]
    var isBuildingPreview = false
    /// Per-clip media-prep state for the timeline UI: caching the local window / ready / failed
    /// (with a human reason).
    var clipPrep: [UUID: ClipPrep] = [:]
    enum ClipPrep: Equatable { case caching, ready, failed(String) }

    /// Aggregate prep state for the status panel (#9): how many clips are ready / still caching /
    /// failed (with reasons), so the UI can say "3 of 7 ready · 1 failed" instead of a bare spinner.
    struct PrepStatus: Equatable { var ready = 0; var caching = 0; var total = 0; var failures: [String] = [] }
    var prepStatus: PrepStatus {
        var s = PrepStatus(); s.total = clips.count
        for c in clips {
            switch clipPrep[c.id] {
            case .ready: s.ready += 1
            case .caching: s.caching += 1
            case .failed(let r): s.failures.append(r)
            case nil: break
            }
        }
        return s
    }
    private func markFailed(_ id: UUID, _ reason: String) { clipPrep[id] = .failed(reason) }
    nonisolated static func reason(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "network error — couldn't download" }
        return ns.localizedDescription
    }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    // Auto-retry transient source failures (archive.org /download 503s) a few times with
    // backoff so a clip that missed its window in one rebuild self-heals instead of staying red.
    @ObservationIgnored private var transientRetryTask: Task<Void, Never>?
    @ObservationIgnored private var transientRetries = 0
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
        selection = .clip(clip.id)
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

    /// Set a clip's fade-in / fade-out (seconds). Each is clamped to the clip's duration; the
    /// two are kept from overlapping at build time. Rebuilds preview (fades show live).
    func setClipFade(_ id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let dur = document.project.timeline.clips[i].sourceRange.duration.seconds
        if let fadeIn { document.project.timeline.clips[i].fadeInSeconds = max(0, min(fadeIn, dur)) }
        if let fadeOut { document.project.timeline.clips[i].fadeOutSeconds = max(0, min(fadeOut, dur)) }
        scheduleRebuild()
    }

    /// Set a clip's color grade (Look). The grade is baked into a cached source file on the next
    /// rebuild, so the preview updates after a brief render.
    func setClipLook(_ id: UUID, _ look: ClipLook) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        document.project.timeline.clips[i].lookRaw = look.rawValue
        scheduleRebuild()
    }

    /// Set the cross-dissolve duration FROM the previous clip INTO this one (seconds). Clamped to
    /// the shorter of this clip and the previous clip. 0 = a hard cut. Re-lays-out the timeline
    /// (the clip slides earlier by the overlap) and rebuilds.
    func setClipTransition(_ id: UUID, _ seconds: Double) {
        let clips = self.clips
        guard let pos = clips.firstIndex(where: { $0.id == id }), pos > 0,
              let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let cap = min(clips[pos].sourceRange.duration.seconds, clips[pos - 1].sourceRange.duration.seconds) - 0.1
        document.project.timeline.clips[i].transitionInSeconds = max(0, min(seconds, max(0, cap)))
        relayout()             // the overlap shifts this clip + all following earlier
        scheduleRebuild()
    }

    /// Set the transition STYLE (dissolve / wipe / push) for this clip's incoming transition.
    func setClipTransitionKind(_ id: UUID, _ kind: TransitionKind) {
        guard let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        document.project.timeline.clips[i].transitionKindRaw = kind.rawValue
        scheduleRebuild()
    }

    /// Add a clip from a saved proxy (dragged from the Library, or just-marked).
    func addClip(from proxy: ProxyClip) {
        checkpoint()
        let clip = TimelineClip.from(proxy, at: .zero)
        document.project.timeline.clips.append(clip)
        relayout()
        selection = .clip(clip.id)
        loadFilmstrip(for: clip)
        scheduleRebuild()
    }

    // MARK: - Supercut batch add (instant) + background refine

    struct SupercutTake: Sendable { let proxy: ProxyClip; let phrase: String; let captionText: String }
    @ObservationIgnored private var refineTask: Task<Void, Never>?
    /// True while a background supercut tighten/level pass is running (shown in the status panel).
    var isRefining = false

    /// Add MANY supercut takes AT ONCE — instant, just in/out references + the remote-streaming
    /// preview (no per-clip caching/speech blocking the add). If `tighten`/`evenVolume` are on, each
    /// clip is refined in the BACKGROUND (best-effort, non-blocking): the clip is usable immediately
    /// and its in/out + volume update as the refine completes. (The user added 80 clips and it
    /// processed one-by-one — this is the fix.)
    func addSupercutClips(_ takes: [SupercutTake], tighten: Bool, evenVolume: Bool) {
        guard !takes.isEmpty else { return }
        checkpoint()
        var added: [(id: UUID, take: SupercutTake)] = []
        for take in takes {
            let clip = TimelineClip.from(take.proxy, at: .zero)
            document.project.timeline.clips.append(clip)
            added.append((clip.id, take))
            loadFilmstrip(for: clip)
        }
        if let last = added.last { selection = .clip(last.id) }
        relayout(); scheduleRebuild()

        guard tighten || evenVolume else { return }
        isRefining = true
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            await self?.refineSupercut(added, tighten: tighten, evenVolume: evenVolume)
            self?.isRefining = false
        }
    }

    private func refineSupercut(_ added: [(id: UUID, take: SupercutTake)], tighten: Bool, evenVolume: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            var it = added.makeIterator()
            func addNext() {
                guard let entry = it.next() else { return }
                group.addTask { [weak self] in
                    await self?.refineOne(id: entry.id, take: entry.take, tighten: tighten, evenVolume: evenVolume)
                }
            }
            for _ in 0..<2 { addNext() }            // bounded — the cache + speech are heavy
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
            }
        }
        scheduleRebuild()
    }

    private func refineOne(id: UUID, take: SupercutTake, tighten: Bool, evenVolume: Bool) async {
        // Tighten/level need a LOCAL window (speech + RMS). Best-effort: if caching fails, the clip
        // stays as the subtitle-cue window (still a valid clip containing the phrase).
        guard let url = try? await ClipCacheService.cachedURL(for: TimelineClip.from(take.proxy, at: .zero)),
              !Task.isCancelled else { return }
        if tighten, let r = await WordTiming.tighten(mediaURL: url, phrase: take.phrase, caption: take.captionText),
           let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) {
            let newIn = take.proxy.sourceRange.start.seconds + r.start.seconds
            document.project.timeline.clips[i].sourceRange =
                TimeRange(startSeconds: max(0, newIn), durationSeconds: max(0.05, r.duration.seconds))
        }
        if evenVolume, let rms = await Loudness.rms(url: url),
           let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) {
            document.project.timeline.clips[i].audioVolume = Loudness.gain(forRMS: rms)
        }
    }

    func deleteClip(_ id: UUID) {
        checkpoint()
        document.project.timeline.clips.removeAll { $0.id == id }
        thumbnails[id] = nil; clipCache[id] = nil
        if selectedClipID == id { selection = .none }
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
        checkpoint()
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
        selection = .clip(right.id)
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
        checkpoint()
        let src = document.project.timeline.clips[i]
        let copy = TimelineClip(
            proxyClipID: src.proxyClipID, catalogItemID: src.catalogItemID, sourceURL: src.sourceURL,
            sourceRange: src.sourceRange, timelineStart: .zero, track: 0, label: src.label, audioVolume: src.audioVolume)
        document.project.timeline.clips.insert(copy, at: i + 1)
        if let w = clipCache[id] { clipCache[copy.id] = w }                 // same source window
        loadFilmstrip(for: copy)
        selection = .clip(copy.id)
        relayout(); scheduleRebuild()
    }

    // MARK: - Text overlays (#3)

    var textOverlays: [TextOverlay] { document.project.timeline.textOverlays }
    /// A TRACKED @Observable token bumped on every overlay mutation. The live SwiftUI overlay
    /// preview (TextOverlayPreview) reads it so its body re-evaluates when an overlay changes —
    /// `textOverlays` is backed by the non-@Observable `document`, so without this token a paused
    /// preview never sees position/text/color edits (it only re-rendered when `playheadSeconds`
    /// changed, i.e. while playing). Bump on EVERY overlay write.
    private(set) var overlayRevision = 0
    func bumpOverlayRevision() { overlayRevision &+= 1 }

    func addTextOverlay() {
        checkpoint()
        let start = playheadSeconds
        let avail = max(0, totalDuration - start)
        let ov = TextOverlay(text: "Title",
                             timelineRange: TimeRange(startSeconds: start,
                                                      durationSeconds: avail > 1 ? min(3, avail) : 3))
        document.project.timeline.textOverlays.append(ov)
        selection = .overlay(ov.id)
        bumpOverlayRevision()
        // No preview rebuild: overlays aren't baked into the preview composition (the Core
        // Animation tool is export-only) — the live SwiftUI overlay shows them; export reads
        // them at export time. Skipping the rebuild keeps text editing/dragging instant.
    }

    func updateOverlay(_ ov: TextOverlay) {
        guard let i = document.project.timeline.textOverlays.firstIndex(where: { $0.id == ov.id }) else { return }
        document.project.timeline.textOverlays[i] = ov
        bumpOverlayRevision()
    }

    func deleteOverlay(_ id: UUID) {
        checkpoint()
        document.project.timeline.textOverlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selection = .none }
        bumpOverlayRevision()
    }

    // MARK: - Undo / redo (project snapshots via the window UndoManager) + clipboard + mute

    /// Set from ProjectEditorView (@Environment(\.undoManager)) so ⌘Z + the Edit menu drive our
    /// snapshot-based history natively.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var clipboard: TimelineClip?
    var hasClipboard: Bool { clipboard != nil }

    /// Capture the project so the next edit is undoable. Call BEFORE a discrete edit, or once at
    /// the start of a drag (the timeline calls this on mouseDown).
    func checkpoint() {
        let before = document.project
        undoManager?.registerUndo(withTarget: self) { editor in editor.applyHistory(before) }
    }
    private func applyHistory(_ snapshot: ClipProject) {
        let inverse = document.project                       // re-registers as redo
        undoManager?.registerUndo(withTarget: self) { editor in editor.applyHistory(inverse) }
        document.project = snapshot
        selection = .none
        bumpOverlayRevision()    // overlays may have changed → refresh the live preview
        relayout(); scheduleRebuild()
    }

    /// Copy the selected clip; paste inserts a duplicate after the selection (sharing its cached
    /// source window so it doesn't re-download).
    func copySelected() {
        guard let id = selectedClipID, let c = clips.first(where: { $0.id == id }) else { return }
        clipboard = c
    }
    func paste() {
        guard let c = clipboard else { return }
        checkpoint()
        let copy = TimelineClip(proxyClipID: c.proxyClipID, catalogItemID: c.catalogItemID,
                                sourceURL: c.sourceURL, sourceRange: c.sourceRange,
                                timelineStart: .zero, track: 0, label: c.label, audioVolume: c.audioVolume,
                                fadeInSeconds: c.fadeInSeconds, fadeOutSeconds: c.fadeOutSeconds)
        if let id = selectedClipID, let i = document.project.timeline.clips.firstIndex(where: { $0.id == id }) {
            document.project.timeline.clips.insert(copy, at: i + 1)
        } else {
            document.project.timeline.clips.append(copy)
        }
        if let w = clipCache[c.id] { clipCache[copy.id] = w }
        selection = .clip(copy.id)
        loadFilmstrip(for: copy)
        relayout(); scheduleRebuild()
    }

    /// Mute / unmute the selected clip's audio.
    func toggleMuteSelected() {
        guard let id = selectedClipID, let c = clips.first(where: { $0.id == id }) else { return }
        checkpoint()
        setClipVolume(id, c.audioVolume == 0 ? 1 : 0)
    }

    /// Magnetic main track: clips lie end-to-end in ARRAY order, no gaps (Rule 7c). Array order
    /// IS the timeline order — reorder/insert in the array, then relayout assigns each clip's
    /// start. (Was sorting by timelineStart, which made a just-added clip at t=0 jump ahead and
    /// blocked drag-reordering.)
    private func relayout() {
        var cursor = 0.0
        var rebuilt: [TimelineClip] = []
        for (idx, var c) in document.project.timeline.clips.enumerated() {
            // Overlap with the previous clip by transitionIn so the timeline view's positions
            // and total match the composition (CompositionBuilder uses the SAME placement), and
            // the playhead stays aligned with the preview when a cross-dissolve is set.
            let dur = c.sourceRange.duration.seconds
            let trans = idx == 0 ? 0 : max(0, min(c.transitionInSeconds, dur))
            let start = max(0, cursor - trans)
            c.timelineStart = TimeStamp(seconds: start)
            rebuilt.append(c)
            cursor = start + dur
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

        // Cache clips CONCURRENTLY, bounded (#2) — one slow/failed clip no longer blocks the rest.
        // resolveLocal is @MainActor but suspends at the network/export await, so up to N caches run
        // in flight. A clip that won't cache is marked .failed(reason) and EXCLUDED from the build,
        // so it can't stall playback of the good clips (#13).
        let maxConcurrent = 3
        var resolvedByID: [UUID: CompositionBuilder.ResolvedClip] = [:]
        await withTaskGroup(of: (UUID, CompositionBuilder.ResolvedClip?).self) { group in
            var it = timelineClips.makeIterator()
            func addNext() {
                guard let clip = it.next() else { return }
                group.addTask { [weak self] in
                    guard let self else { return (clip.id, nil) }
                    do { return (clip.id, try await self.resolveLocal(clip)) }
                    catch is CancellationError { return (clip.id, nil) }
                    catch { await self.markFailed(clip.id, Self.reason(for: error)); return (clip.id, nil) }
                }
            }
            for _ in 0..<maxConcurrent { addNext() }
            while let (id, r) = await group.next() {
                if let r { resolvedByID[id] = r }
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
            }
        }
        if Task.isCancelled { return }
        // Auto-retry transient source failures: the loader now fails a 503'ing /download over
        // to the item's own node, but a clip can still miss its window in a single rebuild (cold
        // node, alternates not yet resolved). resolveLocal cleared the failed source from the
        // cache, so re-probing re-resolves it. Back off (2s/4s/6s) and stop once nothing fails.
        let failedIDs = timelineClips.filter { if case .failed = clipPrep[$0.id] { return true }; return false }
        if failedIDs.isEmpty {
            transientRetries = 0
        } else if transientRetries < 3 {
            transientRetries += 1
            let n = transientRetries
            transientRetryTask?.cancel()
            transientRetryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(n) * 2))
                guard !Task.isCancelled else { return }
                await self?.rebuildPreview()
            }
        }
        // Build from the READY clips in timeline order (failed clips are excluded, not blockers).
        let resolved = timelineClips.compactMap { resolvedByID[$0.id] }
        guard !resolved.isEmpty else { return }

        // bakeOverlays:false — the Core Animation overlay tool is offline-only (crashes
        // AVPlayerItem). Same clip/reframe/audio recipe as export, so the preview frame matches.
        let credit = document.project.burnAttribution ? ExportService.defaultCredit : nil
        do {
            let built = try await CompositionBuilder.build(
                resolved: resolved, timeline: document.project.timeline,
                creditLine: credit, bakeOverlays: false, beds: resolvedBeds())
            guard !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            // Buffer ahead so a streamed clip's frames are ready when the playhead reaches it, and
            // let the player WAIT to minimize stalling rather than render a clip blank while its
            // remote bytes are still in flight (item 3 — "plays through but the video is blank").
            item.preferredForwardBufferDuration = 8
            player.automaticallyWaitsToMinimizeStalling = true
            player.replaceCurrentItem(with: item)
            // Seek ONCE the item is ready, so the first frame actually decodes + displays. A seek
            // issued before `.readyToPlay` (the old code) is dropped — leaving the program monitor
            // BLACK until the user manually scrubs (which seeks the by-then-ready item). Poll
            // readiness briefly, then seek the still-current item.
            let target = CMTime(seconds: min(playheadSeconds, totalDuration), preferredTimescale: 600)
            for _ in 0..<160 {
                if item.status != .unknown { break }       // ready OR failed — stop waiting
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled, player.currentItem === item, item.status == .readyToPlay else { return }
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        } catch {
            // Leave the previous preview in place on a transient build failure.
        }
    }

    /// Resolve a clip for PREVIEW from a LOCALLY-CACHED window (the Rule 4b reliability win) — the
    /// SAME files export uses, so the preview is frame-identical to the export and ALWAYS plays a
    /// fully-loaded clip (never a blank segment whose remote bytes are still in flight). The cache
    /// reads through the ResilientStreamLoader (byte-range + node failover + resume-on-reset,
    /// Decision 021/031/034) and re-encodes to a small local MP4 (ClipCacheService) — which is why
    /// streaming N deep remote windows straight into one composition (the old path) is no longer
    /// needed: that played some clips blank because one progressive asset can't serve many distant
    /// offsets at once. A GENEROUS window (clip ± cacheHandle) is cached once and reused while the
    /// user trims inside it, so trims don't re-cache; only the composition's insert range changes.
    private func resolveLocal(_ clip: TimelineClip) async throws -> CompositionBuilder.ResolvedClip {
        if clipPrep[clip.id] != .ready { clipPrep[clip.id] = .caching }
        let inS = clip.sourceRange.start.seconds
        let outS = clip.sourceRange.endSeconds

        // Reuse the cached generous window if the current in/out still falls inside it.
        var window = clipCache[clip.id]
        if let w = window,
           inS >= w.sourceStart - 0.01, outS <= w.sourceEnd + 0.01,
           FileManager.default.fileExists(atPath: w.url.path) {
            // reuse w as-is
        } else {
            let wStart = max(0, inS - Self.cacheHandle)
            let wEnd = outS + Self.cacheHandle
            let url = try await CacheCoordinator.window(
                catalogItemID: clip.catalogItemID, sourceURL: clip.sourceURL,
                startSeconds: wStart, endSeconds: wEnd)
            if Task.isCancelled { throw CancellationError() }
            // The cache clamps the window to the source's real duration, so trust the FILE's
            // duration for the window end (makeResolved's avail/dur clamp depends on it).
            let fileDur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? (wEnd - wStart)
            window = CachedWindow(url: url, sourceStart: wStart, sourceEnd: wStart + fileDur)
            clipCache[clip.id] = window
        }
        guard let w = window else {
            throw NSError(domain: "CreationStudio", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't read the source video"])
        }
        clipPrep[clip.id] = .ready
        let graded = await gradedAssetURL(clip, window: w)   // bakes the Look (or passes through)
        ensureThumbnails(clip, window: w)
        return makeResolved(clip, window: w, assetURL: graded)
    }

    /// The clip's in/out expressed as an insert range INTO the cached window file (file t=0 is
    /// the window's source start), clamped to what the file actually holds.
    /// `assetURL` is the window file, OR a color-graded copy of it (same timing) when the clip
    /// carries a Look — the grade is baked into the source file so it composes with transitions.
    private func makeResolved(_ clip: TimelineClip, window: CachedWindow, assetURL: URL) -> CompositionBuilder.ResolvedClip {
        let inS = clip.sourceRange.start.seconds
        let startInFile = max(0, inS - window.sourceStart)
        let avail = max(0.05, window.sourceEnd - inS)
        let dur = min(clip.sourceRange.duration.seconds, avail)
        return .init(asset: AVURLAsset(url: assetURL),
                     insertRange: CMTimeRange(start: CMTime(seconds: startInFile, preferredTimescale: 600),
                                              duration: CMTime(seconds: max(0.05, dur), preferredTimescale: 600)),
                     audioVolume: clip.audioVolume,
                     fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds,
                     transitionIn: clip.transitionInSeconds, transitionKind: clip.transitionKind)
    }

    /// Grade the window for the clip's Look (cached after the first render), or pass it through.
    private func gradedAssetURL(_ clip: TimelineClip, window: CachedWindow) async -> URL {
        guard clip.look != .none else { return window.url }
        return (try? await LookGrader.gradedURL(for: window.url, look: clip.look)) ?? window.url
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

    // MARK: - Audio clips (#4 audio layers — N music + voiceover tracks, Rule 3c)

    var audioClips: [AudioClip] { document.project.timeline.audioClips }
    var selectedAudio: AudioClip? { selectedAudioID.flatMap { id in audioClips.first { $0.id == id } } }
    private func audioIndex(_ id: UUID) -> Int? {
        document.project.timeline.audioClips.firstIndex { $0.id == id }
    }

    /// Import an audio file as a NEW music clip at the current playhead (multiple are allowed).
    func addMusic(from src: URL) {
        let name = "music-\(UUID().uuidString.prefix(6))-\(src.lastPathComponent)"
        let dst = ProjectMediaCache.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        guard (try? FileManager.default.copyItem(at: src, to: dst)) != nil else { return }
        checkpoint()
        let clip = AudioClip(kind: .music, fileName: name,
                             displayName: src.deletingPathExtension().lastPathComponent,
                             volume: 0.5, startSeconds: max(0, playheadSeconds))
        document.project.timeline.audioClips.append(clip)
        selection = .audio(clip.id)
        loadAudioDuration(clip.id)
        scheduleRebuild()
    }

    func setAudioVolume(_ id: UUID, _ v: Double) {
        guard let i = audioIndex(id) else { return }
        document.project.timeline.audioClips[i].volume = max(0, min(1.5, v))
        scheduleRebuild()
    }
    func setAudioStart(_ id: UUID, _ seconds: Double) {
        guard let i = audioIndex(id) else { return }
        document.project.timeline.audioClips[i].startSeconds = max(0, seconds)
        scheduleRebuild()
    }
    func setAudioFade(_ id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let i = audioIndex(id) else { return }
        let dur = max(0.1, document.project.timeline.audioClips[i].sourceDuration)
        if let fadeIn  { document.project.timeline.audioClips[i].fadeInSeconds  = max(0, min(fadeIn,  dur)) }
        if let fadeOut { document.project.timeline.audioClips[i].fadeOutSeconds = max(0, min(fadeOut, dur)) }
        scheduleRebuild()
    }
    func renameAudio(_ id: UUID, _ name: String) {
        guard let i = audioIndex(id) else { return }
        document.project.timeline.audioClips[i].displayName = name
    }
    func removeAudio(_ id: UUID) {
        guard let i = audioIndex(id) else { return }
        let clip = document.project.timeline.audioClips[i]
        try? FileManager.default.removeItem(at: ProjectMediaCache.directory.appendingPathComponent(clip.fileName))
        checkpoint()
        document.project.timeline.audioClips.remove(at: i)
        if selectedAudioID == id { selection = .none }
        scheduleRebuild()
    }

    /// Fill an audio clip's cached `sourceDuration` from the file (async — for the timeline block
    /// width + the fade clamps).
    private func loadAudioDuration(_ id: UUID) {
        guard let i = audioIndex(id) else { return }
        let url = ProjectMediaCache.directory.appendingPathComponent(document.project.timeline.audioClips[i].fileName)
        Task { [weak self] in
            let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard let self, let j = self.audioIndex(id) else { return }
            self.document.project.timeline.audioClips[j].sourceDuration = dur
        }
    }

    /// Every audio clip resolved for the composition (music + voiceover, each its own track).
    func resolvedBeds() -> [CompositionBuilder.ResolvedMusic] {
        document.project.timeline.audioClips.compactMap { clip in
            let url = ProjectMediaCache.directory.appendingPathComponent(clip.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return .init(asset: AVURLAsset(url: url), volume: clip.volume, startSeconds: clip.startSeconds,
                         maxDuration: clip.sourceDuration > 0 ? clip.sourceDuration : nil,
                         fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds)
        }
    }

    // MARK: - Voiceover recording (adds a NEW voiceover audio clip)

    var isRecordingVoiceover: Bool { voiceRecorder?.isRecording ?? false }
    /// Surfaced so a failed recording isn't silent (#10).
    var voiceoverError: String?
    @ObservationIgnored private var voiceRecorder: AVAudioRecorder?
    @ObservationIgnored private var voiceStartSeconds = 0.0
    @ObservationIgnored private var voicePendingName = ""

    /// Start recording mic narration to the project cache (begins at the current playhead).
    /// Requests mic access first — on macOS, recording without authorization (or without the
    /// mic entitlement) silently captures nothing, so we gate + surface the failure.
    func startVoiceover() { Task { await beginVoiceover() } }

    private func beginVoiceover() async {
        voiceoverError = nil
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) == false {
                voiceoverError = "Microphone access denied. Enable it in System Settings ▸ Privacy & Security ▸ Microphone."
                return
            }
        default:
            voiceoverError = "Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone."
            return
        }
        let name = "voiceover-\(UUID().uuidString.prefix(6)).m4a"
        let url = ProjectMediaCache.directory.appendingPathComponent(name)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                                        AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings), rec.record() else {
            voiceoverError = "Couldn't start recording."
            return
        }
        voiceStartSeconds = playheadSeconds
        voicePendingName = name
        voiceRecorder = rec
    }

    /// Stop recording and add the take as a NEW voiceover clip (multiple are allowed).
    func stopVoiceover() {
        guard let rec = voiceRecorder else { return }
        rec.stop()
        voiceRecorder = nil
        checkpoint()
        let clip = AudioClip(kind: .voiceover, fileName: voicePendingName, displayName: "Voiceover",
                             volume: 1.0, startSeconds: voiceStartSeconds)
        document.project.timeline.audioClips.append(clip)
        selection = .audio(clip.id)
        loadAudioDuration(clip.id)
        scheduleRebuild()
    }

    // MARK: - Retime lane blocks (drag on the titles / audio lanes — multi-track timeline)

    /// Move a text overlay along the titles lane (keeps its duration).
    func setOverlayStart(_ id: UUID, seconds: Double) {
        guard var o = textOverlays.first(where: { $0.id == id }) else { return }
        o.timelineRange = TimeRange(startSeconds: max(0, seconds),
                                    durationSeconds: o.timelineRange.duration.seconds)
        updateOverlay(o)
    }

    // MARK: - Project canvas / frame rate (editable in the project inspector)

    struct CanvasPreset: Identifiable, Hashable {
        let name: String, width: Double, height: Double
        var isCustom = false
        var id: String { name }
        var size: RenderSize { RenderSize(width: width, height: height) }
    }
    static let canvasPresets: [CanvasPreset] = [
        .init(name: "Landscape · 16:9 (1920×1080)", width: 1920, height: 1080),
        .init(name: "Portrait · 9:16 (1080×1920)", width: 1080, height: 1920),
        .init(name: "Square · 1:1 (1080×1080)", width: 1080, height: 1080),
        .init(name: "Portrait · 4:5 (1080×1350)", width: 1080, height: 1350),
        .init(name: "Landscape · 4:3 (1440×1080)", width: 1440, height: 1080),
    ]
    /// The preset matching the current render size, or a synthetic "Custom" entry.
    var matchedCanvasPreset: CanvasPreset {
        let r = document.project.timeline.renderSize
        return Self.canvasPresets.first { $0.width == r.width && $0.height == r.height }
            ?? CanvasPreset(name: "Custom", width: r.width, height: r.height, isCustom: true)
    }
    func setRenderSize(_ s: RenderSize) {
        guard document.project.timeline.renderSize != s else { return }
        checkpoint()
        document.project.timeline.renderSize = s
        scheduleRebuild()
    }
    func setFrameRate(_ fps: Double) {
        guard document.project.timeline.frameRate != fps else { return }
        document.project.timeline.frameRate = max(1, fps)
        scheduleRebuild()
    }

    // MARK: - Markers (navigation + snap targets)

    var markers: [Double] { document.project.timeline.markers }

    /// Toggle a marker at the playhead (remove if one is within 0.3s, else add). M key.
    func toggleMarkerAtPlayhead() {
        let t = playheadSeconds
        if let i = document.project.timeline.markers.firstIndex(where: { abs($0 - t) < 0.3 }) {
            document.project.timeline.markers.remove(at: i)
        } else {
            document.project.timeline.markers.append(t)
            document.project.timeline.markers.sort()
        }
    }

    /// Jump the playhead to the next/prev marker (or clip boundary if no marker is closer).
    func goToMarker(forward: Bool) {
        let t = playheadSeconds
        let stops = (markers + clips.map { $0.timelineStart.seconds }
                     + clips.map { $0.timelineRange.endSeconds }).sorted()
        let next = forward ? stops.first(where: { $0 > t + 0.05 })
                           : stops.last(where: { $0 < t - 0.05 })
        if let next { seek(toSeconds: next) }
    }

    // MARK: - Keyboard transport (FCP-style — ←/→ frame step, ↑/↓ edit nav, Home/End)

    /// One frame at the project frame rate.
    var frameStep: Double { 1.0 / max(1, document.project.timeline.frameRate) }

    /// Move the playhead by a signed delta (←/→ = ±1 frame; ⇧←/⇧→ = ±1 s).
    func nudgePlayhead(seconds delta: Double) { seek(toSeconds: playheadSeconds + delta) }

    /// Jump the playhead to the next/previous EDIT point (clip boundary or 0/end) — FCP ↑/↓.
    func goToEdit(forward: Bool) {
        let t = playheadSeconds
        let stops = ([0, totalDuration] + clips.map { $0.timelineStart.seconds }
                     + clips.map { $0.timelineRange.endSeconds }).sorted()
        let next = forward ? stops.first(where: { $0 > t + 0.01 })
                           : stops.last(where: { $0 < t - 0.01 })
        if let next { seek(toSeconds: next) }
    }

    func goToStart() { seek(toSeconds: 0) }
    func goToEnd() { seek(toSeconds: totalDuration) }

    // MARK: - Snapping

    /// Snap a dragged timeline second to a nearby edit point (clip edges, markers, playhead, 0)
    /// when within `tolerancePoints` on screen. Returns the snapped seconds (or the input).
    func snap(_ seconds: Double, excluding excludeID: UUID? = nil, tolerancePoints: Double = 8) -> Double {
        let tol = tolerancePoints / max(1, pointsPerSecond)
        var best = seconds, bestD = tol
        var stops: [Double] = markers + [0, playheadSeconds]
        for c in clips where c.id != excludeID {
            stops.append(c.timelineStart.seconds)
            stops.append(c.timelineRange.endSeconds)
        }
        for s in stops where abs(s - seconds) < bestD {
            best = s; bestD = abs(s - seconds)
        }
        return best
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
