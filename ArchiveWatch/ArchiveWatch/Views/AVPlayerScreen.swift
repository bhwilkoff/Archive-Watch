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
    /// The source currently being transcribed, so an autoplay advance to the
    /// next film restarts the engine instead of captioning the previous one
    /// forever (the container is reused; only its player is swapped).
    private var sourceURL: URL?
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

    /// `reviewing` is the published WebVTT when the film already HAS subtitles:
    /// the engine then runs only long enough to judge that file, and draws
    /// nothing unless it turns out to be wrong.
    func startCaptions(url: URL, player: AVPlayer?, in vc: AVPlayerViewController,
                       reviewing vtt: URL? = nil) {
        guard sourceURL != url else { return }
        stop()
        sourceURL = url
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
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                l.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor,
                                          constant: -90),
                l.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor,
                                         multiplier: 0.8),
            ])
        }
        label = l

        draws = vtt == nil
        loop = Task { @MainActor [weak self] in
            // Let the system speak first. On tvOS 27 it captions this film
            // itself; ours would be a second, differently timed copy over the
            // top of it. On tvOS 26 nothing legible ever appears, so this costs
            // one poll and then proceeds exactly as before.
            if await SystemCaptions.handOver(to: player, directURL: url) {
                print("[AWCAP] system provides subtitles — standing down")
                self?.label?.removeFromSuperview()
                self?.label = nil
                return
            }
            guard !Task.isCancelled else { return }
            // The system did not caption this film. On an Apple TV our own
            // engine cannot either — tvOS carries no speech models and cannot
            // install them (Decision 060) — so without this the screen simply
            // stays blank and the reason is unknowable from the room it happens
            // in. Say which stage the handover reached.
            if await CaptionCapability.shared.resolved() == false {
                self?.systemNote = "Subtitles unavailable — \(SystemCaptions.stage.rawValue)."
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
                    guard let outcome = await SubtitleReview.review(vttURL: vtt,
                                                                    captions: lc) else { return }
                    if outcome.replacesNativeTrack {
                        await SubtitleReview.deselectNativeSubtitles(on: player)
                        self?.draws = true
                    } else {
                        self?.label?.isHidden = true
                    }
                }
            }
            while !Task.isCancelled, lc.isRunning {
                let now = player?.currentTime() ?? .zero
                lc.throttle(playhead: now)
                // Between captions, say why there are none — a blank screen and
                // a failed recognizer look identical from the sofa.
                let line = lc.line(at: now)
                let text = (self?.draws ?? true) ? (line.isEmpty ? lc.notice : line) : ""
                // A caption is two lines; an explanation may need more.
                self?.label?.numberOfLines = line.isEmpty ? 4 : 2
                self?.label?.text = text.isEmpty ? nil : "  \(text)  "
                self?.label?.isHidden = text.isEmpty
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        captions?.stop(); captions = nil
        label?.removeFromSuperview(); label = nil
        sourceURL = nil
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
