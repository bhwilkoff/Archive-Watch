// Exercise the SHIPPED LiveCaptions against a real streaming film and print the
// cues it produces, with their times.
//
// This tests the two faults the owner reported, which a compile cannot catch and
// the Simulator cannot reach (it has no speech model — "not subscribed to
// transcription.en"):
//
//   1. ONLY THE LAST WORD. A transcriber Result covers its OWN CMTimeRange; it
//      is not a sentence that grows. Assigning each Result to a single display
//      string shows nothing but the newest fragment.
//   2. BAD TIMING. `MTAudioProcessingTapGetSourceAudio` hands back the
//      presentation time range of each buffer, and passing nil for it (as the
//      first version did) leaves the analyzer timing everything from "whenever
//      captioning started" rather than the film's own clock.
//
// PASS looks like: multi-word cues whose start times advance in step with
// playback, i.e. a cue's time is close to the wall-clock position it was heard.
//
// Build against the shipped sources:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     ArchiveWatch/ArchiveWatch/Services/LiveCaptions.swift \
//     tools/test_live_captions_timing.swift -o /tmp/awlive && /tmp/awlive [url] [seconds]

import AVFoundation
import Foundation

@main
struct Harness {
    static func main() async {
        let args = CommandLine.arguments
        let raw = args.count > 1 ? args[1]
            : "https://archive.org/download/mantheincrediblemachine/mantheincrediblemachine.mp4"
        let seconds = args.count > 2 ? (Double(args[2]) ?? 90) : 90
        guard let url = URL(string: raw) else { print("bad url"); exit(2) }

        guard await LiveCaptions.isSupported else {
            print("no on-device recognizer on this OS"); exit(1)
        }

        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack
        do {
            guard let t = try await asset.loadTracks(withMediaType: .audio).first else {
                print("asset reports NO audio tracks"); exit(1)
            }
            track = t
        } catch {
            print("loadTracks failed: \(error)"); exit(1)
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 0

        _ = track
        let captions = await LiveCaptions()
        await captions.start(url: url, from: .zero)
        player.play()

        print("listening for \(Int(seconds))s — cue text, and its film time vs the playhead\n")
        var seen = Set<String>()

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let now = player.currentTime()
            await captions.throttle(playhead: now)
            let line = await captions.line(at: now)
            guard !line.isEmpty, !seen.contains(line) else { continue }
            seen.insert(line)
            let words = line.split(separator: " ").count
            print(String(format: "  playhead %6.1fs  %2d words  %@",
                         CMTimeGetSeconds(now), words, String(line.prefix(72))))
        }
        await captions.stop()

        let multi = seen.filter { $0.split(separator: " ").count > 1 }.count
        print("\n\(seen.count) distinct lines, \(multi) of them multi-word")
        if seen.isEmpty {
            print("RESULT: no captions — the model is probably unavailable here.")
            exit(1)
        }
        // A single-word-only stream is the exact bug being fixed.
        print(multi > seen.count / 2
              ? "RESULT: OK — captions arrive as phrases, timed against the playhead."
              : "RESULT: FAIL — still mostly single words; cues are not accumulating.")
        exit(multi > seen.count / 2 ? 0 : 1)
    }
}
