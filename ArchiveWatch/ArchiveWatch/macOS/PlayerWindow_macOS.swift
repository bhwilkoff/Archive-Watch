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
                          videoURL: item.videoURLParsed,
                          subtitleHLS: item.subtitleHLSURL,
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
    @State private var captionedLoader: CaptionedHLSLoader?   // Part (a): Config C HLS
    @State private var statusObs: NSKeyValueObservation?
    @State private var didFallback = false
    // AirPlay. The `.floating` HUD below carries a route button, but every path
    // here builds a CUSTOM-SCHEME resource-loader asset, and Apple does not
    // support video AirPlay for those (see AirPlayRouting) — so choosing a route
    // failed on every title, exactly as it did on iOS before this was fixed
    // there. macOS never got the fix; this is it.
    @State private var externalObs: NSKeyValueObservation?
    @State private var isExternalActive = false

    var body: some View {
        ZStack {
            Color.black
            if let player {
                // `.floating` = the native macOS TV-app HUD (centre play/skip, scrubber + timecodes,
                // volume, PiP + AirPlay, full-screen, speed) — the interface the owner asked to mimic.
                VideoPlayerNS(player: player, controlsStyle: .floating).ignoresSafeArea()
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
        // Part (c): captioned (HLS) titles — recover to the resilient MP4 on a hard
        // load failure OR a persistent stutter. Non-captioned MP4 already streams
        // through ResilientStreamLoader, so it needs no fallback.
        if subtitleHLS != nil, videoURL != nil {
            statusObs = playerItem.observe(\.status, options: [.new]) { item, _ in
                MainActor.assumeIsolated { if item.status == .failed { fallbackToResilientMP4() } }
            }
            captionStall.attach(player: p, item: playerItem) { fallbackToResilientMP4() }
        }
        // Periodic save (every 5s) — macOS previously saved ONLY on window close, so a crash /
        // force-quit lost the whole session and nothing synced mid-playback (owner 2026-06-29).
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { _ in
            MainActor.assumeIsolated { persist() }
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
        let pos = p.currentTime()
        newItem.preferredForwardBufferDuration = 300
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: newItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        p.replaceCurrentItem(with: newItem)
        if pos.seconds > 5 { p.seek(to: pos) }
        p.play()
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
    private func fallbackToResilientMP4() {
        guard !didFallback, let url = videoURL, let p = player else { return }
        didFallback = true
        captionStall.detach()
        statusObs = nil
        captionedLoader = nil
        let pos = p.currentTime()
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let newItem = AVPlayerItem(asset: asset)
        newItem.preferredForwardBufferDuration = 300
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: newItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        p.replaceCurrentItem(with: newItem)
        if pos.seconds > 5 { p.seek(to: pos) }
        p.play()
    }

    private func teardown() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        captionStall.detach()
        statusObs = nil
        externalObs = nil
        captionedLoader = nil
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
        let id = archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        if let wp = try? ctx.fetch(d).first {
            wp.positionSeconds = pos; if dur > 0 { wp.durationSeconds = dur }; wp.lastWatchedAt = .now
        } else {
            ctx.insert(WatchProgress(archiveID: id, positionSeconds: pos, durationSeconds: dur))
        }
        try? ctx.save()
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
