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
// to its @Observable properties. Mutations write through to `project` so SwiftUI
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
            case .overlay: project.timeline.textOverlays.removeAll { $0.id == id }
            case .audio:
                if let i = audioIndex(id) {
                    try? FileManager.default.removeItem(at: ProjectMediaCache.directory
                        .appendingPathComponent(project.timeline.audioClips[i].fileName))
                    project.timeline.audioClips.remove(at: i)
                }
            case .clip: project.timeline.clips.removeAll { $0.id == id }
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
                if let i = project.timeline.textOverlays.firstIndex(where: { $0.id == id }) {
                    let dur = project.timeline.textOverlays[i].timelineRange.duration.seconds
                    project.timeline.textOverlays[i].timelineRange =
                        TimeRange(startSeconds: target, durationSeconds: dur)
                }
            case .audio:
                if let i = audioIndex(id) { project.timeline.audioClips[i].startSeconds = target }
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
    /// A clip whose source HAS video but didn't cache this pass stays "preparing" (it retries) — it is
    /// NEVER shown as a hard failure. Only a source with literally no video track is `.failed`. This is
    /// the "if it's in the DB, it can go in the supercut — no persistent error" guarantee.
    private func markPreparing(_ id: UUID) { if clipPrep[id] != .ready { clipPrep[id] = .caching } }
    nonisolated static func reason(for error: Error) -> String {
        if error is CancellationError { return "took too long to load" }   // a per-clip cache timeout
        if let code = urlErrorCode(in: error as NSError) {
            switch code {
            case NSURLErrorNotConnectedToInternet: return "you appear to be offline"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorResourceUnavailable:
                return "couldn’t reach archive.org"
            default: return "network error — couldn’t download"
            }
        }
        return (error as NSError).localizedDescription
    }
    /// archive.org's connection failures surface either as a plain NSURLError or wrapped inside an
    /// AVFoundation error (the AVAssetReader reads through our loader). Dig the chain for the URL code.
    nonisolated static func urlErrorCode(in error: NSError) -> Int? {
        if error.domain == NSURLErrorDomain { return error.code }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return urlErrorCode(in: underlying) }
        return nil
    }
    nonisolated static func isConnectivity(_ error: Error) -> Bool { urlErrorCode(in: error as NSError) != nil }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    // Auto-retry transient source failures (archive.org /download 503s) a few times with
    // backoff so a clip that missed its window in one rebuild self-heals instead of staying red.
    @ObservationIgnored private var transientRetryTask: Task<Void, Never>?
    @ObservationIgnored private var transientRetries = 0
    // The ACTUAL playable duration per clip (composition insert duration, clamped to cached footage).
    // rebuildPreview reconciles the timeline to this so blocks/playhead match the preview exactly.
    @ObservationIgnored private var clipActualDuration: [UUID: Double] = [:]

    // MARK: - Diagnostic accessors (CreationStudioFeatureAudit) — read-only views of private state.
    // Harmless in release; used by the env-gated in-app feature audit to assert that an edit actually
    // reached the cached window + the composition, not just the timeline model.
    var debug_clipActualDuration: [UUID: Double] { clipActualDuration }
    func debug_windowSpan(_ id: UUID) -> (url: URL, start: Double, end: Double)? {
        clipCache[id].map { ($0.url, $0.sourceStart, $0.sourceEnd) }
    }
    /// Bumped once at the END of every rebuildPreview cycle (any exit path), so the audit can wait for a
    /// real rebuild to COMPLETE rather than racing the 140ms debounce.
    @ObservationIgnored var debug_rebuildCount = 0
    /// Bumped on every player-item swap (replaceCurrentItem). Each swap blanks the program monitor —
    /// the audit asserts a load does only a FEW swaps so the preview doesn't "flash with every update".
    @ObservationIgnored var debug_swapCount = 0
    // Sources whose window PERMANENTLY failed to encode ("Cannot Encode movie" — a codec/format the
    // encoder can't handle). Keyed by source URL → the failure reason. A clip from such a source is
    // marked failed once and NEVER re-encoded (it used to re-attempt on every rebuild). Cleared by an
    // explicit Retry. Keyed by source (not clip id) so a duplicate/split of the same bad source is
    // skipped too.
    @ObservationIgnored private var permanentlyFailed: [String: String] = [:]
    // Consecutive cache failures per source. We DON'T trust a single error code (the player streams
    // these same sources fine — most re-encode errors are transient read hiccups). A source becomes
    // permanent only after it fails repeatedly, OR on a definitively-unrecoverable error.
    @ObservationIgnored private var sourceFailCount: [String: Int] = [:]
    static let maxSourceFailures = 3
    private func isKnownPermanent(_ source: String) -> Bool { permanentlyFailed[source] != nil }
    /// Set when EVERY clip failed for an environmental reason (archive.org refusing connections / you're
    /// offline) — shown in the preview overlay so it reads "can't reach the server", not a frozen
    /// progress number, and so we DON'T mark clips permanently failed (they recover when access returns).
    var previewBlockedReason: String?
    /// Record a cache failure for a source. Promote to permanent only if definitively unrecoverable;
    /// the count-based promotion is decided AFTER the pass (so an environmental outage, where the count
    /// would spuriously climb, never permanently fails a clip).
    private func recordFailure(_ source: String, reason: String, definitelyPermanent: Bool) {
        sourceFailCount[source, default: 0] += 1
        sourceFailReason[source] = reason
        if definitelyPermanent { permanentlyFailed[source] = reason }
        if firstFailAt[source] == nil {
            firstFailAt[source] = Date()
            // Guarantee a rebuild EVALUATES the wall-clock give-up at the deadline even if the auto-retry
            // chain has stopped — otherwise a single dead clip churns for minutes (owner: "the last few
            // hang almost every time"). The deadline rebuild fast-fails the source (resolveLocal) → gap.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.maxGiveUpSeconds + 0.5))
                self?.scheduleRebuild()   // Task inherits @MainActor; scheduleRebuild is sync — no await
            }
        }
    }
    @ObservationIgnored private var sourceFailReason: [String: String] = [:]
    // When a source FIRST failed — a wall-clock give-up complements the count-based one so a single dead
    // clip can't churn for minutes (the preview AND verify passes both retry it through backoffs, which
    // stretched 3 failures to 137s). A source still failing after maxGiveUpSeconds is given up = a gap.
    @ObservationIgnored private var firstFailAt: [String: Date] = [:]
    static let maxGiveUpSeconds: TimeInterval = 45
    /// A source cached successfully — clear its failure streak so a later transient blip starts fresh.
    private func noteSourceSucceeded(_ source: String) {
        if sourceFailCount[source] != nil { sourceFailCount[source] = nil }
        firstFailAt[source] = nil
        previewBlockedReason = nil          // something loaded → connectivity is back
    }
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let thumbGen = ThumbnailGenerator()

    /// A locally-cached GENEROUS source window (clip ± handles). Trimming within
    /// [sourceStart, sourceEnd] reuses this file — only the composition's insert range
    /// changes, so no re-cache and no "Preparing clips" per trim.
    struct CachedWindow { let url: URL; let sourceStart: Double; let sourceEnd: Double }
    @ObservationIgnored private var clipCache: [UUID: CachedWindow] = [:]
    /// Extra source footage cached on each side of a clip so small trims are free. Kept small: the
    /// window is downloaded + re-encoded through the resilient loader, so every extra second is
    /// network + encode time — a big handle made short supercut clips take minutes to load. 3s
    /// covers ordinary fine-trims; a larger trim simply re-caches (a brief wait), not a failure.
    // 1.5s handle (was 3): smaller window = fewer bytes per clip = faster prep; still covers ordinary
    // fine-trims (a larger trim simply re-caches). Tunable for the benchmark (BenchConfig/env).
    static var cacheHandle: Double { BenchConfig.handle ?? Double(ProcessInfo.processInfo.environment["AW_CS_HANDLE"] ?? "") ?? 1.5 }

    // Per-attempt deadline for a PROXY window (preview + verify). A tiny 512kb-derivative window
    // lands in seconds on a healthy node; the 90s export budget was sized for full-quality and made
    // a single stalling clip hold a shared encode permit for 90s x2 x3-retries (~9 min) — the
    // "stuck downloading / Verifying X of Y" hang. 25s fails a true stall fast, frees the permit,
    // and lets the give-up fire quickly, while still tolerating a slow-but-progressing connection.
    static var proxyCacheTimeout: Double { Double(ProcessInfo.processInfo.environment["AW_CS_PROXY_TIMEOUT"] ?? "") ?? 25 }

    // archive.org's per-~60s thumbnail strip (ArchiveThumbnails) is the timeline filmstrip
    // source: it's tiny + already-served, so a clip shows frames INSTANTLY without waiting for
    // the (slow) window cache + AVAssetImageGenerator. Cached per item + per image so trimming
    // re-derives the strip with no new network.
    @ObservationIgnored private var archiveStrips: [String: [ArchiveThumb]] = [:]
    @ObservationIgnored private var thumbImageCache: [URL: CGImage] = [:]

    static let minPPS = 6.0, maxPPS = 600.0

    init(document: ClipProjectDocument) {
        self.document = document
        self._project = document.project        // seed the observed source of truth from the document
        // Bound the re-encoded-window cache (it was unbounded and grew to GBs, filling the disk →
        // corrupt SQLite caches + mmap faults). Off-main; sweeps orphaned staging files too.
        Task.detached { ProjectMediaCache.sweep() }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, t.isNumeric else { return }
                // While the user is dragging (scrub/trim/move), the playhead they set is authoritative —
                // don't let the player's clock overwrite it and fight them. Likewise while a preview
                // ITEM SWAP is in flight: a freshly-replaced AVPlayerItem reports currentTime 0 until the
                // re-seek lands, and letting that 0 through made the playhead snap to the start of the
                // timeline on every clip re-render (owner: "keeps going back to the beginning").
                if self.isInteracting || self.isSwappingPreview { return }
                self.playheadSeconds = t.seconds
                let playing = self.player.rate != 0
                // Playback just STOPPED (paused at the transport, or reached the end). If clip fills were
                // deferred while playing, catch the preview up to the timeline now.
                if self.isPlaying, !playing, self.previewDirty { self.scheduleRebuild() }
                self.isPlaying = playing
            }
        }
    }

    /// The live project — the SINGLE @Observable source of truth for the editor. Backed by the
    /// tracked stored `_project`, so ANY read (e.g. `clips` in the timeline's updateNSView) registers
    /// an observation dependency and the AppKit timeline + SwiftUI re-render automatically on every
    /// edit — no manual `bumpTimeline()` nudges. Writes ALSO mirror to the document (its @Published
    /// `project`, exactly as before), so SwiftUI's autosave is unchanged.
    private var _project: ClipProject
    var project: ClipProject {
        get { _project }
        set { _project = newValue; document.project = newValue }
    }
    var clips: [TimelineClip] { project.timeline.clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds } }
    var totalDuration: Double { project.timeline.durationSeconds }

    // MARK: - Edits (magnetic single track → relayout after every change)

    func addClip(catalogItemID: String, sourceURL: URL, title: String,
                 inSeconds: Double = 3, durationSeconds: Double = 8) {
        let clip = TimelineClip(
            catalogItemID: catalogItemID, sourceURL: sourceURL,
            sourceRange: TimeRange(startSeconds: inSeconds, durationSeconds: durationSeconds),
            timelineStart: .zero, track: 0, label: title)
        project.timeline.clips.append(clip)
        relayout()
        selection = .clip(clip.id)
        loadFilmstrip(for: clip)   // instant archive.org-thumbnail filmstrip (no wait on the cache)
        scheduleRebuild()          // window caching for preview/export happens in the rebuild
    }

    var selectedClip: TimelineClip? { clips.first { $0.id == selectedClipID } }

    /// Set a clip's audio volume in the mix (#4).
    func setClipVolume(_ id: UUID, _ vol: Double) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        project.timeline.clips[i].audioVolume = max(0, min(1.5, vol))
        scheduleRebuild()
    }

    /// Set a clip's fade-in / fade-out (seconds). Each is clamped to the clip's duration; the
    /// two are kept from overlapping at build time. Rebuilds preview (fades show live).
    func setClipFade(_ id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let dur = project.timeline.clips[i].sourceRange.duration.seconds
        if let fadeIn { project.timeline.clips[i].fadeInSeconds = max(0, min(fadeIn, dur)) }
        if let fadeOut { project.timeline.clips[i].fadeOutSeconds = max(0, min(fadeOut, dur)) }
        scheduleRebuild()
    }

    /// Set a clip's color grade (Look). The grade is baked into a cached source file on the next
    /// rebuild, so the preview updates after a brief render.
    func setClipLook(_ id: UUID, _ look: ClipLook) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        project.timeline.clips[i].lookRaw = look.rawValue
        scheduleRebuild()
    }

    /// Set the cross-dissolve duration FROM the previous clip INTO this one (seconds). Clamped to
    /// the shorter of this clip and the previous clip. 0 = a hard cut. Re-lays-out the timeline
    /// (the clip slides earlier by the overlap) and rebuilds.
    func setClipTransition(_ id: UUID, _ seconds: Double) {
        let clips = self.clips
        guard let pos = clips.firstIndex(where: { $0.id == id }), pos > 0,
              let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let cap = min(clips[pos].sourceRange.duration.seconds, clips[pos - 1].sourceRange.duration.seconds) - 0.1
        project.timeline.clips[i].transitionInSeconds = max(0, min(seconds, max(0, cap)))
        relayout()             // the overlap shifts this clip + all following earlier
        scheduleRebuild()
    }

    /// Set the transition STYLE (dissolve / wipe / push) for this clip's incoming transition.
    func setClipTransitionKind(_ id: UUID, _ kind: TransitionKind) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        project.timeline.clips[i].transitionKindRaw = kind.rawValue
        scheduleRebuild()
    }

    /// Add a clip from a saved proxy (dragged from the Library, or just-marked).
    func addClip(from proxy: ProxyClip) {
        checkpoint()
        let clip = TimelineClip.from(proxy, at: .zero)
        project.timeline.clips.append(clip)
        relayout()
        selection = .clip(clip.id)
        loadFilmstrip(for: clip)
        scheduleRebuild()
    }

    /// Add a clip at the PLAYHEAD on the magnetic track (owner #5 — double-click a Library clip).
    /// Inserts before the first clip starting at/after the playhead, so it lands where you're parked
    /// rather than always at the end.
    func addClipAtPlayhead(from proxy: ProxyClip) {
        checkpoint()
        let clip = TimelineClip.from(proxy, at: .zero)
        let t = playheadSeconds
        // `clips` is the timeline-ordered view and the document array is kept in that same order by
        // relayout, so an index found here maps straight onto the array.
        var insertIdx = project.timeline.clips.count
        for (i, c) in clips.enumerated() where c.timelineStart.seconds >= t - 0.01 { insertIdx = i; break }
        project.timeline.clips.insert(clip, at: min(insertIdx, project.timeline.clips.count))
        relayout()
        selection = .clip(clip.id)
        loadFilmstrip(for: clip)
        scheduleRebuild()
    }

    // MARK: - Supercut batch add (instant) + background refine

    struct SupercutTake: Sendable {
        let proxy: ProxyClip
        let phrase: String
        let captionText: String
        /// Ranked FALLBACK sources for the SAME phrase (Supercut Search / compose mode). If the
        /// chosen clip turns out not to actually SPEAK the phrase, the verify pass swaps in the first
        /// alternate that does — so the sentence stays complete instead of losing the word.
        var alternates: [ProxyClip] = []
    }
    /// The verify pass's DECISION for one clip, computed WITHOUT mutating the timeline. All plans are
    /// applied atomically AFTER the pass, so the timeline never changes mid-pass — keeping it in sync
    /// with the preview throughout (owner: "preview and timeline get out of sync as clips render").
    struct RefinePlan: Sendable {
        let id: UUID
        var remove = false                                                  // contradicted, no alternate
        var newSourceRange: TimeRange? = nil                                // tighten / replacement range
        var newVolume: Double? = nil                                        // evenVolume
        var replacement: (catalogItemID: String, sourceURL: URL, label: String)? = nil  // confirmed alternate
    }
    @ObservationIgnored private var refineTask: Task<Void, Never>?
    /// True while a background supercut verify/tighten/level pass is running (shown in the status panel).
    var isRefining = false
    /// Verify-pass progress so the status panel can show "N of M" (and a bar) and the user knows when
    /// ALL processing tasks are done — not just a bare spinner that looks frozen on a long supercut.
    var verifyDone = 0
    var verifyTotal = 0
    /// A brief note after a supercut verify pass — e.g. how many clips were removed because the
    /// phrase wasn't actually spoken (owner #1/#2). Auto-clears.
    var supercutVerifyNote: String?

    /// Add MANY supercut takes AT ONCE — instant, just in/out references + the remote-streaming
    /// preview (no per-clip caching/speech blocking the add). If `tighten`/`evenVolume` are on, each
    /// clip is refined in the BACKGROUND (best-effort, non-blocking): the clip is usable immediately
    /// and its in/out + volume update as the refine completes. (The user added 80 clips and it
    /// processed one-by-one — this is the fix.)
    func addSupercutClips(_ takes: [SupercutTake], tighten: Bool, evenVolume: Bool, addSubtitles: Bool = false) {
        guard !takes.isEmpty else { return }
        checkpoint()
        var added: [(id: UUID, take: SupercutTake)] = []
        for take in takes {
            let clip = TimelineClip.from(take.proxy, at: .zero)
            project.timeline.clips.append(clip)
            added.append((clip.id, take))
            loadFilmstrip(for: clip)
        }
        if let last = added.last { selection = .clip(last.id) }
        relayout(); scheduleRebuild()

        // ALWAYS run the background pass: it VERIFIES each clip actually speaks the phrase (owner
        // #1/#2 — subtitles are spotty) and removes the ones it doesn't, plus optional tighten/level.
        isRefining = true
        verifyDone = 0; verifyTotal = added.count
        supercutVerifyNote = nil
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            await self?.refineSupercut(added, tighten: tighten, evenVolume: evenVolume, addSubtitles: addSubtitles)
            self?.isRefining = false
        }
    }

    private func refineSupercut(_ added: [(id: UUID, take: SupercutTake)], tighten: Bool, evenVolume: Bool, addSubtitles: Bool) async {
        // Phase 1: COMPUTE every clip's plan WITHOUT touching the timeline (so the timeline stays
        // exactly what the preview is showing during the whole pass — no mid-pass desync).
        var plans: [RefinePlan] = []
        await withTaskGroup(of: RefinePlan.self) { group in
            var it = added.makeIterator()
            func addNext() {
                guard let entry = it.next() else { return }
                group.addTask { [weak self] in
                    await self?.refineOne(id: entry.id, take: entry.take, tighten: tighten, evenVolume: evenVolume)
                        ?? RefinePlan(id: entry.id)
                }
            }
            // Verify concurrency is env-tunable but DEFAULTS TO 2 — measured: raising it storms
            // archive.org. For a FRESH phrase the verify pass RACES the preview pass, so its windows
            // are NOT yet cached and each opens its own connection; at conc 4 this tripped the per-IP
            // rate limit (24× -1011, 8 forced give-ups, retention 88%→70%, time 84s→424s). 2 is the
            // proven-safe value; the give-up + the preview cache (shared) handle the rest.
            let verifyConc = Int(ProcessInfo.processInfo.environment["AW_CS_VERIFY_CONC"] ?? "") ?? 2
            for _ in 0..<max(1, verifyConc) { addNext() }   // shares the preview's window cache + the global
                                                    // ReencodeLimiter; kept low so we don't storm archive.org
                                                    // archive.org connections at once (it rate-limits the IP)
            while let plan = await group.next() {
                plans.append(plan)
                verifyDone += 1
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
            }
        }
        // Phase 2: APPLY all plans ATOMICALLY (one timeline mutation, one rebuild) so the timeline and
        // preview switch from "the raw cut" to "the verified cut" together — never partially out of sync.
        var removed = 0, replaced = 0
        for plan in plans where !plan.remove {
            guard let i = project.timeline.clips.firstIndex(where: { $0.id == plan.id }) else { continue }
            if let rep = plan.replacement {
                project.timeline.clips[i].catalogItemID = rep.catalogItemID
                project.timeline.clips[i].sourceURL = rep.sourceURL
                project.timeline.clips[i].label = rep.label
                clipCache[plan.id] = nil; thumbnails[plan.id] = nil          // source changed → drop stale window/strip
                replaced += 1
            }
            if let r = plan.newSourceRange { project.timeline.clips[i].sourceRange = r }
            if let v = plan.newVolume { project.timeline.clips[i].audioVolume = v }
        }
        let removeIDs = Set(plans.filter { $0.remove }.map { $0.id })
        if !removeIDs.isEmpty { project.timeline.clips.removeAll { removeIDs.contains($0.id) }; removed = removeIDs.count }
        for plan in plans where plan.replacement != nil {
            if let c = project.timeline.clips.first(where: { $0.id == plan.id }) { loadFilmstrip(for: c) }
        }
        relayout()          // final repack so the surviving clips form one gap-free run
        Task.detached { ProjectMediaCache.sweep() }   // a batch can add many big windows — keep the cache bounded
        // Subtitles last (owner ask): the verify pass removes/replaces/tightens clips, so the spoken
        // text only lines up with each clip's FINAL position+length here. One editable title overlay
        // per surviving clip, spanning exactly that clip, anchored to the lower third.
        if addSubtitles { addSupercutSubtitles(phraseByID: Dictionary(added.map { ($0.id, $0.take.phrase) },
                                                                      uniquingKeysWith: { a, _ in a })) }
        scheduleRebuild()
        var parts: [String] = []
        if replaced > 0 { parts.append("swapped \(replaced) to a clip that says it") }
        if removed > 0  { parts.append("removed \(removed) with no match") }
        if !parts.isEmpty {
            supercutVerifyNote = "Verified phrases — " + parts.joined(separator: ", ") + "."
            let note = supercutVerifyNote
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                if self?.supercutVerifyNote == note { self?.supercutVerifyNote = nil }
            }
        }
    }

    /// Lay a subtitle (a normal, editable TextOverlay) under each surviving supercut clip so the
    /// viewer can read what the cross-film collage is saying (owner ask). Each title spans exactly
    /// its clip's final timeline range and shows that clip's spoken words; removed clips contribute
    /// none. These are ordinary overlays — draggable, restyleable, deletable like any other text clip.
    private func addSupercutSubtitles(phraseByID: [UUID: String]) {
        var overlays: [TextOverlay] = []
        for c in clips {
            guard let phrase = phraseByID[c.id], !phrase.isEmpty else { continue }
            let range = TimeRange(startSeconds: c.timelineStart.seconds,
                                  durationSeconds: max(0.05, c.sourceRange.duration.seconds))
            overlays.append(TextOverlay(text: phrase, timelineRange: range,
                                        positionX: 0.5, positionY: 0.88, fontScale: 0.045))
        }
        guard !overlays.isEmpty else { return }
        project.timeline.textOverlays.append(contentsOf: overlays)
        bumpOverlayRevision()
    }

    /// Refine ONE supercut take. Verification listens to the AUDIO, not the caption, so it catches
    /// clips the spotty subtitle put on screen but that don't actually contain the phrase. On such a
    /// clip it first tries to SWAP IN a ranked alternate that DOES speak the phrase (compose mode);
    /// only if none do is the clip removed.
    /// The SAME generous window (clip ± cacheHandle) the preview caches, fetched through
    /// CacheCoordinator so the verify pass and the preview SHARE one download+re-encode per clip
    /// (the coordinator coalesces identical in-flight requests) instead of each fetching its own —
    /// the dominant cost of "add supercut" was paying for every clip's bytes twice. Returns the
    /// local file and the SOURCE time its t=0 maps to (windowStart), so verified ranges convert back.
    private func refineWindow(for proxy: ProxyClip) async throws -> (url: URL, windowStart: Double) {
        let inS = proxy.sourceRange.start.seconds, outS = proxy.sourceRange.endSeconds
        let wStart = max(0, inS - Self.cacheHandle)
        // The verify pass uses the small proxy too — faster, and phrase-verification needs no full res.
        let src = await ProxySource.proxyURL(archiveID: proxy.catalogItemID, fallback: proxy.sourceURL)
        // Proxy windows are tiny (a few seconds of the 512kb derivative) — a healthy node returns one
        // in seconds, so a SHORT timeout + single attempt fails a stall fast instead of paying the
        // 90s x2 export budget (which starved the shared permits + hung "Verifying X of Y").
        let url = try await CacheCoordinator.window(
            catalogItemID: proxy.catalogItemID, sourceURL: src,
            startSeconds: wStart, endSeconds: outS + Self.cacheHandle,
            attempts: 1, timeout: Self.proxyCacheTimeout)
        return (url, wStart)
    }

    /// refineWindow bounded by a timeout: it WAITS for the preview's shared/in-flight cache (fast for
    /// any reachable clip) but ABORTS a long fresh fetch on a stalling/-1011 source, so the verify
    /// pass can't hang "Verifying X of Y" for minutes (owner 2026-06-27 — the preview pass owns the
    /// real fetch + give-up; verification of an unfetchable clip is simply skipped, the clip kept).
    private func refineWindowBounded(_ proxy: ProxyClip, timeout: Double = 20) async -> (url: URL, windowStart: Double)? {
        await withTaskGroup(of: (url: URL, windowStart: Double)?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return try? await self.refineWindow(for: proxy)
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func refineOne(id: UUID, take: SupercutTake, tighten: Bool, evenVolume: Bool) async -> RefinePlan {
        // COMPUTES a plan; does NOT mutate the timeline (refineSupercut applies all plans atomically at
        // the end). Verification + tighten/level need a LOCAL window — reuse the preview's generous
        // window (shared cache). Skip clips the preview already GAVE UP on, and BOUND the fetch so a
        // stalling source never blocks the pass for minutes.
        var plan = RefinePlan(id: id)
        if isKnownPermanent(take.proxy.sourceURL.absoluteString) {
            if CreationStudioBench.isEnabled { CreationStudioBench.mark("refine-skip-permfail \(take.proxy.catalogItemID)") }
            return plan
        }
        let _wt0 = Date()
        guard let (url, wStart) = await refineWindowBounded(take.proxy),
              !Task.isCancelled else {
            if CreationStudioBench.isEnabled { CreationStudioBench.mark("refine-skip-nowindow winMs=\(Int(Date().timeIntervalSince(_wt0)*1000)) \(take.proxy.catalogItemID)") }
            return plan
        }
        let _winMs = Int(Date().timeIntervalSince(_wt0) * 1000)

        // 1) VERIFY the phrase is actually spoken (independent of the subtitle) — ONE speech pass,
        //    reused below. Only a CONTRADICTED verdict (speech recognized, phrase absent) acts;
        //    unverifiable audio (music / rough old prints) is kept.
        let _vt0 = Date()
        let verdict = await WordTiming.verify(mediaURL: url, phrase: take.phrase)
        if CreationStudioBench.isEnabled {
            CreationStudioBench.mark("refine-timing winMs=\(_winMs) verifyMs=\(Int(Date().timeIntervalSince(_vt0)*1000)) \(take.proxy.catalogItemID)")
        }
        if CreationStudioBench.isEnabled {
            let kind: String
            switch verdict { case .confirmed: kind = "confirmed"; case .contradicted: kind = "contradicted"; case .unverifiable: kind = "unverifiable" }
            CreationStudioBench.noteVerdict(kind, phrase: take.phrase, detail: "caption=\"\(take.captionText.prefix(60))\"")
        }
        if case .contradicted = verdict {
            // Try each ranked ALTERNATE (Supercut Search) — the first that actually speaks the phrase
            // REPLACES this clip in place (same timeline slot), tightened to the spoken words.
            for alt in take.alternates {
                if Task.isCancelled { return plan }
                if isKnownPermanent(alt.sourceURL.absoluteString) { continue }
                guard let (altURL, altStart) = await refineWindowBounded(alt) else { continue }
                guard case .confirmed(let r) = await WordTiming.verify(mediaURL: altURL, phrase: take.phrase) else { continue }
                let newIn = altStart + r.start.seconds       // file t=0 = altStart (the window start)
                plan.replacement = (alt.catalogItemID, alt.sourceURL, alt.label)
                plan.newSourceRange = TimeRange(startSeconds: max(0, newIn), durationSeconds: max(0.05, r.duration.seconds))
                return plan
            }
            plan.remove = true                               // no alternate spoke it → remove
            return plan
        }
        if Task.isCancelled { return plan }

        // 2) TIGHTEN (when requested) to the spoken-word bounds — prefer the verified range, else the
        //    caption-validated tighten as a fallback. Ranges are file-relative (t=0 = wStart).
        if tighten {
            var range: CMTimeRange?
            if case .confirmed(let r) = verdict { range = r }
            if range == nil { range = await WordTiming.tighten(mediaURL: url, phrase: take.phrase, caption: take.captionText) }
            if let r = range {
                plan.newSourceRange = TimeRange(startSeconds: max(0, wStart + r.start.seconds),
                                                durationSeconds: max(0.05, r.duration.seconds))
            }
        }
        if evenVolume, let rms = await Loudness.rms(url: url) {
            plan.newVolume = Loudness.gain(forRMS: rms)
        }
        return plan
    }

    func deleteClip(_ id: UUID) {
        checkpoint()
        project.timeline.clips.removeAll { $0.id == id }
        thumbnails[id] = nil; clipCache[id] = nil
        if selectedClipID == id { selection = .none }
        relayout(); scheduleRebuild()
    }

    /// Re-attempt caching a clip whose window failed to load (transient archive.org failure).
    func retryClip(_ id: UUID) {
        clipPrep[id] = nil
        thumbnails[id] = nil
        clipCache[id] = nil          // force a fresh cache attempt
        if let c = clips.first(where: { $0.id == id }) {
            permanentlyFailed[c.sourceURL.absoluteString] = nil   // explicit Retry gives it another full chance
            sourceFailCount[c.sourceURL.absoluteString] = nil
        }
        scheduleRebuild()
    }

    /// Set a clip's in/out (frame-exact handle drag). `newIn`/`newOut` are SOURCE seconds.
    func trim(_ id: UUID, newInSeconds: Double? = nil, newOutSeconds: Double? = nil) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = project.timeline.clips[i]
        var inS = clip.sourceRange.start.seconds
        var outS = clip.sourceRange.endSeconds
        if let newInSeconds { inS = min(max(0, newInSeconds), outS - 0.1) }
        if let newOutSeconds { outS = max(newOutSeconds, inS + 0.1) }
        clip.sourceRange = TimeRange(startSeconds: inS, durationSeconds: outS - inS)
        project.timeline.clips[i] = clip
        // Refresh the filmstrip for the new sub-range from cached thumbnails (instant, no flash);
        // the cached generous window is reused (no re-cache) while the trim stays inside it.
        loadFilmstrip(for: clip)
        // While the LEFT handle is being dragged, DEFER the magnetic re-pack to release: the timeline
        // renders this clip's right edge anchored (left follows the cursor), so re-packing now would
        // ripple the following clips LEFT under the anchored edge (overlap). endInteraction re-packs.
        let leftTrimDrag = newInSeconds != nil && newOutSeconds == nil && isInteracting
        if leftTrimDrag { scheduleRebuild() } else { relayout(); scheduleRebuild() }
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
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = project.timeline.clips[i]
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
        project.timeline.clips[i] = left
        project.timeline.clips.insert(right, at: i + 1)
        // Both halves come from the same source — share the cached generous window so neither
        // re-caches; just refresh each half's filmstrip for its new sub-range.
        if let w = clipCache[clip.id] { clipCache[right.id] = w }
        loadFilmstrip(for: left); loadFilmstrip(for: right)
        selection = .clip(right.id)
        relayout(); scheduleRebuild()
    }

    /// Reorder a clip on the magnetic track by dragging (toIndex = desired slot).
    func moveClip(_ id: UUID, toIndex target: Int) {
        let original = project.timeline.clips
        guard let from = original.firstIndex(where: { $0.id == id }) else { return }
        var arr = original
        let clip = arr.remove(at: from)
        arr.insert(clip, at: min(max(0, target), arr.count))
        guard arr.map(\.id) != original.map(\.id) else { return }          // no order change
        project.timeline.clips = arr
        relayout(); scheduleRebuild()
    }

    /// Duplicate a clip immediately after itself (context menu).
    func duplicateClip(_ id: UUID) {
        guard let i = project.timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        let src = project.timeline.clips[i]
        let copy = TimelineClip(
            proxyClipID: src.proxyClipID, catalogItemID: src.catalogItemID, sourceURL: src.sourceURL,
            sourceRange: src.sourceRange, timelineStart: .zero, track: 0, label: src.label, audioVolume: src.audioVolume)
        project.timeline.clips.insert(copy, at: i + 1)
        if let w = clipCache[id] { clipCache[copy.id] = w }                 // same source window
        loadFilmstrip(for: copy)
        selection = .clip(copy.id)
        relayout(); scheduleRebuild()
    }

    // MARK: - Text overlays (#3)

    var textOverlays: [TextOverlay] { project.timeline.textOverlays }
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
        project.timeline.textOverlays.append(ov)
        selection = .overlay(ov.id)
        bumpOverlayRevision()
        // No preview rebuild: overlays aren't baked into the preview composition (the Core
        // Animation tool is export-only) — the live SwiftUI overlay shows them; export reads
        // them at export time. Skipping the rebuild keeps text editing/dragging instant.
    }

    func updateOverlay(_ ov: TextOverlay) {
        guard let i = project.timeline.textOverlays.firstIndex(where: { $0.id == ov.id }) else { return }
        project.timeline.textOverlays[i] = ov
        bumpOverlayRevision()
    }

    func deleteOverlay(_ id: UUID) {
        checkpoint()
        project.timeline.textOverlays.removeAll { $0.id == id }
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
        let before = project
        undoManager?.registerUndo(withTarget: self) { editor in editor.applyHistory(before) }
    }
    private func applyHistory(_ snapshot: ClipProject) {
        let inverse = project                       // re-registers as redo
        undoManager?.registerUndo(withTarget: self) { editor in editor.applyHistory(inverse) }
        project = snapshot
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
        if let id = selectedClipID, let i = project.timeline.clips.firstIndex(where: { $0.id == id }) {
            project.timeline.clips.insert(copy, at: i + 1)
        } else {
            project.timeline.clips.append(copy)
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
        for (idx, var c) in project.timeline.clips.enumerated() {
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
        project.timeline.clips = rebuilt
    }

    // MARK: - Preview (rebuild-and-swap, debounced)

    // MARK: - Interactive editing (timeline drags) — while the user scrubs / trims / moves, the
    // PLAYER must not fight them: no preview rebuild churn (each swap reseeks + interrupts), and the
    // periodic time observer must not overwrite the playhead the user is dragging. The timeline brackets
    // every drag with beginInteraction()/endInteraction(); a single rebuild runs on release.
    @ObservationIgnored private(set) var isInteracting = false
    @ObservationIgnored private var pendingRebuildAfterInteraction = false
    // TRUE whenever an edit has been made that the current preview composition does NOT yet reflect —
    // cleared only when a rebuild runs to completion and swaps the item. beginInteraction CANCELS any
    // in-flight rebuild (to stop mid-drag reseek churn), so without this flag a committed edit's
    // rebuild is silently lost when the user immediately scrubs/plays to check it — the reported
    // "trim grows the block but the preview never shows the new footage" bug. endInteraction
    // re-schedules whenever the preview is still dirty, so a committed edit always reaches the preview.
    @ObservationIgnored private var previewDirty = false
    // TRUE while composeAndSwap is replacing the player item + re-seeking to the playhead. The periodic
    // time observer ignores the new item's transient currentTime 0 during this window, so the playhead
    // never snaps to the timeline start on a re-render.
    @ObservationIgnored private var isSwappingPreview = false

    func beginInteraction() {
        isInteracting = true
        pendingRebuildAfterInteraction = false
        rebuildTask?.cancel()              // stop any in-flight debounced rebuild from reseeking under us
        transientRetryTask?.cancel()
        if isPlaying { pause() }            // a scrub/trim drag pauses playback (no fighting the play rate)
    }

    func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        // Re-pack the magnetic track now the drag is done — a left-trim deferred its ripple to here so
        // the clip could shrink from the left during the drag (idempotent for an already-packed track).
        relayout()
        // Re-run the rebuild if this drag committed an edit OR an earlier committed edit's rebuild is
        // still un-reflected (previewDirty) — e.g. a scrub that cancelled the trim's rebuild before it
        // finished. Either way the preview must end up matching the timeline.
        if pendingRebuildAfterInteraction || previewDirty {
            pendingRebuildAfterInteraction = false
            scheduleRebuild()              // ONE rebuild reflecting the final edit, after the drag ends
        } else {
            // Scrub-only: settle on the exact frame the drag used tolerant seeks to find.
            player.seek(to: CMTime(seconds: min(max(0, playheadSeconds), max(0, totalDuration)),
                                   preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func scheduleRebuild() {
        previewDirty = true               // an edit wants the preview updated; cleared on a completed rebuild
        // During a drag, defer the rebuild to release — rebuilding mid-drag swaps the player item and
        // reseeks repeatedly, which is the "playhead skips around / fights me" behavior.
        if isInteracting { pendingRebuildAfterInteraction = true; return }
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
        defer { debug_rebuildCount += 1 }   // signal completion to the feature audit (any exit path)
        let timelineClips = clips
        let wasPlaying = isPlaying        // a recompose (e.g. deleting a clip) should keep playing
        guard !timelineClips.isEmpty else {
            player.replaceCurrentItem(with: nil); previewDirty = false; return
        }
        // Show "Preparing clips…" ONLY while a clip is genuinely downloading/encoding. A recompose
        // from already-cached windows (deleting a clip, reordering, trimming inside the cached window)
        // leaves every remaining clip .ready, so the overlay never flashes and reviewing stays fluid.
        let overlay = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if self.clips.contains(where: { self.clipPrep[$0.id] == .caching }) { self.isBuildingPreview = true }
        }
        defer { overlay.cancel(); isBuildingPreview = false }

        // Cache clips CONCURRENTLY, bounded (#2) — one slow/failed clip no longer blocks the rest.
        // resolveLocal is @MainActor but suspends at the network/export await, so up to N caches run
        // in flight. A clip that won't cache is marked .failed(reason) and EXCLUDED from the build,
        // so it can't stall playback of the good clips (#13).
        // 6 is the measured sweet spot: node-direct URLs (ClipCache.ProxySource) bypass archive.org's
        // rate-limited /download main host, so parallel byte-range reads hit storage NODES and 6-wide
        // is ~5× faster than the old 2 (20 fresh clips: 86s → ~16s) without tripping the per-IP
        // throttle that starts failing copies above ~10. Tunable for the benchmark (BenchConfig/env).
        let maxConcurrent = BenchConfig.concurrency ?? Int(ProcessInfo.processInfo.environment["AW_CS_CONC"] ?? "") ?? 6
        var resolvedByID: [UUID: CompositionBuilder.ResolvedClip] = [:]
        await withTaskGroup(of: (UUID, CompositionBuilder.ResolvedClip?).self) { group in
            var it = timelineClips.makeIterator()
            func addNext() {
                guard let clip = it.next() else { return }
                group.addTask { [weak self] in
                    guard let self else { return (clip.id, nil) }
                    do { return (clip.id, try await self.resolveLocal(clip)) }
                    catch {
                        // A SUPERSEDED rebuild (a newer one started — transient retry, verify, edit) must
                        // NOT record a stale failure: the current rebuild may have already resolved this
                        // clip to .ready, and a late failure here would stick a false "cannot decode"
                        // banner on a clip that's actually playing. Drop it. Checked via Task.isCancelled
                        // so it ONLY skips genuine cancellation — a per-clip TIMEOUT also surfaces as a
                        // CancellationError (the cache withTimeout deadline) but with Task.isCancelled
                        // FALSE, so it falls through and IS counted: a persistently-stalling clip then
                        // gives up after maxSourceFailures instead of retrying forever (the "waiting
                        // minutes at 50+ clips" hang — a dead -1011 derivative used to never give up).
                        if Task.isCancelled { return (clip.id, nil) }
                        // Already known-permanent: resolveLocal fast-failed and set the real reason —
                        // leave it (don't overwrite with this rebuild's generic error).
                        if await self.isKnownPermanent(clip.sourceURL.absoluteString) { return (clip.id, nil) }
                        let reason = Self.reason(for: error)
                        // Count failures per source: give up (stop re-encoding on every rebuild) only
                        // after REPEATED failures, or a definitively-unrecoverable error. Most errors
                        // are transient (the source plays fine) and a retry succeeds.
                        let permanent = ClipCacheService.isPermanent(error)
                        await self.recordFailure(clip.sourceURL.absoluteString, reason: reason,
                                                 definitelyPermanent: permanent)
                        // Only a genuinely unclippable source (no video track) shows a hard failure;
                        // everything else stays "preparing" and retries — never a stuck red error.
                        if permanent { await self.markFailed(clip.id, reason) }
                        else { await self.markPreparing(clip.id) }
                        return (clip.id, nil)
                    }
                }
            }
            for _ in 0..<maxConcurrent { addNext() }
            // Fill the preview as clips resolve, so the editor is USABLE within seconds and the slow
            // last clips finish in the BACKGROUND (black gaps at their slots until they do) — the
            // preview is NEVER gated on the slowest clip. Re-compose whenever ANY new clip is ready and
            // it's been ≥1.5s since the last swap (owner: clips were "not available until ALL rendered"
            // — a per-batch cadence held the tail back). The 1.5s throttle keeps it from per-clip
            // strobing, and the playhead-stable swap (isSwappingPreview) makes each fill gentle.
            var lastComposeAt = Date(timeIntervalSince1970: 0)
            var composedReals = 0
            while let (id, r) = await group.next() {
                if let r { resolvedByID[id] = r }
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
                let firstShow = composedReals == 0 && !resolvedByID.isEmpty
                // Use "uncomposed reals exist" (not "this completion was a real") so the fill still
                // fires on a straggler's completion that follows freshly-resolved fast clips.
                let haveNew = resolvedByID.count > composedReals
                if firstShow || (haveNew && Date().timeIntervalSince(lastComposeAt) > 2.0) {
                    composedReals = resolvedByID.count
                    lastComposeAt = Date()
                    _ = await composeAndSwap(resolvedByID, timelineClips: timelineClips,
                                             wasPlaying: wasPlaying, maxPollMs: firstShow ? 800 : 200,
                                             markClean: false)
                }
            }
        }
        if Task.isCancelled { return }

        // Clips that didn't resolve this pass and aren't genuinely unclippable (no video track) — they
        // are still "preparing" and will retry. Drive environmental/retry off THIS (resolution), not a
        // hard `.failed` state, so a transient miss never surfaces as a stuck error.
        let retryable = timelineClips.filter {
            resolvedByID[$0.id] == nil && permanentlyFailed[$0.sourceURL.absoluteString] == nil
        }
        // ENVIRONMENTAL outage: NOTHING cached and clips remain → archive.org refusing connections
        // (per-IP rate limit) or you're offline — NOT the clips. Clear streaks so they recover, show a
        // clear "can't reach the server" message, and BACK OFF hard (hammering only prolongs the block).
        let environmental = resolvedByID.isEmpty && !retryable.isEmpty
        if environmental {
            for c in retryable { sourceFailCount[c.sourceURL.absoluteString] = nil }
            previewBlockedReason = retryable.compactMap { sourceFailReason[$0.sourceURL.absoluteString] }
                .first ?? "couldn’t reach archive.org"
            if transientRetries < 4 && !CreationStudioBench.isEnabled {
                transientRetries += 1
                let delay = Double(transientRetries) * 8        // 8s, 16s, 24s, 32s — give the IP time to un-throttle
                transientRetryTask?.cancel()
                transientRetryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    await self?.rebuildPreview()
                }
            }
            return
        }
        previewBlockedReason = nil
        // GIVE UP on a clip that has failed to cache maxSourceFailures times while OTHERS succeeded
        // (so it's that clip/source — a dead derivative or a server returning -1011 — not an outage).
        // Mark it terminally failed so it LEAVES "preparing": otherwise a couple of bad-server clips
        // hold the whole "add 50" in a spinner for minutes (owner: "sometimes it still takes a very
        // long time"). It stays visible (red, retryable); the preview/export use the rest.
        // Give up on count OR wall-clock: a dead clip that the preview + verify passes keep retrying
        // through backoffs can take minutes to hit the count, so a 40s wall-clock cap bounds the tail.
        let givenUp = retryable.filter {
            let src = $0.sourceURL.absoluteString
            if (sourceFailCount[src] ?? 0) >= Self.maxSourceFailures { return true }
            if let t = firstFailAt[src], Date().timeIntervalSince(t) >= Self.maxGiveUpSeconds { return true }
            return false
        }
        for c in givenUp {
            let src = c.sourceURL.absoluteString
            let reason = sourceFailReason[src] ?? "couldn’t load this source"
            permanentlyFailed[src] = reason
            clipPrep[c.id] = .failed(reason)
        }
        // RECONCILE displayed state with what's ACTUALLY in the build, so the overlay + timeline never
        // lie: a clip that resolved is READY (clears any stale/false "cannot decode"), its source is no
        // longer considered failed, and its TIMELINE length is set to the real playable duration so the
        // blocks + playhead stay locked to the preview (a clip clamped to the film's end was drawn too
        // long, which is the "clip finished but the timeline still shows a second left" drift).
        var durChanged = false
        for c in timelineClips where resolvedByID[c.id] != nil {
            let src = c.sourceURL.absoluteString
            permanentlyFailed[src] = nil; sourceFailCount[src] = nil
            if clipPrep[c.id] != .ready { clipPrep[c.id] = .ready }
            if let actual = clipActualDuration[c.id], actual > 0.05,
               let i = project.timeline.clips.firstIndex(where: { $0.id == c.id }),
               project.timeline.clips[i].sourceRange.duration.seconds - actual > 0.05 {
                let inS = project.timeline.clips[i].sourceRange.start.seconds
                project.timeline.clips[i].sourceRange = TimeRange(startSeconds: inS, durationSeconds: actual)
                durChanged = true
            }
        }
        if durChanged { relayout() }   // realign blocks to the real durations — the composition already matches

        // Auto-retry the remaining TRANSIENT misses (a cold node, a passthrough/re-encode hiccup). Back
        // off (2s/4s/6s) and stop once nothing's left; clips that resolve clear themselves above, and
        // ones that exhausted maxSourceFailures were just marked terminally failed (excluded here).
        // The bench retries too (it used to be disabled, which left stragglers stuck .caching forever
        // — they now accumulate failures and give up, so the run terminates as the real app does).
        let failedIDs = retryable.filter { permanentlyFailed[$0.sourceURL.absoluteString] == nil }
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
        // FINAL build — every clip in timeline order, GAPS reserving the slots of any that failed/
        // didn't resolve, so the composition is positionally 1:1 with the timeline (the playhead
        // always lands on the clip the timeline shows; a missing clip is black at its slot, never a
        // shifted neighbour). Uses the post-reconcile `clips` so clamped durations are reflected.
        _ = await composeAndSwap(resolvedByID, timelineClips: clips,
                                 wasPlaying: wasPlaying, maxPollMs: 4000, markClean: true)
    }

    /// Build the composition from `resolvedByID` — reserving a black GAP for every clip not yet
    /// resolved, so composition time == timeline time and the preview matches the timeline 1:1 — and
    /// swap it into the player, preserving the playhead. `maxPollMs` is how long to wait for the new
    /// item to become ready before seeking (a longer wait on the final build so the first frame
    /// displays; a short wait on progressive builds so they don't stall resolution). `markClean`
    /// clears `previewDirty` (only the final build, which fully reflects the current timeline).
    @discardableResult
    private func composeAndSwap(_ resolvedByID: [UUID: CompositionBuilder.ResolvedClip],
                                timelineClips: [TimelineClip], wasPlaying: Bool,
                                maxPollMs: Int, markClean: Bool) async -> Bool {
        // Reserve EVERY clip's slot: its resolved footage, else a black gap of its timeline duration.
        let resolved: [CompositionBuilder.ResolvedClip] = timelineClips.map {
            resolvedByID[$0.id] ?? .gap(seconds: $0.sourceRange.duration.seconds)
        }
        guard resolved.contains(where: { !$0.isGap }) else { return false }   // nothing real yet → keep current
        // Do NOT swap the player item while it is actively PLAYING — replaceCurrentItem interrupts
        // playback and restarts the new item from 0 (owner: "as each clip loads the playhead jumps back
        // to the beginning"). Defer the fill: keep playing through the not-yet-rendered clips (black
        // gaps) and mark the preview dirty; a catch-up rebuild runs when playback stops (pause/end). The
        // very first compose (no current item yet) always proceeds.
        if isPlaying, player.currentItem != nil { previewDirty = true; return false }
        // bakeOverlays:false — the Core Animation overlay tool is offline-only (crashes AVPlayerItem).
        // Same clip/reframe/audio recipe as export, so the preview frame matches.
        let credit = project.burnAttribution ? ExportService.defaultCredit : nil
        do {
            let built = try await CompositionBuilder.build(
                resolved: resolved, timeline: project.timeline,
                creditLine: credit, bakeOverlays: false, beds: resolvedBeds())
            guard !Task.isCancelled else { return false }
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            item.preferredForwardBufferDuration = 8
            player.automaticallyWaitsToMinimizeStalling = true
            // Hold the playhead the user is at across the swap: capture it BEFORE replacing the item,
            // and suppress the time observer (isSwappingPreview) so the new item's transient currentTime
            // 0 can't overwrite it. We restore EXACTLY here, so the playhead never snaps to the start.
            let target = CMTime(seconds: min(playheadSeconds, totalDuration), preferredTimescale: 600)
            isSwappingPreview = true
            defer { isSwappingPreview = false }
            player.replaceCurrentItem(with: item)
            debug_swapCount += 1
            // Seek ONCE the item is ready, so the first frame actually decodes + displays (a seek
            // issued before .readyToPlay is dropped, leaving the monitor black until a manual scrub).
            let polls = max(1, maxPollMs / 25)
            for _ in 0..<polls {
                if item.status != .unknown { break }       // ready OR failed — stop waiting
                if Task.isCancelled { return false }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled, player.currentItem === item, item.status == .readyToPlay else { return false }
            if markClean { previewDirty = false }   // the preview now reflects the current timeline
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            // Keep playing across the swap, unless the playhead is now past the (shortened) timeline.
            if wasPlaying, target.seconds < totalDuration - 0.05 { player.play() }
            return true
        } catch {
            return false   // leave the previous preview in place on a transient build failure
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
        // A source that already failed to ENCODE can't be fixed by retrying — fail fast without
        // re-attempting the (expensive, doomed) re-encode on this and every future rebuild.
        if let reason = permanentlyFailed[clip.sourceURL.absoluteString] {
            clipPrep[clip.id] = .failed(reason)
            throw CreationStudioError.cannotCreateExportSession
        }
        // A source that's been failing past the wall-clock deadline is given up HERE (no further 25s
        // attempt) so the dead clip becomes a gap promptly instead of re-attempting every rebuild.
        let srcKey = clip.sourceURL.absoluteString
        if let t = firstFailAt[srcKey], Date().timeIntervalSince(t) >= Self.maxGiveUpSeconds {
            let reason = sourceFailReason[srcKey] ?? "took too long to load"
            permanentlyFailed[srcKey] = reason
            clipPrep[clip.id] = .failed(reason)
            throw CreationStudioError.cannotCreateExportSession
        }
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
            let bench = CreationStudioBench.isEnabled
            if bench { CreationStudioBench.mark("clip \(clip.catalogItemID) proxy-resolve-start") }
            // PREVIEW uses a small proxy derivative (≈10× less to download); export keeps full quality.
            let previewSrc = await ProxySource.proxyURL(archiveID: clip.catalogItemID, fallback: clip.sourceURL)
            if bench { CreationStudioBench.mark("clip \(clip.catalogItemID) proxy=\(previewSrc.lastPathComponent) cache-start") }
            let url = try await CacheCoordinator.window(
                catalogItemID: clip.catalogItemID, sourceURL: previewSrc,
                startSeconds: wStart, endSeconds: wEnd,
                attempts: 1, timeout: Self.proxyCacheTimeout)   // small proxy → fail a stall fast (see refineWindow)
            if bench { CreationStudioBench.mark("clip \(clip.catalogItemID) cached") }
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
        CreationStudioBench.noteReady()                        // bench: time-to-first-clip
        noteSourceSucceeded(clip.sourceURL.absoluteString)    // clear any prior failure streak
        let graded = await gradedAssetURL(clip, window: w)   // bakes the Look (or passes through)
        ensureThumbnails(clip, window: w)
        let resolved = makeResolved(clip, window: w, assetURL: graded)
        // Record the ACTUAL playable duration (clamped to the footage the cache holds). When a clip's
        // out-point runs past the film's end the composition is SHORTER than the clip's requested
        // length — rebuildPreview reconciles the timeline to this so the blocks + playhead match the
        // preview instead of drifting a second or two per clamped clip.
        clipActualDuration[clip.id] = resolved.insertRange.duration.seconds
        return resolved
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
    func pause() {
        player.pause(); isPlaying = false
        // Catch the preview up to the timeline if clip fills were deferred while playing.
        if previewDirty { scheduleRebuild() }
    }

    func seek(toSeconds s: Double) {
        let clamped = min(max(0, s), max(0, totalDuration))
        playheadSeconds = clamped
        let t = CMTime(seconds: clamped, preferredTimescale: 600)
        if isInteracting {
            // Scrubbing: tolerant seeks decode fast and keep up with the drag. Zero-tolerance seeks
            // queue up exact-frame decodes that lag behind the cursor and make the playhead jump
            // ("skips around"). endInteraction settles on the exact frame.
            let tol = CMTime(seconds: 0.2, preferredTimescale: 600)
            player.seek(to: t, toleranceBefore: tol, toleranceAfter: tol)
        } else {
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func zoom(by factor: Double, focusSeconds: Double? = nil) {
        pointsPerSecond = min(Self.maxPPS, max(Self.minPPS, pointsPerSecond * factor))
    }

    // MARK: - Audio clips (#4 audio layers — N music + voiceover tracks, Rule 3c)

    var audioClips: [AudioClip] { project.timeline.audioClips }
    var selectedAudio: AudioClip? { selectedAudioID.flatMap { id in audioClips.first { $0.id == id } } }
    private func audioIndex(_ id: UUID) -> Int? {
        project.timeline.audioClips.firstIndex { $0.id == id }
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
        project.timeline.audioClips.append(clip)
        selection = .audio(clip.id)
        loadAudioDuration(clip.id)
        scheduleRebuild()
    }

    func setAudioVolume(_ id: UUID, _ v: Double) {
        guard let i = audioIndex(id) else { return }
        project.timeline.audioClips[i].volume = max(0, min(1.5, v))
        scheduleRebuild()
    }
    func setAudioStart(_ id: UUID, _ seconds: Double) {
        guard let i = audioIndex(id) else { return }
        project.timeline.audioClips[i].startSeconds = max(0, seconds)
        scheduleRebuild()
    }
    func setAudioFade(_ id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let i = audioIndex(id) else { return }
        let dur = max(0.1, project.timeline.audioClips[i].sourceDuration)
        if let fadeIn  { project.timeline.audioClips[i].fadeInSeconds  = max(0, min(fadeIn,  dur)) }
        if let fadeOut { project.timeline.audioClips[i].fadeOutSeconds = max(0, min(fadeOut, dur)) }
        scheduleRebuild()
    }
    func renameAudio(_ id: UUID, _ name: String) {
        guard let i = audioIndex(id) else { return }
        project.timeline.audioClips[i].displayName = name
    }
    func removeAudio(_ id: UUID) {
        guard let i = audioIndex(id) else { return }
        let clip = project.timeline.audioClips[i]
        try? FileManager.default.removeItem(at: ProjectMediaCache.directory.appendingPathComponent(clip.fileName))
        checkpoint()
        project.timeline.audioClips.remove(at: i)
        if selectedAudioID == id { selection = .none }
        scheduleRebuild()
    }

    /// Fill an audio clip's cached `sourceDuration` from the file (async — for the timeline block
    /// width + the fade clamps).
    private func loadAudioDuration(_ id: UUID) {
        guard let i = audioIndex(id) else { return }
        let url = ProjectMediaCache.directory.appendingPathComponent(project.timeline.audioClips[i].fileName)
        Task { [weak self] in
            let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard let self, let j = self.audioIndex(id) else { return }
            self.project.timeline.audioClips[j].sourceDuration = dur
        }
    }

    /// Every audio clip resolved for the composition (music + voiceover, each its own track).
    func resolvedBeds() -> [CompositionBuilder.ResolvedMusic] {
        project.timeline.audioClips.compactMap { clip in
            let url = ProjectMediaCache.directory.appendingPathComponent(clip.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return .init(asset: AVURLAsset(url: url), volume: clip.volume, startSeconds: clip.startSeconds,
                         maxDuration: clip.sourceDuration > 0 ? clip.sourceDuration : nil,
                         fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds)
        }
    }

    // MARK: - Voiceover recording (set up in the inspector, then record; adds a NEW voiceover clip)

    /// idle → armed (inspector setup: pick a mic) → recording. The toolbar/inspector drive this so
    /// the Stop control is always visible while recording, and you choose the input BEFORE you start
    /// (owner #9). Recording uses AVCaptureSession + AVCaptureAudioFileOutput — the only macOS way to
    /// record from a CHOSEN device (AVAudioRecorder only ever uses the system default input).
    enum VoiceoverPhase: Equatable { case idle, armed, recording }
    var voiceoverPhase: VoiceoverPhase = .idle
    var isRecordingVoiceover: Bool { voiceoverPhase == .recording }
    /// Surfaced so a failed recording isn't silent.
    var voiceoverError: String?
    struct AudioInput: Identifiable, Hashable, Sendable { let id: String; let name: String }
    var audioInputs: [AudioInput] = []
    var selectedAudioInputID: String?

    @ObservationIgnored private var captureSession: AVCaptureSession?
    @ObservationIgnored private var audioFileOutput: AVCaptureAudioFileOutput?
    @ObservationIgnored private var voiceDelegate: VoiceoverDelegate?
    @ObservationIgnored private var voiceStartSeconds = 0.0
    @ObservationIgnored private var voicePendingName = ""

    /// Open the voiceover setup in the inspector (does NOT start recording — owner #9).
    func armVoiceover() {
        voiceoverError = nil
        refreshAudioInputs()
        selection = .none           // show the project inspector, where the panel lives
        voiceoverPhase = .armed
    }

    /// Close the panel without recording.
    func cancelVoiceover() {
        teardownCapture()
        voiceoverPhase = .idle
    }

    /// Enumerate the available microphones / audio inputs for the picker.
    func refreshAudioInputs() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        audioInputs = discovery.devices.map { AudioInput(id: $0.uniqueID, name: $0.localizedName) }
        if selectedAudioInputID == nil || !audioInputs.contains(where: { $0.id == selectedAudioInputID }) {
            selectedAudioInputID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? audioInputs.first?.id
        }
    }

    /// Begin recording from the SELECTED input at the playhead.
    func startVoiceover() { Task { await beginCapture() } }

    private func beginCapture() async {
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
        let device = selectedAudioInputID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
        guard let device else { voiceoverError = "No microphone available."; return }
        let session = AVCaptureSession()
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            voiceoverError = "Couldn't open \(device.localizedName)."; return
        }
        session.addInput(input)
        let output = AVCaptureAudioFileOutput()
        guard session.canAddOutput(output) else { voiceoverError = "Couldn't start recording."; return }
        session.addOutput(output)
        session.startRunning()

        let name = "voiceover-\(UUID().uuidString.prefix(6)).m4a"
        let url = ProjectMediaCache.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let delegate = VoiceoverDelegate()
        output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: delegate)
        captureSession = session; audioFileOutput = output; voiceDelegate = delegate
        voiceStartSeconds = playheadSeconds; voicePendingName = name
        voiceoverPhase = .recording
    }

    /// Stop — the clip is added only once the file is finalized (the capture delegate), so its
    /// duration loads correctly.
    func stopVoiceover() {
        guard voiceoverPhase == .recording, let output = audioFileOutput else { return }
        voiceoverPhase = .idle
        voiceDelegate?.onFinish = { [weak self] url, error in
            Task { @MainActor in self?.finishVoiceover(url: url, error: error) }
        }
        output.stopRecording()
    }

    @MainActor private func finishVoiceover(url: URL, error: Error?) {
        teardownCapture()
        if let error { voiceoverError = "Recording failed: \(error.localizedDescription)"; return }
        checkpoint()
        let clip = AudioClip(kind: .voiceover, fileName: url.lastPathComponent, displayName: "Voiceover",
                             volume: 1.0, startSeconds: voiceStartSeconds)
        project.timeline.audioClips.append(clip)
        selection = .audio(clip.id)
        loadAudioDuration(clip.id)
        scheduleRebuild()
    }

    private func teardownCapture() {
        captureSession?.stopRunning()
        captureSession = nil; audioFileOutput = nil; voiceDelegate = nil
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
        let r = project.timeline.renderSize
        return Self.canvasPresets.first { $0.width == r.width && $0.height == r.height }
            ?? CanvasPreset(name: "Custom", width: r.width, height: r.height, isCustom: true)
    }
    func setRenderSize(_ s: RenderSize) {
        guard project.timeline.renderSize != s else { return }
        checkpoint()
        project.timeline.renderSize = s
        scheduleRebuild()
    }
    func setFrameRate(_ fps: Double) {
        guard project.timeline.frameRate != fps else { return }
        project.timeline.frameRate = max(1, fps)
        scheduleRebuild()
    }

    // MARK: - Markers (navigation + snap targets)

    var markers: [Double] { project.timeline.markers }

    /// Toggle a marker at the playhead (remove if one is within 0.3s, else add). M key.
    func toggleMarkerAtPlayhead() {
        let t = playheadSeconds
        if let i = project.timeline.markers.firstIndex(where: { abs($0 - t) < 0.3 }) {
            project.timeline.markers.remove(at: i)
        } else {
            project.timeline.markers.append(t)
            project.timeline.markers.sort()
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
    var frameStep: Double { 1.0 / max(1, project.timeline.frameRate) }

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
    ///
    /// `excludingNear` drops any target sitting on a given position (within tolerance). A trim
    /// handle STARTS ON a clip edge — the left handle's rest position IS the previous clip's end —
    /// so without this it snaps right back to that edge on every small move, making the beginning
    /// of a clip impossible to fine-tune (the "sticky left-trim"). Excluding the rest position keeps
    /// snapping to edges you drag TOWARD while freeing the handle from the one it sits on.
    func snap(_ seconds: Double, excluding excludeID: UUID? = nil, tolerancePoints: Double = 8,
              excludingNear rest: Double? = nil) -> Double {
        let tol = tolerancePoints / max(1, pointsPerSecond)
        var best = seconds, bestD = tol
        var stops: [Double] = markers + [0, playheadSeconds]
        for c in clips where c.id != excludeID {
            stops.append(c.timelineStart.seconds)
            stops.append(c.timelineRange.endSeconds)
        }
        for s in stops where abs(s - seconds) < bestD {
            if let rest, abs(s - rest) < tol { continue }   // skip the edge the handle rests on
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
            // GATE the cosmetic filmstrip work (strip + thumbnail fetches all hit archive.org's
            // MAIN host). A large add (e.g. 68 clips) otherwise fires hundreds of main-host requests
            // at once, which STARVES the window pipeline's proxy-metadata resolution (same host) and
            // trips the per-IP rate limit (-1001 timeouts → -1004). Bounding the producer keeps the
            // queue shallow so clips actually cache. Filmstrips fill in progressively.
            await Self.filmstripGate.acquire()
            await self.buildFilmstrip(id: id, catID: catID, url: url, inS: inS, outS: outS)
            await Self.filmstripGate.release()
        }
    }

    /// Bounds concurrent filmstrip strip+thumbnail fetches to the MAIN archive.org host (shared
    /// across all clips) so a big batch can't flood it. Reuses the generic limiter (a counting
    /// semaphore); separate INSTANCE from the window ReencodeLimiter so the two don't share slots.
    static let filmstripGate = ReencodeLimiter(3)

    private func buildFilmstrip(id: UUID, catID: String, url: URL, inS: Double, outS: Double) async {
        let strip: [ArchiveThumb]
        if let cached = archiveStrips[catID] { strip = cached }
        else { let s = await ArchiveThumbnails.strip(for: url); archiveStrips[catID] = s; strip = s }
        guard !strip.isEmpty else { return }
        var picks = strip.filter { $0.seconds >= inS - 1 && $0.seconds <= outS + 1 }
        if picks.isEmpty, let n = strip.min(by: { abs($0.seconds - inS) < abs($1.seconds - inS) }) { picks = [n] }
        if picks.count > 12 {                                  // cap a long clip's strip
            let step = Double(picks.count - 1) / 11
            picks = (0..<12).map { picks[min(picks.count - 1, Int((Double($0) * step).rounded()))] }
        }
        var imgs: [CGImage] = []
        for t in picks {
            if let c = thumbImageCache[t.url] { imgs.append(c) }
            else if let img = await Self.downloadThumb(t.url) { thumbImageCache[t.url] = img; imgs.append(img) }
        }
        if !imgs.isEmpty, !Task.isCancelled { thumbnails[id] = imgs }
    }

    private nonisolated static func downloadThumb(_ url: URL) async -> CGImage? {
        guard let data = await StudioNet.data(from: url),   // capped session — share the studio's bounded pool
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

// Bridges AVCaptureAudioFileOutput's recording-finished callback back to the model so the clip is
// added only once the file is fully written. @unchecked Sendable: the only escape is the onFinish
// closure, which hops to the MainActor.
final class VoiceoverDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    var onFinish: ((URL, Error?) -> Void)?
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        onFinish?(outputFileURL, error)
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
