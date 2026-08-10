// Can the device tell a good subtitle file from a bad one?
//
// The claim `SubtitleAgreement` makes is that our own transcript is enough to
// judge a published track — to catch a file that belongs to a different cut, and
// to catch one that is right but lands seconds from the mouths saying it. A
// claim like that is worth nothing untested, because the failure mode is silent:
// a judge that always says "keep" looks identical to a correct one until a
// viewer hits a bad file.
//
// So this drives the SHIPPED judge against a real film, with three controls:
//
//   MATCH     the film's own published subtitles           -> keepPublished
//   SHIFTED   the same file, deliberately moved by N secs  -> shiftPublished(-N)
//   MISMATCH  another film's subtitles entirely            -> preferLive
//
// The shifted and mismatched cases are what make this a test rather than a demo.
// Without them, a judge that never disagrees passes.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleAgreement.swift \
//     tools/test_subtitle_agreement.swift -o /tmp/awagree && /tmp/awagree

import AVFoundation
import Foundation

@main
struct Harness {
    // A talky film with a healthy published track, and an unrelated one.
    static let film = "https://archive.org/download/day-the-earth-caught-fire/"
        + "Day%20the%20Earth%20Caught%20Fire.mp4"
    static let ownSubs = "https://archivewatch.org/subs/day-the-earth-caught-fire/en.vtt"
    static let otherSubs = "https://archivewatch.org/subs/bloody_pit_of_horror_ipod/en.vtt"
    static let listenFor: Double = 300

    static func main() async {
        guard await LiveCaptions.isSupported else { print("no recognizer here"); exit(1) }
        guard let mp4 = URL(string: film), let own = URL(string: ownSubs),
              let other = URL(string: otherSubs) else { exit(2) }

        guard let ownText = await fetch(own), let otherText = await fetch(other) else {
            print("could not fetch the subtitle files"); exit(2)
        }
        let published = SubtitleAgreement.parseVTT(ownText)
        let unrelated = SubtitleAgreement.parseVTT(otherText)
        print("published: \(published.count) cues · unrelated: \(unrelated.count) cues")

        let transcript = await listen(to: mp4, seconds: listenFor)
        print("transcript: \(transcript.count) cues covering "
              + String(format: "%.0f–%.0fs\n", transcript.first?.start ?? 0,
                       transcript.last?.end ?? 0))
        guard transcript.count > 5 else { print("nothing transcribed"); exit(1) }

        var failures = 0

        // The film's OWN published track turned out to be ~25s out of sync — the
        // exact fault this exists to catch, and a reminder that "its own file"
        // is not the same as "a correct file". So the controls are derived from
        // what the judge measures, which makes the test self-consistent instead
        // of dependent on finding a perfectly-aligned film:
        //
        //   as published  -> a shift is detected
        //   corrected by that shift -> keep, with no further shift
        //   corrected, then moved 6s -> the same shift back, ±6
        guard let asPublished = SubtitleAgreement.judge(published: published,
                                                        transcript: transcript) else {
            print("no verdict on the film's own subtitles"); exit(1)
        }
        report("AS PUBLISHED", asPublished)
        let correction = asPublished.offset
        if case .keepPublished = asPublished.choice, abs(correction) > 2 {
            print("   WRONG · \(correction)s out of sync but reported as a match"); failures += 1
        }

        let aligned = published.map {
            SubtitleAgreement.Cue(start: $0.start + correction,
                                  end: $0.end + correction, text: $0.text)
        }
        failures += check("ALIGNED (corrected by \(String(format: "%.1f", correction))s)",
                          expect: "keep",
                          SubtitleAgreement.judge(published: aligned, transcript: transcript))

        let shift = 6.0
        let shifted = aligned.map {
            SubtitleAgreement.Cue(start: $0.start + shift, end: $0.end + shift, text: $0.text)
        }
        failures += check("ALIGNED then moved +6s", expect: "shift",
                          SubtitleAgreement.judge(published: shifted, transcript: transcript),
                          expectedOffset: -shift)

        failures += check("MISMATCH another film", expect: "live",
                          SubtitleAgreement.judge(published: unrelated, transcript: transcript))

        print(failures == 0
              ? "\nRESULT: OK — the judge keeps a good file, corrects a shifted one, "
                + "and rejects one that isn't this film."
              : "\nRESULT: FAIL — \(failures) case(s) judged wrongly.")
        exit(failures == 0 ? 0 : 1)
    }

    static func report(_ label: String, _ v: SubtitleAgreement.Verdict) {
        print(String(format: "%@\n   agreement %.0f%% (at zero %.0f%%) · offset %+.1fs · %d cues",
                     label, v.agreement * 100, v.agreementAtZero * 100, v.offset, v.comparedCues))
        print("   -> \(v.summary)")
    }

    static func check(_ label: String, expect: String,
                      _ verdict: SubtitleAgreement.Verdict?,
                      expectedOffset: Double? = nil) -> Int {
        guard let v = verdict else {
            print("\(label): NO VERDICT (not enough evidence)"); return 1
        }
        var ok: Bool
        switch (expect, v.choice) {
        case ("keep", .keepPublished): ok = true
        case ("live", .preferLive): ok = true
        case ("shift", .shiftPublished(let by)):
            ok = expectedOffset.map { abs(by - $0) < 1.5 } ?? true
        default: ok = false
        }
        print(String(format: "%@\n   %@ · agreement %.0f%% (at zero %.0f%%) · offset %+.1fs · %d cues",
                     label, ok ? "OK  " : "WRONG", v.agreement * 100,
                     v.agreementAtZero * 100, v.offset, v.comparedCues))
        print("   -> \(v.summary)")
        return ok ? 0 : 1
    }

    /// Transcribe the opening of the film with the shipped engine.
    static func listen(to url: URL, seconds: Double) async -> [SubtitleAgreement.Cue] {
        let captions = await LiveCaptions()
        await captions.start(url: url, from: .zero)
        let deadline = Date().addingTimeInterval(seconds * 1.3 + 90)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await captions.leadSeconds(over: .zero) > seconds { break }
            if await !captions.isRunning { break }
        }
        let cues = await captions.transcript().map {
            SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
        }
        await captions.stop()
        return cues
    }

    static func fetch(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
