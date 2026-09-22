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
    /// Samples discarded to hold the backlog under `maxBacklog` — latency
    /// trimming, which is a different fault from `framesOverflowed` (the ring
    /// physically out of room) and is counted separately.
    private(set) var framesDroppedForLatency = 0

    /// Interleaved samples written but not yet read. This is LATENCY: whatever
    /// sits here was decoded already and will not be encoded until the mixer
    /// reaches it.
    var availableSamples: Int {
        lock.lock(); defer { lock.unlock() }
        return available
    }

    /// How big the ring is, so a fill ratio can be reported beside the
    /// overflow count above — "overflowed 0" means nothing without knowing
    /// whether the ring ever ran near full.
    var capacitySamples: Int { capacity }

    /// The most the ring will keep BEHIND the reader before discarding the
    /// oldest. Capacity bounds memory; this bounds LATENCY, which is the thing
    /// an audience notices.
    ///
    /// It exists because of the microphone. `AudioRing.read` was LIFO until
    /// 2026-09-19 — it always jumped to the newest sample, so a deep ring cost
    /// nothing visible. Making it FIFO made the read correct AND made the
    /// backlog into delay: whatever is queued is exactly how far behind the
    /// audio is. The owner, 2026-09-20, on a live broadcast: "the audio is
    /// about a second later than the video so my words do not match my lips."
    /// The film ring is held shallow by the decoder's pump ceiling; nothing
    /// bounded the microphone's.
    ///
    /// Default = capacity, so no caller changes behaviour by accident.
    var maxBacklog: Int

    init(capacity: Int = 44100 * 2, maxBacklog: Int? = nil) {
        self.capacity = capacity
        self.maxBacklog = maxBacklog ?? capacity
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
        // DROP THE OLDEST PAST THE WORKING DEPTH. Reads start at
        // `writeIndex - available`, so shrinking `available` discards the
        // oldest and keeps the newest — which is what a live path wants once
        // it has fallen behind: late audio is worth less than synchronised
        // audio, and for a host's voice it is worth nothing at all.
        if available > maxBacklog {
            framesDroppedForLatency += available - maxBacklog
            available = maxBacklog
        }
        lock.unlock()
    }

    /// Reads exactly `count` frames, padding the shortfall with silence.
    /// Returns how many were real.
    func read(into out: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock()
        let have = min(available, count)
        // THE OLDEST UNREAD SAMPLE, NOT THE NEWEST.
        //
        // This was `writeIndex - have`, which is the newest `have` samples —
        // a LIFO read out of a FIFO ring, with no read index at all. Whenever
        // more was buffered than the mixer asked for (the normal case: 120-300
        // ms sitting in the ring against ~20 ms reads), every read returned
        // the most recent chunk and silently skipped everything behind it,
        // while `available -= have` kept FIFO books over it.
        //
        // What went to air was therefore real film audio, at the right film
        // position, at the right level, with the right spectrum, no
        // discontinuities, no overflow and no padding — and fragmented beyond
        // recognition. Measured 2026-09-19: the broadcast correlated 0.139
        // with the source film where the correlator scores 1.000 against
        // itself, while the DECODER's own output one stage upstream scored
        // 0.993-0.997 with its position advancing exactly in step. That bisect
        // is what pinned it here. Owner: "every single snippet of audio is
        // being digitally re-rendered slower and with huge digital garbage
        // being inserted in between."
        //
        // `writeIndex - available` is self-consistent across reads: after
        // reading `have`, `available` drops by the same amount, so the next
        // read starts exactly where this one stopped, wherever the writer has
        // got to meanwhile.
        let start = ((writeIndex - available) % capacity + capacity) % capacity
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
        // ONE SECOND EVERYWHERE, reverted. macOS/iOS were cut to 250 ms on the
        // strength of an IN-APP number that moved with the ring — and the wire
        // says the ring changes nothing a viewer hears: -144.5 ms at 1000,
        // -149.0 at 250, -131.0 at 100, all inside a 70-93 ms spread and not
        // even ordered by size. The offset that "improved" was the formula
        // measuring its own buffer (§9.ggggg). An unjustified change that costs
        // headroom on slower machines does not get kept for looking tidy; the
        // env door stays, because it is how that was established.
        let fallback = 1000
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

    /// The program's sample rate. The tap resamples to it with
    /// `PolyphaseResampler` — see that type for the measurements that
    /// retired the nearest-neighbour hold this comment used to describe as
    /// "honest ... a §9 follow-up if a 48 kHz film ever sounds wrong".
    var programRate: Double = 44100
    /// Band-limited conversion, configured once the source format is known.
    private let resampler = PolyphaseResampler()
    /// Source-rate interleaved stereo, between de-shaping and resampling.
    private var srcScratch = [Float](repeating: 0, count: 8192 * 2)

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
        //
        // Briefly changed to PreEffects on the theory that it would stop a
        // muted monitor silencing the broadcast. It does not, and the theory
        // was wrong: the harness mutes the PLAYER (`isMuted`), which silences
        // the rendering path the tap lives in, before any effects stage. The
        // change fixed nothing and altered behaviour that was chosen
        // deliberately, so it is reverted (§9.ddddd).
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
        // HERE, not in `append`: building the kernel allocates, and `append`
        // runs in the tap's real-time process callback. This is the prepare
        // callback, which is not.
        resampler.configure(sourceRate: asbd.mSampleRate, programRate: programRate)
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

    /// PCM floats the ring DISCARDED because it was full when they arrived.
    ///
    /// `AudioRing` has counted this since it was written and NOTHING has ever
    /// read it — the same shape as the camera counter that hid a dead capture
    /// session for a whole day. It matters here because the ring holds exactly
    /// one second (44100 * 2 floats) while the pull path keeps a 12-18 second
    /// lookahead: if the pump outruns the mixer, `write` wraps over audio the
    /// mixer has not read yet, and what goes to air is fragments of the film
    /// overwritten by later fragments. That would be inaudible to every
    /// instrument used on 2026-09-19 — right level, right spectrum, right film
    /// position, no discontinuities — and it is exactly what the measured
    /// correlation looks like: the film, everywhere, at ~0.2 instead of ~1.0.
    var filmRingOverflowed: Int { ring.framesOverflowed }
    var filmRingFill: Double { Double(ring.availableSamples) / Double(max(ring.capacitySamples, 1)) }

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
        let channels = sourceChannels
        lock.unlock()

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard abl.count > 0 else { return }

        // TWO STEPS, DELIBERATELY. First de-shape whatever the tap handed
        // back into interleaved stereo AT THE SOURCE RATE — a straight copy,
        // no rate arithmetic. Then resample that with a real filter. The old
        // code fused the two, which is how a nearest-neighbour hold ended up
        // buried inside a channel-layout branch, repeated three times, where
        // nothing measured it.
        let srcFrames: Int
        if abl.count == 1 && channels >= 2 {
            srcFrames = Int(abl[0].mDataByteSize) / (4 * channels)
        } else {
            srcFrames = Int(abl[0].mDataByteSize) / 4
        }
        guard srcFrames > 0 else { return }
        if srcScratch.count < srcFrames * 2 {
            srcScratch = [Float](repeating: 0, count: srcFrames * 2)
        }
        srcScratch.withUnsafeMutableBufferPointer { sp in
            guard let src = sp.baseAddress else { return }
            if abl.count == 1 && channels >= 2 {
                guard let m = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                for i in 0..<srcFrames {
                    src[i * 2] = m[i * channels]
                    src[i * 2 + 1] = m[i * channels + 1]
                }
            } else if abl.count >= 2 {
                guard let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let r = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return }
                for i in 0..<srcFrames { src[i * 2] = l[i]; src[i * 2 + 1] = r[i] }
            } else {
                // Mono: the same sample in both program channels.
                guard let m = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                for i in 0..<srcFrames { src[i * 2] = m[i]; src[i * 2 + 1] = m[i] }
            }

            let cap = resampler.capacityNeeded(forInputFrames: srcFrames)
            if scratch.count < cap * 2 { scratch = [Float](repeating: 0, count: cap * 2) }
            scratch.withUnsafeMutableBufferPointer { out in
                guard let outBase = out.baseAddress else { return }
                let n = resampler.process(src, inFrames: srcFrames,
                                          out: outBase, outCapacity: cap)
                if n > 0 { ring.write(outBase, count: n * 2) }
            }
        }
    }
}

