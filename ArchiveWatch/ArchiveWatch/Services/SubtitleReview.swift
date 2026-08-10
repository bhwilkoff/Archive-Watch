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

    /// How long to listen before judging. Long enough for a verdict on a film
    /// that opens quietly; at the scout's 2x that is ~90s of wall clock.
    static let sampleSeconds: Double = 180

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
        guard let published = await fetchCues(vttURL), !published.isEmpty else { return nil }

        // Wait for the scout to cover the sample window, or to give up.
        let deadline = Date().addingTimeInterval(sampleSeconds * 1.5 + 60)
        while Date() < deadline {
            if !captions.isRunning { break }
            if captions.leadSeconds(over: .zero) > sampleSeconds { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        let transcript = captions.transcript().map {
            SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
        }
        guard let verdict = SubtitleAgreement.judge(published: published,
                                                    transcript: transcript) else {
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

    private struct LegibleGroup: @unchecked Sendable {
        let asset: AVAsset
        func load() async -> Box {
            Box(group: try? await asset.loadMediaSelectionGroup(for: .legible))
        }
        struct Box: @unchecked Sendable { let group: AVMediaSelectionGroup? }
    }

    private static func fetchCues(_ url: URL) async -> [SubtitleAgreement.Cue]? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let body = String(data: data, encoding: .utf8) else { return nil }
        let cues = SubtitleAgreement.parseVTT(body)
        return cues.isEmpty ? nil : cues
    }
}
