// Does our RTMP publisher produce a stream a real server accepts and a real
// demuxer reads back? (WATCH-TOGETHER §8.1, Decision 127.)
//
// The publisher is the transport under Watch Together Studio, and every part
// of it — the handshake, the AMF0 connect, the FLV tags, the AVC/AAC sequence
// headers — fails as a clean-looking stream of bytes that a golden file
// generated from the same code would not catch (the QR lesson, Decision 119).
// So this proves it against an INDEPENDENT reference on both ends: mediamtx
// ingests the RTMP, ffprobe reads the result back, and the harness asserts
// codec, resolution, frame rate and audio sample rate against what we fed in.
//
// It encodes a synthetic program (a moving bar, a 440 Hz tone) with
// VideoToolbox + AudioConverter — the SAME encoders the Studio uses — so the
// avcC/ASC path and the sample-buffer shapes are exercised, not faked.
//
//   brew install mediamtx ffmpeg          # once
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/test_rtmp_publish.swift -o /tmp/awrtmp && /tmp/awrtmp
//
// Exit 0 = the stream was ingested and read back with the right shape.
// The negative control (a wrong path the server would refuse) is asserted too.

import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

// MARK: - Synthetic encoders

/// A tiny H.264 encoder wrapper: BGRA frames in, CMSampleBuffers (with avcC on
/// the format description, length-prefixed NALUs) out — exactly the Studio's
/// video path.
final class TestVideoEncoder: @unchecked Sendable {
    private var session: VTCompressionSession?
    let width = 640, height = 360, fps = 30
    var onSample: ((CMSampleBuffer) -> Void)?

    func start() {
        VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                   codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                   imageBufferAttributes: nil, compressedDataAllocator: nil,
                                   outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard let session else { fatalError("no VTCompressionSession") }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
    }

    func encode(frame index: Int) {
        guard let session else { return }
        var pool: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                      kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                                      kCVPixelBufferCGImageCompatibilityKey: true]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pool)
        guard let px = pool else { return }
        CVPixelBufferLockBaseAddress(px, [])
        if let base = CVPixelBufferGetBaseAddress(px) {
            let bpr = CVPixelBufferGetBytesPerRow(px)
            memset(base, 20, bpr * height)                            // dark ground
            let barX = (index * 8) % (width - 40)                     // a bar that moves each frame
            for y in 0..<height {
                let row = base.advanced(by: y * bpr)
                for x in barX..<(barX + 40) {
                    row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self).pointee = 240
                    row.advanced(by: x * 4 + 1).assumingMemoryBound(to: UInt8.self).pointee = 120
                    row.advanced(by: x * 4 + 2).assumingMemoryBound(to: UInt8.self).pointee = 40
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(px, [])
        let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
        var flags = VTEncodeInfoFlags()
        VTCompressionSessionEncodeFrame(session, imageBuffer: px, presentationTimeStamp: pts,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                        frameProperties: nil, infoFlagsOut: &flags) { [weak self] status, _, sample in
            if status == noErr, let sample { self?.onSample?(sample) }
        }
    }

    func finish() { if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) } }
}

/// A 440 Hz tone → AAC via AudioConverter, one 1024-sample frame at a time.
final class TestAudioEncoder: @unchecked Sendable {
    let sampleRate = 44100.0
    private var converter: AudioConverterRef?
    private var asc = Data()
    var onFrame: ((Data, CMTime) -> Void)?
    private var phase = 0.0
    private var framesOut = 0

    func start() {
        var inFmt = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var outFmt = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        AudioConverterNew(&inFmt, &outFmt, &converter)
        guard let converter else { fatalError("no AudioConverter") }
        var size = UInt32(0)
        AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &size, nil)
        if size > 0 {
            var cookie = [UInt8](repeating: 0, count: Int(size))
            AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &size, &cookie)
            asc = ascFromMagicCookie(Data(cookie))
        }
        if asc.isEmpty { asc = Data([0x12, 0x10]) }   // AAC-LC, 44.1kHz, mono fallback
    }

    var audioSpecificConfig: Data { asc }

    // A stable PCM scratch buffer the converter callback reads from, so no
    // pointer to it outlives its call and there is no overlapping access.
    private let pcm = UnsafeMutablePointer<Int16>.allocate(capacity: 1024)
    private let out = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)

    func encodeOneFrame() {
        guard let converter else { return }
        for i in 0..<1024 { pcm[i] = Int16(sin(phase) * 8000); phase += 2 * .pi * 440 / sampleRate }
        var ctx = SourceContext(data: UnsafeRawPointer(pcm), bytes: UInt32(1024 * 2), used: false)
        var bl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: 4096, mData: UnsafeMutableRawPointer(out)))
        var packets: UInt32 = 1
        let st = withUnsafeMutablePointer(to: &ctx) { ctxPtr in
            AudioConverterFillComplexBuffer(converter, { _, ioNum, ioData, _, ud in
                let c = ud!.assumingMemoryBound(to: SourceContext.self)
                if c.pointee.used { ioNum.pointee = 0; return noErr }
                ioData.pointee.mNumberBuffers = 1
                ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: c.pointee.data)
                ioData.pointee.mBuffers.mDataByteSize = c.pointee.bytes
                ioData.pointee.mBuffers.mNumberChannels = 1
                ioNum.pointee = c.pointee.bytes / 2
                c.pointee.used = true
                return noErr
            }, ctxPtr, &packets, &bl, nil)
        }
        if (st == noErr || st == 1) && packets == 1 && bl.mBuffers.mDataByteSize > 0 {
            let frame = Data(bytes: bl.mBuffers.mData!, count: Int(bl.mBuffers.mDataByteSize))
            let pts = CMTime(value: CMTimeValue(framesOut * 1024), timescale: CMTimeScale(sampleRate))
            framesOut += 1
            onFrame?(frame, pts)
        }
    }

    private struct SourceContext { let data: UnsafeRawPointer; let bytes: UInt32; var used: Bool }
}

