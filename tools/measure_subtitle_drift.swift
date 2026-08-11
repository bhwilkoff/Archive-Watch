// Is a subtitle file merely LATE, or does it DRIFT?
//
// A single shift fixes a file that is uniformly late. It cannot fix one whose
// error grows through the film — which is what a 25 fps subtitle laid over a
// 23.976 fps print does: 4.3% slower, so a cue that is a second out at the start
// is nearly three minutes out at the end of a feature. The owner's report on The
// Night Stalker after correction — "far better than it was ... but not perfectly
// in sync" — is exactly what a residual drift feels like.
//
// So this measures the offset at TWO points in the film and reports whether they
// agree. If they do, one shift is the whole answer. If they don't, the file needs
// a scale as well, and every constant-shift correction is leaving error on the
// table at one end or the other.
//
// Build:
//   xcrun swiftc -O -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleAgreement.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/measure_subtitle_drift.swift -o /tmp/awdrift
//   /tmp/awdrift <mp4> <vtt> [windowSeconds]

import AVFoundation
import Foundation

@main
struct Drift {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 2, let mp4 = URL(string: args[1]), let vtt = URL(string: args[2]) else {
            print("usage: awdrift <mp4> <vtt> [windowSeconds]"); exit(2)
        }
        let window = args.count > 3 ? (Double(args[3]) ?? 240) : 240

        guard let body = await fetchText(vtt) else { print("no vtt"); exit(2) }
        let published = SubtitleAgreement.parseVTT(body)
        guard let last = published.map(\.end).max(), last > 600 else {
            print("film too short to show drift"); exit(1)
        }
        print("published: \(published.count) cues, ending at \(Int(last))s")

        // Early and late samples, both well inside the film.
        let points: [Double] = [30, last * 0.75]
        var measured: [(at: Double, offset: Double, agreement: Double)] = []

        for start in points {
            let cues = await listen(mp4, from: start, seconds: window)
            guard cues.count >= 5 else {
                print(String(format: "  %.0fs: only %d cues transcribed", start, cues.count))
                continue
            }
            guard let v = SubtitleAgreement.judge(published: published, transcript: cues) else {
                print(String(format: "  %.0fs: no verdict", start))
                continue
            }
            measured.append((start, v.offset, v.agreement))
            print(String(format: "  at %6.0fs → offset %+.1fs (agreement %.0f%%, %d cues heard)",
                         start, v.offset, v.agreement * 100, cues.count))
        }

        guard measured.count == 2 else {
            print("\nneed both samples to judge drift"); exit(1)
        }
        let (a, b) = (measured[0], measured[1])
        let spread = b.offset - a.offset
        let span = b.at - a.at
        let rate = span > 0 ? spread / span : 0

        print(String(format: "\noffset moved %+.1fs across %.0fs of film", spread, span))
        print(String(format: "that is a rate error of %+.3f%% (%.0f fps ↔ %.3f fps would be %+.2f%%)",
                     rate * 100, 25.0, 23.976, (25.0 / 23.976 - 1) * 100))

        if abs(spread) < 1.0 {
            print("\nRESULT: CONSTANT — one shift is the whole correction.")
        } else {
            let scale = 1 + rate
            print(String(format: """

                RESULT: DRIFTING — a single shift cannot fix this file.
                  correct as  t' = %.6f × t %+.2f
                  a constant shift leaves ~%.1fs of error at one end
                """, scale, a.offset - rate * a.at, abs(spread) / 2))
        }
    }

    static func listen(_ url: URL, from: Double, seconds: Double) async
        -> [SubtitleAgreement.Cue] {
        let captions = await LiveCaptions()
        await captions.start(url: url, from: CMTime(seconds: from, preferredTimescale: 600))
        let deadline = Date().addingTimeInterval(seconds * 1.4 + 90)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let lead = await captions.leadSeconds(over: CMTime(seconds: from,
                                                              preferredTimescale: 600))
            if lead > seconds { break }
            if await !captions.isRunning { break }
        }
        let cues = await captions.transcript().map {
            SubtitleAgreement.Cue(start: $0.start, end: $0.end, text: $0.text)
        }
        await captions.stop()
        return cues
    }

    static func fetchText(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
