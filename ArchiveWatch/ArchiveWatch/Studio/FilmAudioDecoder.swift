// The film's audio, decoded and released at playback rate (WATCH-TOGETHER
// §9.jjjj–§9.oooo).
//
// The last link of a repair with three designs behind it. On tvOS the film
// plays as HLS, an HLS asset vends no `AVAssetTrack`s, and so the Studio's
// `MTAudioProcessingTap` never attaches: every television broadcast went out at
// −91 dB while the readout said "audio: active". `FilmAudioBridge` now tees the
// compressed frames out of the HLS segment route, which already fetches them to
// mux the fragment the player is about to consume — measured as real audio
// (−17.9 dB against −91) before this file was written, deliberately, because a
// decoder fed the wrong bytes fails like a broken decoder.
//
// TWO THINGS THIS MUST GET RIGHT, both learned the expensive way:
//
//  1. **It must PACE ITSELF.** The tee is fed by the player's BUFFERING, not by
//     playback: 378 seconds of audio arrived in 90 (§9.nnnn). The mixer's ring
//     holds one second. Decoding on arrival would overflow it and then starve —
//     the two-clock failure that cost the Android port two rounds. So the
//     compressed frames queue (they are small) and are decoded one packet at a
//     time by a pump running at real time.
//  2. **It supplies SAMPLES, never TIMESTAMPS.** The engine owns the one show
//     clock that stamps both tracks (§9.qq). This writes PCM into the film ring
//     and says nothing about when it happened.

import AVFoundation
import Foundation

final class FilmAudioDecoder: @unchecked Sendable {

    /// Where decoded, interleaved stereo Float PCM goes — the mixer's film ring.
    private let write: (UnsafePointer<Float>, Int) -> Void

    private let lock = NSLock()
    /// Each packet with the FILM FRAME INDEX it starts at, so the decoder can
    /// say where in the film the audio it just released came from. The bridge
    /// has always sent this; until §9.rrrr nothing read it.
    ///
    /// UNITS, and they cost a run: an MP4 `sample` of a sound track is one AAC
    /// FRAME (1024 PCM samples), so `firstSample` counts frames, not samples.
    /// Reading it as a PCM count put every position under 7.5 s and drove the
    /// out-of-order counter up — the control caught it, the number never
    /// reached a document.
    private var queue: [(data: Data, frame: Int)] = []
    private var lastAcceptedFirst = -1
    private var decodedFrame = -1
    private var sourceRate: Double = 44100
    /// Channels in the FILM's audio, not an assumption about it.
    ///
    /// This was hardcoded to 2, and a MONO film then failed every decode with
    /// OSStatus 1650549857 — 'bada', bad data — so the television broadcast
    /// silence while the puller happily delivered thousands of frames. A
    /// public-domain catalogue is mostly pre-1950s cinema, which is mostly
    /// mono, so this was not an edge case: it was most of the library
    /// (§9.jjjjj).
    private var sourceChannels: UInt32 = 2
    private var triedMonoFallback = false
    /// What the decoder currently BELIEVES the film is, and whether it changed
    /// its mind. Read into the periodic diagnostic so a run says so for its
    /// whole length rather than for one overwritten instant.
    public var channelState: String {
        lock.lock(); defer { lock.unlock() }
        return triedMonoFallback ? "mono(after-fallback)" : "\(sourceChannels)ch"
    }
    private var upmix: [Float] = []
    private var converter: AVAudioConverter?
    private var inFormat: AVAudioFormat?
    private var outFormat: AVAudioFormat?
    private var pump: Task<Void, Never>?

    /// The film time the PICTURE is showing, PUSHED in by a periodic time
    /// observer rather than pulled: an `AVPlayer` is not `Sendable` and the
    /// pump runs on a detached task, so a closure over the player could not
    /// cross that boundary under Swift 6. Below zero means "not aligned yet",
    /// which restores plain FIFO.
    private var headSeconds: Double = -1

    /// The playhead last pushed in, for the puller that decides what to fetch.
    var currentPlayhead: Double? {
        lock.lock(); defer { lock.unlock() }
        return headSeconds >= 0 ? headSeconds : nil
    }

    /// Called ~4x a second from the player's own time observer.
    func setPlayhead(_ seconds: Double) {
        guard seconds.isFinite else { return }
        lock.lock(); headSeconds = seconds; lock.unlock()
    }

    private(set) var droppedStale = 0
    private(set) var heldEarly = 0

    private(set) var packetsDecoded = 0
    private(set) var framesWritten = 0
    private(set) var lastError: String?
    /// Bursts that did not continue where the previous one ended. A re-fetched
    /// segment would REPLAY audio through a FIFO that cannot tell, so this is
    /// counted before it is ever explained away.
    private(set) var outOfOrderBursts = 0

