import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

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

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
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
// of stall-starting on an empty buffer. 120s at a typical PD bitrate is tens of
// MB — comfortable headroom on the 3 GB Apple TV.
let archivePreferredForwardBufferDuration: TimeInterval = 120

func tunePlaybackBuffering(item: AVPlayerItem, player: AVPlayer) {
    item.preferredForwardBufferDuration = archivePreferredForwardBufferDuration
    player.automaticallyWaitsToMinimizeStalling = true
}

// Registers a Now Playing data source so the system stops logging
// "[MRPlaybackQueueServiceClient] ... Code=15 Operation requires a client data
// source to have been registered" — those are MediaRemote (PineBoard, the
// Remote app, AVKit) polling for Now Playing artwork that was never published.
// Populating MPNowPlayingInfoCenter with title + poster also makes the poster
// show on the Now Playing widget and the remote. AVPlayerViewController owns the
// transport, so we only supply metadata + artwork, not remote-command handlers.
@MainActor
final class NowPlayingController {
    private var artworkTask: Task<Void, Never>?

    func begin(title: String, subtitle: String?, posterURL: URL?, player: AVPlayer) {
        // An active playback audio session is what registers us as a MediaRemote
        // client; without it the Now Playing info is ignored.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let subtitle, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
        let duration = player.currentItem?.duration.seconds
        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        let elapsed = player.currentTime().seconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed.isFinite ? elapsed : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Poster bytes load async; patch the artwork in once it arrives so we
        // never block playback start on a network fetch.
        guard let posterURL else { return }
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: posterURL),
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
    }

    // Keep the scrubber on the Now Playing widget in sync (the system
    // extrapolates from rate, but a periodic nudge corrects drift after seeks).
    func update(elapsed: Double, rate: Float) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        if elapsed.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
