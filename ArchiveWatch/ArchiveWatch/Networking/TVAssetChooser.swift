#if os(tvOS)
import AVFoundation
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
    static func makeItem(for url: URL) -> (AVPlayerItem, ResilientStreamLoader?) {
        // A loopback URL is already ours; never wrap it again.
        if url.host == "127.0.0.1" {
            return (AVPlayerItem(asset: AVURLAsset(url: url)), nil)
        }
        if ProcessInfo.processInfo.environment["AW_PLAIN_ASSET"] == "1" {
            return (AVPlayerItem(asset: AVURLAsset(url: url)), nil)
        }
        if needsHLS,
           let hls = LocalMediaServer.shared.hlsURL(for: url) {
            awdiag("AWHLS serving %@ as HLS", url.lastPathComponent)
            return (AVPlayerItem(url: hls), nil)
        }
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        return (AVPlayerItem(asset: asset), loader)
    }
}
#endif
