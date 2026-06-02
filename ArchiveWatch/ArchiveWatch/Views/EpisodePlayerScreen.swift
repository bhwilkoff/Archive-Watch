import SwiftUI
import AVKit
import SwiftData

// Full-screen episode player with prev/next transport.
//
// Owns its own `currentEpisode` state so the parent SeriesDetailView
// can present it once and let the user walk the entire series without
// dismiss/re-present cycles. Keeps per-episode watch progress in
// SwiftData (keyed on the episode's archiveID, same as film-side).
//
// When the user presses the up arrow on the Siri Remote, AVPlayerVC's
// own overlay surfaces — no need for us to render custom transport
// ourselves. Instead we overlay compact prev/next buttons as peer
// controls so they're reachable without pausing.

struct EpisodePlayerScreen: View {
    let series: Series
    let initialEpisode: Episode

    @State private var currentEpisode: Episode
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    init(series: Series, initialEpisode: Episode) {
        self.series = series
        self.initialEpisode = initialEpisode
        _currentEpisode = State(initialValue: initialEpisode)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                // AVPlayerViewController (same as the film player) — robust on
                // tvOS and shows a native buffering spinner while large Archive
                // MP4s load (8-15s for some), so a slow start doesn't read as a
                // black "doesn't load". Its native transport + our end-of-item
                // observer (auto-advance) cover prev/next.
                AVPlayerContainer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .onAppear { setupPlayer(for: currentEpisode) }
        .onDisappear { teardownPlayer(finalPersist: true) }
        .onChange(of: currentEpisode) { _, new in
            teardownPlayer(finalPersist: true)
            setupPlayer(for: new)
        }
    }

    // MARK: - Player lifecycle

    private func setupPlayer(for episode: Episode) {
        guard let url = episode.videoURLParsed else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        // Seek to last-known progress for this particular episode
        let archiveID = episode.archiveID
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID }
        )
        if let existing = try? modelContext.fetch(descriptor).first,
           existing.positionSeconds > 10,
           !existing.isComplete {
            p.seek(to: CMTime(seconds: existing.positionSeconds, preferredTimescale: 600))
        }

        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        let seriesID = series.seriesID
        let episodeTitle = episode.title
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                persistProgress(at: time.seconds,
                                duration: p.currentItem?.duration.seconds,
                                for: archiveID,
                                seriesID: seriesID,
                                episodeTitle: episodeTitle)
            }
        }

        // Auto-advance when the current item finishes.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main,
        ) { _ in
            Task { @MainActor in
                if let next = series.episode(after: episode) {
                    currentEpisode = next
                }
            }
        }
    }

    private func teardownPlayer(finalPersist: Bool) {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if finalPersist, let p = player {
            persistProgress(at: p.currentTime().seconds,
                            duration: p.currentItem?.duration.seconds,
                            for: currentEpisode.archiveID,
                            seriesID: series.seriesID,
                            episodeTitle: currentEpisode.title)
        }
        player?.pause()
        player = nil
        timeObserver = nil
    }

    private func persistProgress(at position: Double, duration: Double?,
                                 for archiveID: String,
                                 seriesID: String,
                                 episodeTitle: String) {
        guard position.isFinite, position > 0 else { return }
        let descriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate<WatchProgress> { $0.archiveID == archiveID }
        )
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.positionSeconds = position
                if let d = duration, d.isFinite, d > 0 { existing.durationSeconds = d }
                existing.lastWatchedAt = Date()
                existing.seriesID = seriesID
                existing.episodeTitle = episodeTitle
            } else {
                let record = WatchProgress(
                    archiveID: archiveID,
                    positionSeconds: position,
                    durationSeconds: duration ?? 0,
                    seriesID: seriesID,
                    episodeTitle: episodeTitle,
                )
                modelContext.insert(record)
            }
            try? modelContext.save()
        } catch {}
    }
}
