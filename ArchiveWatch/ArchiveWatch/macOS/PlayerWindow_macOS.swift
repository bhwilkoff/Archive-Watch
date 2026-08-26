#if os(macOS)
import SwiftUI
import AVKit
import SwiftData

// Native macOS player: AVPlayerView (AppKit) wrapped in NSViewRepresentable, fed by the
// SHARED ResilientStreamLoader (resume-on-reset + node failover) for MP4 or the native
// HLS master when the title has subtitles. Resume + progress via the SwiftData
// WatchProgress model (same store the other platforms write).
//
// PlayerSurface is the reusable engine; PlayerWindow plays a Catalog.Item and
// EpisodePlayer plays a series Episode with prev/next transport (TV drill-in).

struct PlayerWindow: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        // NavigationStack hosts the native NSToolbar (Done) + window title; the AVPlayerView fills the
        // rest with its OWN native controls (transport, scrubber, volume, PiP, full-screen, speed). No
        // hand-drawn controls.
        NavigationStack {
            PlayerSurface(archiveID: item.archiveID,
                          // Honour the viewer's chosen copy (ArchiveVersions).
                          // Rebuilt from the stored file name, so it costs no
                          // network and cannot delay playback.
                          videoURL: item.videoURLParsed.map {
                              ArchiveVersions.preferredURL(for: item.archiveID, default: $0)
                          },
                          // The sheet's caption-type choice (owner 2026-08-26):
                          // Automatic/Off drop the captioned-HLS wrapper so the
                          // engine (or nothing) captions; File keeps it.
                          subtitleHLS: {
                              let c = CaptionChoiceSession.byItem[item.archiveID]
                              return (c == .automatic || c == .off) ? nil : item.subtitleHLSURL
                          }(),
                          captionsOff: CaptionChoiceSession.byItem[item.archiveID] == .off,
                          publishedVTT: item.publishedVTTURL,
                          onEnded: autoplayNext)
                .navigationTitle(item.year.map { "\(item.title) (\($0))" } ?? item.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { router.nowPlaying = nil } label: { Image(systemName: "xmark") }
                            .keyboardShortcut(.cancelAction).help("Close")
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// When a film ends and Autoplay is on, swap the player to the next title
    /// (router.nowPlaying drives the overlay, so changing it re-presents the player).
    private func autoplayNext() {
        guard store.autoplayMode != .off,
              let next = ContinuousPlayback.next(after: item, mode: store.autoplayMode, store: store)
        else { return }
        router.play(next)
    }
}

// Shared speed control for the macOS players (AVPlayerView has no built-in speed
// menu; the tvOS/iOS AVPlayerViewController does). Drives the player's rate.
struct SpeedMenu: View {
    @Binding var speed: Double
    private let speeds: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]
    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { s in
                Button {
                    speed = s
                } label: {
                    if speed == s { Label(label(s), systemImage: "checkmark") }
                    else { Text(label(s)) }
                }
            }
        } label: { Label("Speed", systemImage: "speedometer") }
        .help("Playback speed")
    }
    private func label(_ s: Double) -> String {
        s == 1.0 ? "Normal" : (s == floor(s) ? "\(Int(s))×" : "\(s)×")
    }
}

// Episode player with manual prev/next (parity §3 "prev/next episode in player").
// Switching recreates the surface via .id, so each episode keeps its own resume
// position; the chevrons live in a small overlay capsule.
struct EpisodePlayer: View {
    let context: EpisodeContext
    @Environment(AppRouter.self) private var router
    @State private var episode: Episode

    init(context: EpisodeContext) {
        self.context = context
        _episode = State(initialValue: context.episode)
    }

    private var series: Series { context.series }
    private var prev: Episode? { series.episode(before: episode) }
    private var next: Episode? { series.episode(after: episode) }

