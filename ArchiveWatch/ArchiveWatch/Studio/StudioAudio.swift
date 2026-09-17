// Watch Together Studio — the audio path (docs/WATCH-TOGETHER.md §4).
//
// Two sources, one program: the FILM's decoded audio (tapped off the player's
// audio mix, exactly as the caption scout does) and the HOST's microphone.
// They are mixed with independent gains, the film ducks under the host's voice,
// and the sum is encoded to AAC and handed to the publisher.
//
// WHY A TAP AND NOT A RE-DECODE: the film's audio is already being decoded to
// play it. `MTAudioProcessingTap` on the item's audio mix hands back those
// same PCM buffers (Decision 058's mechanism, reused — see LiveCaptions), so
// the program costs one decode, not two, and the audio the audience hears is
// byte-for-byte the audio in the room.
//
// THE CLOCK. Neither source can be the clock: the film's stops when the film
// pauses, and the microphone's stops when the capture session hiccups. A
// dedicated ticker pulls a fixed 1024-frame chunk from both ring buffers every
// 1024/44100 s and pads whichever is short with silence. That is what keeps the
// program's audio continuous while the film is paused and the host keeps
// talking — the same rule §3's video clock follows, for the same reason.
//
// ISOLATION. The tap's `prepare` and `process` callbacks run on MediaToolbox's
// real-time audio thread. Swift infers a closure's isolation from the type it
// is written in, so a tap declared inside a @MainActor type traps the instant
// audio arrives (LiveCaptions records the exact backtrace). Everything here is
// a plain final class with no isolation, deliberately.

import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import MediaToolbox

// MARK: - Ring buffer

/// A fixed-capacity float ring for one source. Written from a real-time audio
/// callback, read by the mixer's ticker — so it never allocates on write and
/// never blocks longer than a lock hold of a memcpy.
final class AudioRing: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Float]
    private var writeIndex = 0
    private var available = 0
    let capacity: Int

    /// Frames written and frames the reader had to pad. Both are health: a
    /// ring that is always empty means its source is dead, and a ring that
    /// overflows means the reader is too slow.
    private(set) var framesWritten = 0
    private(set) var framesPadded = 0
    private(set) var framesOverflowed = 0

    init(capacity: Int = 44100 * 2) {
        self.capacity = capacity
        buffer = [Float](repeating: 0, count: capacity)
    }

    func write(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        if count >= capacity {
            // A burst bigger than the whole ring: keep the newest tail.
            let tail = samples.advanced(by: count - capacity)
            for i in 0..<capacity { buffer[i] = tail[i] }
            writeIndex = 0
            available = capacity
            framesOverflowed += count - capacity
        } else {
            for i in 0..<count {
                buffer[(writeIndex + i) % capacity] = samples[i]
            }
            writeIndex = (writeIndex + count) % capacity
            let room = capacity - available
            if count > room { framesOverflowed += count - room }
            available = min(capacity, available + count)
        }
        framesWritten += count
        lock.unlock()
    }

    /// Reads exactly `count` frames, padding the shortfall with silence.
    /// Returns how many were real.
    func read(into out: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock()
        let have = min(available, count)
        let start = ((writeIndex - have) % capacity + capacity) % capacity
        for i in 0..<have { out[i] = buffer[(start + i) % capacity] }
        for i in have..<count { out[i] = 0 }
        available -= have
        if have < count { framesPadded += count - have }
        lock.unlock()
        return have
    }

    func silenceAll() {
        lock.lock(); available = 0; lock.unlock()
    }
}

// MARK: - Film audio tap

/// Taps the film's decoded audio off the player item's audio mix and writes it
/// into a ring, downmixed to mono-per-channel-pair at the program rate.
final class FilmAudioTap: @unchecked Sendable {
    let ring = AudioRing()
    private let lock = NSLock()
    private var sourceRate: Double = 44100
    private var sourceChannels: Int = 2
    private(set) var prepared = false
    /// Interleaved stereo scratch, sized once at prepare.
    private var scratch = [Float](repeating: 0, count: 8192 * 2)

    /// The program's sample rate; the tap resamples by nearest-neighbour,
    /// which is honest for a 44.1/48 kHz mismatch and costs nothing. A proper
    /// resampler is a §9 follow-up if a 48 kHz film ever sounds wrong.
    var programRate: Double = 44100

