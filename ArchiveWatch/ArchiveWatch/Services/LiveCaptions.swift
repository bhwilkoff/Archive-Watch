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

    /// Finalized cues, each on the FILM's timeline. A transcriber Result covers
    /// its OWN range — it is not a sentence that grows — so they have to be
    /// collected. Replacing a single string with each Result (what this did
    /// first) shows nothing but the newest fragment, which is why only the last
    /// word of every sentence appeared.
    private var cues: [(range: CMTimeRange, text: String)] = []
    /// Playhead position when analysis began — the offset from the analyzer's
    /// clock to the film's.
    private var analysisStart: Double = 0

    /// What to show at `time`: the cue being spoken now, joined with its
    /// immediate neighbours so a caption reads as a phrase rather than a word.
    func line(at playhead: CMTime) -> String {
        guard !cues.isEmpty else { return "" }
        let time = CMTime(seconds: max(0, playhead.seconds - analysisStart),
                          preferredTimescale: 600)
        // The cue containing `time`, else the most recent one that has started —
        // the analyzer runs a beat behind live audio, and a caption that
        // disappears between cues flickers.
        var idx = cues.lastIndex { $0.range.start <= time }
        if let i = idx, CMTimeRangeContainsTime(cues[i].range, time: time) == false,
           CMTimeGetSeconds(CMTimeSubtract(time, cues[i].range.end)) > 3.0 {
            idx = nil                      // stale: nothing has been said for 3s
        }
        guard let i = idx else { return "" }
        // Join backwards until the line is a readable length.
        var parts: [String] = [cues[i].text]
        var j = i - 1
        while j >= 0, parts.joined(separator: " ").count < 60,
              CMTimeGetSeconds(CMTimeSubtract(cues[i].range.end, cues[j].range.start)) < 6.0 {
            parts.insert(cues[j].text, at: 0)
            j -= 1
        }
        return parts.joined(separator: " ")
    }

    /// True where the on-device recognizer exists at all.
    static var isSupported: Bool { AutoCaptions.isSupported }

    private var tap: MTAudioProcessingTap?
    private var task: Task<Void, Never>?
    private let sink = BufferSink()

    /// Start captioning the audio of `item` as it plays.
    ///
    /// `track` is the item's audio track; the caller has it already from the
    /// asset, and loading it here would mean an await on the main actor at the
    /// moment playback starts.
    func start(item: AVPlayerItem, track: AVAssetTrack) {
        guard !isRunning, Self.isSupported else { return }
        isRunning = true
        failure = nil
        // Result ranges are relative to when ANALYSIS started, so remember where
        // the film was at that moment. Without this a title resumed at 20:00
        // would show cues 20 minutes early.
        let now = item.currentTime()
        analysisStart = (now.isValid && now.isNumeric) ? now.seconds : 0

        guard let tap = sink.makeTap() else {
            failure = "Couldn't attach to the audio."
            isRunning = false
            return
        }
        self.tap = tap
        print("[AWCAP] tap attached to track \(track.trackID)")
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix

        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            task = Task { [weak self] in await self?.consume() }
        }
        #endif
    }

    func stop() {
        task?.cancel(); task = nil
        sink.finish()
        tap = nil
        isRunning = false
        cues.removeAll()
    }

    // The tap callbacks live on BufferSink, NOT here — see the note there.

    // MARK: - The recognizer

    #if canImport(Speech)
    @available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
    private func consume() async {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"),
                                            preset: .timeIndexedTranscriptionWithAlternatives)
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
            let feed = Task { try await analyzer.analyzeSequence(sink.stream()) }
            for try await result in transcriber.results {
                if Task.isCancelled { break }
                let line = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                // Keep FINAL results only. Volatile ones are revised in place and
                // would make the caption stutter as it is re-written.
                guard result.isFinal else { continue }
                if self.cues.count < 3 {
                    print("[AWCAP] cue @\(String(format: "%.1f", CMTimeGetSeconds(result.range.start)))s: \(line.prefix(48))")
                }
                let range = result.range
                await MainActor.run {
                    // Replace any cue covering the same span (a final can supersede
                    // an earlier one), then keep the list ordered and bounded.
                    self.cues.removeAll { CMTimeCompare($0.range.start, range.start) == 0 }
                    self.cues.append((range: range, text: line))
                    self.cues.sort { CMTimeCompare($0.range.start, $1.range.start) < 0 }
                    if self.cues.count > 400 { self.cues.removeFirst(self.cues.count - 400) }
                }
            }
            feed.cancel()
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
