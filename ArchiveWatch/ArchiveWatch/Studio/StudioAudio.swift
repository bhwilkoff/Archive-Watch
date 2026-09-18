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

    /// Interleaved samples written but not yet read. This is LATENCY: whatever
    /// sits here was decoded already and will not be encoded until the mixer
    /// reaches it.
    var availableSamples: Int {
        lock.lock(); defer { lock.unlock() }
        return available
    }

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
/// The film's COMPRESSED audio, teed out of the path that is already fetching it.
///
/// WHY THIS EXISTS (WATCH-TOGETHER §9.jjjj–§9.mmmm). On tvOS the film plays as
/// HLS (Decision 106), an HLS asset vends no `AVAssetTrack`s, and so
/// `FilmAudioTap`'s `AVMutableAudioMix` has nothing to attach to: every
/// television broadcast went out silent. Two fixes were built and rejected — a
/// second `AVAssetReader` over the source (a second full download) and a
/// whole-file audio rendition (measured: ~2,200 requests, did not finish in
/// 250 s, and delays go-live by minutes even if it did).
///
/// This is the third and it costs nothing: `LocalMediaServer`'s HLS segment
/// route ALREADY fetches the audio sample bytes for every fragment, because it
/// must, to mux the fragment the player is about to consume. So the audio is
/// already in hand, already in playback order, already paced by playback, and
/// already carrying Decision 031/034's pinning and failover. It only needed
/// handing over.
///
/// It delivers COMPRESSED frames. The mixer wants PCM, so a decoder sits
/// between this and `StudioAudioMixer` — and per §9.qq's Android lesson the
/// decoder supplies SAMPLES and never timestamps: the engine's single show
/// clock stamps both tracks.
final class FilmAudioBridge: @unchecked Sendable {
    static let shared = FilmAudioBridge()

    private let lock = NSLock()
    private var sink: (([Data], Int, Int) -> Void)?

    /// Counters, for the diagnostic that proves the tee actually runs. Read
    /// without the sink attached they stay zero, which is the control.
    private(set) var framesTeed = 0
    private(set) var bytesTeed = 0

    /// Nil unregisters. The Studio owns the sink for the life of a show.
    /// The sink receives `(frames, firstSampleIndex, sampleRate)`.
    ///
    /// Frames arrive SEPARATELY, one `Data` each, never concatenated. AAC frames
    /// are variable-size, so a single blob cannot be re-split — a first version
    /// passed one blob and divided it evenly, which is wrong for any VBR track
    /// and would have written nothing at all. The decoder needs these
    /// boundaries too: an AAC packet is only decodable whole.
    ///
    /// The rate comes from the audio track's timescale, which for a sound track
    /// IS the sample rate.
    func setSink(_ s: (([Data], Int, Int) -> Void)?) {
        lock.lock(); sink = s
        if s == nil { framesTeed = 0; bytesTeed = 0 }
        lock.unlock()
    }

    var isAttached: Bool { lock.lock(); defer { lock.unlock() }; return sink != nil }

    /// Called by the segment route with one fragment's worth of audio frames.
    ///
    /// `firstSample` is the audio track's sample index this fragment starts at,
    /// and it is the whole reason this signature carries a third argument.
    /// MEASURED on an Apple TV (§9.nnnn): the player fetches segments in
    /// BURSTS far ahead of the playhead — 16,296 AAC frames (~378 s of audio)
    /// arrived in about 90 s, and then the counter sat still for a minute while
    /// the buffer drained. So the tee delivers in playback ORDER but nowhere
    /// near playback RATE, and a consumer that fed the mixer as bytes arrived
    /// would push six minutes of sound into a live show and then starve.
    ///
    /// The index makes the frames addressable by FILM TIME, so the decoder can
    /// hold them and release what the show clock actually asks for. Per §9.qq
    /// the engine still owns the clock: this supplies position, never
    /// timestamps.
    func deliver(_ frames: [Data], firstSample: Int, sampleRate: Int) {
        lock.lock()
        let s = sink
        if s != nil {
            framesTeed += frames.count
            bytesTeed += frames.reduce(0) { $0 + $1.count }
        }
        lock.unlock()
        s?(frames, firstSample, sampleRate)
    }
}