/// The 0–10 scale the host actually reads, on EVERY platform.
///
/// It lived inside `StudioMixerTV.swift` behind `#if os(tvOS)` for one
/// afternoon, which is the same mistake §9.ccc found with the go-live
/// request: a rule that applies to every host, written where only one
/// platform can compile it. macOS and iOS were still drawing a bare
/// `Slider(value: gain, in: 0...1.5)` — a linear amplitude, no number, and
/// a different ceiling from the television's +6 dB.
///
/// The 0–10 scale the host actually reads, and its one conversion to the
/// linear gain the mixer multiplies by.
///
/// WHY A SCALE AT ALL, rather than the decibels the mixer works in: the owner
/// asked for "a scale of 0 to 10 rather than ... decibles that most people
/// won't understand". Decibels are the right unit INSIDE `StudioAudio` and the
/// wrong unit on a television, so the conversion happens once, here, and
/// nothing downstream changes.
///
/// The taper has two segments because one straight line cannot serve both ends
/// of a fader — the same reason every real fader is tapered:
///
/// - **8 is unity**, the source's own level, untouched. It is the default for
///   both channels, so a host who never opens this screen is already there.
/// - **0…8 cuts** at 5 dB a step, so 0 is silence and 4 is a clear half.
/// - **8…10 boosts** at 3 dB a step, to the mixer's existing +6 dB ceiling.
///   The boost is not decoration: the microphone was measured at RMS
///   0.007–0.023 with the owner speaking beside the phone (`StudioAudio`'s
///   `micGain`), which is quiet enough that a host needs somewhere to go.
enum MixLevel {
    static let unity: Double = 8          // the tick that means "as recorded"
    static let maximum: Double = 10

