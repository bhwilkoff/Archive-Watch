#if os(iOS)
import SwiftUI
import AVKit
import AVFoundation
import SwiftData

// Touch-native player: AVPlayerViewController (free transport, scrubber, AirPlay,
// PiP) built on the SHARED Core `ResilientStreamLoader` (Decision 021) so Archive's
// idle-connection resets are handled identically to tvOS. Resumes from + persists
// WatchProgress (SwiftData), which syncs to the Apple TV via CloudKit.
//
// Continuous play (#10 / F4): an optional `PlaybackQueue` supplies the next item to
// play when the current one ends. The Coordinator swaps it in on the SAME AVPlayer
// (`replaceCurrentItem`) so playback is seamless — episodes binge-advance, movies
// autoplay per the user's AutoplayMode (off → queue returns nil → stops).
struct PlayerView: UIViewControllerRepresentable {
    let archiveID: String
    let videoURL: URL?
    let queue: PlaybackQueue?
    // Shown in the title+description overlay that fades with the transport
    // controls (AVPlayerViewController shows no title on iOS, so this overlay is
    // the only place the user sees what's playing).
    var overlayTitle: String = ""
    var overlayDescription: String? = nil

    /// Play a movie/standalone item. Pass `store` to enable movie autoplay
    /// (gated by `store.autoplayMode`; .off means play just this one).
    init(item: Catalog.Item, autoplayIn store: AppStore? = nil) {
        archiveID = item.archiveID
        videoURL = item.videoURLParsed
        queue = store.map { MovieAutoplayQueue(start: item, store: $0) }
        overlayTitle = item.title
        overlayDescription = item.synopsis
    }
    /// Play a TV episode. Pass `series` to binge-advance to the next episode on
    /// end; `onAdvance` reports the new archiveID so a host view's episode state
    /// stays truthful (manual prev/next relies on it).
    init(episode: Episode, in series: Series? = nil, onAdvance: ((String) -> Void)? = nil) {
        archiveID = episode.archiveID
        videoURL = episode.videoURLParsed
        queue = series.map { EpisodeQueue(series: $0, start: episode) }
        self.onAdvance = onAdvance
        overlayTitle = episode.title
        overlayDescription = episode.overview
    }

    /// Tune into a channel lineup (programs + woven commercials), starting the
    /// first item at `startOffset` (join-in-progress, #92) and playing straight
    /// through. Channel playback ignores per-title resume — live TV doesn't.
    init?(lineup: [Catalog.Item], startOffset: TimeInterval) {
        guard let first = lineup.first(where: { $0.videoURLParsed != nil }) else { return nil }
        archiveID = first.archiveID
        videoURL = first.videoURLParsed
        queue = LineupQueue(lineup: lineup, startAt: first.archiveID)
        self.startOffset = startOffset
        persistsProgress = false   // live TV: no resume, no Watched pollution
        overlayTitle = first.title
        overlayDescription = first.synopsis
    }

    private var onAdvance: ((String) -> Void)? = nil
    private var startOffset: TimeInterval? = nil
    private var persistsProgress = true

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(archiveID: archiveID, ctx: ctx, queue: queue, onAdvance: onAdvance,
                    persistsProgress: persistsProgress)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.delegate = context.coordinator
        context.coordinator.playerVC = vc

        // iOS/iPadOS REQUIRE an active .playback audio session or AVPlayer
        // frequently fails to start, stalls, or plays silently — especially with
        // our custom resource loader (Decision 021) or when the ringer is silent.
        // tvOS doesn't need this; this is the main iOS-vs-tvOS playback gap.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let url = videoURL else { return vc }

        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        context.coordinator.loader = loader   // retain (delegate is held weakly)
        let pItem = AVPlayerItem(asset: asset)
        // Native title+description: AVPlayerViewController renders externalMetadata
        // in its own chrome, shown/hidden WITH the transport controls (the Apple TV
        // app's behavior). This replaces a custom overlay — it's controls-synced
        // for free and survives load.
        pItem.externalMetadata = playerExternalMetadata(title: overlayTitle, description: overlayDescription)
        pItem.preferredForwardBufferDuration = 300
        let player = AVPlayer(playerItem: pItem)
        vc.player = player
        context.coordinator.observe(player, item: pItem)
        PlaybackDiag.attach(item: pItem, player: player)   // no-op unless AW_PLAYBACK_DIAG=1

