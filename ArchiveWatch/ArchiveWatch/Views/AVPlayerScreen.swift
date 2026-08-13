#if os(tvOS)
import SwiftUI
import AVKit
import AVFoundation
import UIKit

// Native tvOS playback surface.
//
// Per docs/tvos-playbook.md "Playback": AVPlayerViewController is the
// baseline, not SwiftUI's VideoPlayer — it gives the full tvOS transport
// (scrubbing thumbnails, the Info tab with title/description/genre, audio
// + subtitle menus, Now Playing on the remote) for free. We feed it
// `externalMetadata` so that Info tab shows the real film details instead
// of a bare scrubber.

/// Owns the live-caption engine + its label for a tvOS player.
@MainActor
final class CaptionCoordinator {
    private var captions: LiveCaptions?
    private var label: UILabel?
    private var loop: Task<Void, Never>?
    /// The concurrent watch for the system's generated track — held so
    /// teardown can cancel it; otherwise it would poll a paused player for
    /// the rest of its 300s patience after the viewer has left.
    private var systemWatch: Task<Void, Never>?
    /// The source currently being transcribed, so an autoplay advance to the
    /// next film restarts the engine instead of captioning the previous one
    /// forever (the container is reused; only its player is swapped).
    private var sourceURL: URL?
    /// The player whose clock drives the display — held HERE, not captured by
    /// the loop. On tvOS a persistent stall REBUILDS the AVPlayer for the same
    /// url (`forceResilientFallback`), and a loop that captured the original
    /// kept reading a torn-down player whose `currentTime()` never moves: the
    /// caption at the resume position stayed on screen for the rest of the
    /// film. iOS and macOS swap the ITEM on one player, which is why only the
    /// living room froze.
    private weak var observedPlayer: AVPlayer?
    /// `AW_CAPTION_TRACE=1`: print the playhead and every displayed-line
    /// change, so caption progression on a paired Apple TV is verifiable from
    /// the dev Mac's console instead of by watching the bedroom TV.
    private let trace = ProcessInfo.processInfo.environment["AW_CAPTION_TRACE"] == "1"
    /// False while a published track is only being JUDGED — the player already
    /// draws its own subtitles, and a second set underneath is the
    /// double-caption bug in miniature.
    private var draws = true
    /// Why there are no subtitles, when the answer came from the SYSTEM rather
    /// than from our own engine.
    ///
    /// An Apple TV is the only device that can answer whether tvOS captioned a
    /// film, and its console cannot be read from a development machine — so
    /// three fixes shipped on evidence gathered entirely on a Mac. This is the
    /// state made visible where it can actually be observed. It is also the
    /// honest thing to tell a viewer: a blank screen and a recognizer that
    /// declined look identical from a sofa.
    private var systemNote = ""
    /// Decision 070: on tvOS the subtitle FILE is rendered by this overlay —
    /// there is no native track any more (the single-segment HLS wrapper that
    /// carried one was a memory bomb on 3 GB Apple TVs). The parsed cues live
    /// here; `showFile` mirrors what the old track's AUTOSELECT/DEFAULT +
    /// viewer preference produced: on when the viewer's caption preference is.
    private var fileCues: [SubtitleAgreement.Cue] = []
    private var showFile = false
    /// Set once SubtitleReview has returned (any answer): after a deliberate
    /// keep/shift the engine is DONE, and the resync rescue must not restart a
    /// second stream under a film whose captions are already on screen.
    private var verdictReached = false