    static func decibels(_ level: Double) -> Double {
        level > unity ? (level - unity) * 3 : (level - unity) * 5
    }

    static func gain(_ level: Double) -> Float {
        level <= 0 ? 0 : Float(pow(10, decibels(min(level, maximum)) / 20))
    }

    static func level(_ gain: Float) -> Double {
        guard gain > 0.0001 else { return 0 }
        let dB = 20 * log10(Double(gain))
        let l = dB > 0 ? unity + dB / 3 : unity + dB / 5
        return min(maximum, max(0, l))
    }

    /// An RMS reading drawn on the SAME scale as the fader, so the meter and
    /// the number a host is setting can be compared by eye. A linear 0…1 meter
    /// cannot: speech at RMS 0.02 is 2% of the bar and reads as dead.
    static func meterFraction(rms: Float) -> Double {
        level(rms) / maximum
    }

    /// One decimal, because the roll is continuous and rounding it to whole
    /// numbers would throw away the granularity the owner asked for.
    static func text(_ level: Double) -> String {
        String(format: "%.1f", level)
    }
}


// MARK: - Sample-rate conversion for the TAP paths

/// Band-limited sample-rate conversion, allocation-free at process time.
///
/// **WHY THIS EXISTS, measured rather than assumed.** Both taps used to
/// resample by nearest-neighbour — `let j = Int(Double(i) / ratio)`, a
/// zero-order hold — and this file's own comment called that "honest for a
/// 44.1/48 kHz mismatch", with a note that "a proper resampler is a §9
/// follow-up if a 48 kHz film ever sounds wrong". One did: §9.mmmmm found a
/// THIRD of broadcastable films are 48 kHz, and the owner heard the tvOS
/// version of that fault as digital artifacts.
///
/// Zero-order hold at 48000 -> 44100 measures like this, against a control
/// that proves the instrument is not biased (at ratio 1.0 the hold is
/// bit-identical to its input and scores the same as an ideal resample):
///
///     tone      ZOH      linear   band-limited
///      440 Hz   35.6 dB  78.2 dB     153.3 dB
///     1000 Hz   28.4 dB  63.9 dB     153.3 dB
///     3000 Hz   18.9 dB  44.7 dB     153.3 dB
///     8000 Hz   10.1 dB  26.7 dB     153.3 dB
///
/// 10 dB SNR is aliasing nearly as loud as the signal. tvOS does not have
/// this: its pull path converts with `AVAudioConverter` off the render
/// thread (§9.mmmmm). macOS and iOS cannot copy that directly, because their
/// film audio arrives in an `MTAudioProcessingTap` PROCESS callback, which is
/// real time — `AVAudioConverter` allocates and takes locks, and that is
/// almost certainly why the hold was chosen in the first place.
///
/// So: a polyphase windowed-sinc FIR. The kernel is built ONCE in
/// `configure`, off the render thread; `process` does nothing but multiply
/// and add.
///
/// **It carries state between calls, which is the part that is easy to get
/// wrong.** A filter needs samples either side of the point it is
/// interpolating, and the tap delivers discrete buffers. Resampling each
/// buffer independently puts a discontinuity at every boundary — clicks, the
/// exact symptom §9.jjjjj spent a day on. So the last `taps` source frames
/// are kept as history, and the fractional read position is carried over.
final class PolyphaseResampler {

    private let taps: Int
    private let phases: Int
    private var kernel: [Float] = []          // phases * taps, phase-major
    /// The previous `taps` source frames, interleaved stereo — the filter's
    /// left-hand context for the first outputs of the next buffer.
    private var history: [Float]
    /// Interleaved stereo history + incoming, so the filter can read across
    /// the join. Grown only when a buffer is bigger than any seen before.
    private var work: [Float] = []
    /// Where the next output sample reads from, in `work` frame coordinates.
    private var pos: Double
    private(set) var ratio: Double = 1        // output frames per input frame
    /// What it was configured FROM, so a caller whose rate is discovered
    /// rather than declared can notice a change.
    private(set) var sourceRate: Double = 0
    private(set) var configured = false

    init(taps: Int = 32, phases: Int = 256) {
        precondition(taps % 2 == 0 && taps >= 4)
        self.taps = taps
        self.phases = phases
        self.history = [Float](repeating: 0, count: taps * 2)
        self.pos = Double(taps) - 1
    }