    var body: some View {
        NavigationStack {
            PlayerSurface(archiveID: episode.archiveID,
                          videoURL: episode.videoURLParsed,
                          subtitleHLS: nil,
                          onEnded: { if let n = next { episode = n } })   // binge auto-advance
                .id(episode.archiveID)
                .navigationTitle(episode.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { router.nowPlayingEpisode = nil } label: { Image(systemName: "xmark") }
                            .keyboardShortcut(.cancelAction).help("Close")
                    }
                    // Native prev/next episode controls in the toolbar (binge transport).
                    ToolbarItemGroup(placement: .navigation) {
                        Button { if let p = prev { episode = p } } label: { Image(systemName: "backward.end.fill") }
                            .disabled(prev == nil).help("Previous episode")
                        Button { if let n = next { episode = n } } label: { Image(systemName: "forward.end.fill") }
                            .disabled(next == nil).help("Next episode")
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// The shared playback surface: builds the AVPlayer (HLS or resilient MP4), resumes
// from + persists WatchProgress keyed by archiveID. archiveID is the resume key for
// both films and episodes (an episode's archiveID is a real archive.org item).
private struct PlayerSurface: View {
    let archiveID: String
    let videoURL: URL?
    let subtitleHLS: URL?
    var captionsOff: Bool = false
    /// The published WebVTT, so the track can be CHECKED rather than trusted.
    var publishedVTT: URL? = nil
    var onEnded: (() -> Void)? = nil

    @Environment(\.modelContext) private var ctx
    @State private var player: AVPlayer?
    @State private var loader: ResilientStreamLoader?     // retained for the asset's lifetime
    @State private var endObserver: NSObjectProtocol?
    @State private var timeObserver: Any?                 // periodic progress save (Continue Watching)
    // Part (c): captioned titles play native HLS (bypassing ResilientStreamLoader).
    // On a persistent mid-stream stall — or a hard load failure — drop CC and
    // rebuild on the resilient MP4 (smooth-without-CC beats stutter-with-CC).
    @State private var captionStall = CaptionStallMonitor()
    /// The Decision-067 plain-URL branch was taken (no loader on the item).
    @State private var usedDirectURL = false
    @State private var captionedLoader: CaptionedHLSLoader?   // Part (a): Config C HLS
    @State private var localSubsLoader: LocalSubtitleHLSLoader?  // on-device subtitles
    @State private var statusObs: NSKeyValueObservation?
    @State private var didFallback = false
    @State private var unplayableObs: NSKeyValueObservation?
    @State private var loadWatchdog: DispatchWorkItem?
    @State private var loadError: String?
    @State private var liveCaptions: LiveCaptions?
    @State private var liveLine: String = ""
    @State private var drawsCaptions = true
    // AirPlay. The `.floating` HUD below carries a route button, but every path
    // here builds a CUSTOM-SCHEME resource-loader asset, and Apple does not
    // support video AirPlay for those (see AirPlayRouting) — so choosing a route
    // failed on every title, exactly as it did on iOS before this was fixed
    // there. macOS never got the fix; this is it.
    @State private var externalObs: NSKeyValueObservation?
    @State private var resumeObs: NSKeyValueObservation?
    @State private var isExternalActive = false

    var body: some View {
        ZStack {
            Color.black
            if let loadError {
                // A dead source is a fact worth stating, not a spinner to sit in.
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Can't play this title").font(.title3.weight(.semibold))
                    Text(loadError)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Close") { onEnded?() }.keyboardShortcut(.defaultAction)
                }
                .foregroundStyle(.white)
            } else if let player {
                // `.floating` = the native macOS TV-app HUD (centre play/skip, scrubber + timecodes,
                // volume, PiP + AirPlay, full-screen, speed) — the interface the owner asked to mimic.
                VideoPlayerNS(player: player, controlsStyle: .floating).ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        // Live captions for a film with no subtitle track of its
                        // own. Non-interactive so it never intercepts the HUD.
                        if !liveLine.isEmpty {
                            Text(liveLine)
                                .font(.system(size: 18, weight: .medium))
                                .lineLimit(4)   // two stacked cues, each may wrap
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.black.opacity(0.6), in: .rect(cornerRadius: 7))
                                .padding(.bottom, 72)
                                .frame(maxWidth: 760)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    private func setup() {
        guard player == nil else { return }
        let playerItem: AVPlayerItem
        if let hls = subtitleHLS, let mp4 = videoURL {
            // Part (a) Config C: native CC menu, but START on a known-live storage
            // node — the loader serves the HLS playlists with the segment rewritten
            // to a freshly node-resolved direct https URL (skips the /download 302).
            let (asset, l) = CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: mp4)
            captionedLoader = l
            playerItem = AVPlayerItem(asset: asset)
        } else if let hls = subtitleHLS {
            playerItem = AVPlayerItem(url: hls)                 // no MP4 to resolve; native HLS
        } else if let mp4 = videoURL,
                  let dir = SubtitleStore.cachedDir(for: archiveID),
                  let (asset, l) = LocalSubtitleHLSLoader.makeAsset(
                    dir: dir, downloadURL: mp4,
                    resolveNode: { await ResilientStreamLoader.resolvedNodeURL(for: $0) }) {
            // Subtitles fetched or transcribed on this device (SubtitleFinder).
            localSubsLoader = l
            playerItem = AVPlayerItem(asset: asset)
        } else if let url = videoURL,
                  SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
            // From 27 the system captions video that carries none — but only for
            // an ordinary asset. Through `aw-stream://` no subtitle track is
            // ever offered (measured on macOS 27, one shape per process), so the
            // resilient loader gives way for films with no subtitles of their
            // own.
            playerItem = AVPlayerItem(url: url)
            usedDirectURL = true
        } else if let url = videoURL {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
        } else {
            return
        }
        playerItem.preferredForwardBufferDuration = 300
        // Title rides the native window title bar (navigationTitle "Title (Year)"). macOS AVPlayerItem
        // has NO externalMetadata (iOS/tvOS only — verified in the SDK), and the only way to override
        // the MP4's own embedded title is to wrap the asset, which over our custom-scheme resilient
        // asset renders BLANK video — so we DON'T. Speed/PiP/AirPlay/full-screen are AVPlayerView's
        // native HUD controls.

        let p = AVPlayer(playerItem: playerItem)
        if let resume = savedProgress(), resume > 5 {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        p.play()
        player = p
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        // AirPlay route engaged/disengaged — see externalPlaybackChanged.
        externalObs = p.observe(\.isExternalPlaybackActive, options: [.new]) { pl, _ in
            let active = pl.isExternalPlaybackActive
            MainActor.assumeIsolated { externalPlaybackChanged(active) }
        }
        // Part (c): recover to the resilient MP4 on a hard load failure OR a
        // persistent stutter — for captioned (HLS) titles AND the Decision-067
        // direct-URL path. The old premise ("non-captioned MP4 already streams
        // through ResilientStreamLoader, so it needs no fallback") died the day
        // D067 gave uncaptioned films a plain AVPlayerItem(url:) so the system
        // could caption them: that item has NO loader, so one archive.org idle
        // reset froze it forever (F-8: reproduced twice on macOS 27 within the
        // first minute — 38s and 55s — while the scout streamed the same file
        // happily on its own loader).
        if (subtitleHLS != nil || usedDirectURL), videoURL != nil {
            statusObs = playerItem.observe(\.status, options: [.new]) { item, _ in
                MainActor.assumeIsolated { if item.status == .failed { fallbackToResilientMP4() } }
            }
            captionStall.attach(player: p, item: playerItem) { fallbackToResilientMP4() }
        }
        // EVERY item is watched for "this will never play", not just captioned
        // ones — the same gap iOS had. An archive.org item removed since the last
        // catalog build 503s, and with no observer on the plain-MP4 path the
        // window just spins forever. 60s matches the tvOS backstop.
        unplayableObs = playerItem.observe(\.status, options: [.new]) { item, _ in
            MainActor.assumeIsolated {
                if item.status == .readyToPlay { loadWatchdog?.cancel(); loadWatchdog = nil }
                // A captioned item gets its CC-dropping fallback first; only
                // report once that has been spent.
                if item.status == .failed, subtitleHLS == nil || didFallback {
                    reportUnplayable()
                }
            }
        }
        loadWatchdog?.cancel()
        let watchdog = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard player?.currentItem?.status != .readyToPlay else { return }
                guard subtitleHLS == nil || didFallback else { return }
                reportUnplayable()
            }
        }
        loadWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: watchdog)
        // Periodic save (every 5s) — macOS previously saved ONLY on window close, so a crash /
        // force-quit lost the whole session and nothing synced mid-playback (owner 2026-06-29).
        // Live captions when the film carries no subtitle track of its own:
        // transcribe the audio that is ALREADY streaming (no download).
        if captionsOff {
            // Captions Off means NOTHING caption-shaped runs: not the engine,
            // and not the subtitle review either — the review starts its own
            // scout (a second player + tap + recognizer) to judge a file that
            // will never display. Measured 2026-08-26: with Off, the else-if
            // below started the scout anyway ("scout playing at 2.0x").
        } else if subtitleHLS == nil {
            startLiveCaptions(on: p)
        } else if let vtt = publishedVTT {
            // The film HAS subtitles — but a published file can belong to a
            // different cut, or be right and land seconds late. Listen briefly
            // and check it, then stop.
            reviewPublishedSubtitles(vtt: vtt, on: p)
        }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { _ in
            MainActor.assumeIsolated { persist() }
        }
    }

    /// Replace the current item and resume at `pos` EXACTLY.
    ///
    /// A seek issued straight after `replaceCurrentItem` is DROPPED — the new
    /// item has no loaded timeline yet — so playback restarted at 0 on every
    /// AirPlay engage/disengage and on every caption-stall fallback. Wait for
    /// `.readyToPlay`, seek with ZERO tolerance, then play.
    private func swap(to newItem: AVPlayerItem, resumingAt pos: CMTime, on p: AVPlayer) {
        newItem.preferredForwardBufferDuration = 300
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: newItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        resumeObs = nil
        p.replaceCurrentItem(with: newItem)
        guard pos.isNumeric, pos.seconds > 1 else { p.play(); return }
        resumeObs = newItem.observe(\.status, options: [.initial, .new]) { it, _ in
            guard it.status == .readyToPlay else { return }
            MainActor.assumeIsolated {
                resumeObs = nil
                p.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
            }
        }
    }

    /// Swap between a receiver-fetchable asset (AirPlay engaged) and the
    /// resilient on-device path (disengaged), preserving position and the end
    /// observer. Mirrors the iOS coordinator; the routing decision itself is
    /// shared (AirPlayRouting) so both platforms cannot drift.
    private func externalPlaybackChanged(_ active: Bool) {
        guard active != isExternalActive, let p = player else { return }
        isExternalActive = active
        let newItem: AVPlayerItem
        if active {
            // The stall/failure machinery watches the LOCAL loader paths; it must
            // not fire against a stream the receiver now owns.
            captionStall.detach()
            statusObs = nil
            if PlaybackDiag.enabled {
                print(AirPlayRouting.describe(hls: subtitleHLS, mp4: videoURL))
            }
            guard let url = AirPlayRouting.receiverURL(hls: subtitleHLS, mp4: videoURL) else {
                isExternalActive = false
                return          // nothing fetchable — leave playback as it is
            }
            newItem = AVPlayerItem(url: url)
        } else {
            // Restore the same path playback started on (Decision 021/031/034
            // resilience only matters once we own the connection again).
            guard let item = makeLocalItem() else { return }
            newItem = item
        }
        swap(to: newItem, resumingAt: p.currentTime(), on: p)
    }

    /// Rebuild the on-device item, mirroring `setup`'s branch.
    private func makeLocalItem() -> AVPlayerItem? {
        if let hls = subtitleHLS, let mp4 = videoURL, !didFallback {
            let (asset, l) = CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: mp4)
            captionedLoader = l
            return AVPlayerItem(asset: asset)
        }
        if let mp4 = videoURL {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: mp4)
            loader = l
            return AVPlayerItem(asset: asset)
        }
        if let hls = subtitleHLS { return AVPlayerItem(url: hls) }
        return nil
    }

