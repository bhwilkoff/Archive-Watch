import AVFoundation
#if canImport(AVKit)
import AVKit
#endif

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


    /// The full hand-over: offer, switch on, and if nothing comes through the
    /// resilient loader, move to the direct URL and try once more.
    ///
    /// Returns true when the system is genuinely captioning this film, which is
    /// the only condition under which our own engine should stand down.
    @MainActor
    static func handOver(to player: AVPlayer?, directURL: URL?) async -> Bool {
        guard await waitForLegibleOption(on: player) else { return false }
        guard await enableSystemCaptions(on: player) else { return false }
        if await emitsCaptions(on: player) { return true }
        // Offered but mute: the loader is disqualifying it. Give it the one
        // thing it needs, then judge again — and if it still says nothing, this
        // film is not one the system will caption and we keep our own engine.
        guard let directURL else { return false }
        guard await swapToCaptionableAsset(on: player, url: directURL) else { return false }
        guard await enableSystemCaptions(on: player) else { return false }
        return await emitsCaptions(on: player)
    }

    /// Swap to an asset the system can actually caption, keeping the position.
    ///
    /// Generated subtitles do NOT work through a custom `AVAssetResourceLoader`.
    /// Measured on macOS 27, same film, same moment:
    ///
    ///     plain URL        option offered · first text at 34s
    ///     aw-stream://     option offered · NEVER any text
    ///
    /// The system advertises the track either way and silently produces nothing
    /// through the loader — the same disqualification that rules out video
    /// AirPlay (Decision 051), which is why an Apple TV on tvOS 27 showed
    /// file-based captions and never an automatic one.
    ///
    /// Decision 061 recorded that this DID work through the loader. That test
    /// only checked an option was OFFERED, never that text was produced — the
    /// exact distinction Decision 063 was later written about.
    ///
    /// So the loader is kept for every film until the system has been given a
    /// fair chance and failed; only then is playback moved onto the direct URL,
    /// paying Decisions 021/031/034's resilience for captions that would
    /// otherwise never appear. Films the system was never going to caption keep
    /// the resilient path.
    @MainActor
    static func swapToCaptionableAsset(on player: AVPlayer?, url: URL) async -> Bool {
        guard let player, let current = player.currentItem else { return false }
        let position = current.currentTime()
        let replacement = AVPlayerItem(url: url)
        replacement.preferredForwardBufferDuration = 300
        #if os(iOS) || os(tvOS) || os(visionOS)
        // Carry the Info-panel metadata across, or the swap blanks the title.
        // macOS AVPlayerItem has no `externalMetadata` at all — verified against
        // the macOS 27 SDK; its player carries the title in the window bar.
        replacement.externalMetadata = current.externalMetadata
        #endif
        player.replaceCurrentItem(with: replacement)
        // A seek issued before the new item is ready is DROPPED — the lesson
        // that cost AirPlay its resume position (Decision 051).
        for _ in 0..<40 {
            if replacement.status == .readyToPlay { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if position.isNumeric, position.seconds > 1 {
            await replacement.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        print("[AWCAP] moved to the direct URL so the system can caption this film")
        return true
    }

    /// Turn the system's subtitle track ON.
    ///
    /// Offering a track and showing it are different things, and this app was
    /// inconsistent about which it did. A PUBLISHED track is declared
    /// `AUTOSELECT=YES,DEFAULT=YES` in the master playlist we generate, so
    /// AVPlayer switches it on by itself. A GENERATED track has no such
    /// declaration — the system lists it in the subtitle menu and leaves it off
    /// — and nothing here ever selected it. On tvOS 27 that is exactly what the
    /// owner saw: file-based captions working, automatic ones never appearing.
    ///
    /// It also broke the check below, which listens for emitted text: a track
    /// that is switched off emits nothing, so the app concluded the system had
    /// declined and fell back to an engine that, on an Apple TV, has no models
    /// (Decision 060). Select first, then judge.
    ///
    /// A selection the VIEWER has already made is never overridden.
    @MainActor
    @discardableResult
    static func enableSystemCaptions(on player: AVPlayer?) async -> Bool {
        guard let item = player?.currentItem else { return false }
        let box = await LegibleProbe(asset: item.asset).group()
        guard let group = box.group, !group.options.isEmpty else { return false }
        if item.currentMediaSelection.selectedMediaOption(in: group) != nil { return true }
        let preferred = AVMediaSelectionGroup.mediaSelectionOptions(
            from: group.options, with: Locale.current)
        guard let option = preferred.first ?? group.options.first else { return false }
        item.select(option, in: group)
        print("[AWCAP] system captions on: \(option.displayName)")
        return true
    }

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
