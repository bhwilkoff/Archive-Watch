import AVFoundation

// Does the SYSTEM already offer subtitles for what is playing?
//
// From 27, Apple generates subtitles for video that has none — on device, live,
// in the player's own subtitle menu, styled by the viewer's caption settings, on
// iOS, macOS, tvOS and visionOS. Apple's position is explicit: "you don't need to
// implement anything to turn on generated subtitles. They're available
// automatically during video playback" (WWDC26 session 256), for any app using
// AVPlayerViewController / AVPlayerView — which all three of ours do.
//
// So the work is not to ADD anything. It is to not fight it. The failure that
// would otherwise arrive with 27 is DOUBLE captions: the system drawing its own
// subtitles while `LiveCaptions` draws a second, differently timed copy over the
// top. On iOS and macOS, where our engine genuinely works today, that would be a
// visible regression on upgrade day.
//
// The system's are better on every count — they live in the native menu, obey
// the viewer's chosen style, survive scrubbing, and cost no second stream — so
// ours stands down whenever the system has anything legible to offer.
//
// There is no "are these generated?" API, and none is needed: the question that
// decides our behaviour is whether ANY legible option exists. A published WebVTT
// track and a generated one both answer yes, and in both cases our overlay is
// redundant. `AVPlayerItem.selectableMediaSelectionOptions(in:)` is new in 27 and
// is where a generated track can appear — it is not in the file, so the asset's
// own group will never list it.
enum SystemCaptions {

    /// `AVAsset` and `AVMediaSelectionGroup` are not Sendable, so loading the
    /// group from a main-actor context is a concurrency error. Both are
    /// effectively immutable here — we read `options` and nothing else — so a
    /// narrow box is the honest way across, rather than the deprecated
    /// synchronous accessor.
    private struct LegibleProbe: @unchecked Sendable {
        let asset: AVAsset
        func group() async -> GroupBox {
            GroupBox(group: try? await asset.loadMediaSelectionGroup(for: .legible))
        }
    }
    private struct GroupBox: @unchecked Sendable { let group: AVMediaSelectionGroup? }

    /// True once the player offers a subtitle track of its own.
    ///
    /// Polled rather than checked once: a generated track appears a moment after
    /// playback begins, not at item creation. On a system with no such feature
    /// this simply costs one wait before our own engine starts — and on those
    /// systems our engine is usually the only thing that will ever caption.
    @MainActor
    static func waitForLegibleOption(on player: AVPlayer?,
                                     within seconds: Double = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let item = player?.currentItem {
                let box = await LegibleProbe(asset: item.asset).group()
                if let group = box.group {
                    // Ask the ITEM what is selectable, not the asset what it
                    // contains: a generated track exists only at the item.
                    if #available(iOS 27, tvOS 27, macOS 27, visionOS 27, *) {
                        if !item.selectableMediaSelectionOptions(in: group).isEmpty {
                            return true
                        }
                    }
                    if !group.options.isEmpty { return true }
                }
            }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 700_000_000)
        } while Date() < deadline
        return false
    }
}