    /// Part (c): swap the failed/stuttering native-HLS item for the resilient MP4
    /// (resume-on-reset + node failover), preserving the play position. Fires once.
    private func reportUnplayable() {
        guard loadError == nil else { return }
        loadWatchdog?.cancel(); loadWatchdog = nil
        player?.pause()
        loadError = "The copy on archive.org may have been removed or is temporarily unavailable."
    }

    private func fallbackToResilientMP4() {
        guard !didFallback, let url = videoURL, let p = player else { return }
        didFallback = true
        captionStall.detach()
        statusObs = nil
        captionedLoader = nil
        let pos = p.currentTime()
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        swap(to: AVPlayerItem(asset: asset), resumingAt: pos, on: p)
        // The subtitle track went with the HLS path — caption the audio instead.
        // Unless the engine is already running (the direct-URL branch started
        // it at setup) or the viewer chose captions Off.
        if liveCaptions == nil, !captionsOff { startLiveCaptions(on: p) }
    }

    /// Check the published track against what is actually being said.
    private func reviewPublishedSubtitles(vtt: URL, on p: AVPlayer) {
        startLiveCaptions(on: p, draws: false)
        Task { @MainActor in
            guard let captions = liveCaptions,
                  let outcome = await SubtitleReview.review(vttURL: vtt, captions: captions)
            else { return }
            if outcome.replacesNativeTrack {
                await SubtitleReview.deselectNativeSubtitles(on: p)
                drawsCaptions = true
            }
        }
    }