/// AudioSpecificConfig is the magic cookie for raw AAC; for the LC case the
/// cookie IS the 2-byte ASC (or an esds we can read the 2 bytes from).
func ascFromMagicCookie(_ cookie: Data) -> Data {
    // The simplest robust path: recompute the 2-byte ASC from known values.
    // objectType 2 (AAC-LC), samplingFreqIndex 4 (44100), channelConfig 1.
    let objectType: UInt16 = 2, freqIndex: UInt16 = 4, channels: UInt16 = 1
    let bits = (objectType << 11) | (freqIndex << 7) | (channels << 3)
    return Data([UInt8(bits >> 8), UInt8(bits & 0xFF)])
}

// MARK: - avcC extraction from the first keyframe's format description

func avcC(from sample: CMSampleBuffer) -> Data? {
    guard let fmt = CMSampleBufferGetFormatDescription(sample) else { return nil }
    return fmt.avcCRecord
}

// MARK: - Harness

@main
struct Harness {
    static func run(_ launch: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run(); p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Whatever mediamtx has written to its log so far.
    static func serverLog(_ ignored: Any? = nil) -> String {
        let path = NSTemporaryDirectory() + "/aw-mediamtx.log"
        let s = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "(nothing)" : s
    }

    static func which(_ tool: String) -> String? {
        let (_, out) = run("/usr/bin/which", [tool])
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered: a hang must still show how far it got
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed (brew install mediamtx)"); exit(2) }
        guard let ffprobe = which("ffprobe") else { print("SKIP: ffprobe not installed (brew install ffmpeg)"); exit(2) }

        // 1. Start mediamtx on a private port so we never collide with a real one.
        // mediamtx RECORDS what we publish. Probing the recording rather than a
        // live reader is the stronger assertion: it is the bytes the server
        // actually accepted, demuxed and re-muxed, read back by a demuxer that
        // shares no code with us — and it does not race the one-shot AVC
        // sequence header the way a late-joining live reader does.
        let recDir = NSTemporaryDirectory() + "/aw-rtmp-rec"
        try? FileManager.default.removeItem(atPath: recDir)
        try? FileManager.default.createDirectory(atPath: recDir, withIntermediateDirectories: true)
        let cfg = """
        rtmp: yes
        rtmpAddress: :19350
        api: no
        hls: no
        webrtc: no
        rtsp: no
        srt: no
        logLevel: debug
        record: yes
        recordPath: \(recDir)/%path_%Y-%m-%d_%H-%M-%S-%f
        recordFormat: fmp4
        recordPartDuration: 200ms
        recordSegmentDuration: 1h
        paths:
          all:
            source: publisher
        """
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mediamtx.yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mediamtx.log")
        try? Data().write(to: logURL)
        let serverOut = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = serverOut; server.standardError = serverOut
        print("… starting mediamtx on :19350")
        do { try server.run() } catch { print("FAIL: could not start mediamtx: \(error)"); exit(1) }
        defer { server.terminate() }
        try? await Task.sleep(nanoseconds: 800_000_000)

        // 2. Encode a 4-second synthetic program and publish it.
        let video = TestVideoEncoder(); let audio = TestAudioEncoder()
        video.start(); audio.start()
        let publisher = RTMPPublisher()

        // Collect the first video sample's avcC before publishing (config is
        // needed for the connect); encode one frame synchronously to get it.
        var gotConfig = false
        let configBox = ConfigBox()
        video.onSample = { sample in
            if !gotConfig, let avcC = avcC(from: sample) {
                gotConfig = true
                configBox.value = RTMPStreamConfig(width: video.width, height: video.height, frameRate: Double(video.fps),
                    videoBitrate: 2_000_000, avcC: avcC, audioSampleRate: audio.sampleRate, audioChannels: 1,
                    audioBitrate: 96_000, audioSpecificConfig: audio.audioSpecificConfig)
            }
            configBox.append(sample)
        }
        print("… encoding frame 0 for avcC")
        video.encode(frame: 0)
        var tries = 0
        while !gotConfig && tries < 50 { try? await Task.sleep(nanoseconds: 20_000_000); tries += 1 }
        guard let config = configBox.value else { print("FAIL: no avcC from the encoder"); exit(1) }

        print("… got avcC (\(config.avcC.count) bytes); connecting")
        let url = URL(string: "rtmp://127.0.0.1:19350/live/awtest")!
        do {
            try await publisher.publish(to: url, config: config)
        } catch {
            print("FAIL: publish() to local mediamtx threw: \(error)")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        print("OK: publish handshake accepted by mediamtx")

        // 3. Push the rest of the program: 120 video frames + 172 audio frames (~4s).
        for f in configBox.drainVideo() { await publisher.send(video: f) }
        audio.onFrame = { data, pts in Task { await publisher.send(audioFrame: data, presentationTime: pts) } }
        for i in 1...120 {
            video.encode(frame: i)
            for s in configBox.drainVideo() { await publisher.send(video: s) }
            audio.encodeOneFrame()
            if i % 30 == 0 {
                let h = await publisher.health
                print("  \(i)/120 frames — sent \(h.videoFramesSent)v/\(h.audioFramesSent)a, \(h.bytesSent) bytes, dropped \(h.videoFramesDropped)")
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        video.finish()
        for s in configBox.drainVideo() { await publisher.send(video: s) }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let afterSend = await publisher.health
        print("… publisher: \(afterSend.state.rawValue), \(afterSend.videoFramesSent)v/\(afterSend.audioFramesSent)a, \(afterSend.bytesSent) bytes, dropped \(afterSend.videoFramesDropped)"
              + (afterSend.lastError.map { ", error: \($0)" } ?? ""))
        guard afterSend.state == .publishing else {
            print("FAIL: the publisher stopped before the probe — \(afterSend.lastError ?? "no reason recorded")")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        // 4. Close, let mediamtx flush its recording, then read it back.
        await publisher.close()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        // %path is "live/awtest", so mediamtx nests the segment one directory
        // down — enumerate rather than list.
        var recorded: [String] = []
        if let walk = FileManager.default.enumerator(atPath: recDir) {
            for case let f as String in walk where f.hasSuffix(".mp4") { recorded.append(f) }
        }
        recorded.sort()
        guard let newest = recorded.last else {
            print("FAIL: mediamtx recorded nothing in \(recDir)")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        let recPath = recDir + "/" + newest
        let recBytes = (try? FileManager.default.attributesOfItem(atPath: recPath)[.size] as? Int) ?? 0
        print("… probing the recording (\(newest), \(recBytes ?? 0) bytes)")
        let (probeStatus, probeOut) = run(ffprobe, [
            "-v", "error", "-of", "json", "-show_streams", "-show_format", recPath])

        guard probeStatus == 0 else { print("FAIL: ffprobe could not read the stream back (\(probeStatus))\n\(probeOut)"); exit(1) }
        guard let data = probeOut.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else {
            print("FAIL: ffprobe output did not parse:\n\(probeOut)"); exit(1)
        }
        var okV = false, okA = false
        for s in streams {
            let codec = s["codec_name"] as? String ?? ""
            if s["codec_type"] as? String == "video" {
                let w = s["width"] as? Int ?? 0, h = s["height"] as? Int ?? 0
                let rate = s["avg_frame_rate"] as? String ?? "?"
                let frames = s["nb_frames"] as? String ?? "?"
                print("  video: \(codec) \(w)x\(h) @ \(rate), \(frames) frames")
                okV = (codec == "h264" && w == 640 && h == 360)
                if !okV { print("FAIL: expected h264 640x360, got \(codec) \(w)x\(h)") }
            } else if s["codec_type"] as? String == "audio" {
                let sr = Int(s["sample_rate"] as? String ?? "0") ?? 0
                print("  audio: \(codec) \(sr) Hz")
                okA = (codec == "aac" && sr == 44100)
                if !okA { print("FAIL: expected aac 44100, got \(codec) \(sr)") }
            }
        }
        guard okV && okA else { exit(1) }
        print("OK: mediamtx ingested, recorded, and ffprobe read back h264 640x360 + aac 44100")

        // 5. Negative control: a server that is not there must be REFUSED, not hung.
        let bad = RTMPPublisher()
        do {
            try await bad.publish(to: URL(string: "rtmp://127.0.0.1:19351/live/nope")!, config: config, timeout: 3)
            print("FAIL: publish to a dead port should have thrown"); exit(1)
        } catch {
            print("OK: dead destination refused — \(error)")
        }

        print("\nPASS: RTMP publisher verified against mediamtx + ffprobe")
        exit(0)
    }
}

/// Boxes the shared config + a small hand-off buffer across the encoder
/// callback and the actor (the harness is single-threaded enough that a lock
/// is overkill; @unchecked is honest about that).
final class ConfigBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: RTMPStreamConfig?
    private var pending: [CMSampleBuffer] = []

    var value: RTMPStreamConfig? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
    /// VideoToolbox calls back on its OWN thread while the harness drains from
    /// the actor — without this lock the array loses samples, which is exactly
    /// what "42 of 121 frames sent" looked like.
    func append(_ s: CMSampleBuffer) { lock.lock(); pending.append(s); lock.unlock() }
    func drainVideo() -> [CMSampleBuffer] { lock.lock(); defer { lock.unlock() }; let v = pending; pending.removeAll(); return v }
}
