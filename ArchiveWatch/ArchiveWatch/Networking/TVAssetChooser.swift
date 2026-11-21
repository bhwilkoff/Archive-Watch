#if os(tvOS)
import AVFoundation
import UIKit
import Foundation

/// The ONE place tvOS decides how a film's bytes reach AVPlayer.
///
/// tvOS 27 stops rendering the AUDIO of a NON-FRAGMENTED mp4 a few minutes in.
/// Measured on the owner's Apple TV, at the moment audio died: buffer healthy
/// (75-89s ahead), rate 1.00, zero stalls, an EMPTY error log, the audio track
/// still enabled with 2 channels on the route, and the player item never
/// swapped -- video simply played on in silence. A fragmented mp4 of the same
/// footage ran 11+ minutes untouched and HLS played a whole feature, on the
/// same device, same film, same build. Another Apple TV on tvOS 26.6 is fine,
/// and other apps on 27 are fine because they ship HLS; this catalog is
/// progressive mp4 end to end, which is why only we are hit.
///
/// So on 27+ the film is remuxed to fragments on the fly (`MP4Fragmenter`,
/// no re-encode) and published as an HLS VOD playlist by the EXISTING
/// `LocalMediaServer` (Decision 082). Its origin side already carries
/// Decisions 021/031/034 -- chunked ranged reads, node pinning, failover --
/// so resilience is inherited rather than rebuilt. Segments travel over that
/// loopback HTTP because AVFoundation refuses a custom-scheme HLS media
/// segment with -12881 (harness-proven 2026-07-22).
///
/// Below 27, Decision 072's single pipeline is untouched.
///
/// EVERY tvOS playback surface calls this. The movie player and the episode
/// player choosing separately is precisely how this project has repeatedly
/// shipped a fix to one screen and not the other.
enum TVAssetChooser {

    /// The defect is tvOS 27's. Earlier systems play the plain file correctly
    /// and keep Decision 072's pipeline; overrides exist for bisecting.
    static var needsHLS: Bool {
        if ProcessInfo.processInfo.environment["AW_FORCE_FRAG"] == "1" { return true }
        if ProcessInfo.processInfo.environment["AW_NO_FRAG"] == "1" { return false }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(
            .init(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }

    /// Returns the item to play, plus the resilient loader to RETAIN when one
    /// is used (`AVURLAsset` holds its resource-loader delegate weakly).
    ///
    /// A non-zero `audioOffset` (Audio Sync, tvOS-DESIGN §8.2a) always takes
    /// the remux, on any tvOS: the remux is the only place the sound can be
    /// moved against the picture without re-encoding.
    static func makeItem(for url: URL, audioOffset: Double = 0) -> (AVPlayerItem, ResilientStreamLoader?) {
        // A loopback URL is already ours; never wrap it again.
        if url.host == "127.0.0.1" {
            return (AVPlayerItem(asset: AVURLAsset(url: url)), nil)
        }
        #if DEBUG
        // Caption research door (owner 2026-09-28): AW_PLAY_PATH=direct|proxy|hls.
        if let forced = ProcessInfo.processInfo.environment["AW_PLAY_PATH"] {
            let local = forced == "hls" ? LocalMediaServer.shared.hlsURL(for: url)
                      : forced == "proxy" ? LocalMediaServer.shared.proxyURL(for: url) : url
            awdiag("AWPLAYER research path=%@ url=%@", forced, (local ?? url).absoluteString)
            return (AVPlayerItem(url: local ?? url), nil)
        }
        #endif
        if ProcessInfo.processInfo.environment["AW_PLAIN_ASSET"] == "1" {
            return (AVPlayerItem(asset: AVURLAsset(url: url)), nil)
        }
        if needsHLS || audioOffset != 0,
           let hls = LocalMediaServer.shared.hlsURL(for: url, audioOffset: audioOffset) {
            awdiag("AWHLS serving %@ as HLS audioOffset=%.1f", url.lastPathComponent, audioOffset)
            return (AVPlayerItem(url: hls), nil)
        }
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        return (AVPlayerItem(asset: asset), loader)
    }
}

/// Audio Sync (tvOS-DESIGN §8.2a): the transport-bar menu that moves a film's
/// sound against its picture, for an upload whose sound has drifted. One
/// builder for the movie and the episode players, for the reason
/// `TVAssetChooser` gives. The choice lasts for the film on screen; the
/// player rebuilds at the same moment through the remux.
@MainActor
enum AudioSync {
    /// -2.0 ... +2.0 s in 0.1 s steps; positive plays the sound later.
    static let steps: [Double] = (-20...20).map { Double($0) / 10 }

    static func label(_ v: Double) -> String {
        if abs(v) < 0.05 { return "Original" }
        return String(format: "%.1f s %@", abs(v), v < 0 ? "earlier" : "later")
    }

    static func menu(current: Double, choose: @escaping @MainActor (Double) -> Void) -> UIMenu {
        let actions = steps.map { v in
            UIAction(title: label(v), state: abs(v - current) < 0.05 ? .on : .off) { _ in
                choose(v)
            }
        }
        // Single selection, like the system's Playback Speed menu: the menu
        // opens with focus on the current value, not at the top of 41 steps.
        let m = UIMenu(title: "Audio Sync", image: UIImage(systemName: "waveform.badge.plus"),
                       options: .singleSelection, children: actions)
        if abs(current) >= 0.05 { m.subtitle = label(current) }
        return m
    }
}
#endif
