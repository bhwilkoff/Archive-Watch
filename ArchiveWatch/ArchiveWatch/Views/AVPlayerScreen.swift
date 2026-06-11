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

struct AVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var menuItems: [UIMenuElement] = []   // #10: per-video transport menu (autoplay override)

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.speeds = AVPlaybackSpeed.systemDefaultSpeeds   // #5: native speed menu
        vc.transportBarCustomMenuItems = menuItems
        // tvOS PiP (swipe up / TV button while playing → corner window). Needs
        // the `audio` UIBackgroundModes entry, added alongside this.
        vc.allowsPictureInPicturePlayback = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        vc.transportBarCustomMenuItems = menuItems        // reflect autoplay-mode changes
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
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.parent = self
        context.coordinator.apply(to: vc)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator {
        var parent: EpisodeAVPlayerContainer
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
