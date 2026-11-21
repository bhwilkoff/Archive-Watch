// Audio Sync (tvOS-DESIGN §8.2a): does AVPlayer RENDER the sound where the
// remux's shifted tfdt says, through the real LocalMediaServer HLS path?
//
// THE INSTRUMENT. A synthetic film flashes white and beeps at the same
// instant every 5 s (written here by AVAssetWriter, so no ffmpeg). It is
// played by AVPlayer through `LocalMediaServer.hlsURL(for:audioOffset:)`
// exactly as tvOS plays a film. Two independent clocks then say when each
// event reached the viewer, both in host time:
//   - the PICTURE: an AVPlayerItemVideoOutput polled every 2 ms; a white
//     frame's presentation host time is now + (its PTS - the item time now);
//   - the SOUND: a Core Audio process tap on this very process, MUTED (the
//     tap takes the audio and the speakers get none), stamped by the IO
//     cycle's host time plus the sample index of the beep's first sample.
// D = sound host time - picture host time, per event. The output path's own
// latency is a constant in D, so the claim is about DIFFERENCES: offset +x
// must move D by +x against offset 0 and the direct mp4 (the CONTROLS: both
// must agree with each other, i.e. the remux at 0 changes nothing).
//
// Needs macOS 14.2+ and, once, the terminal's Audio Capture permission.
// Plays NOTHING aloud: if the muted tap cannot be created it exits first.
//
//   any HTTP server that honors Range, serving <dir> on <port>
//   swiftc -O -parse-as-library tools/test_audio_sync_offset.swift \
//     tools/audio_sync_stubs.swift \
//     ArchiveWatch/ArchiveWatch/Networking/MP4Fragmenter.swift \
//     ArchiveWatch/ArchiveWatch/Networking/LocalMediaServer.swift -o /tmp/avsync
//   /tmp/avsync gen <dir>/flashbeep.mp4
//   /tmp/avsync measure http://127.0.0.1:<port>/flashbeep.mp4
import AVFoundation
import AudioToolbox
import CoreAudio
import CoreVideo
import Foundation
import QuartzCore

// MARK: - The synthetic film

func generate(_ path: String, seconds: Int = 60) throws {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    w.shouldOptimizeForNetworkUse = true
    let fps: Int32 = 30, width = 320, height = 240
    let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 60,
                                          AVVideoAllowFrameReorderingKey: false]])
    let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
    vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    w.add(vIn); w.add(aIn)
    w.startWriting(); w.startSession(atSourceTime: .zero)

    func frame(white: Bool) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        let b = pb!
        CVPixelBufferLockBaseAddress(b, [])
        memset(CVPixelBufferGetBaseAddress(b), white ? 255 : 0,
               CVPixelBufferGetBytesPerRow(b) * height)
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }
    var fmt: CMAudioFormatDescription?
    var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
        mBitsPerChannel: 16, mReserved: 0)
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                   formatDescriptionOut: &fmt)
    let totalFrames = seconds * Int(fps)
    let totalSamples = seconds * 48000
    var vi = 0, ai = 0
    let chunk = 4800
    while vi < totalFrames || ai < totalSamples {
        while vi < totalFrames, vIn.isReadyForMoreMediaData {
            let t = Double(vi) / Double(fps)
            let white = t.truncatingRemainder(dividingBy: 5) < 0.066
            adaptor.append(frame(white: white), withPresentationTime: CMTime(value: CMTimeValue(vi), timescale: fps))
            vi += 1
        }
        while ai < totalSamples, aIn.isReadyForMoreMediaData {
            let n = min(chunk, totalSamples - ai)
            var pcm = [Int16](repeating: 0, count: n * 2)
            for k in 0..<n {
                let t = Double(ai + k) / 48000
                let on = t.truncatingRemainder(dividingBy: 5) < 0.05
                let v = on ? Int16(sin(2 * .pi * 1000 * t) * 26000) : 0
                pcm[2 * k] = v; pcm[2 * k + 1] = v
            }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 4,
                blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: n * 4,
                flags: 0, blockBufferOut: &block)
            pcm.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                                                    offsetIntoDestination: 0, dataLength: n * 4) }
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!,
                formatDescription: fmt!, sampleCount: n,
                presentationTimeStamp: CMTime(value: CMTimeValue(ai), timescale: 48000),
                packetDescriptions: nil, sampleBufferOut: &sb)
            aIn.append(sb!)
            ai += n
        }
        if vi >= totalFrames { vIn.markAsFinished() }
        if ai >= totalSamples { aIn.markAsFinished() }
        Thread.sleep(forTimeInterval: 0.002)
    }
    let done = DispatchSemaphore(value: 0)
    w.finishWriting { done.signal() }
    done.wait()
    print("wrote \(path) status=\(w.status.rawValue) \(w.error.map { "\($0)" } ?? "")")
}