    /// Builds the kernel and resets the filter. Call when the source format is
    /// known — NOT from the render callback.
    func configure(sourceRate: Double, programRate: Double) {
        let r = programRate / max(sourceRate, 1)
        ratio = r
        self.sourceRate = sourceRate
        for i in history.indices { history[i] = 0 }
        pos = Double(taps) - 1
        configured = true
        guard r != 1 else { kernel = []; return }   // a copy needs no kernel

        // DOWNSAMPLING MOVES THE CUTOFF, not just the rate. Going 48 -> 44.1
        // the new Nyquist is lower, so the filter has to remove what will not
        // fit BEFORE the decimation, or it folds back as the aliasing the
        // measurements above are made of.
        let cutoff = min(1.0, r) * 0.92
        let half = Double(taps) / 2
        // phases + 1 ROWS, not phases. `process` interpolates between row `ph`
        // and row `ph + 1`, and the extra row is offset 1.0 — the same filter
        // one source sample along — so the interpolation needs no special case
        // at the wrap.
        //
        // WHY INTERPOLATE AT ALL, measured: with a truncated phase index, a
        // float-noise difference in `pos` that straddles a phase boundary
        // flips the index by one and moves the output by one phase step of the
        // waveform. §8.17's chunk-independence assertion caught exactly that —
        // 256 phases predicts a 5.11e-04 worst-case difference at 1 kHz and
        // the harness measured 5.05e-04. Not a state bug, but it put a floor
        // under both the SNR and the reproducibility for no good reason.
        kernel = [Float](repeating: 0, count: (phases + 1) * taps)
        for ph in 0...phases {
            let offset = Double(ph) / Double(phases)
            var sum = 0.0
            var row = [Double](repeating: 0, count: taps)
            for k in 0..<taps {
                let x = Double(k) - half + 1 - offset
                let s: Double = x == 0 ? 1 : sin(.pi * cutoff * x) / (.pi * cutoff * x)
                // Blackman-Harris, for a stopband deep enough that what it
                // rejects is genuinely gone rather than merely quieter.
                let t = (x + half) / Double(taps)
                let w = 0.35875
                    - 0.48829 * cos(2 * .pi * t)
                    + 0.14128 * cos(4 * .pi * t)
                    - 0.01168 * cos(6 * .pi * t)
                row[k] = s * w
                sum += row[k]
            }
            // Unit DC gain per phase, or the output level pumps at the phase
            // rate — a buzz, not a hiss, and far more audible.
            let norm = sum == 0 ? 1 : sum
            for k in 0..<taps { kernel[ph * taps + k] = Float(row[k] / norm) }
        }
    }

    /// The most output frames `process` can produce from `inFrames` input.
    func capacityNeeded(forInputFrames inFrames: Int) -> Int {
        Int((Double(inFrames) * ratio).rounded(.up)) + 2
    }

    /// Reads `inFrames` interleaved-stereo source frames and writes
    /// interleaved-stereo frames at the program rate. Returns frames written.
    ///
    /// Allocation-free unless the input is larger than anything seen before.
    @discardableResult
    func process(_ src: UnsafePointer<Float>, inFrames: Int,
                 out: UnsafeMutablePointer<Float>, outCapacity: Int) -> Int {
        guard inFrames > 0 else { return 0 }
        guard configured, !kernel.isEmpty else {
            // Ratio 1: a straight copy, and it must be EXACT — the §8 control
            // asserts bit-identity, because a resampler that perturbs audio it
            // was not asked to touch is worse than none.
            let n = min(inFrames, outCapacity)
            out.update(from: src, count: n * 2)
            return n
        }
        let workFrames = taps + inFrames
        if work.count < workFrames * 2 { work = [Float](repeating: 0, count: workFrames * 2) }
        work.withUnsafeMutableBufferPointer { w in
            guard let wb = w.baseAddress else { return }
            history.withUnsafeBufferPointer { h in
                wb.update(from: h.baseAddress!, count: taps * 2)
            }
            (wb + taps * 2).update(from: src, count: inFrames * 2)
        }

        var written = 0
        let half = taps / 2
        work.withUnsafeBufferPointer { w in
            guard let wb = w.baseAddress else { return }
            kernel.withUnsafeBufferPointer { kb in
                guard let kbase = kb.baseAddress else { return }
                let step = 1.0 / ratio
                while written < outCapacity {
                    let j = Int(pos)
                    guard j + half < workFrames else { break }
                    let start = j - half + 1
                    guard start >= 0 else { pos += step; continue }
                    let phf = (pos - Double(j)) * Double(phases)
                    var ph = Int(phf)
                    if ph >= phases { ph = phases - 1 }
                    let a = Float(phf - Double(ph))
                    let k0 = kbase + ph * taps
                    let k1 = kbase + (ph + 1) * taps
                    var l: Float = 0, r: Float = 0
                    for k in 0..<taps {
                        let c = k0[k] + a * (k1[k] - k0[k])
                        l += c * wb[(start + k) * 2]
                        r += c * wb[(start + k) * 2 + 1]
                    }
                    out[written * 2] = l
                    out[written * 2 + 1] = r
                    written += 1
                    pos += step
                }
            }
        }

        // Keep the tail as the next call's left-hand context, and shift the
        // read position into the new coordinates.
        work.withUnsafeBufferPointer { w in
            guard let wb = w.baseAddress else { return }
            history.withUnsafeMutableBufferPointer { h in
                h.baseAddress!.update(from: wb + (workFrames - taps) * 2, count: taps * 2)
            }
        }
        pos -= Double(inFrames)
        if pos < Double(half) { pos = Double(half) }
        return written
    }
}

