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
/// A label with breathing room, so a caption is not flush against its backing.
final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right,
                      height: s.height + inset.top + inset.bottom)
    }
}

struct PlayerView: UIViewControllerRepresentable {
    let archiveID: String
    let videoURL: URL?
    let queue: PlaybackQueue?
    // Shown in the title+description overlay that fades with the transport
    // controls (AVPlayerViewController shows no title on iOS, so this overlay is
    // the only place the user sees what's playing).
    var overlayTitle: String = ""
    var overlaySubtitle: String? = nil
    var overlayDescription: String? = nil
    // When present, the player loads this HLS playlist (MP4 + WebVTT) instead of
    // the bare MP4, so AVPlayerViewController shows native subtitles (Decision 039).
    var subtitleHLSURL: URL? = nil
    /// The published WebVTT, so the track can be CHECKED against what is
    /// actually said rather than trusted (SubtitleReview).
    var publishedVTTURL: URL? = nil
    /// Called when the title will never play, so the host can close the player
    /// and say so instead of leaving a spinner up indefinitely.
    var onUnplayable: ((String) -> Void)? = nil
    /// Transcribe the streaming audio when the film carries no subtitle track.
    var liveCaptionsEnabled: Bool = true

    /// Play a movie/standalone item. Pass `store` to enable movie autoplay
    /// (gated by `store.autoplayMode`; .off means play just this one).
    init(item: Catalog.Item, autoplayIn store: AppStore? = nil,
         onUnplayable: ((String) -> Void)? = nil) {
        archiveID = item.archiveID
        // Honour the viewer's chosen copy (ArchiveVersions). Rebuilt from the
        // stored file name, so this needs no network and cannot delay playback.
        videoURL = item.videoURLParsed.map {
            ArchiveVersions.preferredURL(for: item.archiveID, default: $0)
        }
        subtitleHLSURL = item.subtitleHLSURL
        publishedVTTURL = item.publishedVTTURL
        self.onUnplayable = onUnplayable
        queue = store.map { MovieAutoplayQueue(start: item, store: $0) }
        overlayTitle = item.title
        overlaySubtitle = [item.year.map(String.init), item.genres.first]
            .compactMap { $0 }.joined(separator: " · ")
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
        let c = Coordinator(archiveID: archiveID, ctx: ctx, queue: queue, onAdvance: onAdvance,
                            persistsProgress: persistsProgress)
        c.onUnplayable = onUnplayable
        // A captioned film that drops to the plain MP4 loses its subtitle track
        // with it; live captions are what should take over there.
        c.liveCaptionsAllowed = liveCaptionsEnabled
        return c
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.allowsPictureInPicturePlayback = true          // PiP button (#1)
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.speeds = AVPlaybackSpeed.systemDefaultSpeeds   // native speed menu (#7, iOS 16+)
        vc.updatesNowPlayingInfoCenter = true             // lock-screen / Control Center
        vc.delegate = context.coordinator
        context.coordinator.playerVC = vc

        // iOS/iPadOS REQUIRE an active .playback audio session or AVPlayer
        // frequently fails to start, stalls, or plays silently — especially with
        // our custom resource loader (Decision 021) or when the ringer is silent.
        // tvOS doesn't need this; this is the main iOS-vs-tvOS playback gap.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // Receiver-fetchable URLs for AirPlay (A0) — see Coordinator.directVideoURL.
        context.coordinator.directVideoURL = videoURL
        context.coordinator.directHLSURL = subtitleHLSURL

        let pItem: AVPlayerItem
        if let hls = subtitleHLSURL, let mp4 = videoURL {
            // Part (a) Config C (Decision 039): AVPlayerViewController shows the CC
            // menu for the WebVTT tracks. A resource-loader delegate serves the HLS
            // playlists with the video segment rewritten to a freshly node-resolved
            // direct https URL, so captioned playback STARTS on a known-live storage
            // node (skips the /download 302 + node-rotation-at-start). The segment
            // stays AVFoundation-owned (no mid-stream failover — Part c's stall
            // fallback covers that).
            let (asset, hlsLoader) = CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: mp4)
            context.coordinator.captionedLoader = hlsLoader   // retain (weak delegate)
            pItem = AVPlayerItem(asset: asset)
            // A non-faststart (moov-at-EOF) MP4 can still fail as a single HLS
            // segment. Arm a fallback to the resilient MP4 loader (handles
            // moov-at-EOF via byte-range seeks) so the film still plays (sans CC).
            context.coordinator.fallbackVideoURL = mp4
        } else if let hls = subtitleHLSURL {
            pItem = AVPlayerItem(url: hls)         // no MP4 to node-resolve; native HLS
        } else if let mp4 = videoURL,
                  let dir = SubtitleStore.cachedDir(for: archiveID),
                  let (asset, subsLoader) = LocalSubtitleHLSLoader.makeAsset(
                    dir: dir, downloadURL: mp4,
                    resolveNode: { await ResilientStreamLoader.resolvedNodeURL(for: $0) }) {
            // Subtitles fetched or transcribed on this device (SubtitleFinder).
            // Same Config C shape; the playlists are read off disk.
            context.coordinator.localSubsLoader = subsLoader   // retain (weak delegate)
            pItem = AVPlayerItem(asset: asset)
            context.coordinator.fallbackVideoURL = mp4
        } else if let url = videoURL,
                  SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
            // From 27 the system captions video that carries none — but only for
            // an ordinary asset. Through `aw-stream://` no subtitle track is
            // ever offered (measured on macOS 27, one shape per process), so the
            // resilient loader gives way here for films with no subtitles of
            // their own. `fallbackVideoURL` keeps the loader one stall away.
            pItem = AVPlayerItem(url: url)
            context.coordinator.fallbackVideoURL = url
        } else if let url = videoURL {
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
            context.coordinator.loader = loader   // retain (delegate is held weakly)
            pItem = AVPlayerItem(asset: asset)
        } else {
            return vc
        }
        // Native title+description: AVPlayerViewController renders externalMetadata
        // in its own chrome, shown/hidden WITH the transport controls (the Apple TV
        // app's behavior). This replaces a custom overlay — it's controls-synced
        // for free and survives load.
        pItem.externalMetadata = playerExternalMetadata(title: overlayTitle, subtitle: overlaySubtitle,
                                                        description: overlayDescription)
        context.coordinator.fallbackMetadata = pItem.externalMetadata
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

        // Live captions for a film with NO subtitle track: tap the audio that is
        // already streaming and transcribe it on device. Costs no extra bytes —
        // the player is decoding this audio regardless.
        if liveCaptionsEnabled, LiveCaptions.isSupported, let src = videoURL {
            if subtitleHLSURL == nil {
                context.coordinator.startLiveCaptions(url: src, in: vc)
            } else if let vtt = publishedVTTURL {
                // The film HAS subtitles — but a published file can belong to a
                // different cut, or be right and land seconds late. Listen
                // briefly and check it (SubtitleReview), then stop.
                context.coordinator.reviewPublishedSubtitles(vtt: vtt, source: src, in: vc)
            }
        }
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
        var captionedLoader: CaptionedHLSLoader?   // Part (a): Config C HLS (weak delegate)
        var localSubsLoader: LocalSubtitleHLSLoader?   // on-device subtitles (weak delegate)
        weak var playerVC: AVPlayerViewController?
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?
        private var interruptionObserver: NSObjectProtocol?
        private var isPiPActive = false
        private weak var player: AVPlayer?
        // HLS-subtitle → resilient-MP4 fallback (non-faststart MP4s fail to start
        // as a single HLS segment; the loader handles moov-at-EOF via byte ranges).
        var fallbackVideoURL: URL?
        var fallbackMetadata: [AVMetadataItem] = []
        // AirPlay (backlog A0). A custom-scheme resource-loader asset CANNOT be
        // routed to an AirPlay receiver: the delegate that serves `aw-stream://`
        // lives on THIS device, so the receiver has no way to fetch the media.
        // Apple states video AirPlay is unsupported with a custom resource
        // loader, and every playback path here is loader-backed (Decisions 021 /
        // 031 / 034 for MP4, Config C for captioned HLS) — so AirPlay would have
        // failed on every title. When a route engages we swap to a URL the
        // RECEIVER can pull itself, and swap the resilient path back in when it
        // disengages. The loader's resume/failover cannot help on AirPlay anyway:
        // the receiver owns the connection, exactly the trade Decision 047
        // records for Roku.
        var directVideoURL: URL?          // published progressive MP4
        var directHLSURL: URL?            // published HLS — receiver-fetchable AND keeps captions
        private var externalObs: NSKeyValueObservation?
        private var isExternalActive = false
        private var didFallback = false
        private var statusObs: NSKeyValueObservation?
        private var fallbackWork: DispatchWorkItem?
        /// Reports a title that will never play, so the host can dismiss and say
        /// so. Without it an unplayable item spins forever — see `loadWatchdog`.
        var onUnplayable: ((String) -> Void)?
        private var loadWatchdog: DispatchWorkItem?
        private var didReportUnplayable = false
        private var unplayableObs: NSKeyValueObservation?
        var liveCaptions: LiveCaptions?
        var captionLabel: UILabel?
        var liveCaptionsAllowed = true
        /// False while a published track is only being JUDGED — the
        /// player is already drawing its own subtitles, and a second
        /// set underneath them is the double-caption bug in miniature.
        var showsCaptionOverlay = true
        private let captionStall = CaptionStallMonitor()   // Part (c): stutter → resilient MP4

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
                forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.persistCurrent() }
            }
            registerEnd(for: playerItem)

            // AirPlay route engaged/disengaged — see `directVideoURL` above.
            externalObs = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] p, _ in
                let active = p.isExternalPlaybackActive
                MainActor.assumeIsolated { self?.externalPlaybackChanged(active) }
            }

            // HLS-subtitle → resilient-MP4 fallback. If the HLS item fails, or
            // never becomes ready within a grace window (a non-faststart MP4 as a
            // single HLS segment can hang), recreate playback through the resilient
            // loader so the film plays even without the caption track.
            // EVERY item is watched, not just captioned ones. These observers used
            // to be armed only when `fallbackVideoURL != nil` — i.e. only on the
            // captioned-HLS path — so a plain MP4 that could never load had no
            // status observer, no timeout and no error surface, and simply span
            // forever. That is what an archive.org item removed since the last
            // catalog build looks like to a viewer: an eternal spinner.
            // tvOS has had a 60s backstop all along; iOS and macOS had none.
            watchForUnplayable(playerItem)

            if fallbackVideoURL != nil {
                statusObs = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                    MainActor.assumeIsolated { if item.status == .failed { self?.fallbackToLoader() } }
                }
                let work = DispatchWorkItem { [weak self] in
                    if self?.player?.currentItem?.status != .readyToPlay { self?.fallbackToLoader() }
                }
                fallbackWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
                // Part (c): also fall back when the native-HLS path merely STUTTERS
                // mid-stream (not just on a hard load failure) — the resilient loader
                // is only used once we've dropped CC, so a persistent stall is a
                // strict win. Gated against transient blips inside the monitor.
                captionStall.attach(player: player, item: playerItem) { [weak self] in
                    self?.fallbackToLoader()
                }
            }

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

            // Audio-session interruptions (a call, an alarm, Siri, another app
            // taking the session). The system DEACTIVATES our session and pauses
            // playback; nothing reactivated it, so after an interruption — the
            // common case when an app has been backgrounded a long time — audio
            // stayed dead until the player was torn down and rebuilt.
            // Reactivating on .ended is the documented recovery, and we only
            // auto-resume when the system says we should.
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main) { [weak self] note in
                // Pull the primitives out here: Notification isn't Sendable, so
                // capturing it into the isolated closure is a Swift 6 error.
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optsRaw)
                }
            }
        }

        private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
            guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
            else { return }
            switch type {
            case .began:
                break                                   // the system already paused us
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true)
                let opts = optionsRaw.map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                if opts.contains(.shouldResume) { player?.play() }
            @unknown default:
                break
            }
        }

        private var resumeObs: NSKeyValueObservation?

        /// Replace the current item and resume at `pos` EXACTLY.
        ///
        /// A seek issued straight after `replaceCurrentItem` is DROPPED: the new
        /// item has no loaded timeline yet, so AVFoundation has nothing to seek
        /// within and playback begins at 0. That restarted the film every time an
        /// AirPlay route engaged, every time playback came back to the phone, and
        /// on every caption-stall fallback. The fix is to wait for
        /// `.readyToPlay`, then seek with ZERO tolerance (the viewer asked to land
        /// exactly where they left off, not at the nearest keyframe), and only
        /// then play.
        private func swap(to item: AVPlayerItem, resumingAt pos: CMTime, on player: AVPlayer) {
            item.externalMetadata = fallbackMetadata
            item.preferredForwardBufferDuration = 300
            registerEnd(for: item)
            // A swapped-in item (AirPlay, CC fallback, next episode) gets the same
            // watchdog — otherwise only the FIRST item of a session is covered.
            watchForUnplayable(item)
            resumeObs = nil
            player.replaceCurrentItem(with: item)
            guard pos.isNumeric, pos.seconds > 1 else { player.play(); return }
            // .initial so an item that is ALREADY ready still seeks.
            resumeObs = item.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
                guard it.status == .readyToPlay else { return }   // .failed -> the
                MainActor.assumeIsolated {                        // fallback observers own it
                    self?.resumeObs = nil
                    player.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        player.play()
                    }
                }
            }
        }

        /// Watch an item for "this will never play", on every path.
        ///
        /// Two ways a title dies: AVFoundation reports `.failed` (the loader gave
        /// up — an item removed from archive.org 503s and lands here), or nothing
        /// happens at all. The watchdog covers the silent case; 60s matches the
        /// tvOS backstop, and is generous enough that a cold storage node still
        /// wins. A captioned item is left to `fallbackToLoader` first — dropping
        /// CC to play is always better than an error — and only reported if that
        /// fallback has already been spent.
        private func watchForUnplayable(_ item: AVPlayerItem) {
            didReportUnplayable = false
            let obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch it.status {
                    case .readyToPlay:
                        self.loadWatchdog?.cancel(); self.loadWatchdog = nil
                    case .failed:
                        guard self.fallbackVideoURL == nil || self.didFallback else { return }
                        self.reportUnplayable(it.error?.localizedDescription)
                    default: break
                    }
                }
            }
            unplayableObs = obs
            loadWatchdog?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.player?.currentItem?.status != .readyToPlay else { return }
                guard self.fallbackVideoURL == nil || self.didFallback else { return }
                self.reportUnplayable(nil)
            }
            loadWatchdog = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
        }

        private func reportUnplayable(_ detail: String?) {
            guard !didReportUnplayable else { return }
            didReportUnplayable = true
            loadWatchdog?.cancel(); loadWatchdog = nil
            player?.pause()
            // Say what is true — the source is gone or unreachable — rather than
            // implying the viewer did something wrong.
            onUnplayable?("This title couldn't be played. The copy on archive.org "
                          + "may have been removed or is temporarily unavailable.")
            if let detail { print("[AWPLAY] unplayable \(archiveID): \(detail)") }
        }

        /// Transcribe the streaming audio and show it under the picture.
        ///
        /// The film's audio is already being decoded for playback, so this costs
        /// no extra bytes — `tools/test_live_audio_tap.swift` measured 9.1s of
        /// PCM captured in 8.8s of wall clock from a REMOTE asset.
        /// Transcribe AHEAD of playback and pop complete captions on in time.
        ///
        /// A second, muted player runs the same URL faster than playback and is
        /// the one that gets tapped — so a caption is ready before the viewer
        /// reaches it and can be shown whole, the way a captioned film reads.
        /// Tapping the PLAYING item can only ever trail the speech.
        func startLiveCaptions(url: URL, in vc: AVPlayerViewController,
                               showsImmediately: Bool = true) {
            showsCaptionOverlay = showsImmediately
            let captions = LiveCaptions()
            liveCaptions = captions
            let label = PaddedLabel()
            label.numberOfLines = 2
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isUserInteractionEnabled = false   // AVKit owns the gestures
            label.isHidden = true
            SystemCaptionStyle.apply(to: label)            // the viewer's system caption style
            if let overlay = vc.contentOverlayView {
                overlay.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                    label.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor,
                                                  constant: -64),
                    label.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor,
                                                 multiplier: 0.9),
                ])
            }
            captionLabel = label

            Task { @MainActor [weak self] in
                guard let self else { return }
                // Let the system speak first: from iOS 27 it captions this film
                // itself, and ours would be a second, differently timed copy
                // over the top of it. ONLY for a film with no track of its own —
                // `showsImmediately == false` means the job is to JUDGE a
                // published track (Decision 062), and running the handover
                // first killed that judge on every 27 device: the published
                // track emits text, handOver reports "captioning", and the
                // review never ran.
                if showsImmediately,
                   await SystemCaptions.handOver(to: self.player, directURL: url) {
                    self.captionLabel?.removeFromSuperview()
                    self.captionLabel = nil
                    return
                }
                let from = self.player?.currentTime() ?? .zero
                await captions.start(url: url, from: from)
                while !Task.isCancelled, captions.isRunning {
                    let now = self.player?.currentTime() ?? .zero
                    captions.throttle(playhead: now)
                    let line = captions.line(at: now)
                    // Between captions, say why there are none — silence and a
                    // failed recognizer are otherwise indistinguishable.
                    let text = self.showsCaptionOverlay
                        ? (line.isEmpty ? captions.notice : line) : ""
                    // Stacked rapid-dialogue captions are two cues, either of
                    // which may wrap once.
                    self.captionLabel?.numberOfLines = 4
                    self.captionLabel?.text = text.isEmpty ? nil : text
                        .components(separatedBy: "\n")
                        .map { "  \($0)  " }
                        .joined(separator: "\n")
                    self.captionLabel?.isHidden = text.isEmpty
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }

        /// Check a published subtitle track against what is being said.
        ///
        /// Runs the same scout the uncaptioned path uses, but only long enough
        /// to form a verdict. If the file is good it is left alone and the
        /// scout stops; if it is mistimed or belongs to another film, the
        /// player's own track is switched off and our overlay takes over —
        /// carrying the corrected HUMAN words where we have them.
        func reviewPublishedSubtitles(vtt: URL, source: URL, in vc: AVPlayerViewController) {
            startLiveCaptions(url: source, in: vc, showsImmediately: false)
            guard let captions = liveCaptions else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let outcome = await SubtitleReview.review(vttURL: vtt, captions: captions)
                else { return }
                if outcome.replacesNativeTrack {
                    await SubtitleReview.deselectNativeSubtitles(on: self.player)
                    self.showsCaptionOverlay = true
                } else {
                    self.captionLabel?.removeFromSuperview()
                    self.captionLabel = nil
                }
            }
        }

        private func fallbackToLoader() {
            guard !didFallback, let url = fallbackVideoURL, let player else { return }
            didFallback = true
            fallbackWork?.cancel(); fallbackWork = nil
            statusObs = nil
            captionStall.detach()
            captionedLoader = nil                 // release the Config-C HLS loader
            let pos = player.currentTime()
            let (asset, ldr) = ResilientStreamLoader.makeAsset(for: url)
            loader = ldr
            swap(to: AVPlayerItem(asset: asset), resumingAt: pos, on: player)
            // The subtitle track went with the HLS path — caption the audio
            // instead, rather than leaving this film silently uncaptioned.
            if liveCaptionsAllowed, liveCaptions == nil, LiveCaptions.isSupported,
               let vc = playerVC {
                startLiveCaptions(url: url, in: vc)
            }
        }

        /// Swap between a receiver-fetchable asset (AirPlay) and the resilient
        /// on-device path. Preserves position, metadata and the end observer.
        private func externalPlaybackChanged(_ active: Bool) {
            guard active != isExternalActive, let player else { return }
            isExternalActive = active
            let item: AVPlayerItem?
            if active {
                // The stall/fallback machinery watches the LOCAL loader paths;
                // it must not fire against a receiver-owned stream.
                fallbackWork?.cancel(); fallbackWork = nil
                statusObs = nil
                captionStall.detach()
                // Prefer the published HLS: the receiver fetches it directly and
                // keeps the WebVTT caption renditions. MP4 is the fallback.
                //
                // Routed through AirPlayRouting so the URL is CHECKED to be
                // receiver-fetchable rather than assumed. `directHLSURL ??
                // directVideoURL` would hand the receiver whatever was set —
                // including, if either ever came from a loader-backed path, a
                // custom-scheme URL only this device can serve, which is the
                // exact failure the swap exists to fix.
                if PlaybackDiag.enabled {
                    print(AirPlayRouting.describe(hls: directHLSURL, mp4: directVideoURL))
                }
                guard let url = AirPlayRouting.receiverURL(hls: directHLSURL,
                                                           mp4: directVideoURL) else {
                    // Nothing the receiver can pull — leave the local item alone
                    // rather than replace it with something that cannot play.
                    isExternalActive = false
                    return
                }
                item = AVPlayerItem(url: url)
            } else {
                item = makeLocalItem()
            }
            guard let item else { return }
            swap(to: item, resumingAt: player.currentTime(), on: player)
        }

        /// Rebuild the on-device item, mirroring `makeUIViewController`'s branch
        /// so returning from AirPlay restores the same path playback started on.
        private func makeLocalItem() -> AVPlayerItem? {
            if let hls = directHLSURL, let mp4 = directVideoURL, !didFallback {
                let (asset, l) = CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: mp4)
                captionedLoader = l
                return AVPlayerItem(asset: asset)
            }
            if let mp4 = directVideoURL {
                let (asset, l) = ResilientStreamLoader.makeAsset(for: mp4)
                loader = l
                return AVPlayerItem(asset: asset)
            }
            if let hls = directHLSURL { return AVPlayerItem(url: hls) }
            return nil
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
            // Shared write path — watch-history semantics (first-watch,
            // session count, durable everCompleted) live in ONE place.
            WatchProgress.record(in: ctx, archiveID: archiveID,
                                 position: pos, duration: dur)
            SyncNudge.nudge(ctx)   // push progress promptly (debounced) for cross-device resume
        }

        // isolated deinit (SE-0371): touch the MainActor-isolated observers natively under
        // the Swift 6 language mode without a nonisolated(unsafe) escape hatch.
        isolated deinit {
            captionStall.detach()
            externalObs = nil
            resumeObs = nil
            if let t = timeObserver { player?.removeTimeObserver(t) }
            if let e = endObserver { NotificationCenter.default.removeObserver(e) }
            if let b = backgroundObserver { NotificationCenter.default.removeObserver(b) }
            if let f = foregroundObserver { NotificationCenter.default.removeObserver(f) }
            if let i = interruptionObserver { NotificationCenter.default.removeObserver(i) }
        }
    }
}

// MARK: - Native player metadata (title + description in AVKit's chrome)

/// External metadata for the AVPlayerItem so AVPlayerViewController shows the
/// title + description in its OWN controls overlay, synced with the transport
/// (the Apple TV app's behavior). The empty creation-date overrides blank the
/// MP4's bogus embedded year (see tvOS `suppressedDateMetadata`).
private func playerExternalMetadata(title: String, subtitle: String? = nil,
                                    description: String?) -> [AVMetadataItem] {
    func entry(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let m = AVMutableMetadataItem()
        m.identifier = id
        m.value = value as NSString
        m.extendedLanguageTag = "und"
        return m
    }
    var meta = [entry(.commonIdentifierTitle, title)]
    if let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        // Subtitle line under the title (WWDC22 player title/subtitle/info layout).
        meta.append(entry(.iTunesMetadataTrackSubTitle, s))
    }
    if let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
        // Tapping the title reveals iOS's native info panel with this description.
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