        // Channel join-in-progress beats per-title resume; otherwise resume.
        if let so = startOffset {
            if so > 5 { player.seek(to: CMTime(seconds: so, preferredTimescale: 600)) }
        } else if let p = context.coordinator.savedProgress(), p > 10 {
            player.seek(to: CMTime(seconds: p, preferredTimescale: 600))
        }
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.persist(vc.player)
        vc.player?.pause()
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private(set) var archiveID: String
        let ctx: ModelContext
        let queue: PlaybackQueue?
        let onAdvance: ((String) -> Void)?
        let persistsProgress: Bool
        var loader: ResilientStreamLoader?
        weak var playerVC: AVPlayerViewController?
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?
        private var isPiPActive = false
        private weak var player: AVPlayer?

        init(archiveID: String, ctx: ModelContext, queue: PlaybackQueue?,
             onAdvance: ((String) -> Void)? = nil, persistsProgress: Bool = true) {
            self.archiveID = archiveID; self.ctx = ctx; self.queue = queue
            self.onAdvance = onAdvance
            self.persistsProgress = persistsProgress
        }

        func observe(_ player: AVPlayer, item playerItem: AVPlayerItem) {
            self.player = player
            // Persist progress every 10s so resume survives a crash, not just dismiss.
            // The observer fires on the main queue, so assumeIsolated is safe and
            // keeps us out of Swift 6's nonisolated-capture warnings.
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.persistCurrent() }
            }
            registerEnd(for: playerItem)

            // Background play: AVKit pauses any player it is DISPLAYING when the
            // app backgrounds. The supported way to keep audio running (with the
            // `audio` background mode + .playback session) is to detach the player
            // from the view controller on background and reattach on foreground.
            // Skipped while PiP owns the video — detaching would kill the PiP window.
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil,
                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            }
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil,
                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            }
        }

        private func enterBackground() {
            guard !isPiPActive, let vc = playerVC, vc.player != nil else { return }
            persist(player)
            vc.player = nil
        }

        private func enterForeground() {
            guard let vc = playerVC, vc.player == nil, let player else { return }
            vc.player = player
        }

        // MARK: AVPlayerViewControllerDelegate (PiP lifecycle)

        func playerViewControllerWillStartPictureInPicture(_ vc: AVPlayerViewController) {
            isPiPActive = true
        }

        func playerViewControllerDidStopPictureInPicture(_ vc: AVPlayerViewController) {
            isPiPActive = false
        }

        // The full-screen player stays in the hierarchy while PiP runs, so
        // restoring from the PiP window is just "show it again".
        func playerViewController(
            _ vc: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        /// On end-of-item: persist (marks it complete) and, if a queue supplies a
        /// next item, swap it onto the same player without re-presenting.
        private func registerEnd(for item: AVPlayerItem) {
            if let e = endObserver { NotificationCenter.default.removeObserver(e) }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
        }

        private func advance() {
            persist(player)   // captures end position → WatchProgress marks complete
            guard let player, let nxt = queue?.next(afterFinishing: archiveID) else { return }
            archiveID = nxt.id
            onAdvance?(nxt.id)
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: nxt.url)
            self.loader = loader
            let item = AVPlayerItem(asset: asset)
            item.externalMetadata = playerExternalMetadata(title: nxt.title, description: nxt.description)
            item.preferredForwardBufferDuration = 300
            player.replaceCurrentItem(with: item)
            registerEnd(for: item)
            // Resume the next item if it was partially watched before.
            if let p = savedProgress(), p > 10 {
                player.seek(to: CMTime(seconds: p, preferredTimescale: 600))
            }
            player.play()
        }

        /// Persist the player we're holding (avoids capturing an AVPlayer in the
        /// Sendable observer closures).
        func persistCurrent() { persist(player) }

        func savedProgress() -> Double? {
            let id = archiveID
            return (try? ctx.fetch(FetchDescriptor<WatchProgress>(
                predicate: #Predicate { $0.archiveID == id })))?.first?.positionSeconds
        }

        func persist(_ player: AVPlayer?) {
            guard persistsProgress, let player, let cur = player.currentItem else { return }
            let pos = player.currentTime().seconds
            let dur = cur.duration.seconds
            guard pos.isFinite, pos > 0 else { return }
            let id = archiveID
            let existing = (try? ctx.fetch(FetchDescriptor<WatchProgress>(
                predicate: #Predicate { $0.archiveID == id })))?.first
            if let wp = existing {
                wp.positionSeconds = pos
                if dur.isFinite, dur > 0 { wp.durationSeconds = dur }
                wp.lastWatchedAt = Date()
            } else {
                ctx.insert(WatchProgress(archiveID: id, positionSeconds: pos,
                                         durationSeconds: dur.isFinite ? dur : 0))
            }
            try? ctx.save()
        }

        deinit {
            if let t = timeObserver { player?.removeTimeObserver(t) }
            if let e = endObserver { NotificationCenter.default.removeObserver(e) }
            if let b = backgroundObserver { NotificationCenter.default.removeObserver(b) }
            if let f = foregroundObserver { NotificationCenter.default.removeObserver(f) }
        }
    }
}

// MARK: - Native player metadata (title + description in AVKit's chrome)

/// External metadata for the AVPlayerItem so AVPlayerViewController shows the
/// title + description in its OWN controls overlay, synced with the transport
/// (the Apple TV app's behavior). The empty creation-date overrides blank the
/// MP4's bogus embedded year (see tvOS `suppressedDateMetadata`).
private func playerExternalMetadata(title: String, description: String?) -> [AVMetadataItem] {
    func entry(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let m = AVMutableMetadataItem()
        m.identifier = id
        m.value = value as NSString
        m.extendedLanguageTag = "und"
        return m
    }
    var meta = [entry(.commonIdentifierTitle, title)]
    if let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
        meta.append(entry(.commonIdentifierDescription, d))
    }
    let dateBlanks: [AVMetadataItem] = ([
        .commonIdentifierCreationDate, .quickTimeMetadataCreationDate, .quickTimeUserDataCreationDate,
    ] as [AVMetadataIdentifier]).map { id in
        let m = AVMutableMetadataItem()
        m.identifier = id
        m.value = "" as NSString
        m.extendedLanguageTag = "und"
        return m
    }
    return meta.compactMap { $0 } + dateBlanks
}

// MARK: - Playback queues (what plays next)

@MainActor
protocol PlaybackQueue: AnyObject {
    /// The next item to play after `archiveID` finishes, or nil to stop.
    /// Carries title/description so the player's overlay updates on advance.
    func next(afterFinishing archiveID: String) -> (id: String, url: URL, title: String, description: String?)?
}

/// Movie continuous play: delegates to the shared ContinuousPlayback engine using
/// the user's AutoplayMode. Returns nil when the mode is .off.
@MainActor
final class MovieAutoplayQueue: PlaybackQueue {
    private let store: AppStore
    private var current: Catalog.Item
    init(start: Catalog.Item, store: AppStore) { self.current = start; self.store = store }

    func next(afterFinishing _: String) -> (id: String, url: URL, title: String, description: String?)? {
        guard let n = ContinuousPlayback.next(after: current, mode: store.autoplayMode, store: store),
              let u = n.videoURLParsed else { return nil }
        current = n
        return (n.archiveID, u, n.title, n.synopsis)
    }
}

/// Channel lineup: plays the array straight through, skipping unplayable items.
@MainActor
final class LineupQueue: PlaybackQueue {
    private let items: [Catalog.Item]
    private var idx: Int
    init(lineup: [Catalog.Item], startAt archiveID: String) {
        items = lineup
        idx = lineup.firstIndex(where: { $0.archiveID == archiveID }) ?? 0
    }

    func next(afterFinishing _: String) -> (id: String, url: URL, title: String, description: String?)? {
        idx += 1
        while idx < items.count {
            if let u = items[idx].videoURLParsed {
                return (items[idx].archiveID, u, items[idx].title, items[idx].synopsis)
            }
            idx += 1
        }
        return nil
    }
}

/// Episode binge: the next canonical episode in the series, or nil at the finale.
@MainActor
final class EpisodeQueue: PlaybackQueue {
    private let series: Series
    private var current: Episode
    init(series: Series, start: Episode) { self.series = series; self.current = start }

    func next(afterFinishing _: String) -> (id: String, url: URL, title: String, description: String?)? {
        guard let n = series.episode(after: current), let u = n.videoURLParsed else { return nil }
        current = n
        return (n.archiveID, u, n.title, n.overview)
    }
}

#endif