    /// `reviewing` is the published WebVTT when the film already HAS subtitles:
    /// the engine then runs only long enough to judge that file, and draws
    /// nothing unless it turns out to be wrong.
    func startCaptions(url: URL, player: AVPlayer?, in vc: AVPlayerViewController,
                       reviewing vtt: URL? = nil) {
        // AW_NO_CAPTIONS=1: the entire caption system stands down — no scout,
        // no judge, no overlay, no deselects. The BASELINE the last four fix
        // rounds never established: whether this film stutters with nothing
        // of ours running at all. Without that control, every stutter theory
        // was attribution, not measurement.
        guard ProcessInfo.processInfo.environment["AW_NO_CAPTIONS"] != "1" else { return }
        guard sourceURL != url else {
            // Same film, new player: the stall fallback rebuilt it. The clock
            // the display follows moves to the new player — and the SCOUT
            // STOPS FOR THE SESSION. A rebuild is the player telling us this
            // film's stream could not survive contention; a second 2x stream
            // of the same film from the same node is the contention. Captions
            // continue as far as they were transcribed, and playback — which
            // the owner watched stutter through two rounds of gentler
            // remedies (yield-on-unhealthy, background QoS) — wins outright.
            if let player, player !== observedPlayer {
                observedPlayer = player
                captions?.stopListening()
                if trace {
                    print("[AWCAP] trace: rebuilt player — scout STOPPED for this "
                          + "session (marginal stream; playback wins)")
                }
            }
            return
        }
        stop()
        sourceURL = url
        observedPlayer = player
        let lc = LiveCaptions()
        captions = lc

        let l = UILabel()
        l.numberOfLines = 2
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false     // the focus engine owns input here
        l.isHidden = true
        SystemCaptionStyle.apply(to: l, baseSize: 34)   // ten-foot size
        if let overlay = vc.contentOverlayView {
            overlay.addSubview(l)
            // Anchored to the CONTROLLER'S VIEW, not the overlay's own frame.
            // Two constraint schemes against contentOverlayView both rendered
            // the caption at the vertical center on tvOS 27 (its
            // safeAreaLayoutGuide excludes the transport zone, and its frame
            // itself is not the full screen) — the owner saw mid-screen
            // captions on two builds that each "fixed" this. vc.view is the
            // one view guaranteed to span the screen; the label stays a child
            // of the overlay (the sanctioned layer between video and
            // controls), the overlay does not clip, and cross-hierarchy
            // constraints to an ancestor are legal.
            overlay.clipsToBounds = false
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                l.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor,
                                          constant: -100),
                l.widthAnchor.constraint(lessThanOrEqualTo: vc.view.widthAnchor,
                                         multiplier: 0.8),
            ])
        }
        label = l

        // With a file to show (Decision 070) the overlay draws from the start —
        // it IS the subtitle track now. Without one, it draws the engine's text.
        draws = true
        if let vtt {
            Task { @MainActor [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: vtt),
                      let body = String(data: data, encoding: .utf8) else { return }
                let cues = SubtitleAgreement.parseVTT(body)
                guard !cues.isEmpty else { return }
                self?.fileCues = cues
                // Mirrors the retired native track's behavior: AUTOSELECT/DEFAULT
                // showed it when the viewer's system caption preference is on.
                self?.showFile = SystemCaptionStyle.viewerWantsCaptions
                if self?.trace == true {
                    print("[AWCAP] trace file subtitles loaded: \(cues.count) cues, "
                          + "showing=\(self?.showFile == true)")
                }
            }
        }
        loop = Task { @MainActor [weak self] in
            // OUR ENGINE LEADS on tvOS; the system's generated track is
            // opportunistic. Measured on the real Apple TV (tvOS 27.0
            // 24J5346a, probe v3): the system's track was offered and selected
            // on every asset shape — local file, plain remote MP4, HLS wrapper
            // — and produced NO TEXT in over ten minutes of playback, while
            // our SpeechAnalyzer scout cued the same clip in 14 seconds. tvOS
            // 27 ships working speech models (Decision 060 was true of 26
            // only), so the engine that captions iOS and macOS captions the
            // living room too. Blocking it for 300s behind a system track that
            // has never once spoken was the delay the owner kept reporting as
            // "no captions".
            //
            // The system-watch still runs, CONCURRENTLY: if a track ever emits
            // — this beta, a later one, or a device where it genuinely works —
            // ours stops and stands down, because the system's is better on
            // every count (native menu, viewer's style, no second stream).
            //
            // Films WITH a published track (`vtt != nil`) skip the watch: the
            // job there is to JUDGE the file (Decision 062), and a handover
            // that stands down on the published track's own emission killed
            // that judge once already.
            if vtt == nil {
                // A viewer whose caption preference is forced-only has asked
                // NOT to see captions. Respect it for the automatic path: no
                // engine, no second stream, no note. (Published tracks and the
                // manual subtitle menu remain theirs to switch on.)
                guard SystemCaptionStyle.viewerWantsCaptions else {
                    self?.label?.removeFromSuperview()
                    self?.label = nil
                    return
                }
                self?.systemWatch = Task { @MainActor [weak self] in
                    guard await SystemCaptions.handOver(to: player, directURL: url,
                                                        patience: 300) else { return }
                    // The system's track spoke — hide ours, but DON'T kill the
                    // engine. On this tvOS beta the generated track refused to
                    // emit through ten minutes of probing and then emitted
                    // mid-film in real playback: it is flaky in both
                    // directions, and a permanent stand-down would strand the
                    // viewer captionless the moment it goes quiet again. So
                    // the overlay yields, the scout keeps transcribing, and if
                    // the system falls silent for 45s ours comes straight back.
                    print("[AWCAP] system captions arrived — yielding to them")
                    self?.draws = false
                    var window = 0
                    while !Task.isCancelled {
                        window += 1
                        let began = Date()
                        let p = self?.observedPlayer
                        if await SystemCaptions.emitsCaptions(on: p, within: 45) {
                            if self?.trace == true {
                                print("[AWCAP] trace system still captioning (window \(window))")
                            }
                            // `emitsCaptions` returns the moment it sees text,
                            // which on a continuously-captioning system is ~1s
                            // in — re-checking immediately spun this loop once
                            // a second. Sleep out the window: the question is
                            // "did it go quiet", and that only needs asking
                            // every 45s.
                            let left = 45 - Date().timeIntervalSince(began)
                            if left > 0 {
                                try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
                            }
                            continue
                        }
                        guard !Task.isCancelled else { return }
                        print("[AWCAP] system captions went quiet — ours resume")
                        self?.draws = true
                        return
                    }
                }
            }
            guard !Task.isCancelled else { return }
            // Nothing to say and no way to say it: without models the screen
            // stays blank, and the reason must be visible from the sofa. Only
            // for a film with no track — a review film's subtitles are on
            // screen and need no note.
            if vtt == nil, await CaptionCapability.shared.resolved() == false {
                self?.systemNote = SystemCaptions.stage == .declined
                    ? "No subtitles: the system couldn't transcribe this film's audio."
                    : "Subtitles unavailable — \(SystemCaptions.stage.rawValue)."
                // Shown HERE rather than in the loop below, because on this
                // device the engine never starts, so that loop exits at once
                // and would never draw anything. Time-boxed: an explanation
                // earns a few seconds over a film, not the whole running time.
                if let l = self?.label, let note = self?.systemNote, !note.isEmpty {
                    l.numberOfLines = 4
                    l.text = "  \(note)  "
                    l.isHidden = false
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        guard self?.systemNote == note else { return }
                        self?.label?.isHidden = true
                    }
                }
            }
            let from = player?.currentTime() ?? .zero
            await lc.start(url: url, from: from)
            if let vtt {
                Task { @MainActor [weak self] in
                    defer { self?.verdictReached = true }
                    guard let outcome = await SubtitleReview.review(vttURL: vtt,
                                                                    captions: lc) else { return }
                    // Decision 070: there is no native track to take over from —
                    // the file's cues are OURS to correct or discard directly.
                    switch outcome.verdict.choice {
                    case .keepPublished:
                        break
                    case .shiftPublished(let by):
                        if let cues = self?.fileCues {
                            self?.fileCues = cues.map {
                                SubtitleAgreement.Cue(start: $0.start + by,
                                                      end: $0.end + by, text: $0.text)
                            }
                        }
                    case .preferLive:
                        // The file belongs to a different cut or film; the
                        // engine's transcript is the captions from here.
                        self?.showFile = false
                    }
                }
            }
            // Until CANCELLED, not while the engine runs: a loop conditioned on
            // `lc.isRunning` exits the moment the engine stops and leaves
            // whatever the label last said on screen for the rest of the film —
            // the second way a caption freezes. Display outlives transcription
            // (a finished transcript is still worth showing); only `stop()`
            // ends it.
            var shown = ""
            var lastTrace = Date.distantPast
            var resyncTicks = 0
            var deselectTick = 0
            var geometryPrinted = false
            while !Task.isCancelled {
                let now = self?.observedPlayer?.currentTime() ?? .zero
                // The scout yields whenever the MAIN stream's buffer struggles
                // — a second 2x stream of the same film can starve the very
                // playback it captions, and the captioned-HLS path has no
                // resilience to starve into (D054's AVFoundation-owned
                // segment). His Girl Friday stuttered exactly this way.
                let item = self?.observedPlayer?.currentItem
                let healthy = item.map {
                    $0.isPlaybackLikelyToKeepUp && !$0.isPlaybackBufferEmpty
                } ?? true
                lc.throttle(playhead: now, playbackHealthy: healthy)
                // Between captions, say why there are none — a blank screen and
                // a failed recognizer look identical from the sofa.
                // The subtitle FILE, when one is showing, outranks the engine
                // (Decision 070: the overlay is the subtitle track now).
                let line: String
                if self?.showFile == true, let cues = self?.fileCues, !cues.isEmpty {
                    line = Self.fileLine(cues, at: now.seconds)
                } else {
                    line = lc.line(at: now)
                }
                let text = (self?.draws ?? true) ? (line.isEmpty ? lc.notice : line) : ""
                // A caption is two lines; an explanation may need more.
                self?.label?.numberOfLines = line.isEmpty ? 4 : 2
                self?.label?.text = text.isEmpty ? nil : "  \(text)  "
                self?.label?.isHidden = text.isEmpty
                if self?.trace == true {
                    if text != shown {
                        print("[AWCAP] trace t=\(String(format: "%.1f", now.seconds)) "
                              + (text.isEmpty ? "(blank)" : "show: \(text.prefix(50))"))
                        // The caption's ACTUAL geometry, once: two rounds of
                        // constraint fixes were shipped against an assumed
                        // overlay frame and the label still rendered at the
                        // vertical center — measure the thing itself.
                        if !geometryPrinted, !text.isEmpty, let l = self?.label,
                           let sv = l.superview {
                            geometryPrinted = true
                            print("[AWCAP] trace geometry label=\(l.frame) "
                                  + "overlay=\(sv.bounds) "
                                  + "screen=\(sv.window?.bounds ?? .zero) "
                                  + "safeBottomInset=\(sv.safeAreaInsets.bottom)")
                        }
                    } else if Date().timeIntervalSince(lastTrace) > 10 {
                        print("[AWCAP] trace t=\(String(format: "%.1f", now.seconds)) "
                              + "steady (\(lc.isRunning ? "engine running" : "engine stopped"), "
                              + "lead \(Int(lc.leadSeconds(over: now)))s)")
                        lastTrace = Date()
                    }
                }
                shown = text
                // Decision 070 retired the deselect loop that used to live here:
                // with the captioned-HLS wrapper gone there is no native
                // subtitle track to fight — the overlay is the only renderer.
                // The session is hopeless for where the viewer is (seek behind
                // it, or the scout fell irrecoverably behind — both observed
                // live): start fresh from the playhead. NOT gated on `draws`:
                // that gate left a review film whose scout died at 330s
                // grinding through 700s of watched film with no captions and
                // no way out — the review path needs a living engine more
                // than anyone, because without a transcript it can never
                // reach a verdict at all. ~3s of steady evidence first: a
                // player rebuild passes through t=0 for a moment, and one
                // glimpse must not throw away a good session.
                // While the FILE's cues are on screen after a deliberate verdict,
                // the engine is done — restarting it here would put a second 2x
                // stream under a film whose captions are already right.
                let engineIsTheCaptions = !(self?.showFile == true && self?.verdictReached == true)
                if engineIsTheCaptions, lc.needsResync(at: now) {
                    resyncTicks += 1
                    if resyncTicks >= 20 {
                        resyncTicks = 0
                        print("[AWCAP] session hopeless for playhead — "
                              + "restarting captions from \(Int(now.seconds))s")
                        lc.stop()
                        await lc.start(url: url, from: now)
                    }
                } else {
                    resyncTicks = 0
                }
                // Engine gone and nothing left to say: hide and stop polling —
                // unless a subtitle FILE is on screen, whose quiet stretches
                // between cues are normal, not the end of captioning.
                if !lc.isRunning, text.isEmpty, self?.showFile != true { break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            self?.label?.isHidden = true
        }
    }

    /// The file cue covering `t`, if any. Small linear scan — display runs at
    /// ~7 Hz over at most a few thousand cues, and the common case exits on the
    /// first cue past the playhead.
    private static func fileLine(_ cues: [SubtitleAgreement.Cue], at t: Double) -> String {
        for cue in cues {
            if cue.start > t + 0.2 { break }
            if t >= cue.start - 0.2 && t <= cue.end + 0.3 { return cue.text }
        }
        return ""
    }

    func stop() {
        loop?.cancel(); loop = nil
        systemWatch?.cancel(); systemWatch = nil
        captions?.stop(); captions = nil
        label?.removeFromSuperview(); label = nil
        sourceURL = nil
        observedPlayer = nil
        fileCues = []
        showFile = false
        verdictReached = false
    }
}

