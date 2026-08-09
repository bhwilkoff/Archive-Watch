// Can we extract a film's audio for transcription WITHOUT downloading the film?
//
// AutoCaptions needs a local audio file (`AVAudioFile` cannot read an .mp4, and
// SpeechAnalyzer wants a file). The open question is whether
// AVAssetExportSession can read a REMOTE archive.org MP4 directly. Decision 033
// records that Clip Studio's first version downloaded whole films and that
// streaming remote into an export was the thing to avoid — but that was a VIDEO
// export. An audio-only AppleM4A export may behave differently, and the answer
// decides whether "Get subtitles" costs a few MB or a gigabyte.
//
// Run:  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//       xcrun swift tools/test_remote_audio_extract.swift <url> [seconds]
//
// Reports: whether it succeeded, how long it took, and how big the audio is —
// so the ratio against the source size shows what a viewer would actually pay.

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count > 1, let url = URL(string: args[1]) else {
    print("usage: test_remote_audio_extract.swift <mp4-url> [limit-seconds]")
    exit(2)
}
let limit = args.count > 2 ? Double(args[2]) : nil

func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

func sourceSize(_ url: URL) async -> Int {
    var r = URLRequest(url: url)
    r.httpMethod = "HEAD"
    guard let (_, resp) = try? await URLSession.shared.data(for: r),
          let http = resp as? HTTPURLResponse else { return 0 }
    return Int(http.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
}

let t0 = Date()
let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

do {
    let dur = try await asset.load(.duration)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    print("loaded metadata in \(String(format: "%.1fs", -t0.timeIntervalSinceNow))")
    print("  duration: \(String(format: "%.0f", CMTimeGetSeconds(dur)))s   audio tracks: \(tracks.count)")
    guard !tracks.isEmpty else { print("RESULT: no audio track"); exit(1) }

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
        print("RESULT: no export session"); exit(1)
    }
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("aw-audio-\(UUID().uuidString).m4a")
    if let limit {
        // A partial export answers the same question far faster: if the first N
        // seconds come out, the reader works on a remote asset.
        export.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: limit, preferredTimescale: 600))
    }
    let tExport = Date()
    try await export.export(to: out, as: .m4a)
    let elapsed = -tExport.timeIntervalSinceNow
    let attrs = try? FileManager.default.attributesOfItem(atPath: out.path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    let src = await sourceSize(url)
    print("RESULT: OK")
    print("  export took \(String(format: "%.1fs", elapsed))\(limit.map { " for the first \(Int($0))s" } ?? " for the whole film")")
    print("  audio out : \(mb(size))")
    print("  source mp4: \(mb(src))")
    if src > 0, limit == nil {
        print("  ratio     : audio is \(String(format: "%.1f%%", Double(size) / Double(src) * 100)) of the film")
    }
    try? FileManager.default.removeItem(at: out)
} catch {
    print("RESULT: FAILED after \(String(format: "%.1fs", -t0.timeIntervalSinceNow)) — \(error)")
    exit(1)
}