    /// Transcribe the streaming audio and publish it to `liveLine`.
    ///
    /// `draws` is false while a published track is only being JUDGED: the
    /// player is already showing its own subtitles, and a second set underneath
    /// them is the double-caption bug in miniature.
    private func startLiveCaptions(on p: AVPlayer, draws: Bool = true) {
        drawsCaptions = draws
        guard liveCaptions == nil, LiveCaptions.isSupported, let src = videoURL else { return }
        Task { @MainActor in
            // From macOS 27 the system captions this film itself; ours would
            // double up on it. But ONLY when the film has no track of its own:
            // `draws == false` means the job is to JUDGE a published track
            // (Decision 062), and running the handover first killed that judge
            // on every 27 device — the published track emits text, handOver
            // reports "captioning", and the review never ran.
            if draws, await SystemCaptions.handOver(to: p, directURL: src) { return }
            let lc = LiveCaptions()
            liveCaptions = lc
            await lc.start(url: src, from: p.currentTime())
            while lc.isRunning, player != nil {
                let now = p.currentTime()
                lc.throttle(playhead: now)
                // Between captions, say why there are none.
                let line = lc.line(at: now)
                liveLine = drawsCaptions ? (line.isEmpty ? lc.notice : line) : ""
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            liveLine = ""
        }
    }

    private func teardown() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        captionStall.detach()
        statusObs = nil
        externalObs = nil
        resumeObs = nil
        captionedLoader = nil
        localSubsLoader = nil
        unplayableObs = nil
        loadWatchdog?.cancel(); loadWatchdog = nil
        liveCaptions?.stop(); liveCaptions = nil
        persist()
    }

