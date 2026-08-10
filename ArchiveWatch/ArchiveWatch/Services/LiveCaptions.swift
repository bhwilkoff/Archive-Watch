import AVFoundation
import Foundation
#if canImport(Speech)
import Speech
#endif

// Live captions for a film that is STREAMING — no download, no server.
//
// WHY THIS EXISTS, and the mistake it corrects. `SubtitleFinder.transcribe`
// downloads the whole film first, because `AVAssetReader` refuses a remote URL
// and `AVAssetExportSession` fails -11838 on one. I took that to mean
// transcription requires the file. It does not: those APIs only rule out reading
// the asset AS A FILE. A player decodes remote audio continuously, and
// `MTAudioProcessingTap` on the item's audio mix hands back those decoded PCM
// buffers in real time — which is exactly what `SpeechAnalyzer` consumes
// (`AnalyzerInput(buffer:)`). Measured on a remote archive.org MP4 before
// building this: 106 tap callbacks and 9.1s of PCM captured in 8.8s of wall
// clock (`tools/test_live_audio_tap.swift`).
//
// So the cost of captioning a film the viewer is already watching is zero extra
// bytes. That is what every other streaming app does, and it is what the "full
// download" caveat should never have been.
//
// HONESTY ABOUT WHAT THIS IS. These are machine captions of an 80-year-old
// optical soundtrack, produced live with no second pass. They are labelled as
// automatic wherever they appear. They are NOT offered for silent films — that
// is refused upstream, never detected afterwards (Decision 039b).
@MainActor
@Observable
final class LiveCaptions {

    private(set) var isRunning = false
    private(set) var failure: String?

    /// Complete cues on the FILM's timeline, transcribed AHEAD of playback.
    ///
    /// The display is POP-ON: a whole caption appears when its line begins and
    /// is replaced by the next, which is how a professionally captioned film
    /// reads. Live roll-up — words arriving one at a time and the line reflowing
    /// — is the convention for BROADCAST, where nobody knows what is coming.
    /// Here we do: the scout below transcribes ahead of the playhead, so there is
    /// no reason to make the viewer watch a sentence assemble itself.
    private var cues: [(start: Double, end: Double, text: String)] = []
    /// Where the scout began, in film time; the analyzer clocks from zero.
    private var contentOffset: Double = 0
    private var pendingWords: [(start: Double, end: Double, text: String)] = []

    /// The caption to show at `playhead`, or "" between lines.
    func line(at playhead: CMTime) -> String {
        let t = playhead.seconds
        guard t.isFinite else { return "" }
        // The cue covering now. A small lead-in keeps a caption from flashing on
        // a frame late; a short hold keeps it up through natural pauses.
        if let c = cues.last(where: { $0.start - 0.25 <= t && t <= $0.end + 0.6 }) {
            return c.text
        }
        return ""
    }

    /// How far ahead of `playhead` the transcript currently reaches.
    func leadSeconds(over playhead: CMTime) -> Double {
        (cues.last?.end ?? contentOffset) - playhead.seconds
    }

    /// True where the on-device recognizer exists at all.
    static var isSupported: Bool { AutoCaptions.isSupported }

    private var tap: MTAudioProcessingTap?
    private var scoutPlayer: AVPlayer?
    private var task: Task<Void, Never>?
    private let sink = BufferSink()

