// Follow-up to test_remote_audio_extract.swift, which proved AVAssetExportSession
// refuses a remote asset (-11838 "not supported for this media").
//
// This asks the narrower question: can AVAssetReader DECODE audio from a remote
// archive.org MP4? If it can, "Get subtitles" never needs a second copy of the
// film on disk — it decodes to PCM and writes only a small m4a (or feeds
// SpeechAnalyzer directly). If it cannot, the only on-device path is downloading
// the whole film first, which is worth knowing before building the UI around it.
//
// Run:  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//       xcrun swift tools/test_remote_audio_reader.swift <url> [seconds]

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count > 1, let url = URL(string: args[1]) else {
    print("usage: test_remote_audio_reader.swift <mp4-url> [seconds]"); exit(2)
}
let want = args.count > 2 ? Double(args[2]) ?? 60 : 60

let asset = AVURLAsset(url: url)
let t0 = Date()

do {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = tracks.first else { print("RESULT: no audio track"); exit(1) }

    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: .zero,
                                   duration: CMTime(seconds: want, preferredTimescale: 600))
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,          // what a speech recognizer wants anyway
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    guard reader.canAdd(output) else { print("RESULT: cannot add output"); exit(1) }
    reader.add(output)

    guard reader.startReading() else {
        print("RESULT: FAILED to start — \(reader.error.map(String.init(describing:)) ?? "?")")
        exit(1)
    }

    var bytes = 0, buffers = 0
    var lastPTS = CMTime.zero
    while let sb = output.copyNextSampleBuffer() {
        bytes += CMSampleBufferGetTotalSampleSize(sb)
        buffers += 1
        lastPTS = CMSampleBufferGetPresentationTimeStamp(sb)
    }
    let elapsed = -t0.timeIntervalSinceNow

    switch reader.status {
    case .completed, .cancelled:
        let decoded = CMTimeGetSeconds(lastPTS)
        print("RESULT: OK — AVAssetReader decodes a REMOTE asset")
        print("  decoded  : \(String(format: "%.0f", decoded))s of audio in \(String(format: "%.1fs", elapsed))")
        print("  speed    : \(String(format: "%.0f×", decoded / max(elapsed, 0.001))) realtime")
        print("  pcm out  : \(String(format: "%.1f MB", Double(bytes) / 1_048_576)) over \(buffers) buffers")
        print("  → 16 kHz mono PCM for a 90-min film would be ~\(Int(16_000 * 2 * 5400 / 1_048_576)) MB")
    default:
        print("RESULT: FAILED — \(reader.status.rawValue): \(reader.error.map(String.init(describing:)) ?? "?")")
        exit(1)
    }
} catch {
    print("RESULT: FAILED — \(error)")
    exit(1)
}
