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
    @State private var overlayVisible = true
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
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            }
            // Compact prev/next + title overlay. tvOS 26 supports focus
            // on overlaid controls; placed in the top-leading safe area
            // so it doesn't fight with AVKit's own transport bar.
            overlay
                .allowsHitTesting(overlayVisible)
                .opacity(overlayVisible ? 1 : 0)
                .animation(Motion.chrome, value: overlayVisible)
        }
        .onAppear { setupPlayer(for: currentEpisode) }
        .onDisappear { teardownPlayer(finalPersist: true) }
        .onChange(of: currentEpisode) { _, new in
            // Re-prepare the player for the new episode. Teardown persists
            // progress for the previous episode first.
            teardownPlayer(finalPersist: true)
            setupPlayer(for: new)
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        VStack {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 12) {
                        if let num = currentEpisode.numberLabel {
                            Text(num)
                                .font(.system(size: 16, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Text(currentEpisode.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    transportButton(
                        systemName: "backward.end.fill",
                        isEnabled: series.episode(before: currentEpisode) != nil,
                    ) {
                        if let prev = series.episode(before: currentEpisode) {
                            currentEpisode = prev
                        }
                    }
                    transportButton(
                        systemName: "forward.end.fill",
                        isEnabled: series.episode(after: currentEpisode) != nil,
                    ) {
                        if let next = series.episode(after: currentEpisode) {
                            currentEpisode = next
                        }
                    }
                }
            }
            .padding(.horizontal, 72)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.9), .black.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom,
                )
                .allowsHitTesting(false),
            )
            Spacer()
        }
    }

    @ViewBuilder
    private func transportButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.3))
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.card)
        .disabled(!isEnabled)
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