// MARK: - The sound clock: a muted process tap on ourselves

final class SoundClock: @unchecked Sendable {
    private let lock = NSLock()
    private var onsets: [Double] = []
    private var lastLoud = -10.0
    private(set) var rate = 48000.0
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agg = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    var frames = 0

    static func hostSeconds(_ h: UInt64) -> Double {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        return Double(h) * Double(tb.numer) / Double(tb.denom) / 1e9
    }

    func take() -> [Double] { lock.lock(); defer { lock.unlock() }; let o = onsets; onsets = []; return o }

    func start() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = getpid(); var obj = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                         UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj) == noErr,
              obj != 0 else { return "no audio process object for this pid" }
        let desc = CATapDescription(stereoMixdownOfProcesses: [obj])
        desc.isPrivate = true
        desc.muteBehavior = .muted
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, tap != kAudioObjectUnknown
        else { return "AudioHardwareCreateProcessTap refused" }

        var outAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var outDev = AudioObjectID(0); var ods = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outAddr, 0, nil, &ods, &outDev)
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString; var us = UInt32(MemoryLayout<CFString>.size)
        withUnsafeMutablePointer(to: &uid) { _ = AudioObjectGetPropertyData(outDev, &uidAddr, 0, nil, &us, $0) }
        let cfg: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "AW Sync Probe",
            kAudioAggregateDeviceUIDKey as String: "app.archivewatch.syncprobe.\(getpid())",
            kAudioAggregateDeviceMainSubDeviceKey as String: uid as String,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: uid as String]],
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapUIDKey as String: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey as String: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(cfg as CFDictionary, &agg) == noErr
        else { return "aggregate device refused" }
        var fAddr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var f = AudioStreamBasicDescription(); var fs = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tap, &fAddr, 0, nil, &fs, &f) == noErr, f.mSampleRate > 0 { rate = f.mSampleRate }
        let st = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, nil) { [self] _, inData, inTime, _, _ in
            let base = SoundClock.hostSeconds(inTime.pointee.mHostTime)
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard let b = abl.first, let d = b.mData else { return }
            let ch = max(1, Int(b.mNumberChannels))
            let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size / ch
            let p = d.assumingMemoryBound(to: Float.self)
            for i in 0..<n where abs(p[i * ch]) > 0.25 {
                let t = base + Double(i) / rate
                lock.lock()
                if t - lastLoud > 1.0 { onsets.append(t) }
                lastLoud = t
                lock.unlock()
            }
            frames += n
        }
        guard st == noErr, let proc else { return "IOProc refused" }
        AudioDeviceStart(agg, proc)
        return nil
    }

    func stop() {
        if let proc { AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc) }
        AudioHardwareDestroyAggregateDevice(agg)
        AudioHardwareDestroyProcessTap(tap)
    }
}

// MARK: - The picture clock

@MainActor
final class PictureClock {
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    var flashes: [(host: Double, pts: Double)] = []
    var firstPTS: Double?
    private var wasWhite = false

    func poll() {
        let now = CACurrentMediaTime()
        let it = output.itemTime(forHostTime: now)
        guard output.hasNewPixelBuffer(forItemTime: it) else { return }
        var shown = CMTime.zero
        guard let pb = output.copyPixelBuffer(forItemTime: it, itemTimeForDisplay: &shown) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let row = CVPixelBufferGetBytesPerRow(pb), h = CVPixelBufferGetHeight(pb)
        let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let v = Int(p[(h / 2) * row + 4 * 160 + 1])
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        let white = v > 128
        if firstPTS == nil { firstPTS = shown.seconds }
        if white && !wasWhite {
            flashes.append((now + (shown.seconds - it.seconds), shown.seconds))
        }
        wasWhite = white
    }
}

// MARK: - One run

