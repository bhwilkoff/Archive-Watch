// Does on-device captioning actually produce usable subtitles for a real film?
//
// `AutoCaptions` has been shipped and unit-reasoned but never run against real
// archival audio, which is precisely the thing Decision 039b says cannot be
// assumed: whisper produced fluent, confident, WRONG dialogue on exactly this
// material. This drives the SHIPPED engine on a real film and prints the VTT so
// the output can be read rather than trusted.
//
// Takes a LOCAL audio/video file (AVFoundation refuses to read a remote asset
// for anything but playback — measured in test_remote_audio_extract.swift), so
// pull a slice first:
//   ffmpeg -ss 300 -t 180 -i "<mp4 url>" -vn -c:a aac /tmp/slice.m4a
//
// Run:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift \
//     tools/test_autocaptions_end_to_end.swift -o /tmp/awcap && /tmp/awcap /tmp/slice.m4a 180

import AVFoundation
import Foundation

@main
struct Harness {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            print("usage: test_autocaptions_end_to_end.swift <local-audio-file> [runtime-seconds]")
            exit(2)
        }
        let file = URL(fileURLWithPath: args[1])
        var runtime = args.count > 2 ? (Double(args[2]) ?? 0) : 0
        if runtime <= 0 {
            runtime = CMTimeGetSeconds((try? await AVURLAsset(url: file).load(.duration)) ?? .zero)
        }

        print("engine supported on this OS: \(AutoCaptions.isSupported)")
        guard AutoCaptions.isSupported else { exit(1) }
        print("transcribing \(file.lastPathComponent) (\(Int(runtime))s)…\n")

        let started = Date()
        do {
            let vtt = try await AutoCaptions.transcribe(fileURL: file, runtime: runtime,
                                                        isSilentFilm: false)
            let secs = -started.timeIntervalSinceNow
            let cues = vtt.components(separatedBy: "-->").count - 1
            let words = vtt.split(separator: " ").count
            let speed = String(format: "%.1f", runtime / max(secs, 1))
            let wpm = Int(Double(words) / max(runtime / 60, 1))
            print("PASSED the quality gate in \(String(format: "%.0fs", secs)) (\(speed)x realtime)")
            print("cues: \(cues)   words: \(words)   approx \(wpm) words/min\n")
            print(String(vtt.prefix(1400)))
        } catch {
            print("REJECTED: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            print("\n(a rejection is a RESULT, not a failure — the gate exists to refuse "
                  + "output that would be worse than no subtitles at all)")
            exit(1)
        }
        exit(0)
    }
}