    /// Film time of the audio most recently released, in seconds; nil before
    /// the first packet. Compare against the player's `currentTime` and the
    /// difference IS the lip-sync offset — no stimulus clip required.
    var filmPosition: Double? {
        lock.lock(); defer { lock.unlock() }
        return decodedFrame < 0 ? nil
            : Double(decodedFrame * Self.samplesPerPacket) / sourceRate
    }

    /// Audio delivered but not yet released, in seconds of film.
    var queuedSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(queue.count * Self.samplesPerPacket) / sourceRate
    }

    private static let samplesPerPacket = 1024

    /// How far from the playhead a packet may be and still be released. One
    /// AAC frame is 23.2 ms, so half a second is ~21 frames of slack — enough
    /// to absorb pump and playhead jitter, far inside the ~45 ms at which a
    /// human notices audio leading picture.
    private static let tolerance = 0.5

    /// Bounded so one tick can never monopolise the pump; 8 packets is 186 ms
    /// of audio, comfortably more than a 20 ms tick can consume.
    private static let maxPacketsPerTick = 8

    init(write: @escaping (UnsafePointer<Float>, Int) -> Void) {
        self.write = write
    }

    /// Called from the bridge. Cheap on purpose: queueing compressed frames
    /// costs ~4 MB for six minutes, and the decode happens on the pump.
    func accept(_ frames: [Data], firstSample: Int, sampleRate: Int) {
        lock.lock()
        if sourceRate != Double(sampleRate) {
            sourceRate = Double(sampleRate)
            converter = nil                      // rebuilt on the next pump tick
        }
        if lastAcceptedFirst >= 0, firstSample != lastAcceptedFirst { outOfOrderBursts += 1 }
        for (j, f) in frames.enumerated() {
            queue.append((f, firstSample + j))
        }
        lastAcceptedFirst = firstSample + frames.count
        lock.unlock()
    }

    func start() {
        stop()
        pump = Task.detached(priority: .userInitiated) { [weak self] in
            // FILL THE RING, don't meter it.
            //
            // One AAC packet is 1024 samples = 23.2 ms at 44.1 kHz, so real
            // time needs ~43 packets a second. Decoding ONE per 20 ms tick
            // gives at most 50 — but only if the tick is exactly 20 ms, and
            // `Task.sleep` plus the decode itself push it past 23.2 ms often
            // enough that the ring runs dry again and again. The owner heard
            // exactly that on the first YouTube broadcast: "the audio is
            // coming in but it clicks multiple times a second."
            //
            // Metering the rate was only ever safe because nothing else stopped
            // the decoder running ahead. The playhead rule does that now — a
            // packet more than `tolerance` in front of the picture is HELD — so
            // the pump can decode until it is held and build a cushion instead
            // of living at the edge of starvation.
            while !Task.isCancelled {
                var decoded = 0
                while decoded < Self.maxPacketsPerTick, self?.decodeOnePacket() == true {
                    decoded += 1
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        lock.lock()
        queue.removeAll(); lastAcceptedFirst = -1; decodedFrame = -1
        lock.unlock()
    }

    // MARK: - Decoding

    /// TWO ASSUMPTIONS REMAIN HERE, and they have the same failure signature as
    /// the stereo one that silenced every mono film (§9.jjjjj):
    ///
    ///   `mFormatID: kAudioFormatMPEG4AAC`  — the track might not be AAC.
    ///   `mFramesPerPacket: 1024`           — AAC-LC; HE-AAC packs 2048.
    ///
    /// The tee forwards frames from any track whose handler is "soun", codec
    /// unexamined, and an archive.org catalogue is not uniform — MP3 inside an
    /// MP4 is common in older uploads. Feed either to this converter and every
    /// packet fails with OSStatus 1650549857 ('bada'), the film broadcasts
    /// silence, and the readout looks healthy.
    ///
    /// NOT FIXED HERE, because no such film has been found to test against and
    /// unverified codec plumbing is how the mono bug got written in the first
    /// place. What IS in place is the way to recognise it in one line rather
    /// than five hypotheses:
    ///
    ///     AWAUDIOTEE frames=<large> decoded=0 pcm=0 err=...1650549857
    ///
    /// frames climbing with decoded stuck at zero means the decoder is being
    /// handed something it was not built for. The server knows the codec from
    /// the sample entry; threading it through is the fix when a film needs it.
    private func makeConverter(rate: Double) -> Bool {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: sourceChannels, mBitsPerChannel: 0, mReserved: 0)
        guard let inF = AVAudioFormat(streamDescription: &asbd),
              let outF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                       channels: AVAudioChannelCount(sourceChannels),
                                       interleaved: true),
              let c = AVAudioConverter(from: inF, to: outF) else {
            lastError = "could not build an AAC decoder at \\(Int(rate)) Hz"
            return false
        }
        inFormat = inF; outFormat = outF; converter = c
        return true
    }

    @discardableResult
    private func decodeOnePacket() -> Bool {
        lock.lock()
        let rate = sourceRate
        if converter == nil, !makeConverter(rate: rate) { lock.unlock(); return false }
        guard let converter, let inFormat, let outFormat, !queue.isEmpty else {
            lock.unlock(); return false
        }

        let head: Double? = headSeconds >= 0 ? headSeconds : nil
        if let head {
            // Anything the picture has already passed is gone. Dropped in ONE
            // pass: `removeFirst()` on an Array is O(n), so doing it in a while
            // loop over a burst-fed backlog is O(n^2) WHILE HOLDING THIS LOCK —
            // which is a main-thread stall wearing a correctness bug's clothes.
            var cut = 0
            while cut < queue.count,
                  Double(queue[cut].frame * Self.samplesPerPacket) / rate < head - Self.tolerance {
                cut += 1
            }
            if cut > 0 { queue.removeFirst(cut); droppedStale += cut }
            // Anything the picture has not reached yet waits. Silence now is
            // correct; a fixed delay would be wrong the moment the buffer
            // depth changed (the reasoning §9.ggg used on Android).
            guard let first = queue.first,
                  Double(first.frame * Self.samplesPerPacket) / rate <= head + Self.tolerance
            else { heldEarly += 1; lock.unlock(); return false }
        }

        let (packet, packetFrame) = queue.removeFirst()
        lock.unlock()

        let inBuf = AVAudioCompressedBuffer(format: inFormat, packetCapacity: 1,
                                            maximumPacketSize: packet.count)
        packet.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            inBuf.data.copyMemory(from: base, byteCount: packet.count)
        }
        inBuf.byteLength = UInt32(packet.count)
        inBuf.packetCount = 1
        inBuf.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))

        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 2048) else { return false }
        var supplied = false
        var err: NSError?
        let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return inBuf
        }
        if status == .error {
            lock.lock()
            lastError = err?.localizedDescription ?? "decode failed"
            // ADAPT RATHER THAN ASSUME. A stereo description over a mono stream
            // fails every packet with 'bada', and nothing upstream tells this
            // decoder the channel count — the bridge carries a sample rate and
            // not a layout. So the first failure retries as MONO, once, and the
            // converter is rebuilt; if that decodes, the film was mono.
            if !triedMonoFallback, sourceChannels != 1 {
                triedMonoFallback = true
                sourceChannels = 1
                self.converter = nil          // the instance one, not the local shadow
                lastError = "retrying as mono after a stereo decode failure"
                // SAY IT ONCE, LOUDLY, AND STICKILY. This switch is permanent —
                // there is no path back to stereo even if mono also fails — so
                // one transient decode error silently reinterprets a stereo
                // film as mono for the rest of the show. `lastError` is
                // sampled into AWAUDIOTEE only every 15 s and is overwritten
                // by the next success, so the evidence could vanish between
                // samples: on 2026-09-19 every run read `err=-` and that could
                // not distinguish "never fired" from "fired and cleared".
                awdiag("AWDEC MONO FALLBACK ENGAGED — a stereo decode failed, "
                       + "every later packet is decoded as mono and upmixed")
            }
            lock.unlock()
            return false
        }
        let n = Int(outBuf.frameLength)
        guard n > 0, let ch = outBuf.floatChannelData?[0] else { return false }
        // UPMIX MONO TO STEREO. The ring's contract is INTERLEAVED STEREO at the
        // programme rate — the mixer reads pairs — so handing it mono samples
        // gives half the frames in the wrong layout: it decodes, and it does
        // not sound right. A mono film is duplicated into both channels, which
        // is what every player does with one.
        if sourceChannels == 1 {
            if upmix.count < n * 2 { upmix = [Float](repeating: 0, count: n * 2) }
            upmix.withUnsafeMutableBufferPointer { dst in
                guard let d = dst.baseAddress else { return }
                for i in 0..<n { d[i * 2] = ch[i]; d[i * 2 + 1] = ch[i] }
                write(d, n * 2)
            }
        } else {
            write(ch, n * Int(sourceChannels))
        }
        lock.lock()
        packetsDecoded += 1; framesWritten += n; decodedFrame = packetFrame
        lock.unlock()
        return true
    }
}
