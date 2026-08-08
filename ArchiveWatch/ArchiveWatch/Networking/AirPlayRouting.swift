import Foundation

// AirPlay routing — which URL an AirPlay RECEIVER should fetch, and whether a
// URL is fetchable by a receiver at all.
//
// THE CONSTRAINT (Apple, via TSI): "Video AirPlay is not supported when using a
// custom resource loader." Every playback path in this app is loader-backed —
// `aw-stream://` for the resilient MP4 stream (Decisions 021 / 031 / 034) and
// `aw-hls://` for the captioned HLS layer (Decision 039 Config C). The delegate
// that serves those schemes lives on the SENDING device, so a receiver has no
// way to pull the media: selecting a route showed an error on the Apple TV
// instead of playing, on every title.
//
// The fix is to hand the receiver a URL it can fetch itself the moment a route
// engages, and to restore the resilient on-device path when it disengages. The
// loader's resume/failover cannot help over AirPlay regardless — the receiver
// owns the connection, the same trade Decision 047 records for Roku.
//
// This type is deliberately Foundation-only and free of AVFoundation so
// `tools/test_airplay_routing.swift` can compile THIS FILE and assert the
// decisions. AirPlay cannot be exercised on a simulator (there are no routes),
// so the decision logic is the part that can be tested off-device — and it is
// the part that was wrong.
enum AirPlayRouting {

    /// Custom schemes served by an on-device `AVAssetResourceLoaderDelegate`.
    /// SOURCE OF TRUTH — the loaders read their `scheme` from here, so a new
    /// loader cannot be added without this list learning about it.
    static let streamScheme = "aw-stream"
    static let hlsScheme = "aw-hls"

    static let loaderSchemes: Set<String> = [streamScheme, hlsScheme]

    /// True when an AirPlay receiver could fetch this URL on its own.
    ///
    /// A custom-scheme URL is the failure this whole type exists to prevent, but
    /// a `file://` URL is just as unfetchable from another device, so the test is
    /// an allow-list of remote schemes rather than a deny-list of ours.
    static func isReceiverFetchable(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        guard !loaderSchemes.contains(scheme) else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// The URL to hand a receiver, given the two published forms of a title.
    ///
    /// HLS is preferred: it is receiver-fetchable AND carries the WebVTT caption
    /// renditions, so subtitles survive the handoff. The progressive MP4 is the
    /// fallback for the ~majority of titles that have no caption track.
    /// Returns nil when neither is fetchable — the caller must then leave
    /// playback alone rather than swap to something broken.
    static func receiverURL(hls: URL?, mp4: URL?) -> URL? {
        if isReceiverFetchable(hls) { return hls }
        if isReceiverFetchable(mp4) { return mp4 }
        return nil
    }

    /// Why a swap was or wasn't possible — surfaced in diagnostics
    /// (`AW_PLAYBACK_DIAG=1`) because AirPlay can only be judged on real
    /// hardware, so the logs are the evidence when it is.
    static func describe(hls: URL?, mp4: URL?) -> String {
        guard let picked = receiverURL(hls: hls, mp4: mp4) else {
            return "AWAIRPLAY no receiver-fetchable URL (hls=\(hls?.scheme ?? "nil") "
                 + "mp4=\(mp4?.scheme ?? "nil")) — staying on the local path"
        }
        let kind = (picked == hls) ? "hls+captions" : "mp4"
        return "AWAIRPLAY handing receiver \(kind): \(picked.host ?? "?")"
    }
}
