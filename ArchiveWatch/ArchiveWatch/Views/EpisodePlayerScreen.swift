#if os(tvOS)
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

    @Environment(AppStore.self) private var store   // #83: idle-screensaver gate
    @State private var currentEpisode: Episode
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var promptObserver: Any?      // #1: 1s tick to gate the Next-Episode prompt
    @State private var showNextPrompt = false
    @State private var freezeGuard = PlaybackFreezeGuard()
    @State private var nowPlaying = NowPlayingController()
    @State private var streamLoader: ResilientStreamLoader?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var playback: PlaybackState = .loading
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // A genuinely broken item (bad/missing URL, decode failure, or a load
    // that never readies) must not sit on an indefinite spinner — surface a
    // clear, actionable state. (CLAUDE.md: error states must be user-visible.)
    private enum PlaybackState: Equatable {
        case loading
        case ready
        case failed(String)
    }
    // If the item hasn't reached readyToPlay within this window, treat it as
    // failed. Generous: cold Archive nodes can take 8-15s to first frame.
    private let loadTimeout: Duration = .seconds(30)

    init(series: Series, initialEpisode: Episode) {
        self.series = series
        self.initialEpisode = initialEpisode
        _currentEpisode = State(initialValue: initialEpisode)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if case .failed(let message) = playback {
                failureView(message)
            } else if let player {
                // Episode-aware native player (#9): adds Next/Previous Episode
                // (contextual end-of-episode prompt + transport-bar menu) on top
                // of the native transport. Auto-advance on end still applies.
                EpisodeAVPlayerContainer(
                    player: player,
                    hasPrev: series.episode(before: currentEpisode) != nil,
                    hasNext: series.episode(after: currentEpisode) != nil,
                    showNextPrompt: showNextPrompt,
                    onPrev: { if let p = series.episode(before: currentEpisode) { currentEpisode = p } },
                    onNext: { if let n = series.episode(after: currentEpisode) { currentEpisode = n } }
                )
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .onAppear { store.isPlayingVideo = true; setupPlayer(for: currentEpisode) }
        .onDisappear { store.isPlayingVideo = false; teardownPlayer(finalPersist: true) }
        .onChange(of: currentEpisode) { _, new in
            teardownPlayer(finalPersist: true)
            setupPlayer(for: new)
        }
    }

    // MARK: - Failure state

    @ViewBuilder
    private func failureView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Can't play this episode")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            HStack(spacing: 20) {
                Button {
                    teardownPlayer(finalPersist: false)
                    playback = .loading
                    setupPlayer(for: currentEpisode)
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismiss()
                } label: {
                    Text("Back")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(BarButtonStyle())
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Player lifecycle

    private func setupPlayer(for episode: Episode) {
        guard let url = episode.videoURLParsed else {
            playback = .failed("This episode doesn't have a playable video link.")
            return
        }
        playback = .loading
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        streamLoader = loader
        let item = AVPlayerItem(asset: asset)
        // Show the episode title in the transport, and suppress the MP4's bogus
        // embedded creation year (epoch-0 -> "1969") the same way the movie
        // player does (see suppressedDateMetadata).
        item.externalMetadata =
            [metaEntry(.commonIdentifierTitle, episode.title)].compactMap { $0 }
            + suppressedDateMetadata()
        let p = AVPlayer(playerItem: item)
        tunePlaybackBuffering(item: item, player: p)
        player = p
        freezeGuard.attach(to: p, item: item)
        nowPlaying.begin(posterURL: episode.stillURLParsed ?? series.posterURLParsed,
                         item: item)

        // Watch the item reach readyToPlay or fail, so a broken stream becomes
        // a visible error instead of a forever-spinner. KVO can fire off-main;
        // hop back to the main actor before touching view state.
        statusObserver = item.observe(\.status, options: [.new]) { observed, _ in
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    playback = .ready
                    timeoutTask?.cancel()
                    p.play()   // start on ready — robust across Next/Prev episode
                               // swaps where .onAppear { play() } won't re-fire
                case .failed:
                    let detail = observed.error?.localizedDescription
                        ?? "The video couldn't be loaded."
                    playback = .failed(detail)
                    timeoutTask?.cancel()
                default:
                    break
                }
            }
        }

        // Backstop: if the item never readies (silent stall), fail visibly.
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: loadTimeout)
            guard !Task.isCancelled else { return }
            if playback == .loading {
                playback = .failed("This episode is taking too long to load. The source may be temporarily unavailable.")
            }
        }

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

        let interval = CMTime(seconds: 5, preferredTimescale: 600)
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

        // #1: gate the auto-surfacing Next-Episode prompt to the first 3s + last
        // 15s of the episode (a 1s tick — finer than the 10s progress observer).
        let promptInterval = CMTime(seconds: 1, preferredTimescale: 600)
        promptObserver = p.addPeriodicTimeObserver(forInterval: promptInterval, queue: .main) { time in
            let t = time.seconds
            let d = p.currentItem?.duration.seconds ?? 0
            let show = t < 3 || (d > 0 && d.isFinite && d - t <= 15)
            if show != showNextPrompt { showNextPrompt = show }
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
        if let obs = promptObserver { player?.removeTimeObserver(obs); promptObserver = nil }
        showNextPrompt = false
        freezeGuard.detach()
        nowPlaying.end()
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
        streamLoader = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeoutTask?.cancel()
        timeoutTask = nil
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
            SyncNudge.nudge(modelContext)   // push progress promptly (debounced) for cross-device resume
        } catch {}
    }
}

#endif
