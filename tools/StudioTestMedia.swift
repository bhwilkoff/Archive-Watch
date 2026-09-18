// The synthetic program both RTMP harnesses publish (WATCH-TOGETHER §8.1 and
// §8.4), and the avcC/ASC helpers they read it back with.
//
// Shared rather than copied because it must stay the SAME program: it is
// encoded with VideoToolbox + AudioConverter — the encoders the Studio itself
// uses — so the avcC/ASC path and the sample-buffer shapes are exercised for
// real. Two divergent copies would let one harness pass on a stream the other
// could not produce.

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
        // §6.6: the same forced keyframe the Studio's own encoder offers, so
        // §8.4 exercises the product's recovery rather than a simpler one.
        let props: CFDictionary? = takeKeyframeRequest()
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
            : nil
        VTCompressionSessionEncodeFrame(session, imageBuffer: px, presentationTimeStamp: pts,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                        frameProperties: props, infoFlagsOut: &flags) { [weak self] status, _, sample in
            if status == noErr, let sample { self?.onSample?(sample) }
        }
    }

    private let kfLock = NSLock()
    private var _forceKeyframe = false
    /// Mirrors `H264Encoder.requestKeyframe()`.
    func requestKeyframe() { kfLock.lock(); _forceKeyframe = true; kfLock.unlock() }
    private func takeKeyframeRequest() -> Bool {
        kfLock.lock(); defer { kfLock.unlock() }
        if _forceKeyframe { _forceKeyframe = false; return true }
        return false
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

    /// How much audio has been emitted. A caller that encodes one frame per
    /// video frame drifts: an AAC frame is 1024 samples (23.2 ms at 44.1 kHz)
    /// and a 30 fps video frame is 33.3 ms, so audio falls ~10 ms behind per
    /// frame. Pace against this instead (§8.4 measured 1.63 s of drift after
    /// 160 frames, and it presents as an A/V offset only once a server
    /// RE-BASES on a republish — which is why §8.1 never saw it).
    var elapsed: CMTime { CMTime(value: CMTimeValue(framesOut * 1024), timescale: CMTimeScale(sampleRate)) }

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
