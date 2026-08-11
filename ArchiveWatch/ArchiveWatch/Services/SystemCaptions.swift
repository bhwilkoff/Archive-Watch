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
// redundant.
//
// The asset's OWN legible group is what we read, deliberately. There is also
// `AVPlayerItem.selectableMediaSelectionOptions(in:)`, new in 27 and the obvious
// place to look for a track that is not in the file — but the App Store archive
// is built with the RELEASED Xcode (the workflow requires it, to clear
// ITMS-90111), whose SDK has no 27 symbols, so referencing it compiles here on
// the beta and fails the only build that ships. It is also unnecessary:
// measured on macOS 27 against a live archive.org film, the generated track
// appears in the asset group too — `assetOptions=1` at t=1s.
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

    /// Does the system's track actually SAY anything on this film?
    ///
    /// Offering a track and producing captions are different claims, and on this
    /// catalogue they come apart. Measured on macOS 27 across three films: the
    /// system offered "English (US) Transcribed" on all three and emitted cues on
    /// ONE — a clear 1975 narration. On The Day the Earth Caught Fire (1961) and
    /// Meet John Doe (1941) it produced nothing at all across five minutes, while
    /// our own engine transcribed both at ~55% word error. It appears to decline
    /// rather than guess on poor archival optical sound, which is most of what
    /// this app holds.
    ///
    /// So standing down on the mere PRESENCE of a track would leave a viewer
    /// with no captions at all on exactly the films that need them most. This
    /// waits for real text before handing over.
    @MainActor
    static func emitsCaptions(on player: AVPlayer?, within seconds: Double = 75) async -> Bool {
        guard let item = player?.currentItem else { return false }
        let sink = EmissionSink()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        // Observe only — the player must go on drawing its own subtitles.
        output.suppressesPlayerRendering = false
        output.setDelegate(sink, queue: .main)
        item.add(output)
        defer { item.remove(output) }

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if sink.sawText { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return sink.sawText
    }

    private final class EmissionSink: NSObject, AVPlayerItemLegibleOutputPushDelegate,
                                      @unchecked Sendable {
        private let lock = NSLock()
        private var _sawText = false
        var sawText: Bool { lock.lock(); defer { lock.unlock() }; return _sawText }
        func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                           didOutputAttributedStrings strings: [NSAttributedString],
                           nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
            guard strings.contains(where: {
                !$0.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { return }
            lock.lock(); _sawText = true; lock.unlock()
        }
    }

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
                if let group = box.group, !group.options.isEmpty { return true }
            }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 700_000_000)
        } while Date() < deadline
        return false
    }
}
