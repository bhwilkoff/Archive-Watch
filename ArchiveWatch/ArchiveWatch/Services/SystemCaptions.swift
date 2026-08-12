import AVFoundation
import MediaAccessibility
#if canImport(AVKit)
import AVKit
#endif

// Does the SYSTEM caption this film, and what must we do to let it?
//
// From 27, Apple generates subtitles on device for video that carries none — in
// the player's own subtitle menu, styled by the viewer's caption settings, on
// iOS, macOS, tvOS and visionOS. Apple's position is that no app implementation
// is required (WWDC26 session 256), and for an app that hands AVPlayer an
// ordinary URL that is true.
//
// This app does not hand AVPlayer an ordinary URL. Every playback path wraps
// archive.org's progressive MP4 in a custom `AVAssetResourceLoaderDelegate`
// (Decisions 021/031/034), and THAT is what has to give way. Measured on
// macOS 27.0 (26A5388g), one shape per process so no result could contaminate
// the next, against a film the system is known to caption:
//
//     plain direct MP4 (/download URL)     option offered · TEXT in 33s
//     node-resolved direct node URL        option offered · TEXT in 30s
//     HLS master wrapping the same MP4     option offered · NEVER any text
//     aw-stream:// resilient loader        NO OPTION EVER OFFERED
//
// Two things follow, and both contradict what was previously recorded here.
//
// FIRST: wrapping the MP4 in HLS does not help. The obvious reading of Apple's
// "HLS and file-based content" is that a playlist would qualify us, and it does
// not — a single-segment playlist pointing at a remote MP4 is offered a track
// that stays silent forever, exactly like the loader.
//
// SECOND: through the resilient loader the option is not offered AT ALL.
// Decision 065 recorded "offered but silent" and built a four-stage handover on
// top of that: wait for the option, select it, listen for text, and only then
// swap to the direct URL. But the swap was gated behind an option that never
// arrives, so on tvOS it could never run. That "offered" reading came from a
// harness that probed four shapes in ONE process, where a track left over from
// the previous player was counted as this one's — a shape identical to the
// passing one failed later in the same run, which is what exposed it.
//
// So the asset shape is decided UP FRONT instead: a film with no published
// subtitle track plays on the direct URL where the system can caption it, and
// there is no dance to get wrong. What is left here is small — select the
// track if the viewer wants captions, and report whether the system is
// genuinely captioning so our own engine knows to stand down.
enum SystemCaptions {

    /// Where the handover got to, for a UI that has to explain itself to
    /// someone on a sofa. The Apple TV is the only device that can answer this
    /// question and its console cannot be read from a development machine, so
    /// the state has to be visible in the app or it is not observable at all.
    enum Stage: String {
        case notAttempted     = "not attempted"
        case unavailable      = "system does not generate subtitles here"
        case waitingForTrack  = "waiting for the system's subtitle track"
        case noTrackOffered   = "the system offered no subtitle track"
        case selected         = "subtitle track selected, waiting for text"
        case notSelected      = "a track exists but was not selected — check caption settings"
        case captioning       = "the system is captioning this film"
        case declined         = "the system offered a track but produced no text"
    }

    /// Last handover outcome, for the on-screen notice. Main-actor confined.
    @MainActor private(set) static var stage: Stage = .notAttempted
    @MainActor static func resetStage() { stage = .notAttempted }

    /// True where the system generates subtitles at all.
    ///
    /// A version check only — it references no 27 symbol, deliberately. The App
    /// Store archive is built with the RELEASED Xcode (the workflow requires it
    /// to clear ITMS-90111), whose SDK has none, and reaching for
    /// `AVPlayerItem.selectableMediaSelectionOptions(in:)` is what broke build
    /// 876. Nothing here needs it: the generated track appears in the asset's
    /// own legible group, measured at t=1s.
    static var isAvailable: Bool {
        if #available(iOS 27, tvOS 27, macOS 27, visionOS 27, *) { return true }
        return false
    }