    /// Transcribe `url` AHEAD of playback, starting at `from`.
    ///
    /// This deliberately does NOT tap the playing item. Tapping playback yields
    /// audio at 1x, so the transcript can only ever trail what is being said —
    /// no amount of display polish fixes that. Instead a second, MUTED player
    /// runs the same URL at an elevated rate with the tap on it, so cues are
    /// ready before the viewer reaches them and can be shown whole.
    ///
    /// Transcription measured at ~66x realtime, so the scout is limited by
    /// bandwidth, not compute; it pauses whenever it is far enough ahead
    /// (`throttle`) rather than racing to the end of the film.
    func start(url: URL, from startTime: CMTime) {
        guard !isRunning, Self.isSupported else { return }
        isRunning = true
        failure = nil
        contentOffset = max(0, startTime.seconds.isFinite ? startTime.seconds : 0)

        guard let tap = sink.makeTap() else {
            failure = "Couldn't attach to the audio."
            isRunning = false
            return
        }
        self.tap = tap

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let scout = AVPlayer(playerItem: item)
        // volume 0, but NOT isMuted: muting can take the audio out of the render
        // pipeline altogether, and then the processing tap never fires.
        scout.volume = 0
        scoutPlayer = scout

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
                self.failure = "This title has no audio to transcribe."
                self.isRunning = false
                return
            }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
            await scout.seek(to: CMTime(seconds: self.contentOffset, preferredTimescale: 600))
            scout.rate = Self.scoutRate
            print("[AWCAP] scout playing at \(scout.rate)x from \(self.contentOffset)s")
        }

        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            task = Task { [weak self] in await self?.consume() }
        }
        #endif
    }

    /// Keep the scout a comfortable distance ahead — far enough that cues are
    /// always ready, close enough that we are not downloading the whole film.
    func throttle(playhead: CMTime) {
        guard let scout = scoutPlayer else { return }
        let lead = leadSeconds(over: playhead)
        if lead > Self.maxLead, scout.rate != 0 {
            scout.rate = 0
        } else if lead < Self.minLead, scout.rate == 0 {
            scout.rate = Self.scoutRate
        }
    }

    /// Split a finalized span into caption-sized lines, filed by time.
    ///
    /// A Result can cover a long stretch; a caption should be one or two short
    /// lines (~32 characters is the broadcast convention). Long spans are divided
    /// proportionally so each piece still lands when it is spoken.
    private func appendCue(start: Double, end: Double, text: String) {
        let chunks = Self.wrap(text, limit: Self.maxCharsPerLine * Self.visibleLines)
        guard !chunks.isEmpty else { return }
        let span = max(end - start, 0.4)
        let per = span / Double(chunks.count)
        for (i, chunk) in chunks.enumerated() {
            let s0 = start + per * Double(i)
            cues.append((start: s0, end: s0 + per, text: chunk))
        }
        cues.sort { $0.start < $1.start }
        if cues.count > 600 { cues.removeFirst(cues.count - 600) }
    }

    /// Greedy word wrap into pieces of at most `limit` characters.
    static func wrap(_ text: String, limit: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for w in text.split(separator: " ").map(String.init) {
            if current.isEmpty { current = w }
            else if current.count + 1 + w.count <= limit { current += " " + w }
            else { out.append(current); current = w }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static let maxCharsPerLine = 32
    static let visibleLines = 2

    static let scoutRate: Float = 2.0
    private static let maxLead: Double = 120
    private static let minLead: Double = 45

    func stop() {
        task?.cancel(); task = nil
        sink.finish()
        scoutPlayer?.rate = 0
        scoutPlayer = nil
        tap = nil
        isRunning = false
        cues.removeAll()
        pendingWords.removeAll()
    }

    // The tap callbacks live on BufferSink, NOT here — see the note there.

    // MARK: - The recognizer

    #if canImport(Speech)
    @available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
    private func consume() async {
        // The LIVE preset. `.timeIndexedTranscriptionWithAlternatives` is the
        // offline one: it reports no volatile results, so nothing appears until a
        // whole utterance finalizes. `.timeIndexedProgressiveTranscription` gives
        // interim results as they are heard, which is what a caption needs.
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"),
                                            preset: .timeIndexedProgressiveTranscription)
        do {
            // Reserve the locale + install the model. Without the reservation
            // the analyzer reports "not subscribed to transcription.en" and no
            // format is ever available (see AutoCaptions.prepareModel).
            try await AutoCaptions.prepareModel(for: transcriber,
                                                locale: Locale(identifier: "en-US"))
            guard let want = await SpeechAnalyzer
                .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                print("[AWCAP] NO speech model available — cannot transcribe")
                await MainActor.run { self.failure = "No speech model is available." }
                return
            }
            print("[AWCAP] analyzer format \(want.sampleRate)Hz ch=\(want.channelCount)")
            sink.setTargetFormat(want)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.start(inputSequence: sink.stream())
            for try await result in transcriber.results {
                if Task.isCancelled { break }
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // Only FINAL results become cues. Volatile ones are revised in
                // place and exist so a live display can show speech ARRIVING —
                // exactly what we no longer need, because the scout runs ahead
                // of the viewer and a caption can be shown whole.
                guard result.isFinal else { continue }
                // SCALE BY THE SCOUT RATE. The analyzer clocks by samples it has
                // consumed, and playing at 2x time-compresses the audio — so the
                // same speech yields half as many samples and every cue landed at
                // half its true time ("From cave wall to billboard" at 14.2s when
                // it is spoken at 28.4s). Multiplying by the rate puts cues back
                // on the film's own timeline.
                let rate = Double(Self.scoutRate)
                let s0 = contentOffset + result.range.start.seconds * rate
                let e0 = contentOffset + result.range.end.seconds * rate
                guard s0.isFinite, e0.isFinite else { continue }
                await MainActor.run {
                    if self.cues.count < 3 {
                        print("[AWCAP] cue \(String(format: "%.1f", s0))-\(String(format: "%.1f", e0))s: \(text.prefix(40))")
                    }
                    self.appendCue(start: s0, end: e0, text: text)
                }
            }
        } catch {
            print("[AWCAP] FAILED: \(error)")
            await MainActor.run {
                self.failure = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
    #endif
}

/// Bridges the real-time audio thread to the recognizer's async input.
///
/// The tap's process callback runs on a high-priority media thread and must not
/// block, allocate unpredictably, or hop actors — so it converts into a
/// preallocated buffer and hands it straight to a continuation.
final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var sourceFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    /// Output frames emitted so far — the monotonic clock handed to the analyzer.
    private var elapsedFrames: Int64 = 0
    private var baseFrames: Int64 = 0
    private var anchored = false
    #if canImport(Speech)
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    #endif

    /// Build the processing tap.
    ///
    /// THIS MUST NOT LIVE ON A @MainActor TYPE. The tap's `prepare` and `process`
    /// callbacks are invoked on MediaToolbox's real-time audio thread, and Swift
    /// infers actor isolation for a closure from the type it is written in — so
    /// declaring them inside `@MainActor final class LiveCaptions` made the
    /// runtime assert the main queue from the audio thread and trap:
    ///
    ///   _dispatch_assert_queue_fail <- swift_task_checkIsolatedSwift
    ///     <- closure #2 in LiveCaptions.makeTap() <- aptap_PrepareTapIfNeeded
    ///
    /// A crash on Play, every time, for every film. `BufferSink` is a plain
    /// final class with no isolation, which is what these callbacks require.
    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: nil,
            prepare: { tap, _, format in
                let s = Unmanaged<BufferSink>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                s.setSourceFormat(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                // The 5th parameter is the PRESENTATION TIME RANGE of this audio.
                // Passing nil (as this did) throws away the only thing that ties a
                // transcript to the film's timeline, which is why the captions
                // were mistimed.
                var when = CMTimeRange.zero
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList,
                                                                flagsOut, &when, framesOut)
                guard status == noErr else { return }
                let s = Unmanaged<BufferSink>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                s.append(bufferList, frames: framesOut.pointee, at: when.start)
            })
        var out: MTAudioProcessingTap?
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                             kMTAudioProcessingTapCreationFlag_PostEffects, &out)
        return err == noErr ? out : nil
    }

    func setSourceFormat(_ asbd: AudioStreamBasicDescription) {
        var d = asbd
        lock.lock(); defer { lock.unlock() }
        sourceFormat = AVAudioFormat(streamDescription: &d)
        converter = nil
    }

    func setTargetFormat(_ format: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        targetFormat = format
        converter = nil
    }

    #if canImport(Speech)
    @available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
    func stream() -> AsyncStream<AnalyzerInput> {
        AsyncStream { cont in
            lock.lock(); continuation = cont; lock.unlock()
        }
    }
    #endif

    func finish() {
        lock.lock(); defer { lock.unlock() }
        #if canImport(Speech)
        continuation?.finish()
        continuation = nil
        #endif
    }

    func append(_ bufferList: UnsafeMutablePointer<AudioBufferList>,
                frames: CMItemCount, at start: CMTime) {
        #if canImport(Speech)
        guard #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) else { return }
        // The WHOLE body holds the lock. Releasing it before advancing the frame
        // counter let concurrent tap callbacks interleave and emit out-of-order
        // timestamps, which the analyzer rejects outright with SFSpeechError 17,
        // "Audio input timestamp overlaps or precedes prior audio input" — and no
        // captions are produced at all. The clock has to advance atomically with
        // the yield that uses it.
        lock.lock()
        defer { lock.unlock() }

        guard let src = sourceFormat, let dst = targetFormat,
              let cont = continuation, frames > 0 else { return }
        if converter == nil { converter = AVAudioConverter(from: src, to: dst) }
        guard let conv = converter,
              let inBuf = AVAudioPCMBuffer(pcmFormat: src, bufferListNoCopy: bufferList)
        else { return }

        let ratio = dst.sampleRate / src.sampleRate
        let cap = AVAudioFrameCount(Double(frames) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: cap) else { return }
        var err: NSError?
        var fed = false
        conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        guard err == nil, outBuf.frameLength > 0 else { return }

        // A MONOTONIC clock, anchored once to the film's timeline.
        //
        // Passing the tap's raw time crashed on the buffers it leaves invalid
        // (checkIsValidCMTime). So the FIRST valid timestamp sets the anchor and
        // everything after is counted in output frames: monotonic by
        // construction, and still on the film's timeline, which is what makes a
        // cue match the moment it is spoken.
        if !anchored, start.isValid, start.isNumeric {
            baseFrames = Int64(start.seconds * dst.sampleRate)
            anchored = true
        }
        // Counted in FRAMES at the target rate, not seconds at timescale 600.
        // A 1024-frame step at 16 kHz is 0.064s = 38.4 ticks of a 600 timescale,
        // so consecutive stamps ROUNDED TO THE SAME VALUE and the analyzer read
        // them as overlapping (SFSpeechError 17) — no captions at all. Frames are
        // exact and strictly increasing.
        elapsedFrames += Int64(outBuf.frameLength)
        // NO explicit timestamp. Three attempts at supplying one all failed —
        // the tap's raw time is sometimes invalid (a trap in checkIsValidCMTime),
        // and every clock I derived was rejected as overlapping (SFSpeechError
        // 17), including exact frame counts. The analyzer keeps its own clock
        // perfectly well; what it needs from us is the audio, in order.
        //
        // Result.range is then relative to when analysis STARTED, so
        // `analysisStartSeconds` (the playhead at that moment) maps a cue back
        // onto the film — which is all the display needs.
        cont.yield(AnalyzerInput(buffer: outBuf))
        #endif
    }
}