    /// Attaches to `item`, replacing any audio mix it had. Returns false when
    /// the item has no audio track at all — a silent film, which is a REAL
    /// case in this catalog and must not be reported as a failure.
    @discardableResult
    func attach(to item: AVPlayerItem) -> Bool {
        // `item.tracks` are the PLAYER's tracks, already loaded by the time an
        // item is playable — no await, and no deprecated asset accessor.
        guard let assetTrack = item.tracks.compactMap(\.assetTrack)
                .first(where: { $0.mediaType == .audio }) else { return false }
        guard let tap = makeTap() else { return false }
        let params = AVMutableAudioMixInputParameters(track: assetTrack)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        return true
    }

    private func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: nil,
            prepare: { tap, _, format in
                let s = Unmanaged<FilmAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                s.setSourceFormat(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                var when = CMTimeRange.zero
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList,
                                                                flagsOut, &when, framesOut)
                guard status == noErr else { return }
                let s = Unmanaged<FilmAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                s.append(bufferList, frames: Int(framesOut.pointee))
            })
        var out: MTAudioProcessingTap?
        // PostEffects: what the viewer actually hears, volume and all.
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                             kMTAudioProcessingTapCreationFlag_PostEffects, &out)
        return err == noErr ? out : nil
    }

    private func setSourceFormat(_ asbd: AudioStreamBasicDescription) {
        lock.lock()
        sourceRate = asbd.mSampleRate
        sourceChannels = Int(asbd.mChannelsPerFrame)
        prepared = true
        lock.unlock()
    }

    /// Converts the tap's buffers to interleaved stereo Float at the program
    /// rate and writes them to the ring.
    private func append(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        lock.lock()
        let rate = sourceRate, channels = sourceChannels
        lock.unlock()

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard abl.count > 0 else { return }

        // The tap hands back either one interleaved buffer or N deinterleaved
        // ones; both shapes occur, so handle both rather than assuming.
        let ratio = programRate / max(rate, 1)
        let outFrames = max(1, Int((Double(frames) * ratio).rounded()))
        let needed = outFrames * 2
        if scratch.count < needed { scratch = [Float](repeating: 0, count: needed) }

        scratch.withUnsafeMutableBufferPointer { out in
            guard let outBase = out.baseAddress else { return }
            if abl.count == 1 && channels >= 2 {
                guard let src = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let srcFrames = Int(abl[0].mDataByteSize) / (4 * channels)
                for i in 0..<outFrames {
                    let j = min(srcFrames - 1, Int(Double(i) / max(ratio, 0.0001)))
                    guard j >= 0 else { break }
                    outBase[i * 2] = src[j * channels]
                    outBase[i * 2 + 1] = src[j * channels + 1]
                }
            } else if abl.count >= 2 {
                guard let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let r = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return }
                let srcFrames = Int(abl[0].mDataByteSize) / 4
                for i in 0..<outFrames {
                    let j = min(srcFrames - 1, Int(Double(i) / max(ratio, 0.0001)))
                    guard j >= 0 else { break }
                    outBase[i * 2] = l[j]
                    outBase[i * 2 + 1] = r[j]
                }
            } else {
                // Mono: the same sample in both program channels.
                guard let m = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let srcFrames = Int(abl[0].mDataByteSize) / 4
                for i in 0..<outFrames {
                    let j = min(srcFrames - 1, Int(Double(i) / max(ratio, 0.0001)))
                    guard j >= 0 else { break }
                    outBase[i * 2] = m[j]; outBase[i * 2 + 1] = m[j]
                }
            }
            ring.write(outBase, count: needed)
        }
    }
}

// MARK: - Microphone tap