    /// Should this film play on the DIRECT url rather than through the
    /// resilient loader, so the system can caption it?
    ///
    /// Only for a film with no subtitle track of its own — a film that already
    /// has one keeps the captioned-HLS path, which works today and whose
    /// subtitles are human rather than machine-made.
    ///
    /// This is deliberately NOT gated on the viewer's caption preference. The
    /// tempting version — play direct only when captions are switched on —
    /// keeps maximum resilience for everyone else, but "Generated Subtitles" is
    /// its own Settings toggle, separate from the captions display preference,
    /// so a viewer can have generated subtitles on while the display type is
    /// still `.automatic`. Gating on the preference would then leave the menu
    /// empty for exactly the person who went looking for it, which is the bug
    /// this is fixing. A track nobody can find is not a feature.
    static func prefersDirectPlayback(hasPublishedSubtitles: Bool) -> Bool {
        isAvailable && !hasPublishedSubtitles
    }

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

    /// Let the system caption this film if it will, and say whether it did.
    ///
    /// Returns true only when text was actually seen — the one condition under
    /// which our own engine should stand down. Offering a track and producing
    /// captions are different claims, and on this catalogue they come apart:
    /// measured across three films, the system offered a track on all three and
    /// emitted cues on ONE, declining on poor archival optical sound rather
    /// than guessing at it. Standing down on the mere presence of a track would
    /// leave a viewer with nothing on exactly the films that need help most.
    @MainActor
    static func handOver(to player: AVPlayer?, directURL: URL? = nil) async -> Bool {
        guard isAvailable else { stage = .unavailable; return false }
        stage = .waitingForTrack
        guard await waitForLegibleOption(on: player) else {
            stage = .noTrackOffered
            return false
        }
        // An unselected track emits nothing, so listening for text after a
        // failed selection would report ".declined" 75 seconds later when the
        // truth was known immediately — and on a device set to forced-only
        // subtitles the wait is guaranteed to be wasted. Say why, and stop.
        guard await selectIfWanted(on: player) else {
            stage = .notSelected
            return false
        }
        stage = .selected
        if await emitsCaptions(on: player) { stage = .captioning; return true }
        stage = .declined
        return false
    }

    /// Switch the system's track on, unless the viewer has already chosen.
    ///
    /// A PUBLISHED track is declared `AUTOSELECT=YES,DEFAULT=YES` in the master
    /// playlist we generate, so AVPlayer switches it on by itself. A GENERATED
    /// track carries no such declaration — the system lists it and leaves it
    /// off — and an unselected track emits nothing, so a check that listens for
    /// text before selecting is measuring the selection, not the recognizer.
    ///
    /// A selection the VIEWER has made is never overridden, and nothing is
    /// selected for someone who has asked to see forced subtitles only.
    @MainActor
    @discardableResult
    static func selectIfWanted(on player: AVPlayer?) async -> Bool {
        guard let item = player?.currentItem else { return false }
        let box = await LegibleProbe(asset: item.asset).group()
        guard let group = box.group, !group.options.isEmpty else { return false }
        if item.currentMediaSelection.selectedMediaOption(in: group) != nil { return true }
        guard MACaptionAppearanceGetDisplayType(.user) != .forcedOnly else { return false }
        let preferred = AVMediaSelectionGroup.mediaSelectionOptions(
            from: group.options, with: Locale.current)
        guard let option = preferred.first ?? group.options.first else { return false }
        item.select(option, in: group)
        return true
    }

    /// Does the system's track actually SAY anything on this film?
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
    /// Polled rather than checked once: a generated track appears a moment
    /// after playback begins, not at item creation. Measured at t=1s on a
    /// direct URL, so 15s is generous; on a system with no such feature this
    /// costs one wait before our own engine starts.
    @MainActor
    static func waitForLegibleOption(on player: AVPlayer?,
                                     within seconds: Double = 15) async -> Bool {
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
