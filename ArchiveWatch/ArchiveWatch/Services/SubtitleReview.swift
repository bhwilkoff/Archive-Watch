import AVFoundation
import Foundation

// Check a film's published subtitles against what is actually being said, while
// it plays, and act on the answer.
//
// `SubtitleAgreement` decides; this does the fetching, the sampling and the
// switching. It is deliberately BOUNDED: the scout transcribes a few minutes,
// a verdict is reached, and then it stops. Judging a file costs a short second
// stream, not a whole extra download of every captioned film — which matters
// most on a phone, where the owner says most viewers are.
//
// Three outcomes, three actions:
//
//   keepPublished  stop, and let the native track play as published. The
//                  common case, and the cheapest.
//   shiftPublished deselect the native track and show the SAME human words
//                  through our overlay at corrected times. Measured on The Day
//                  the Earth Caught Fire: its published file runs 25 seconds
//                  late, which is unwatchable and looks exactly like a broken
//                  app rather than a broken file.
//   preferLive     deselect the native track and keep transcribing — the file
//                  belongs to a different cut or a different film entirely.
@MainActor
enum SubtitleReview {

    /// Give up if nothing conclusive has emerged by here. Not a wait — the
    /// verdict lands as soon as the evidence supports it, usually far sooner.
    static let giveUpAfter: Double = 300
    /// How often to re-ask, while the film plays.
    static let checkEvery: UInt64 = 3_000_000_000
    /// The same answer twice before acting. A verdict from the first snatch of
    /// dialogue can be a fluke — two consecutive agreeing ones, on a growing
    /// transcript, is cheap insurance against switching a viewer's subtitles off
    /// on the strength of one mumbled line.
    static let confirmations = 2

    struct Outcome: Sendable {
        let verdict: SubtitleAgreement.Verdict
        /// True when the player's own subtitle track should be turned off.
        let replacesNativeTrack: Bool
    }

    /// Judge `vttURL` against `captions`, and reconfigure `captions` to show
    /// whichever is better. Returns nil when there was not enough to go on.
    ///
    /// The caller supplies the deselect, because turning off a native subtitle
    /// track is per-platform and belongs with the player.
    static func review(vttURL: URL, captions: LiveCaptions) async -> Outcome? {
        guard let published = await fetchCues(vttURL), !published.isEmpty else {
            // The claimed file does not exist or is empty — a purged junk track
            // met a client whose catalog still carries yesterday's claim
            // (measured live: Till the Clouds Roll By's laundered-ASR subtitles
            // were removed server-side and the iOS app then showed NO captions
            // at all: the scout ran forever, the overlay was never enabled, and
            // this returned nil, which callers read as "leave things alone").
            // An unreachable file is not "no opinion" — there is nothing to
            // show from it, so the engine takes over exactly as it does for a
            // file that belongs to another film.
            return Outcome(
                verdict: SubtitleAgreement.Verdict(
                    choice: .preferLive, agreement: 0, agreementAtZero: 0,
                    offset: 0, comparedCues: 0),
                replacesNativeTrack: true)
        }

        // JUDGE AS THE FILM PLAYS, not after a fixed sampling pass. The scout
        // transcribes AHEAD of the viewer, so a verdict reached now is in place
        // before they arrive at the part it was reached from — which is the
        // point: the right subtitles are showing by the time they are needed,
        // rather than three minutes of a broken file first.
        //
        // The earlier version waited out a flat 180s window whatever the film
        // was doing. On a talky opening the answer is available in well under a
        // minute, and on a quiet one no amount of waiting produces evidence.
        var verdict: SubtitleAgreement.Verdict?
        var agreed = 0
        let deadline = Date().addingTimeInterval(giveUpAfter)
        while Date() < deadline {
            let transcript = captions.transcript().map {
                SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
            }
            if let current = SubtitleAgreement.judge(published: published,
                                                     transcript: transcript) {
                if let previous = verdict, previous.choice.matches(current.choice) {
                    agreed += 1
                } else {
                    agreed = 1
                }
                verdict = current
                if agreed >= confirmations { break }
            }
            // The scout stopping is the end of the evidence, not a reason to
            // keep waiting.
            if !captions.isRunning, verdict != nil { break }
            if !captions.isRunning, captions.transcript().isEmpty { break }
            try? await Task.sleep(nanoseconds: checkEvery)
        }

        guard let verdict, agreed >= confirmations else {
            // No opinion is not the same as disagreement: leave the published
            // track alone and stop spending bandwidth on a second stream.
            captions.stopListening()
            return nil
        }
        print("[AWCAP] subtitle review: \(verdict.summary)")

        switch verdict.choice {
        case .keepPublished:
            captions.stopListening()
            return Outcome(verdict: verdict, replacesNativeTrack: false)

        case .shiftPublished(let by):
            captions.adopt(published.map {
                (start: $0.start + by, end: $0.end + by, text: $0.text)
            })
            return Outcome(verdict: verdict, replacesNativeTrack: true)

        case .preferLive:
            // Keep listening — the transcript IS the captions from here.
            return Outcome(verdict: verdict, replacesNativeTrack: true)
        }
    }

    /// Turn off whatever subtitle track the player is showing.
    static func deselectNativeSubtitles(on player: AVPlayer?) async {
        guard let item = player?.currentItem else { return }
        let box = await LegibleGroup(asset: item.asset).load()
        guard let group = box.group else { return }
        item.select(nil, in: group)
    }

    /// Did the deselect actually TAKE? A silent early return here is how His
    /// Girl Friday showed BOTH caption sets at once: the review's deselect
    /// targeted the player it started with, the stall fallback had rebuilt
    /// the player underneath it, the call returned without doing anything,
    /// and the published track kept rendering under our replacement. Offered
    /// ≠ selected ≠ deselected — confirm, never assume (the caption saga's
    /// one recurring lesson, now on its way back down).
    static func nativeSubtitlesOff(on player: AVPlayer?) async -> Bool {
        guard let item = player?.currentItem else { return true }
        let box = await LegibleGroup(asset: item.asset).load()
        guard let group = box.group else { return true }
        return item.currentMediaSelection.selectedMediaOption(in: group) == nil
    }

    private struct LegibleGroup: @unchecked Sendable {
        let asset: AVAsset
        func load() async -> Box {
            Box(group: try? await asset.loadMediaSelectionGroup(for: .legible))
        }
        struct Box: @unchecked Sendable { let group: AVMediaSelectionGroup? }
    }

    private static func fetchCues(_ url: URL) async -> [SubtitleAgreement.Cue]? {
        // One retry: a transient fetch failure must not condemn a good file to
        // preferLive for the whole session. A REAL 404 (purged track, stale
        // client claim) fails both attempts and correctly falls through.
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            if let (data, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
               let body = String(data: data, encoding: .utf8) {
                let cues = SubtitleAgreement.parseVTT(body)
                if !cues.isEmpty { return cues }
            }
        }
        return nil
    }
}