/// The host's microphone, off the same `AVCaptureSession` the camera uses. On
/// tvOS that session's audio device is the Continuity microphone.
final class MicAudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let ring = AudioRing()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "org.archivewatch.studio.mic")
    private var scratch = [Float](repeating: 0, count: 8192 * 2)
    var programRate: Double = 44100

    @discardableResult
    func attach(to session: AVCaptureSession) -> Bool {
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from c: AVCaptureConnection) {
        guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }

        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)
        guard status == noErr, let data = abl.mBuffers.mData else { return }

        let channels = Int(asbd.mChannelsPerFrame)
        let ratio = programRate / max(asbd.mSampleRate, 1)
        let outFrames = max(1, Int((Double(frames) * ratio).rounded()))
        let needed = outFrames * 2
        if scratch.count < needed { scratch = [Float](repeating: 0, count: needed) }

        // A capture session can hand back Int16 or Float32; read the flags
        // rather than assuming (an assumption here is silence or noise).
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        scratch.withUnsafeMutableBufferPointer { out in
            guard let outBase = out.baseAddress else { return }
            if isFloat {
                let src = data.assumingMemoryBound(to: Float.self)
                for i in 0..<outFrames {
                    let j = min(frames - 1, Int(Double(i) / max(ratio, 0.0001)))
                    let v = src[j * channels]
                    outBase[i * 2] = v
                    outBase[i * 2 + 1] = channels > 1 ? src[j * channels + 1] : v
                }
            } else {
                let src = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<outFrames {
                    let j = min(frames - 1, Int(Double(i) / max(ratio, 0.0001)))
                    let v = Float(src[j * channels]) / 32768
                    outBase[i * 2] = v
                    outBase[i * 2 + 1] = channels > 1 ? Float(src[j * channels + 1]) / 32768 : v
                }
            }
            ring.write(outBase, count: needed)
        }
    }
}

// MARK: - Mixer

public struct StudioAudioHealth: Sendable, Equatable {
    public var filmFramesWritten = 0
    public var micFramesWritten = 0
    public var filmFramesPadded = 0
    public var micFramesPadded = 0
    public var aacFramesEncoded = 0
    public var filmLevel: Float = 0        // 0…1 RMS, for the meter
    public var micLevel: Float = 0
    public var ducking = false
}

/// Pulls a fixed chunk from both rings on its own clock, applies gains and
/// ducking, and encodes AAC.
final class StudioAudioMixer: @unchecked Sendable {
    static let framesPerPacket = 1024

    /// §4's faders. 1.0 is unity; the host sets these.
    var filmGain: Float = 1.0
    var micGain: Float = 1.0
    var filmMuted = false
    var micMuted = false
    /// §4: the film ducks 12 dB under the host's voice.
    let duckDecibels: Float = -12
    private let duckThreshold: Float = 0.02      // RMS at which the host counts as speaking
    private var duckGain: Float = 1.0            // smoothed, so ducking is not a click

    let film = FilmAudioTap()
    let mic = MicAudioTap()
    private(set) var health = StudioAudioHealth()
    private let healthLock = NSLock()

