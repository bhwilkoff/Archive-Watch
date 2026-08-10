// Can we get decoded PCM from a film WHILE IT STREAMS — no download?
//
// I previously concluded that transcription requires downloading the whole film,
// because `AVAssetReader` refuses a remote URL and `AVAssetExportSession` fails
// -11838. That conclusion was wrong: it only rules out reading the asset as a
// FILE. Every streaming player decodes remote audio continuously, and
// `MTAudioProcessingTap` on the item's audio mix hands you those decoded PCM
// buffers in real time — which is exactly the input `SpeechAnalyzer` takes
// (`AnalyzerInput(buffer:)`).
//
// This proves the mechanism before any feature is built on it: attach a tap to a
// REMOTE archive.org MP4, play, and count the PCM frames that arrive.
//
// Run: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//      xcrun swift tools/test_live_audio_tap.swift [url] [seconds]

import AVFoundation
import Foundation

final class TapState: @unchecked Sendable {
    var frames: Int64 = 0
    var callbacks = 0
    var format: AudioStreamBasicDescription?
    let lock = NSLock()

    nonisolated func snapshot() -> (Int64, Int, AudioStreamBasicDescription?) {
        lock.lock(); defer { lock.unlock() }
        return (frames, callbacks, format)
    }
}

let args = CommandLine.arguments
let urlString = args.count > 1 ? args[1]
    : "https://archive.org/download/mantheincrediblemachine/mantheincrediblemachine.mp4"
let seconds = args.count > 2 ? (Double(args[2]) ?? 12) : 12
guard let url = URL(string: urlString) else { print("bad url"); exit(2) }

let state = TapState()
let asset = AVURLAsset(url: url)

do {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = tracks.first else { print("RESULT: no audio track"); exit(1) }
    print("remote asset has \(tracks.count) audio track(s); attaching a processing tap")

    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(state).toOpaque()),
        init: { tap, clientInfo, tapStorageOut in
            tapStorageOut.pointee = clientInfo
        },
        finalize: nil,
        prepare: { tap, maxFrames, processingFormat in
            let s = Unmanaged<TapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            s.lock.lock(); s.format = processingFormat.pointee; s.lock.unlock()
        },
        unprepare: nil,
        process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
            // Pull the decoded audio. This is the same call a real-time effect
            // would make; the frames are PCM, ready for a recognizer.
            let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                            flagsOut, nil, numberFramesOut)
            guard status == noErr else { return }
            let s = Unmanaged<TapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            s.lock.lock()
            s.frames += Int64(numberFramesOut.pointee)
            s.callbacks += 1
            s.lock.unlock()
        })

    var tapOut: MTAudioProcessingTap?
    let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut)
    guard err == noErr, let tapOut else {
        print("RESULT: MTAudioProcessingTapCreate failed (\(err))"); exit(1)
    }

    let params = AVMutableAudioMixInputParameters(track: track)
    params.audioTapProcessor = tapOut
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]

    let item = AVPlayerItem(asset: asset)
    item.audioMix = mix
    let player = AVPlayer(playerItem: item)
    player.volume = 0        // silent: we want the samples, not the sound
    player.play()

    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    let (frames, calls, fmt) = state.snapshot()

    let rate = fmt?.mSampleRate ?? 0
    print("played \(String(format: "%.1fs", CMTimeGetSeconds(player.currentTime()))) of wall clock")
    print("  tap callbacks : \(calls)")
    print("  PCM frames    : \(frames)")
    if let fmt {
        print("  format        : \(rate) Hz, \(fmt.mChannelsPerFrame)ch, "
              + "\(fmt.mBitsPerChannel)-bit, flags \(fmt.mFormatFlags)")
    }
    if frames > 0, rate > 0 {
        print("  audio captured: \(String(format: "%.1fs", Double(frames) / rate))")
        print("\nRESULT: OK — decoded PCM arrives from a REMOTE, STREAMING asset.")
        print("Transcription does NOT require downloading the film.")
    } else {
        print("\nRESULT: no audio reached the tap.")
        exit(1)
    }
} catch {
    print("FAILED: \(error)")
    exit(1)
}
