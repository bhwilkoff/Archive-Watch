#if os(iOS)
import SwiftUI
import AVKit
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

    /// Play a movie/standalone item. Pass `store` to enable movie autoplay
    /// (gated by `store.autoplayMode`; .off means play just this one).
    init(item: Catalog.Item, autoplayIn store: AppStore? = nil) {
        archiveID = item.archiveID
        videoURL = item.videoURLParsed
        queue = store.map { MovieAutoplayQueue(start: item, store: $0) }
    }
    /// Play a TV episode. Pass `series` to binge-advance to the next episode on end.
    init(episode: Episode, in series: Series? = nil) {
        archiveID = episode.archiveID
        videoURL = episode.videoURLParsed
        queue = series.map { EpisodeQueue(series: $0, start: episode) }
    }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(archiveID: archiveID, ctx: ctx, queue: queue) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        guard let url = videoURL else { return vc }

        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        context.coordinator.loader = loader   // retain (delegate is held weakly)
        let pItem = AVPlayerItem(asset: asset)
        pItem.preferredForwardBufferDuration = 300
        let player = AVPlayer(playerItem: pItem)
        vc.player = player
        context.coordinator.observe(player, item: pItem)

        // Resume.
        if let p = context.coordinator.savedProgress(), p > 10 {
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
    final class Coordinator {
        private(set) var archiveID: String
        let ctx: ModelContext
        let queue: PlaybackQueue?
        var loader: ResilientStreamLoader?
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private weak var player: AVPlayer?

        init(archiveID: String, ctx: ModelContext, queue: PlaybackQueue?) {
            self.archiveID = archiveID; self.ctx = ctx; self.queue = queue
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
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: nxt.url)
            self.loader = loader
            let item = AVPlayerItem(asset: asset)
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
            guard let player, let cur = player.currentItem else { return }
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
        }
    }
}

// MARK: - Playback queues (what plays next)

@MainActor
protocol PlaybackQueue: AnyObject {
    /// The next item to play after `archiveID` finishes, or nil to stop.
    func next(afterFinishing archiveID: String) -> (id: String, url: URL)?
}

/// Movie continuous play: delegates to the shared ContinuousPlayback engine using
/// the user's AutoplayMode. Returns nil when the mode is .off.
@MainActor
final class MovieAutoplayQueue: PlaybackQueue {
    private let store: AppStore
    private var current: Catalog.Item
    init(start: Catalog.Item, store: AppStore) { self.current = start; self.store = store }

    func next(afterFinishing _: String) -> (id: String, url: URL)? {
        guard let n = ContinuousPlayback.next(after: current, mode: store.autoplayMode, store: store),
              let u = n.videoURLParsed else { return nil }
        current = n
        return (n.archiveID, u)
    }
}

/// Episode binge: the next canonical episode in the series, or nil at the finale.
@MainActor
final class EpisodeQueue: PlaybackQueue {
    private let series: Series
    private var current: Episode
    init(series: Series, start: Episode) { self.series = series; self.current = start }

    func next(afterFinishing _: String) -> (id: String, url: URL)? {
        guard let n = series.episode(after: current), let u = n.videoURLParsed else { return nil }
        current = n
        return (n.archiveID, u)
    }
}

#endif