    private let rate: Double
    private var converter: AudioConverterRef?
    private var asc = Data()
    private var packetsOut = 0
    private var ticker: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "org.archivewatch.studio.audiomix", qos: .userInitiated)
    private var pcm: UnsafeMutablePointer<Float>
    private var micPcm: UnsafeMutablePointer<Float>
    private var interleaved: UnsafeMutablePointer<Int16>
    private var aacOut: UnsafeMutablePointer<UInt8>
    private var micHasEverArrived = false

    /// Called with each encoded AAC frame and its program time.
    var onFrame: ((Data, CMTime) -> Void)?

    init(sampleRate: Double = 44100) {
        rate = sampleRate
        film.programRate = sampleRate
        mic.programRate = sampleRate
        let n = Self.framesPerPacket * 2
        pcm = .allocate(capacity: n)
        micPcm = .allocate(capacity: n)
        interleaved = .allocate(capacity: n)
        aacOut = .allocate(capacity: 4096)
    }

    deinit {
        pcm.deallocate(); micPcm.deallocate(); interleaved.deallocate(); aacOut.deallocate()
        if let converter { AudioConverterDispose(converter) }
    }

    var audioSpecificConfig: Data {
        asc.isEmpty ? StudioAudioMixer.defaultASC(rate: rate, channels: 2) : asc
    }

    static func defaultASC(rate: Double, channels: Int) -> Data {
        let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let index = UInt16(rates.firstIndex(of: rate) ?? 4)
        let bits = (UInt16(2) << 11) | (index << 7) | (UInt16(channels) << 3)
        return Data([UInt8(bits >> 8), UInt8(bits & 0xFF)])
    }

    func start() {
        setUpConverter()
        let interval = Double(Self.framesPerPacket) / rate
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        ticker = t
        t.resume()
    }

    func stop() {
        ticker?.cancel(); ticker = nil
    }

    private func setUpConverter() {
        var inFmt = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var outFmt = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(Self.framesPerPacket),
            mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        AudioConverterNew(&inFmt, &outFmt, &converter)
        asc = StudioAudioMixer.defaultASC(rate: rate, channels: 2)
    }

    private func tick() {
        let n = Self.framesPerPacket
        let samples = n * 2
        let filmReal = film.ring.read(into: pcm, count: samples)
        let micReal = mic.ring.read(into: micPcm, count: samples)
        if micReal > 0 { micHasEverArrived = true }

        // Levels first: ducking is decided on what the host is ACTUALLY saying
        // in this chunk, not on a setting.
        var filmSum: Float = 0, micSum: Float = 0
        for i in 0..<samples { filmSum += pcm[i] * pcm[i]; micSum += micPcm[i] * micPcm[i] }
        let filmRMS = (filmSum / Float(samples)).squareRoot()
        let micRMS = (micSum / Float(samples)).squareRoot()

        // Smooth the duck so it is a fade, not a click: ~40 ms attack, ~300 ms
        // release, which is what a viewer hears as "the film got out of the way".
        let wantDuck = !micMuted && micRMS > duckThreshold
        let target: Float = wantDuck ? pow(10, duckDecibels / 20) : 1.0
        let coefficient: Float = target < duckGain ? 0.45 : 0.06
        duckGain += (target - duckGain) * coefficient

        let fg = (filmMuted ? 0 : filmGain) * duckGain
        let mg = micMuted ? 0 : micGain
        for i in 0..<samples {
            let v = pcm[i] * fg + micPcm[i] * mg
            // Hard-limit rather than wrap: a summed peak must never invert.
            interleaved[i] = Int16(max(-1, min(1, v)) * 32767)
        }

        encode(frames: n)

        healthLock.lock()
        health.filmFramesWritten = film.ring.framesWritten
        health.micFramesWritten = mic.ring.framesWritten
        health.filmFramesPadded = film.ring.framesPadded
        health.micFramesPadded = mic.ring.framesPadded
        health.filmLevel = min(1, filmRMS * 3)
        health.micLevel = min(1, micRMS * 3)
        health.ducking = wantDuck
        health.aacFramesEncoded = packetsOut
        healthLock.unlock()
        _ = filmReal
    }

    private struct Source { let data: UnsafeRawPointer; let bytes: UInt32; var used: Bool }

    private func encode(frames: Int) {
        guard let converter else { return }
        var ctx = Source(data: UnsafeRawPointer(interleaved), bytes: UInt32(frames * 4), used: false)
        var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 2, mDataByteSize: 4096, mData: UnsafeMutableRawPointer(aacOut)))
        var packets: UInt32 = 1
        let status = withUnsafeMutablePointer(to: &ctx) { p in
            AudioConverterFillComplexBuffer(converter, { _, ioNum, ioData, _, ud in
                let c = ud!.assumingMemoryBound(to: Source.self)
                if c.pointee.used { ioNum.pointee = 0; return noErr }
                ioData.pointee.mNumberBuffers = 1
                ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: c.pointee.data)
                ioData.pointee.mBuffers.mDataByteSize = c.pointee.bytes
                ioData.pointee.mBuffers.mNumberChannels = 2
                ioNum.pointee = c.pointee.bytes / 4
                c.pointee.used = true
                return noErr
            }, p, &packets, &abl, nil)
        }
        guard (status == noErr || status == 1), packets == 1, abl.mBuffers.mDataByteSize > 0 else { return }
        let frame = Data(bytes: abl.mBuffers.mData!, count: Int(abl.mBuffers.mDataByteSize))
        let pts = CMTime(value: CMTimeValue(packetsOut * Self.framesPerPacket), timescale: CMTimeScale(rate))
        packetsOut += 1
        onFrame?(frame, pts)
    }

    func currentHealth() -> StudioAudioHealth {
        healthLock.lock(); defer { healthLock.unlock() }
        return health
    }

    var micEverArrived: Bool { micHasEverArrived }
}
