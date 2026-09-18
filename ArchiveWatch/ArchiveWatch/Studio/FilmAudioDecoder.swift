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

    /// Called ~10x a second from the player's own time observer.
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
            // One AAC packet is 1024 samples ≈ 23.2 ms at 44.1 kHz. Ticking at
            // 20 ms and decoding at most one packet per tick tracks real time
            // closely without ever running ahead of the ring.
            while !Task.isCancelled {
                self?.decodeOnePacket()
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

    private func makeConverter(rate: Double) -> Bool {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        guard let inF = AVAudioFormat(streamDescription: &asbd),
              let outF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                       channels: 2, interleaved: true),
              let c = AVAudioConverter(from: inF, to: outF) else {
            lastError = "could not build an AAC decoder at \\(Int(rate)) Hz"
            return false
        }
        inFormat = inF; outFormat = outF; converter = c
        return true
    }

    private func decodeOnePacket() {
        lock.lock()
        let rate = sourceRate
        if converter == nil, !makeConverter(rate: rate) { lock.unlock(); return }
        guard let converter, let inFormat, let outFormat, !queue.isEmpty else {
            lock.unlock(); return
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
            else { heldEarly += 1; lock.unlock(); return }
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

        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 2048) else { return }
        var supplied = false
        var err: NSError?
        let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return inBuf
        }
        if status == .error {
            lock.lock(); lastError = err?.localizedDescription ?? "decode failed"; lock.unlock()
            return
        }
        let n = Int(outBuf.frameLength)
        guard n > 0, let ch = outBuf.floatChannelData?[0] else { return }
        write(ch, n * 2)                       // interleaved stereo: 2 floats a frame
        lock.lock()
        packetsDecoded += 1; framesWritten += n; decodedFrame = packetFrame
        lock.unlock()
    }
}