// MARK: - Microphone tap

/// The host's microphone, off the same `AVCaptureSession` the camera uses. On
/// tvOS that session's audio device is the Continuity microphone.
public final class MicAudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// 120 ms of working depth, not a second. A live voice that arrives late
    /// is worse than a live voice with a gap — and the mixer reads in ~20 ms
    /// chunks, so this is six reads of slack for jitter while keeping the host
    /// in step with their own lips. `AW_STUDIO_MIC_BACKLOG_MS` makes it a
    /// control rather than an argument.
    let ring = AudioRing(capacity: 44100 * 2, maxBacklog: MicAudioTap.backlogSamples)

    static let backlogSamples: Int = {
        let ms = Double(ProcessInfo.processInfo.environment["AW_STUDIO_MIC_BACKLOG_MS"] ?? "") ?? 120
        return max(882, Int(44100.0 * ms / 1000.0) * 2)      // interleaved stereo
    }()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "org.archivewatch.studio.mic")
    private var scratch = [Float](repeating: 0, count: 8192 * 2)
    /// Source-rate interleaved stereo, between de-shaping and resampling.
    private var srcScratch = [Float](repeating: 0, count: 8192 * 2)
    /// Band-limited conversion — see `PolyphaseResampler`. A capture device is
    /// discovered rather than declared, so this is configured on the first
    /// buffer and re-configured if the device's rate ever changes under us.
    private let resampler = PolyphaseResampler()
    private var session: AVCaptureSession?
    var programRate: Double = 44100

    public override init() { super.init() }

    @discardableResult
    public func attach(to session: AVCaptureSession) -> Bool {
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        // TRANSACTED, for the reason `CameraFrameTap.attach` carries in full:
        // an un-batched `addOutput` commits immediately and forces a device
        // format renegotiation, which on a Continuity device throws an ObjC
        // exception no Swift `try` can catch. This tap runs one call after
        // the camera's on the same attach sequence, so it is the same bug
        // waiting for the first run that has a Continuity microphone.
        session.beginConfiguration()
        session.addOutput(output)
        session.commitConfiguration()
        // RETAINED, for the reason CameraFrameTap's own property carries: the
        // caller's session is a local and nothing else holds it, so without
        // this the microphone stops the moment that scope ends.
        self.session = session
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
        // THE HOST'S VOICE GOES THROUGH THE SAME FILTER AS THE FILM, and for
        // the same measured reason — a capture device running at 48 kHz into a
        // 44.1 kHz programme was being sample-dropped, which is 28 dB SNR at
        // 1 kHz. Speech is the LAST thing that should be aliased: it is what
        // the audience is listening to when the host talks over the film.
        if !resampler.configured || resampler.sourceRate != asbd.mSampleRate {
            resampler.configure(sourceRate: asbd.mSampleRate, programRate: programRate)
        }
        if srcScratch.count < frames * 2 {
            srcScratch = [Float](repeating: 0, count: frames * 2)
        }

        // A capture session can hand back Int16 or Float32; read the flags
        // rather than assuming (an assumption here is silence or noise).
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        srcScratch.withUnsafeMutableBufferPointer { sp in
            guard let src = sp.baseAddress else { return }
            if isFloat {
                let s = data.assumingMemoryBound(to: Float.self)
                for i in 0..<frames {
                    let v = s[i * channels]
                    src[i * 2] = v
                    src[i * 2 + 1] = channels > 1 ? s[i * channels + 1] : v
                }
            } else {
                let s = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<frames {
                    let v = Float(s[i * channels]) / 32768
                    src[i * 2] = v
                    src[i * 2 + 1] = channels > 1 ? Float(s[i * channels + 1]) / 32768 : v
                }
            }
            let cap = resampler.capacityNeeded(forInputFrames: frames)
            if scratch.count < cap * 2 { scratch = [Float](repeating: 0, count: cap * 2) }
            scratch.withUnsafeMutableBufferPointer { out in
                guard let outBase = out.baseAddress else { return }
                let n = resampler.process(src, inFrames: frames,
                                          out: outBase, outCapacity: cap)
                if n > 0 { ring.write(outBase, count: n * 2) }
            }
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
    /// The CALL's level, and whether there is a call at all. Both, because a
    /// meter reading zero means two different things — "nobody is speaking"
    /// and "no app is being captured" — and a host needs to tell them apart
    /// before they start talking to an audience that cannot hear their guests.
    public var callLevel: Float = 0
    public var callAttached = false
    /// How far behind the host's voice is: what is queued in the mic ring and
    /// therefore not yet encoded. This IS the lip-sync error.
    public var micBacklogSeconds: Double = 0
    public var micDroppedForLatency = 0
    public var ducking = false
    /// Roadmap #4. Reported separately from `micLevel`, which stays RAW.
    public var micGateEnabled = false
    public var micGateOpen = true
}

/// THE MICROPHONE GATE — roadmap #4, as a rule you can test without an engine.
///
/// A Watch Together host is in a room with the FILM PLAYING OUT OF SPEAKERS,
/// and their open microphone is picking it up — so the broadcast carries the
/// film twice, once from the tap at full quality and once as a room-reverb
/// copy a few milliseconds late. That is a comb filter on the thing the
/// audience came for, and no fader fixes it: turning the microphone down
/// turns the HOST down too. A gate does, because the two are separated in
/// LEVEL rather than in frequency — a host speaking is far louder at the
/// microphone than speakers across a room.
///
/// OBS ships one per source. This is the same idea and deliberately NOT the
/// rest of OBS's chain: §D0 still refuses chroma key and LUTs, and this is
/// one input made usable rather than a filter rack.
public struct MicGate: Sendable, Equatable {
    public var enabled = false
    /// RMS to open at. 0.02 ≈ -34 dBFS.
    public var threshold: Float = 0.02

    /// HYSTERESIS. It opens at the threshold and closes at 60% of it, so a
    /// voice hovering at the boundary cannot chatter the gate on every 23 ms
    /// block — audible as a stutter, and the classic way a gate makes things
    /// worse than no gate at all.
    public static let closeRatio: Float = 0.6
    /// FAST OPEN, SLOW CLOSE, and the asymmetry is the whole craft: 0.5
    /// reaches full gain in about two blocks (~46 ms) so the first syllable
    /// survives, while 0.04 takes ~400 ms to close so a pause between words
    /// does not gate the middle of a sentence.
    public static let attack: Float = 0.5
    public static let release: Float = 0.04

    public private(set) var isOpen = true
    public private(set) var gain: Float = 1

    public init() {}

    /// One block. Returns the gain to apply to the microphone.
    public mutating func tick(rms: Float) -> Float {
        guard enabled else { isOpen = true; gain = 1; return 1 }
        let open = isOpen ? rms > threshold * Self.closeRatio : rms > threshold
        isOpen = open
        let target: Float = open ? 1 : 0
        gain += (target - gain) * (open ? Self.attack : Self.release)
        // Snap the last sliver: an exponential approach never reaches zero,
        // and a gate that settles at 0.001 is still sending the room.
        if !open, gain < 0.005 { gain = 0 }
        return gain
    }
}

/// Pulls a fixed chunk from both rings on its own clock, applies gains and
/// ducking, and encodes AAC.
final class StudioAudioMixer: @unchecked Sendable {
    static let framesPerPacket = 1024

    /// AAC priming frames added to each audio timestamp: 2048, the codec's own
    /// priming, which Android has carried since Decision 129 and Apple did not.
    ///
    /// MEASURED ON THE WIRE, not argued — the server's recording of a
    /// flash-and-beep broadcast:
    ///
    ///        0   -129 ms      2048   -64 ms      4096   -40 ms
    ///
    /// AND DELIBERATELY NOT TUNED FURTHER. The trend is roughly linear, so
    /// ~5700 frames would read zero — and that number would be a CALIBRATION,
    /// not a diagnosis. Decision 129 refused the same move on Android in as
    /// many words: "a fixed audio delay would paper over it and would be wrong
    /// the moment the pipeline's latency changed." 2048 is what the codec
    /// actually primes; the ~64 ms still standing belongs to something else and
    /// is an open defect (§9.hhhhh), not a knob to turn until a test passes.
    /// APPLIED WHERE IT WAS MEASURED. This mixer is shared, and the wire
    /// measurement exists only for macOS — tvOS has no `AW_PLAY_URL` door, so
    /// its broadcast has never been put through the flash-and-beep clip. The
    /// television is the best-working platform in this feature and it does not
    /// get its audio timing changed on an inference, however physically sound:
    /// the codec primes the same everywhere, and that is an argument, not a
    /// measurement. tvOS moves when tvOS is measured.
    static var primingOffsetFrames: Int {
        #if os(tvOS)
        let fallback = 0
        #else
        let fallback = 2048
        #endif
        return ProcessInfo.processInfo.environment["AW_STUDIO_AAC_PRIME"]
            .flatMap(Int.init) ?? fallback
    }

    /// Whether the film has delivered its first packet — see `tick()`.
    private var filmHasPrimed = false
    private var primeTicksWaited = 0

    /// §4's faders. 1.0 is unity; the host sets these.
    var filmGain: Float = 1.0
    /// CALIBRATABLE WITHOUT A REBUILD — `AW_STUDIO_MIC_GAIN`.
    ///
    /// Measured on Ben Bedroom 2026-09-19, owner SPEAKING near a paired
    /// iPhone: `AWMIX micLevel=0.007..0.023`. That is far quieter than speech
    /// at a phone should read and it straddles `duckThreshold` (0.02), so the
    /// film barely ducks under the host — the §4 promise that his voice sits
    /// on top of the film does not hold at that level.
    ///
    /// The conversion is NOT at fault: Int16 is divided by 32768, Float32 is
    /// passed through, and the channel indexing is right (read 2026-09-19).
    /// So the remaining candidates are the capture gain itself and the
    /// distance to the phone, and both are questions for a person in the room
    /// rather than a guess here.
    ///
    /// This door and `AW_STUDIO_DUCK_RMS` below exist so that calibration is
    /// ONE session with several runs, rather than one build per value — the
    /// owner's time is the scarce thing, not the Mac's.
    var micGain: Float = {
        Float(ProcessInfo.processInfo.environment["AW_STUDIO_MIC_GAIN"] ?? "") ?? 1.0
    }()
    var filmMuted = false
    var micMuted = false
    /// §4: the film ducks 12 dB under the host's voice.
    let duckDecibels: Float = -12
    /// Rule 8.8c — the Film channel's third state. On by default, because the
    /// duck is right for a host who has not thought about it.
    var duckEnabled = true
    /// RMS at which the host counts as speaking. `AW_STUDIO_DUCK_RMS`
    /// overrides it; see `micGain` for why both are doors.
    private let duckThreshold: Float = {
        Float(ProcessInfo.processInfo.environment["AW_STUDIO_DUCK_RMS"] ?? "") ?? 0.02
    }()
    private var duckGain: Float = 1.0            // smoothed, so ducking is not a click

    let film = FilmAudioTap()
    private(set) var mic = MicAudioTap()

    /// THE CALL'S AUDIO — §D2's fourth input, the piece that makes "With
    /// Friends and the World" real (Decision 131).
    ///
    /// Held as a bare `AudioRing` rather than as the tap, so the mixer stays
    /// platform-neutral: `AudioHardwareCreateProcessTap` is macOS-only and
    /// this file is compiled on four platforms. Nil until the host picks an
    /// app to capture — a channel that exists with nothing behind it would
    /// show a dead meter and read as broken.
    var callRing: AudioRing?

    // MARK: The microphone gate (roadmap #4)
    //
    // The RULE lives in `MicGate`, a pure value type with no ring, no encoder
    // and no clock — the same shape as `CameraStallRecovery`, and for the same
    // reason: a rule that can only be exercised by starting a whole engine is
    // a rule that gets argued about rather than tested (§8.23).
    //
    // WHY THIS PRODUCT NEEDS ONE, specifically. A Watch Together host is in a
    // room with a FILM PLAYING OUT OF SPEAKERS, and their open microphone is
    // picking it up — so the broadcast carries the film twice, once from the
    // tap at full quality and once as a room-reverb copy a few milliseconds
    // late. That is a comb filter on the thing the audience came for, and no
    // fader fixes it: turning the mic down turns the HOST down too.
    //
    // A gate does fix it, because the two are separated in LEVEL rather than
    // in frequency: a host speaking is far louder at the microphone than
    // speakers across the room. OBS ships one per source; this is the same
    // idea, and deliberately NOT the rest of OBS's filter chain (§D0 still
    // refuses chroma key and LUTs — this is one input made usable).
    var micGateEnabled = false {
        didSet { gate.enabled = micGateEnabled }
    }
    /// RMS the microphone must exceed to open. 0.02 is roughly -34 dBFS:
    /// comfortably below conversational speech at a desk microphone and
    /// comfortably above film bleed across a room. The host can move it.
    var micGateThreshold: Float = 0.02 {
        didSet { gate.threshold = micGateThreshold }
    }
    private var gate = MicGate()
    var micGateOpen: Bool { gate.isOpen }
    var callGain: Float = 1.0
    var callMuted = false

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
    private var callPcm: UnsafeMutablePointer<Float>
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
        callPcm = .allocate(capacity: n)
        interleaved = .allocate(capacity: n)
        aacOut = .allocate(capacity: 4096)
    }

    deinit {
        pcm.deallocate(); micPcm.deallocate(); callPcm.deallocate()
        interleaved.deallocate(); aacOut.deallocate()
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
        // The call, when there is one. `read` zero-fills what it cannot
        // supply, so an absent or starved channel contributes silence rather
        // than the previous chunk again.
        if let callRing {
            _ = callRing.read(into: callPcm, count: samples)
        } else {
            for i in 0..<samples { callPcm[i] = 0 }
        }

        // Levels first: ducking is decided on what the host is ACTUALLY saying
        // in this chunk, not on a setting.
        var filmSum: Float = 0, micSum: Float = 0, callSum: Float = 0
        for i in 0..<samples {
            filmSum += pcm[i] * pcm[i]
            micSum += micPcm[i] * micPcm[i]
            callSum += callPcm[i] * callPcm[i]
        }
        let filmRMS = (filmSum / Float(samples)).squareRoot()
        let micRMS = (micSum / Float(samples)).squareRoot()
        let callRMS = (callSum / Float(samples)).squareRoot()

        // Smooth the duck so it is a fade, not a click: ~40 ms attack, ~300 ms
        // release, which is what a viewer hears as "the film got out of the way".
        // Rule 8.8c: manual means manual. With auto-duck off, a host who sets
        // the film to +3 dB and then speaks keeps +3 dB — otherwise the fader
        // they just moved is overruled 12 dB by something invisible, and the
        // control lies.
        // THE CALL DUCKS THE FILM AS THE HOST'S VOICE DOES. A guest speaking
        // is a person talking over the film for exactly the reason the host
        // is, and a duck that only heard the host would leave the guests
        // fighting the soundtrack.
        let callSpeaking = callRing != nil && !callMuted && callRMS > duckThreshold
        // AND A GATED MICROPHONE MUST NOT DUCK THE FILM. Without this, film
        // bleed the gate is busy rejecting would still read as "the host is
        // talking" and pull the soundtrack down 12 dB for the whole show —
        // the gate would fix the echo and introduce a worse fault.
        let hostSpeaking = !micMuted && micRMS > duckThreshold
            && (!micGateEnabled || gate.isOpen)
        let wantDuck = duckEnabled && (hostSpeaking || callSpeaking)
        let target: Float = wantDuck ? pow(10, duckDecibels / 20) : 1.0
        let coefficient: Float = target < duckGain ? 0.45 : 0.06
        duckGain += (target - duckGain) * coefficient

        // THE GATE, decided on THIS chunk's level and applied smoothly.
        //
        // HYSTERESIS: it opens at the threshold and closes at 60% of it, so a
        // voice hovering at the boundary does not chatter the gate open and
        // shut on every 23 ms block — which is audible as a stutter and is
        // the classic way a gate makes things worse than no gate.
        //
        // FAST OPEN, SLOW CLOSE, and the asymmetry is the whole craft: 0.5
        // reaches full gain in about two blocks (~46 ms) so the first syllable
        // survives, while 0.04 takes ~400 ms to close so a pause between words
        // does not gate the middle of a sentence.
        let gateGain = gate.tick(rms: micRMS)

        let fg = (filmMuted ? 0 : filmGain) * duckGain
        let mg = (micMuted ? 0 : micGain) * gateGain
        let cg = (callMuted || callRing == nil) ? 0 : callGain
        for i in 0..<samples {
            let v = pcm[i] * fg + micPcm[i] * mg + callPcm[i] * cg
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
        health.callLevel = min(1, callRMS * 3)
        health.callAttached = callRing != nil
        health.micBacklogSeconds = Double(mic.ring.availableSamples) / 2.0 / max(mic.programRate, 1)
        health.micDroppedForLatency = mic.ring.framesDroppedForLatency
        health.ducking = wantDuck
        // THE METER STAYS RAW and the gate is reported separately (§D3's
        // rule, extended). A meter showing the GATED level would sit at zero
        // while the microphone was plainly working, which is exactly how a
        // host concludes their microphone is broken. The honest pair is "your
        // microphone hears this much" AND "none of it is being sent".
        health.micGateEnabled = micGateEnabled
        health.micGateOpen = gate.isOpen
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
        // AAC PRIMING, as an EXPERIMENT rather than a behaviour change.
        //
        // Android carries this correction and Apple does not
        // (`StudioAacEncoder.kt`: 2048 samples, "output lags its input by the
        // codec's priming samples ... FLV has nowhere to carry an edit list").
        // The wire says macOS audio LEADS the picture by ~130-150 ms, and an
        // uncompensated priming delay makes audio appear early by exactly this
        // kind of margin — 2048 samples is 46 ms at 44.1 kHz.
        //
        // Default ZERO, so nothing changes until the wire says it helps. Adding
        // frames makes the audio stamps LATER, which is the direction that
        // reduces a lead; if the measurement does not move by ~46 ms, the
        // hypothesis is wrong and this comes straight back out.
        let pts = CMTime(value: CMTimeValue(packetsOut * Self.framesPerPacket
                                            + Self.primingOffsetFrames),
                         timescale: CMTimeScale(rate))
        packetsOut += 1
        onFrame?(frame, pts)
    }

    func currentHealth() -> StudioAudioHealth {
        healthLock.lock(); defer { healthLock.unlock() }
        return health
    }

    var micEverArrived: Bool { micHasEverArrived }
}