struct AVPlayerContainer: UIViewControllerRepresentable {
    /// Source URL for live captions. When present and the title has no subtitle
    /// track, the audio is transcribed AHEAD of playback and drawn over the
    /// picture — the same engine iOS and macOS use, wired here so the living
    /// room is not the one platform without it.

    let player: AVPlayer
    var menuItems: [UIMenuElement] = []   // #10: per-video transport menu (autoplay override)
    /// Source URL for live captions. When present and the title has no subtitle
    /// track, the audio is transcribed AHEAD of playback and drawn over the
    /// picture — the same engine iOS and macOS use, wired here so the living
    /// room is not the one platform without it.
    var liveCaptionURL: URL? = nil
    /// Set when the film HAS published subtitles: they are CHECKED against what
    /// is actually said rather than trusted (SubtitleReview).
    var reviewSource: (video: URL, vtt: URL)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.speeds = AVPlaybackSpeed.systemDefaultSpeeds   // #5: native speed menu
        vc.transportBarCustomMenuItems = menuItems
        // tvOS PiP (swipe up / TV button while playing → corner window). Needs
        // the `audio` UIBackgroundModes entry, added alongside this.
        vc.allowsPictureInPicturePlayback = true
        if let src = liveCaptionURL, LiveCaptions.isSupported {
            context.coordinator.startCaptions(url: src, player: player, in: vc)
        } else if let review = reviewSource, LiveCaptions.isSupported {
            context.coordinator.startCaptions(url: review.video, player: player,
                                              in: vc, reviewing: review.vtt)
        }
        return vc
    }

    func makeCoordinator() -> CaptionCoordinator { CaptionCoordinator() }

    static func dismantleUIViewController(_ vc: AVPlayerViewController,
                                          coordinator: CaptionCoordinator) {
        coordinator.stop()
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        vc.transportBarCustomMenuItems = menuItems        // reflect autoplay-mode changes
        // Autoplay swaps the player in place, and the HLS-subtitle path can fall
        // back to the plain MP4 mid-film — both change what should be captioned,
        // and neither goes through makeUIViewController.
        if let src = liveCaptionURL, LiveCaptions.isSupported {
            context.coordinator.startCaptions(url: src, player: player, in: vc)
        } else if let review = reviewSource, LiveCaptions.isSupported {
            context.coordinator.startCaptions(url: review.video, player: player,
                                              in: vc, reviewing: review.vtt)
        } else {
            context.coordinator.stop()
        }
    }
}