@MainActor
func run(_ label: String, url: URL, sound: SoundClock, seconds: Double,
         seekTo: Double? = nil) -> (d: [Double], duration: Double, landed: Double?) {
    let item = AVPlayerItem(url: url)
    let pic = PictureClock()
    item.add(pic.output)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    _ = sound.take()
    player.play()
    let poller = Timer(timeInterval: 0.002, repeats: true) { _ in MainActor.assumeIsolated { pic.poll() } }
    RunLoop.main.add(poller, forMode: .common)
    var landed: Double?
    var startedAt: Double?
    let t0 = Date()
    var seeked = false
    while Date().timeIntervalSince(t0) < seconds {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if startedAt == nil, player.timeControlStatus == .playing { startedAt = player.currentTime().seconds }
        if let s = seekTo, !seeked, Date().timeIntervalSince(t0) > seconds / 2 {
            seeked = true
            var done = false
            player.seek(to: CMTime(seconds: s, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { _ in done = true }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            landed = player.currentTime().seconds
        }
    }
    poller.invalidate()
    let duration = item.duration.seconds
    player.pause()
    player.replaceCurrentItem(with: nil)
    let sounds = sound.take()
    var ds: [Double] = []
    for f in pic.flashes {
        guard let s = sounds.min(by: { abs($0 - f.host) < abs($1 - f.host) }), abs(s - f.host) < 2.5 else { continue }
        ds.append(s - f.host)
    }
    let sorted = ds.sorted()
    let med = sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    print(String(format: "%@: flashes=%d beeps=%d paired=%d  D median=%+.3f s  spread=%.3f  duration=%.3f%@",
                 label, pic.flashes.count, sounds.count, ds.count, med,
                 (sorted.last ?? 0) - (sorted.first ?? 0), duration,
                 landed.map { String(format: "  seek->%.3f", $0) } ?? ""))
    print(String(format: "    started playing at item time %.3f, first frame pts %.3f",
                 startedAt ?? -1, pic.firstPTS ?? -1))
    print("    flash pts: " + pic.flashes.map { String(format: "%.3f", $0.pts) }.joined(separator: " "))
    print("    D each:    " + ds.map { String(format: "%+.3f", $0) }.joined(separator: " "))
    return (ds, duration, landed)
}

func median(_ a: [Double]) -> Double { let s = a.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }

@main
struct AudioSyncProbe {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "gen" { try! generate(args[2]); return }
        guard args.count >= 3, args[1] == "measure", let origin = URL(string: args[2]) else {
            print("usage: gen <out.mp4> | measure <origin url>"); exit(64)
        }
        // A process has no audio object until it opens an output, so open one
        // SILENTLY first; the tap (muted) must exist before anything audible.
        let engine = AVAudioEngine()
        let src = AVAudioSourceNode { _, _, _, abl in
            for b in UnsafeMutableAudioBufferListPointer(abl) { memset(b.mData, 0, Int(b.mDataByteSize)) }
            return noErr
        }
        engine.attach(src); engine.connect(src, to: engine.mainMixerNode, format: nil)
        do { try engine.start() } catch { print("SKIP cannot open audio output: \(error)"); exit(2) }
        Thread.sleep(forTimeInterval: 0.5)
        let sound = SoundClock()
        if let why = sound.start() { print("SKIP muted tap unavailable (\(why)); nothing was played"); exit(2) }
        Thread.sleep(forTimeInterval: 0.5)
        print(String(format: "muted tap running at %.0f Hz, %d frames so far", sound.rate, sound.frames))

        let span = 24.0
        let direct = run("direct mp4 (control)", url: origin, sound: sound, seconds: span)
        var results: [(Double, [Double])] = []
        var durationOK = true
        for off in [0.0, 1.0, -1.0, 0.5, -0.5] {
            guard let u = LocalMediaServer.shared.hlsURL(for: origin, audioOffset: off) else {
                print("FAIL no hls url"); exit(1)
            }
            let r = run(String(format: "remux offset %+.1f", off), url: u, sound: sound,
                        seconds: span + 12, seekTo: 32.0)
            results.append((off, r.d))
            if abs(r.duration - direct.duration) > 0.05 {
                durationOK = false
                print(String(format: "    duration %.3f differs from the direct mp4's %.3f", r.duration, direct.duration))
            }
            if let l = r.landed, abs(l - 32.0) > 0.05 {
                durationOK = false
                print(String(format: "    seek to 32.000 landed at %.3f", l))
            }
        }
        sound.stop()
        let ref = median(results[0].1)
        print(String(format: "\ncontrol: remux@0 - direct = %+.3f s", ref - median(direct.d)))
        var ok = abs(ref - median(direct.d)) < 0.06 && durationOK
        for (off, d) in results.dropFirst() {
            let shift = median(d) - ref
            let good = abs(shift - off) < 0.06
            ok = ok && good
            print(String(format: "offset %+.1f: measured shift %+.3f s (%@)", off, shift, good ? "ok" : "WRONG"))
        }
        print(ok ? "PASS" : "FAIL")
        exit(ok ? 0 : 1)
    }
}