    private func savedProgress() -> Double? {
        let id = archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        guard let wp = try? ctx.fetch(d).first, !wp.isComplete else { return nil }
        return wp.positionSeconds
    }

    private func persist() {
        guard let p = player, let cur = p.currentItem else { return }
        let pos = p.currentTime().seconds
        // Save even a brief view (>1s) and even before duration is known (backfill it later) — the
        // old `pos>3 && dur>0` gate dropped early saves entirely (owner 2026-06-29).
        guard pos.isFinite, pos > 1 else { return }
        let d0 = cur.duration.seconds
        let dur = (d0.isFinite && d0 > 0) ? d0 : 0
        // Shared write path — watch-history semantics live in ONE place.
        WatchProgress.record(in: ctx, archiveID: archiveID, position: pos, duration: dur)
        SyncNudge.nudge(ctx)   // push progress promptly (debounced) so other devices converge fast
    }
}

// MARK: - Channel lineup player (Channels tune-in)
//
// Plays an ordered lineup (programs + woven commercials) straight through, joining
// the first program in progress at `startOffset` (#92). Live TV semantics: NO resume,
// NO WatchProgress writes (persistsProgress=false on the other platforms). On
// end-of-item it swaps the next playable item onto the same player. Mirrors the iOS
// LineupQueue advance, AppKit-side.
struct ChannelPlayer: View {
    let lineup: [Catalog.Item]
    let startOffset: TimeInterval
    var muted: Bool = false           // Party Play starts muted (background eye-candy)
    @Environment(\.dismiss) private var dismiss
    @State private var engine = ChannelEngine()