// NOTE: a "Skip Credits" contextualAction was removed here. It was always shown
// (no per-title credits-timestamp data exists for movies to know WHERE credits
// start), and it merely seeked to the exact end — which does NOT reliably fire
// AVPlayerItemDidPlayToEndTime (you must PLAY to the end), so it ended the film
// without advancing autoplay-next. A real version needs credit timestamps (#8b)
// and would gate visibility to the final minutes. Episodes keep their real
// "Next Episode" action below; movies rely on natural end -> autoplay-next (#10).

// Episode-aware player surface (#9, tvOS-DESIGN §8.3): the native
// AVPlayerViewController plus tvOS episode navigation — "Next Episode" as a
// contextualAction (the prompt that auto-surfaces near the end of an episode) and
// both prev/next as transportBarCustomMenuItems (reachable any time from the
// transport bar). The native Info tab already shows title/synopsis/genre from the
// item's externalMetadata, so we add navigation, not a parallel transport (§8.1).
struct EpisodeAVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var hasPrev: Bool
    var hasNext: Bool
    /// Source for live captions. Episodes had NONE — the movie container has
    /// carried them since Decision 058 and this one was simply never given
    /// them, so a viewer watching Classic TV on an Apple TV got captions on
    /// films and silence on episodes of the same catalogue.
    var liveCaptionURL: URL? = nil
    // #1: the auto-surfacing "Next Episode" prompt should only appear briefly at
    // the start and near the end — not persist the whole episode. The transport-
    // bar menu items (below) stay available the entire time.
    var showNextPrompt: Bool = true
    var onPrev: () -> Void
    var onNext: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.speeds = AVPlaybackSpeed.systemDefaultSpeeds   // #5: native speed menu
        vc.allowsPictureInPicturePlayback = true          // tvOS PiP
        context.coordinator.apply(to: vc)
        if let src = liveCaptionURL, LiveCaptions.isSupported {
            context.coordinator.captions.startCaptions(url: src, player: player, in: vc)
        }
        return vc
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController,
                                          coordinator: Coordinator) {
        coordinator.captions.stop()
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.parent = self
        context.coordinator.apply(to: vc)
        // Binge-advance swaps the player in place, so the next episode needs
        // its own engine — same reason the movie container does this.
        if let src = liveCaptionURL, LiveCaptions.isSupported {
            context.coordinator.captions.startCaptions(url: src, player: player, in: vc)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator {
        var parent: EpisodeAVPlayerContainer
        let captions = CaptionCoordinator()
        init(_ parent: EpisodeAVPlayerContainer) { self.parent = parent }

        func apply(to vc: AVPlayerViewController) {
            let prev = UIAction(title: "Previous Episode",
                                image: UIImage(systemName: "backward.end.fill")) { [weak self] _ in
                self?.parent.onPrev()
            }
            let next = UIAction(title: "Next Episode",
                                image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                self?.parent.onNext()
            }
            var menu: [UIMenuElement] = []
            if parent.hasPrev { menu.append(prev) }
            if parent.hasNext { menu.append(next) }
            vc.transportBarCustomMenuItems = menu
            // The auto-surfacing prompt: only "Next Episode", and only inside the
            // start/end windows (#1) so it doesn't linger the whole episode.
            vc.contextualActions = (parent.hasNext && parent.showNextPrompt) ? [next] : []
        }
    }
}

// Buffering tuning for Archive's PROGRESSIVE (non-HLS) MP4s.
//
// Archive items play as a single progressive file streamed straight from
// archive.org with throttled, variable per-connection bandwidth — there's no
// adaptive bitrate ladder to fall back to. A bare AVPlayerItem keeps
// preferredForwardBufferDuration = 0 (AVFoundation's conservative automatic
// heuristic), so long, higher-bitrate films stall whenever a brief bandwidth
// dip drains that small cushion — the "pause/resume" mid-playback.
//
// Banking a large forward buffer lets the player accumulate surplus during the
// fast stretches and ride through the dips. automaticallyWaitsToMinimizeStalling
// stays on (the default) so the player builds buffer before (re)starting instead
// of stall-starting on an empty buffer.
//
// This is quality-NEUTRAL: it buffers more of the SAME highest-quality stream
// ahead of the playhead — it never changes which derivative or its bitrate. The
// value is a PREFERENCE (a cap), not a hard allocation; AVFoundation fills toward
// it when the connection is faster than playback and self-limits under memory
// pressure. 300s gives deep headroom to ride out Archive's connection
// drops/resets (the TCP RST + read-timeout seen on-device). At a typical PD
// bitrate (1-4 Mbps) that's ~40-150 MB; AVFoundation backs off for the rare
// very-high-bitrate file rather than risk jetsam on the Apple TV.
let archivePreferredForwardBufferDuration: TimeInterval = 300

@MainActor
func tunePlaybackBuffering(item: AVPlayerItem, player: AVPlayer) {
    item.preferredForwardBufferDuration = archivePreferredForwardBufferDuration
    player.automaticallyWaitsToMinimizeStalling = true
    PlaybackDiag.attach(item: item, player: player)   // no-op unless AW_PLAYBACK_DIAG=1
}

// Publishes Now Playing poster artwork the way AVPlayerViewController actually
// reads it on tvOS: as a `commonIdentifierArtwork` item on the player item's
// externalMetadata — NOT via MPNowPlayingInfoCenter (AVKit owns the Now Playing
// session here and ignores a manual one). This is what clears the repeating
// "[MRPlaybackQueueServiceClient] ... Code=15 ... client data source ...
// registered" log, which was MediaRemote polling for artwork we never published,
// and it puts the poster on the Now Playing widget / remote. Title, description,
// genre, and the elapsed/duration scrubber are already published by AVKit from
// the item's other externalMetadata + the asset, so artwork is all we add.
@MainActor
final class NowPlayingController {
    private var artworkTask: Task<Void, Never>?

    func begin(posterURL: URL?, item: AVPlayerItem) {
        guard let posterURL else { return }
        // Poster bytes load async; append the artwork once it arrives so playback
        // start never blocks on a network fetch. Re-encode to PNG so the metadata
        // dataType is always correct regardless of the source format.
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: posterURL),
                  !Task.isCancelled,
                  let image = UIImage(data: data),
                  let png = image.pngData() else { return }
            let artwork = AVMutableMetadataItem()
            artwork.identifier = .commonIdentifierArtwork
            artwork.dataType = kCMMetadataBaseDataType_PNG as String
            artwork.value = png as NSData
            artwork.extendedLanguageTag = "und"
            item.externalMetadata += [artwork]
        }
    }

    func end() {
        artworkTask?.cancel()
        artworkTask = nil
    }
}

