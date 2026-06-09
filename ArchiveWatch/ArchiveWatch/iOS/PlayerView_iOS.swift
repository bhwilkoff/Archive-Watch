#if os(iOS)
import SwiftUI
import AVKit
import SwiftData

// Touch-native player: AVPlayerViewController (free transport, scrubber, AirPlay,
// PiP) built on the SHARED Core `ResilientStreamLoader` (Decision 021) so Archive's
// idle-connection resets are handled identically to tvOS. Resumes from + persists
// WatchProgress (SwiftData), which syncs to the Apple TV via CloudKit.
struct PlayerView: UIViewControllerRepresentable {
    let archiveID: String
    let videoURL: URL?

    /// Play a movie/standalone item.
    init(item: Catalog.Item) {
        archiveID = item.archiveID
        videoURL = item.videoURLParsed
    }
    /// Play a TV episode (its own archiveID → its own WatchProgress / resume).
    init(episode: Episode) {
        archiveID = episode.archiveID
        videoURL = episode.videoURLParsed
    }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(archiveID: archiveID, ctx: ctx) }

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
        let archiveID: String
        let ctx: ModelContext
        var loader: ResilientStreamLoader?
        private var timeObserver: Any?
        private weak var player: AVPlayer?

        init(archiveID: String, ctx: ModelContext) { self.archiveID = archiveID; self.ctx = ctx }

        func observe(_ player: AVPlayer, item playerItem: AVPlayerItem) {
            self.player = player
            // Persist progress every 10s so resume survives a crash, not just dismiss.
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
                self?.persist(player)
            }
        }

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

        deinit { if let t = timeObserver { player?.removeTimeObserver(t) } }
    }
}

#endif