    var body: some View {
        ZStack {
            Color.black
            if let player = engine.player {
                VideoPlayerNS(player: player).ignoresSafeArea()
            } else if engine.failed {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear { engine.start(lineup: lineup, startOffset: startOffset, muted: muted) }
        .onDisappear { engine.stop() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .navigation) {
                Text(engine.nowTitle).font(.headline).lineLimit(1)
            }
        }
    }
}

@MainActor
@Observable
final class ChannelEngine {
    var player: AVPlayer?
    var nowTitle = ""
    var failed = false

    private var items: [Catalog.Item] = []
    private var idx = 0
    private var loader: ResilientStreamLoader?   // retained for the asset's lifetime
    private var endObserver: NSObjectProtocol?

    func start(lineup: [Catalog.Item], startOffset: TimeInterval, muted: Bool = false) {
        guard player == nil else { return }   // onAppear can fire more than once
        items = lineup
        idx = lineup.firstIndex { $0.videoURLParsed != nil } ?? 0
        guard idx < items.count, let url = items[idx].videoURLParsed else { failed = true; return }
        let p = AVPlayer(playerItem: makeItem(for: url))
        p.isMuted = muted
        nowTitle = items[idx].title
        if startOffset > 5 { p.seek(to: CMTime(seconds: startOffset, preferredTimescale: 600)) }
        p.play()
        player = p
    }

    private func makeItem(for url: URL) -> AVPlayerItem {
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 300
        registerEnd(for: item)
        return item
    }

    private func registerEnd(for item: AVPlayerItem) {
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func advance() {
        guard let player else { return }
        idx += 1
        while idx < items.count {
            if let url = items[idx].videoURLParsed {
                player.replaceCurrentItem(with: makeItem(for: url))
                nowTitle = items[idx].title
                player.play()
                return
            }
            idx += 1
        }
        // Lineup exhausted — let it sit on the final frame; the user dismisses.
    }

    func stop() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        player?.pause()
        player = nil
    }
}

struct VideoPlayerNS: NSViewRepresentable {
    let player: AVPlayer
    /// Default `.inline` for the main player; the clip-marking sheet passes `.none` and
    /// supplies its own compact transport (AVKit's inline overlay is too heavy for a sheet).
    var controlsStyle: AVPlayerViewControlsStyle = .inline

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = controlsStyle
        let chrome = controlsStyle != .none
        v.allowsPictureInPicturePlayback = chrome
        v.showsFullScreenToggleButton = chrome
        v.videoGravity = .resizeAspect
        if chrome {
            // Native playback-speed control in the HUD (the speedometer in the TV app) — the HIG-correct
            // speed UI, so we don't bolt a custom Speed menu onto the toolbar.
            v.speeds = AVPlaybackSpeed.systemDefaultSpeeds
            v.allowsVideoFrameAnalysis = false   // Live Text/subject-lookup on film frames isn't wanted
        }
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
        if v.controlsStyle != controlsStyle { v.controlsStyle = controlsStyle }
    }
}
#endif