func metaEntry(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
    guard !value.isEmpty else { return nil }
    let m = AVMutableMetadataItem()
    m.identifier = identifier
    m.value = value as NSString
    m.extendedLanguageTag = "und"
    return m
}

// The wrong "year" above the tvOS transport scrubber (e.g. 1969 on the 1896
// "Le Manoir du Diable") is NOT ours — it's the MP4's embedded creation_time.
// Archive's re-encoded derivatives carry creation_time = epoch 0
// (1970-01-01 UTC), which AVPlayerViewController renders as "1969" in a
// negative-UTC timezone. AVKit reads that off the asset, so deleting our own
// metadata didn't help.
//
// externalMetadata OVERRIDES asset metadata by identifier, so we override the
// creation-date keys (both the common key and the QuickTime-specific key the
// MP4 actually carries) with empty values — that blanks the displayed date on
// every title. Both player surfaces (movies + episodes) apply these.
func suppressedDateMetadata() -> [AVMetadataItem] {
    [AVMetadataIdentifier.commonIdentifierCreationDate,
     .quickTimeMetadataCreationDate,
     .quickTimeUserDataCreationDate].map { id in
        let m = AVMutableMetadataItem()
        m.identifier = id
        m.value = "" as NSString
        m.extendedLanguageTag = "und"
        return m
    }
}

// Builds the AVKit Info-panel metadata from a catalog item. Title +
// description + genre are what the tvOS player surfaces; artwork would
// require fetching poster bytes synchronously, so it's left to the
// poster art on the Detail screen instead. The date-suppressing override is
// appended so the asset's bogus creation year never shows.
func makeExternalMetadata(for item: Catalog.Item) -> [AVMetadataItem] {
    var meta: [AVMetadataItem?] = [
        metaEntry(.commonIdentifierTitle, item.title)
    ]
    if let synopsis = item.displaySynopsis {
        meta.append(metaEntry(.commonIdentifierDescription, synopsis))
    }
    if !item.genres.isEmpty {
        meta.append(metaEntry(.quickTimeMetadataGenre,
                              item.genres.prefix(3).joined(separator: ", ")))
    }
    return meta.compactMap { $0 } + suppressedDateMetadata()
}

#endif