final class FilmAudioTap: @unchecked Sendable {
    /// THE RING IS THE SUSPECT (§9.bbbbb). One second by default, and it sits
    /// ~0.91 s FULL in steady state across 89 samples — which is 0.9 s of audio
    /// latency between the tap and the encoder, and would put the broadcast's
    /// sound about that far behind its picture.
    ///
    /// `AW_STUDIO_RING_MS` exists so that can be a CONTROL rather than an
    /// argument: change the ring, and a causal offset must move with it. If it
    /// does not, the ring is innocent and the latency is somewhere else.
    let ring = AudioRing(capacity: FilmAudioTap.ringCapacity)

    /// THE SIZE FOLLOWS THE PATH, and the two paths need opposite things.
    ///
    /// macOS and iOS fill this ring from the TAP, which delivers inline with
    /// playback — measured at a median +40 ms of the playhead. Nothing needs
    /// buffering ahead, so a full second is pure latency: the ring sat 0.91 s
    /// full in steady state and put the broadcast's audio 0.86 s behind its
    /// picture. Measured causally, by changing the ring and watching the offset
    /// follow: 1000 ms -> -0.86 s, 250 ms -> -0.12 s, with ZERO underruns and
    /// `raw` unmoved (§9.ccccc).
    ///
    /// tvOS fills it from the PULL path, whose decoder deliberately builds a
    /// cushion up to its 0.5 s tolerance (§9.tttt) — that cushion is what
    /// stopped the clicking, and a 250 ms ring could not hold it. So the
    /// television keeps its second. Shrinking one shared default would have
    /// fixed the Mac and broken the TV, which is this feature's oldest defect
    /// wearing a new hat.
    static var ringCapacity: Int {
        #if os(tvOS)
        let fallback = 1000
        #else
        let fallback = 250
        #endif
        let ms = ProcessInfo.processInfo.environment["AW_STUDIO_RING_MS"]
            .flatMap(Int.init) ?? fallback
        // Interleaved stereo: two samples to a frame.
        return max(2048, Int(44100.0 * Double(ms) / 1000.0) * 2)
    }
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
    /// ON THE MAIN ACTOR, and only this method. `AVPlayerItem`, its `asset`
    /// and `AVAssetTrack` are all main-actor isolated and non-Sendable under
    /// Swift 6, so every touch of the item happens here. `makeTap()` stays
    /// non-isolated, which is the part that matters: the tap's callbacks run
    /// on MediaToolbox's real-time thread and trap if Swift infers main-actor
    /// isolation for them (LiveCaptions records the backtrace).
    @MainActor
    @discardableResult
    func attach(to item: AVPlayerItem) async -> Bool {
        let tracks = (try? await item.asset.loadTracks(withMediaType: .audio)) ?? []
        guard let assetTrack = tracks.first else { return false }
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
            // RETAINED, and released in `finalize`. This was
            // `passUnretained` with `finalize: nil`, which is a use-after-free
            // waiting for a teardown: the tap's `process` callback runs on
            // MediaToolbox's own real-time thread and keeps firing after the
            // show ends, so once the mixer is deallocated it dereferences a
            // freed object.
            //
            // MEASURED, not theorised — the Mac crashed ending a broadcast:
            //   EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x10
            //   thread AQProcessingTapManager
            //     _ArrayBuffer.count.getter
            //     FilmAudioTap.append(_:frames:)
            //     closure #3 in FilmAudioTap.makeTap()
            // Two of five layout runs died this way, at the moment the session
            // ended rather than during it, which is why every recording looked
            // healthy. The tap now owns a reference for exactly as long as it
            // exists.
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<FilmAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
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
                // `when` IS the film time of these samples, and it was being
                // thrown away — the same oversight as tvOS's tee carrying
                // `firstSample` to a decoder that dropped it (§9.rrrr). Keeping
                // it makes an A/V measurement possible on the PRODUCT path with
                // a real film, with no stimulus clip and no harness route.
                s.noteSourceTime(when.start)
                s.append(bufferList, frames: Int(framesOut.pointee))
            })
        var out: MTAudioProcessingTap?
        // PostEffects: what the viewer actually hears, volume and all.
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                             kMTAudioProcessingTapCreationFlag_PostEffects, &out)
        guard err == noErr else {
            // No tap means no `finalize`, so the retain above would leak.
            Unmanaged<FilmAudioTap>.passUnretained(self).release()
            return nil
        }
        return out
    }

    private func setSourceFormat(_ asbd: AudioStreamBasicDescription) {
        lock.lock()
        sourceRate = asbd.mSampleRate
        sourceChannels = Int(asbd.mChannelsPerFrame)
        prepared = true
        lock.unlock()
    }

    /// PCM from somewhere OTHER than the tap — the HLS path, where the tap
    /// cannot attach at all (§9.jjjj). Already interleaved stereo Float at the
    /// program rate, so it goes straight to the same ring the tap feeds and
    /// everything downstream is unchanged: the mixer cannot tell the two apart,
    /// which is the point.
    func acceptExternalPCM(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        ring.write(samples, count: count)
        lock.lock()
        externalSamples += count
        lastExternalAt = CACurrentMediaTimeCompat()
        lock.unlock()
    }

    /// Seconds of decoded film audio waiting in the ring — interleaved stereo,
    /// so two samples to a frame.
    var bufferedSeconds: Double {
        Double(ring.availableSamples) / 2.0 / max(programRate, 1)
    }

    /// Whether film audio is ARRIVING, by any route.
    ///
    /// The engine used to answer that question with "did the tap attach", which
    /// on tvOS is permanently false and always will be — Decision 106 plays the
    /// film as HLS and an HLS asset vends no tracks. Once the pull path started
    /// feeding this same ring (§9.tttt), that made the readout say the film's
    /// audio was not being sent while the owner could hear it on the broadcast.
    /// A readout has to describe the OUTCOME, not the mechanism that used to
    /// produce it.
    var isReceivingExternal: Bool {
        lock.lock(); defer { lock.unlock() }
        return externalSamples > 0 && CACurrentMediaTimeCompat() - lastExternalAt < 2.0
    }

    private(set) var externalSamples = 0
    private var lastExternalAt: CFTimeInterval = 0

    /// Film time of the audio the tap most recently handed over, in seconds.
    /// Written on MediaToolbox's real-time thread, so it takes the lock and
    /// does nothing else.
    private var lastSourceSeconds: Double = -1

    nonisolated func noteSourceTime(_ t: CMTime) {
        guard t.isValid, t.isNumeric else { return }
        let v = CMTimeGetSeconds(t)
        guard v.isFinite else { return }
        lock.lock(); lastSourceSeconds = v; lock.unlock()
    }

    /// Where in the film the tapped audio came from; nil before the first
    /// buffer. Compared against the player's `currentTime`, the difference is
    /// the A/V offset — minus whatever is still sitting in the ring.
    var sourceFilmPosition: Double? {
        lock.lock(); defer { lock.unlock() }
        return lastSourceSeconds < 0 ? nil : lastSourceSeconds
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
public final class MicAudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let ring = AudioRing()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "org.archivewatch.studio.mic")
    private var scratch = [Float](repeating: 0, count: 8192 * 2)
    var programRate: Double = 44100

    public override init() { super.init() }

    @discardableResult
    public func attach(to session: AVCaptureSession) -> Bool {
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    public func captureOutput(_ o: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
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

    /// Whether the film has delivered its first packet — see `tick()`.
    private var filmHasPrimed = false
    private var primeTicksWaited = 0

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
    private(set) var mic = MicAudioTap()

    /// Replaces the placeholder mic tap with the one the platform built
    /// against its own capture session.
    func adopt(mic tap: MicAudioTap) {
        tap.programRate = rate
        mic = tap
    }
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

        // DO NOT START MIXING INTO AN EMPTY FILM RING.
        //
        // The ticker runs on its own 1024/44100 s clock, which is right — it
        // is what keeps the program's audio at a constant rate regardless of
        // what the film tap does. But it used to begin the instant `start()`
        // was called, and the film tap has not delivered anything yet at that
        // moment, so the opening chunks were padded with silence: a
        // reproducible 3,316 samples (~38 ms) on a Mac, identical across
        // runs, and ZERO on the same run with a capture session attached —
        // because setting the camera up delayed the start enough for the ring
        // to prime. A measurement that moves when an unrelated device is
        // attached is a startup race, not a property of the film.
        //
        // So: hold off until the film has actually delivered, bounded, so a
        // film with NO audio track (or one that never arrives) still gets a
        // program — silent, but running.
        if !filmHasPrimed {
            if film.ring.framesWritten >= samples {
                filmHasPrimed = true
            } else {
                primeTicksWaited += 1
                // ~30 ticks is 0.7 s, which is longer than any prime observed
                // and short enough that a silent film is not left waiting.
                if primeTicksWaited < 30 { return }
                filmHasPrimed = true
            }
        }

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
