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
    private(set) var failure: String? {
        didSet { if failure != nil, failedAt == nil { failedAt = Date() } }
    }

    /// When a film produces no captions, the viewer is owed a reason.
    ///
    /// Every failure here was previously stored and never shown: the engine set
    /// `failure`, the label stayed hidden, and the screen was indistinguishable
    /// from a film with nothing to say. That is what made "captions don't show
    /// up at all" impossible to act on — the app knew why and never said. This
    /// is the one line it will admit to, and only while it is still useful.
    var notice: String {
        if let failure, let failedAt,
           Date().timeIntervalSince(failedAt) < Self.failureNoticeDuration {
            return failure
        }
        // The model may need installing on first use — on an Apple TV nothing
        // else asks for it, so this is a real download, not an instant.
        if let modelProgress, failure == nil, isRunning {
            return "Downloading the speech model\u{2026} \(Int(modelProgress * 100))%"
        }
        // No "Preparing automatic captions…" notice, ever (owner, 2026-08-26:
        // it "shows for far too long and is almost entirely unneeded"). The
        // Photos app is the bar: captions simply appear when ready. A film
        // being uncaptioned for its first half-minute looks exactly like a
        // film with nothing to say, and that is fine — the two notices that
        // survive are the ones carrying information the viewer can act on:
        // a model download in progress, and a real failure with its reason.
        return ""
    }

    /// Turn a recognizer error into something a viewer can act on.
    ///
    /// "not subscribed to transcription.en" is the shape this takes when the
    /// device has no speech model and cannot get one — accurate, and useless on
    /// a television. The raw text is logged either way.
    static func viewerMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowered = raw.lowercased()
        if lowered.contains("not subscribed") || lowered.contains("download status")
            || lowered.contains("no common audio format") {
            return "Automatic captions need a speech model this device doesn't have."
        }
        return raw
    }

    private var modelProgress: Double?
    private var failedAt: Date?
    private var startedAt: Date?
    private var everProducedCue = false
    /// Long enough that a normal few-second warm-up never announces itself.
    private static let failureNoticeDuration: TimeInterval = 12

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
    /// PIECEWISE analyzer->film mapping. The nominal formula
    /// (offset + raw x scoutRate) is exact only while the renderer honors
    /// the asked rate; The Ghost Train sustained ~1.5x against 2.0x and the
    /// error REGENERATED faster than D081-clamped level corrections could
    /// drain it (floor 16.6 -> 35.8s ahead across two windows, corrections
    /// clamped to -4.3/-2.1/-0.1s). A continuous shortfall is a SLOPE
    /// error: the closed loop below measures d(err)/d(delivered) and
    /// re-anchors the mapping RATE for future cues, with anchor continuity
    /// so no minted cue moves. Level corrections keep draining what
    /// accumulated before the switch — and with the slope gone, the clamp
    /// can finally catch up.
    private var mappingAnchorRaw: Double = 0
    private var mappingAnchorFilm: Double = 0
    private var mappingRate: Double = Double(LiveCaptions.scoutRate)

    private func filmTime(_ raw: Double) -> Double {
        mappingAnchorFilm + (raw - mappingAnchorRaw) * mappingRate
    }

    private func resetMapping() {
        mappingAnchorRaw = 0
        mappingAnchorFilm = contentOffset
        mappingRate = Double(Self.scoutRate)
    }
    private var pendingWords: [(start: Double, end: Double, text: String)] = []
    /// The recognizer's own timings, before any display pacing (Decision 059).
    private var rawCues: [(start: Double, end: Double, text: String)] = []
    /// Where the viewer is, so a caption already on screen is never re-timed.
    private var lastPlayhead: Double = 0

    /// Why the display is blank at `t`: how many cues currently bracket it.
    ///
    /// Reconstructing this from the trace does not work — a drift correction
    /// moves every cue AFTER the mapping lines were logged, so a blank tick
    /// cannot be attributed to a gap or a drop after the fact. On The
    /// Incredible Machine 12 of 19 blanks LOOKED like drops by that method and
    /// none of them could be trusted. The display knows; let it say so.
    func bracketingCueCount(at t: Double) -> Int {
        cues.filter { $0.start <= t && t <= $0.end }.count
    }

    /// The film-time start of the cue being shown at `t`, for the monotonicity
    /// gate. Asserting on the CREATION-time trace lines does not work: a drift
    /// correction shifts cues that were already logged, so an older line's
    /// value is stale and comparing it to a newer one invents regressions that
    /// never reached the screen. Only what the display actually showed, in the
    /// order it showed it, is evidence.
    func shownCueStart(at t: Double) -> Double? {
        let start = cues.first { $0.start <= t && t <= $0.end }?.start
        if let start, start > lastShownCueStart { lastShownCueStart = start }
        return start
    }

    /// The furthest cue start the viewer has actually seen. Recorded for the
    /// gate; NOT used as the clamp floor. Flooring the clamp on it was tried
    /// and measured WORSE (3 displayed cues stepped back against 1), and with
    /// runs of the same film giving 0, 1 and 3 regressions the effect is
    /// nondeterministic — characterising it needs repeated trials per arm, not
    /// one run each (the lesson of Decision 075's bisect).
    private var lastShownCueStart: Double = 0

    /// The caption to show at `playhead`, or "" between lines.
    func line(at playhead: CMTime) -> String {
        let t = playhead.seconds
        guard t.isFinite else { return "" }
        if t > lastPlayhead { lastPlayhead = t }
        return Self.display(cues: cues, at: t)
    }

    /// The cue covering `t`, exactly as authored: shown from its start, held
    /// to its end plus a blink guard. Shared by the engine (whose cues were
    /// paced at creation, Decision 059) and the tvOS file overlay (whose cues
    /// were paced at publish, pace_vtt) — in both cases the CUE TIMES are the
    /// display schedule, and this function adds nothing to them.
    ///
    /// A build that "improved" on this is why it carries a warning: extending
    /// each cue to its reading time and stacking two of them showed old lines
    /// into new dialogue, let an expired short cue leave its PREDECESSOR
    /// alone on screen, and churned in fast runs — the owner saw captions
    /// "almost entirely wrong", on a file whose timing was measured correct.
    /// The display's only job is fidelity to the cue times; pacing problems
    /// are fixed in the cues (at publish or at creation), never here.
    static func display(
        cues: [(start: Double, end: Double, text: String)], at t: Double
    ) -> String {
        guard let i = cues.lastIndex(where: { $0.start <= t }) else { return "" }
        return t <= cues[i].end + holdAfterEnd ? cues[i].text : ""
    }

    /// How long a line needs to be readable. ~2.5 words/second is a common
    /// subtitle guideline (roughly 150 wpm); never less than a second.
    static func readingTime(_ text: String) -> Double {
        max(1.0, Double(text.split(separator: " ").count) / 2.5)
    }
    private static let holdAfterEnd: Double = 0.5

    /// Show these cues instead of our own transcript.
    ///
    /// Used when a published subtitle track turns out to be GOOD BUT MISTIMED
    /// (`SubtitleAgreement`): the viewer then gets the human words at corrected
    /// times, which beats a machine transcript on both counts. Transcription
    /// stops — the scout has done its job, which was to judge the file, and
    /// there is no reason to keep paying for a second stream.
    func adopt(_ replacement: [(start: Double, end: Double, text: String)]) {
        guard !replacement.isEmpty else { return }
        cues = replacement.sorted { $0.start < $1.start }
        rawCues.removeAll()
        everProducedCue = true
        failure = nil
        task?.cancel(); task = nil
        sink.finish()
        silenceScout()
    }

    /// Stop transcribing but keep showing what we have.
    func stopListening() {
        task?.cancel(); task = nil
        sink.finish()
        silenceScout()
    }

    /// Fully stop the scout: pause AND detach its item. Setting rate to 0 and
    /// dropping the reference is not enough — the MAIN player was measured
    /// UNDEAD after exactly that (clock advancing for minutes, Decision 070),
    /// and a leaked scout is worse: a muted 2x stream is invisible and
    /// inaudible while it eats bandwidth and decode, and one can stack up per
    /// resume. No item, no pipeline.
    private func silenceScout() {
        guard let scout = scoutPlayer else { return }
        scout.pause()
        scout.replaceCurrentItem(with: nil)
        scoutPlayer = nil
        if trace { awdiag("[AWCAP] trace scout silenced (item detached)") }
    }

    /// Everything transcribed so far, at the times the recognizer reported.
    ///
    /// This is the app's own independent estimate of what is being said, which
    /// makes it the only thing on hand that can judge whether a PUBLISHED
    /// subtitle track actually matches the film (`SubtitleAgreement`).
    ///
    /// Deliberately the RAW times, not the displayed ones: `cues` has been
    /// re-timed to be readable, and that re-timing only moves cues later, so
    /// measuring against it biases every correction in one direction.
    func transcript() -> [(start: Double, end: Double, text: String)] {
        rawCues.isEmpty ? cues : rawCues
    }

    /// How far ahead of `playhead` the transcript currently reaches.
    func leadSeconds(over playhead: CMTime) -> Double {
        (cues.last?.end ?? contentOffset) - playhead.seconds
    }

    /// True where the on-device recognizer exists at all.
    /// Whether this device should transcribe films that ship with no subtitle
    /// file. Default ON.
    ///
    /// A REAL control, unlike the dead "Offer automatic captions" toggle that
    /// Decision 056 removed for gating nothing. Generating captions runs a
    /// second muted stream over the same film, which is the remaining suspect
    /// for the owner's audio-static report now that the delivery path measures
    /// byte-identical under concurrency — so turning it off is both a
    /// preference someone may want and the A/B that localizes the fault.
    ///
    /// Not on AppStore: this section is shared by three platforms whose stores
    /// are different types, and a device-local preference belongs in
    /// UserDefaults regardless.
    static var transcribeWhenMissing: Bool {
        get { UserDefaults.standard.object(forKey: transcribeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: transcribeKey) }
    }
    private static let transcribeKey = "autoCaptionsEnabled"

    static var isSupported: Bool { AutoCaptions.isSupported }

    private var tap: MTAudioProcessingTap?
    private var scoutPlayer: AVPlayer?
    /// Retained for the scout asset's lifetime — the resource-loader delegate
    /// is held weakly, so dropping this silently stops the stream.
    private var streamLoader: ResilientStreamLoader?
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
    func start(url: URL, from startTime: CMTime) async {
        guard !isRunning, Self.isSupported else { return }
        // Don't stream a second copy of the film to feed a recognizer this
        // device hasn't got. On an Apple TV that was pure waste — a muted 2x
        // download of every film, for captions that could never appear. The
        // answer is AWAITED: playback begins seconds after launch, so a
        // fire-and-forget probe was still running and the scout started anyway.
        guard await CaptionCapability.shared.resolved() else {
            if CaptionCapability.shared.shouldAnnounceUnavailable {
                // The capability probe knows WHY (hardware floor vs unreachable
                // model catalog); a blanket "can't" left a two-Apple-TV
                // household with no way to tell a permanent limit on one unit
                // from a transient failure.
                failure = CaptionCapability.shared.unavailableMessage
                    ?? "This device can't caption films by itself."
            }
            return
        }
        isRunning = true
        failure = nil
        failedAt = nil
        everProducedCue = false
        startedAt = Date()
        contentOffset = max(0, startTime.seconds.isFinite ? startTime.seconds : 0)
        resetMapping()
        sink.reset()   // a restarted session must not inherit the old replay high-water
        driftSamples.removeAll()   // nor the old session's drift envelope
        slopeSamples.removeAll()
        // F-3: a session that began with a SEEK can be carrying the injected
        // pre-target burst the drift bound exists for and may correct from its
        // first window; a session from ZERO cannot, so it must first prove the
        // envelope is a valid instrument for THIS file (see driftCheck).
        sessionBeganSeeked = contentOffset > 5
        envelopeValidated = false
        envelopeWithheldLogged = false
        scoutProgress.removeAll()
        surrendered = false        // a fresh playback earns a fresh chance
        troubleEpisodes = 0
        lastEpisodeAt = nil

        // ARMED, NOT IGNITED. The scout is a second stream of the same film,
        // and starting it at launch made it compete with playback's own
        // startup — measured on a ~10 Mbps morning: probe + moov + scout
        // probe collided, the first item load TIMED OUT (-1001), and every
        // uncaptioned title on the build read as "unable to play" while
        // captioned titles (no scout) were fine. The engine now arms here
        // and throttle() ignites it only once playback has proven the link
        // can afford a passenger: 60s banked, or 30s of healthy play.
        pendingIgnition = (url, contentOffset)
        armedAt = Date()
        return
    }

    private var pendingIgnition: (url: URL, from: Double)?
    private var armedAt: Date?

    /// Actually start the scout. Called by `throttle()` when playback can
    /// afford it — never directly at play-start.
    private func ignite(url: URL) async {
        pendingIgnition = nil
        guard let tap = sink.makeTap() else {
            failure = "Couldn't attach to the audio."
            isRunning = false
            return
        }
        self.tap = tap

        // THE SAME PATH PLAYBACK USES. A bare `AVURLAsset` has none of the
        // resilience the player has had since Decisions 021/031/034 — no
        // resume-on-reset, no storage-node failover, no retry — so a transient
        // archive.org condition that playback rides straight through kills
        // captions outright, and silently: `loadTracks` fails and the engine
        // reports "this title has no audio to transcribe" about a film that
        // plainly has audio and is playing at that moment.
        //
        // Measured: The Night Stalker fails that way in 3 seconds under load
        // while the identical URL loads audio + video fine when asked alone.
        // The owner's report — correct subtitles never appearing on a film with
        // a mistimed file — is that failure, because no transcript means no
        // verdict and the published file plays uncorrected.
        // subordinate: the scout's bytes caption the film; the VIEWER'S bytes
        // play it. On a link that cannot carry both, the OS now starves the
        // scout at the socket level (.background service type) instead of the
        // playback — the stutter the owner watched was this contest going the
        // wrong way.
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url, subordinate: true)
        streamLoader = loader          // the resource-loader delegate is weak
        let item = AVPlayerItem(asset: asset)
        // Ask for the CHEAP time-stretch explicitly. Under the platform default
        // an Apple TV playing at 2x raced its POSITION clock at 2x while the
        // tap received audio at ~1x — half the film's audio was never delivered
        // (the scout would have hit "film end" halfway through), the lookahead
        // never grew past ~30s, and what audio did arrive was mangled enough to
        // garble the transcript. `.timeDomain` is pitch-preserving, rated for
        // 2x, and light enough for the A15.
        // Dev bisect knob (AW_SCOUT_EXP): notap / rate1 / nopitch / volume0 —
        // one scout property per run, judged by the AWAUD meter's continuity.
        let exp = ProcessInfo.processInfo.environment["AW_SCOUT_EXP"] ?? ""
        // D069's explicit pin stands. (An audio-race bisect briefly implicated
        // this and removed it per-platform — then the self-identifying print
        // showed TimeDomain is the tvOS 27 platform DEFAULT, so the "nopitch"
        // arm had never changed anything and the race was elsewhere: the
        // scout's presence in the audio OUTPUT graph, Decision 071.)
        if exp != "nopitch" { item.audioTimePitchAlgorithm = .timeDomain }
        // Self-identifying, because one verification run measured the OLD
        // binary after an unchecked install and nearly overturned a correct
        // bisect result.
        awdiag("[AWCAP] scout pitch algorithm: \(item.audioTimePitchAlgorithm.rawValue)")
        // A small preload budget. A fresh item buffers toward its preference
        // even at rate 0, and on a badly-muxed file that startup fetch is a
        // storm of large random reads — the collision that stalled playback
        // after every restart on TtCRB-4K. Ten seconds keeps a RUNNING scout
        // fed (the tap consumes as delivered) without letting a paused one
        // compete with the viewer's stream.
        item.preferredForwardBufferDuration = 10
        let scout = AVPlayer(playerItem: item)
        #if os(tvOS)
        // Decision 071: the scout is MUTED on tvOS, not volume-0. A volume-0
        // scout stays in the audio OUTPUT graph, and its start/resume can race
        // the main player's render — measured with an RMS meter on the main
        // item: video advancing, buffer full, audio dead for the scout's whole
        // active life in ~half of the runs ("the audio gets swallowed by the
        // captioning process"). Under isMuted the tap still fires on tvOS 27
        // (23 correctly-mapped cues, measured) — D058's "muting can remove
        // audio from the render pipeline" does not hold here — and a muted
        // player cannot contend for the output. AW_SCOUT_EXP=volume0 restores
        // the old behavior for comparison runs.
        if exp == "volume0" { scout.volume = 0 } else { scout.isMuted = true }
        #else
        // volume 0, but NOT isMuted: muting can take the audio out of the render
        // pipeline altogether, and then the processing tap never fires (D058 —
        // measured on the platforms this branch covers; tvOS proved different).
        if exp == "muted" { scout.isMuted = true } else { scout.volume = 0 }
        #endif
        scoutPlayer = scout

        Task { @MainActor [weak self] in
            guard let self else { return }
            let track: AVAssetTrack?
            do {
                // Distinguish "this film has no audio track" (a fact about
                // the film) from "the load failed/timed out" (a fact about
                // the moment). The owner watched "no audio to transcribe"
                // on films that were audibly playing — the load had timed
                // out on a starved link, and the engine blamed the film.
                track = try await asset.loadTracks(withMediaType: .audio).first
                if track == nil {
                    self.failure = "This title has no audio to transcribe."
                }
            } catch {
                awdiag("[AWCAP] scout track load failed (transient): %@",
                       error.localizedDescription)
                track = nil
            }
            guard let track else {
                self.isRunning = false
                self.silenceScout()
                return
            }
            if exp != "notap" {
                let params = AVMutableAudioMixInputParameters(track: track)
                params.audioTapProcessor = tap
                let mix = AVMutableAudioMix()
                mix.inputParameters = [params]
                item.audioMix = mix
            }
            // Exact, because on a badly-muxed file a tolerant seek is what let
            // the tap receive a burst of pre-target audio from the start of a
            // huge interleaved audio chunk (see driftCheck). Zero tolerance
            // narrows the burst; the drift bound below catches whatever remains.
            await scout.seek(to: CMTime(seconds: self.contentOffset, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero)
            scout.rate = exp == "rate1" ? 1.0 : Self.scoutRate
            awdiag("[AWCAP] scout playing at \(scout.rate)x from \(self.contentOffset)s"
                  + (exp.isEmpty ? "" : " [exp=\(exp)]"))
        }

        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            task = Task { [weak self] in await self?.consume() }
        }
        #endif
    }

    /// Keep the scout a comfortable distance ahead — far enough that cues are
    /// always ready, close enough that we are not downloading the whole film.
    ///
    /// `playbackHealthy` is the MAIN player's buffer state, and it outranks the
    /// lead entirely: the scout is a second stream of the same film, and on a
    /// constrained link it can starve the playback it exists to caption — the
    /// owner watched His Girl Friday stutter while its captions generated. The
    /// captioned-HLS path is the most exposed (its segment is
    /// AVFoundation-owned, Decision 054 — no resilience to starve into), so
    /// when the viewer's stream struggles the scout STOPS, and it stays
    /// stopped until playback has been healthy for a while. Captions can run
    /// up to two minutes ahead; playback cannot run behind at all.
    func throttle(playhead: CMTime, playbackHealthy: Bool = true,
                  mainBufferSeconds: Double? = nil) {
        if playhead.seconds.isFinite { lastPlayhead = playhead.seconds }
        if let pending = pendingIgnition {
            guard playbackHealthy else { armedAt = Date(); return }
            let banked = mainBufferSeconds ?? 0
            let healthyFor = armedAt.map { Date().timeIntervalSince($0) } ?? 0
            if banked >= 60 || healthyFor >= 30 {
                pendingIgnition = nil          // synchronously — one ignition
                let url = pending.url
                Task { await self.ignite(url: url) }
            }
            return
        }
        guard let scout = scoutPlayer else { return }
        if !playbackHealthy {
            lastUnhealthyAt = Date()
            lastTroubleAt = Date()
            if scout.rate != 0 {
                scout.rate = 0
                if trace { awdiag("[AWCAP] trace scout YIELDS — playback buffer struggling") }
            }
            // Two minutes yielded with nothing produced: playback on this
            // title cannot spare a second stream, and "Preparing automatic
            // captions…" would otherwise stand for the whole film. Say the
            // true thing once (the notice shows briefly and clears); the
            // engine keeps waiting and springs to life if the stream eases.
            if !everProducedCue, failure == nil, let s = startedAt,
               Date().timeIntervalSince(s) > 120 {
                failure = "Captions are waiting for smoother playback."
            }
            scoutProgress.removeAll()
            troubleEpisodes += (lastEpisodeAt.map { Date().timeIntervalSince($0) > 30 } ?? true) ? 1 : 0
            lastEpisodeAt = Date()
            if troubleEpisodes >= 3 {
                surrender("playback trouble episode #\(troubleEpisodes)")
            }
            return
        }
        // DEPTH gate, when the caller can measure it: the viewer's buffer
        // outranks captions. ONE threshold with a cooldown — the first version
        // was a 60/120 band, and a film whose steady-state buffer sits BETWEEN
        // the two (Till the Clouds Roll By idles at 63-103s on its node)
        // locked the scout out permanently: it yielded once at a dip and could
        // never legally resume. The owner watched "Preparing automatic
        // captions" for minutes; the soak had been declared green from a few
        // DISPLAYED leftover cues while the engine was already locked out —
        // liveness, not display, is what a soak must assert.
        // The depth thresholds only bind while playback has RECENTLY been in
        // trouble. A badly-muxed 4K file (Till the Clouds Roll By) sustains
        // only a 2-15s buffer for whole sections — its random-read pattern is
        // the ceiling, not bandwidth — while playing at rate 1.0 with zero
        // stalls. An unconditional depth gate locked the scout out of exactly
        // those sections forever: "Preparing automatic captions…" stood for
        // minutes over a film that was playing perfectly, and the scout fell
        // behind into resync churn (each resync a fresh seek-burst). Gate on
        // OBSERVED harm: after a real unhealthy event the depth floor rules
        // for 30s; stall-free playback licenses the scout at any depth.
        if let depth = mainBufferSeconds {
            let sinceUnhealthy = lastTroubleAt.map { Date().timeIntervalSince($0) }
                ?? .infinity
            if sinceUnhealthy < 30 {
                if depth < 45, scout.rate != 0 {
                    scout.rate = 0
                    lastDepthYieldAt = Date()
                    if trace { awdiag("[AWCAP] trace scout YIELDS — main buffer \(Int(depth))s < 45s after trouble") }
                    return
                }
                if scout.rate == 0, depth < 60 {
                    return                  // not enough banked to share yet
                }
            }
            if scout.rate == 0, let y = lastDepthYieldAt,
               Date().timeIntervalSince(y) < 10 {
                return                      // brief cooldown so a dip can't flap
            }
        }
        if let u = lastUnhealthyAt {
            guard Date().timeIntervalSince(u) >= Self.healthCooldown else { return }
            lastUnhealthyAt = nil
            if trace { awdiag("[AWCAP] trace playback healthy again — scout may resume") }
        }
        if scout.rate != 0 {
            driftCheck(scout)
            // CAN THE PATH AFFORD A SECOND STREAM AT ALL? A scout that cannot
            // sustain ~2x is in a race it mathematically loses — it runs
            // behind the viewer forever, burning half the request budget of a
            // constrained path until playback starves (TtCRB-4K on a degraded
            // node: chunks at 9-11 Mbps, scout 30-45s behind and falling for
            // minutes before playback finally stalled). Its own progress rate
            // is the preemptive signal: measure it over a window and give the
            // whole stream back to the viewer before any harm shows.
            let pos = scout.currentTime().seconds
            if pos.isFinite {
                let now = Date().timeIntervalSince1970
                scoutProgress.append((wall: now, pos: pos))
                scoutProgress.removeAll { now - $0.wall > 35 }
                if let first = scoutProgress.first, now - first.wall >= 25,
                   (pos - first.pos) / (now - first.wall) < 1.4 {
                    surrender(String(format: "scout sustains only %.1fx",
                                     (pos - first.pos) / (now - first.wall)))
                    return
                }
            }
        } else {
            scoutProgress.removeAll()   // a paused scout's stillness is not evidence
        }
        let lead = leadSeconds(over: playhead)
        if lead > Self.maxLead, scout.rate != 0 {
            scout.rate = 0
            if trace {
                awdiag("[AWCAP] trace scout PAUSED at \(fmt(scout.currentTime().seconds)) "
                      + "(lead \(Int(lead))s)")
            }
        } else if lead < Self.minLead, scout.rate == 0 {
            // Never resume a scout that is far BEHIND the viewer — 2x never
            // catches 1x from minutes back, so it would transcribe film
            // already watched while burning the bandwidth playback needs
            // (observed: a scout resumed at 0.0 against a playhead of 3746).
            // needsResync retargets it with a seek instead.
            let scoutAt = scout.currentTime().seconds
            if scoutAt.isFinite, playhead.seconds - scoutAt > 45 { return }
            scout.rate = Self.scoutRate
            if trace {
                awdiag("[AWCAP] trace scout RESUMED at \(fmt(scout.currentTime().seconds)) "
                      + "(lead \(Int(lead))s)")
            }
        }
    }

    /// How long playback must be continuously healthy before the scout resumes.
    private static let healthCooldown: TimeInterval = 5
    private var lastUnhealthyAt: Date?
    /// Rolling (wall, position) samples of a RUNNING scout, for the
    /// sustain-rate check above.
    private var scoutProgress: [(wall: Double, pos: Double)] = []
    private var troubleEpisodes = 0
    private var lastEpisodeAt: Date?
    private(set) var surrendered = false

    /// Give the viewer the whole stream back, for the rest of this playback.
    ///
    /// Not a yield: the item is DETACHED (a paused item still buffers toward
    /// its preference), the analyzer stops, and nothing restarts it. Cues
    /// already produced keep displaying. The engine reports itself stopped,
    /// so the coordinator's resync path and the review loop both wind down.
    private func surrender(_ reason: String) {
        guard !surrendered else { return }
        surrendered = true
        awdiag("[AWCAP] scout SURRENDERS — %@", reason)
        if !everProducedCue, failure == nil {
            failure = "Captions are paused so playback stays smooth."
        }
        task?.cancel(); task = nil
        sink.finish()
        silenceScout()
        isRunning = false
    }
    /// Like `lastUnhealthyAt` but never cleared — the depth gate's 30s
    /// trouble window must outlive the 5s resume cooldown that nils it.
    private var lastTroubleAt: Date?
    private var lastDepthYieldAt: Date?

    /// Times the mapping was re-anchored against the scout's own position.
    /// The judge reads this: a session whose ruler needed correcting must
    /// never condemn or shift a published file on that evidence.
    private(set) var driftCorrections = 0
    private var driftSamples: [(wall: Double, err: Double)] = []
    /// (delivered-audio seconds, mapping error) pairs for the slope fit.
    private var slopeSamples: [(delivered: Double, err: Double)] = []
    private var sessionBeganSeeked = false
    private var envelopeValidated = false
    private var envelopeWithheldLogged = false

    /// DRIFT BOUND. The mapping `film = offset + raw × rate` trusts the tap
    /// to deliver exactly rate-compressed audio from the session's start
    /// point. A SEEKED session start on a badly-muxed file breaks that trust:
    /// the tap receives a burst of pre-target audio from the start of the
    /// file's huge interleaved audio chunk — measured on His Girl Friday's
    /// resume, +39s of raw clock the scout never played — and every cue
    /// thereafter maps ~39s late. The engine's captions trailed the dialogue
    /// by 40s, and the judge, reading the same broken ruler, condemned the
    /// CORRECT published file at 7% agreement (scenario run atvrun-hgf5).
    ///
    /// Judge by the LOWER ENVELOPE over a window, never the instantaneous
    /// error: the tap delivers in decode-ahead BURSTS, so the instantaneous
    /// error legitimately swings by double digits and an instant-threshold
    /// corrector FLAPPED — fifteen corrections in one run, overcorrecting at
    /// each burst top and then "correcting" back, leaving the ruler piecewise
    /// wrong in both directions (scenario run atvrun-hgf6). The minimum over
    /// 25s is where render has caught decode; healthy it touches ~0. Only a
    /// persistent POSITIVE floor is the injection — a negative error means
    /// the tap has stalled while the clock runs, which no offset can fix.
    private func driftCheck(_ scout: AVPlayer) {
        let delivered = sink.deliveredSeconds()
        guard delivered > 8 else { return }
        let pos = scout.currentTime().seconds
        guard pos.isFinite, pos > 0 else { return }
        let err = filmTime(delivered) - pos
        let now = Date().timeIntervalSince1970
        driftSamples.append((wall: now, err: err))
        driftSamples.removeAll { now - $0.wall > 30 }
        slopeSamples.append((delivered: delivered, err: err))
        if slopeSamples.count > 12 { slopeSamples.removeFirst(slopeSamples.count - 12) }
        if trace {
            awdiag("[AWCAP] drift sample: err \(fmt(err)) delivered \(fmt(delivered)) n \(slopeSamples.count)")
        }
        // SLOPE loop: err growing ~linearly per delivered-audio second means
        // the assumed rate is wrong, and no level correction can outrun it.
        // Least-squares over the window; both terms sampled at the same
        // moments, so the decode-ahead gap cancels out of the slope.
        if slopeSamples.count >= 3,
           let d0 = slopeSamples.first?.delivered,
           let d1 = slopeSamples.last?.delivered, d1 - d0 >= 25 {
            let n = Double(slopeSamples.count)
            let mx = slopeSamples.map(\.delivered).reduce(0, +) / n
            let my = slopeSamples.map(\.err).reduce(0, +) / n
            var sxy = 0.0, sxx = 0.0
            for s in slopeSamples {
                sxy += (s.delivered - mx) * (s.err - my)
                sxx += (s.delivered - mx) * (s.delivered - mx)
            }
            let slope = sxx > 0 ? sxy / sxx : 0
            // Mean absolute residual gates NOISE: on a healthy file the
            // offline harness caught a spurious re-anchor (one 0.4s dwell on
            // the glass) from a fit over decode-ahead jitter. A genuine
            // sustained shortfall (Ghost Train: ~0.3/s) fits tightly; jitter
            // does not. Down-only — a recovering scout just stops adding
            // error, and the level corrections drain the rest.
            var mar = 0.0
            for s in slopeSamples {
                mar += abs((s.err - my) - slope * (s.delivered - mx))
            }
            mar /= n
            if trace {
                awdiag("[AWCAP] slope fit: \(String(format: "%+.3f", slope))/s "
                      + "mar \(fmt(mar)) n \(slopeSamples.count) span \(fmt(d1 - d0))s")
            }
            if slope > 0.12, mar < 2.0 {
                let newRate = min(Double(Self.scoutRate), max(1.0, mappingRate - slope))
                mappingAnchorFilm = filmTime(delivered)
                mappingAnchorRaw = delivered
                let old = mappingRate
                mappingRate = newRate
                slopeSamples.removeAll()
                awdiag("[AWCAP] mapping rate \(fmt(old))x -> \(fmt(newRate))x "
                      + "(err slope \(String(format: "%+.3f", slope))/s of audio; "
                      + "future cues re-anchored at raw \(fmt(delivered)))")
            }
        }
        // The envelope's premise — "healthy, the floor touches ~0" — holds only
        // when tap delivery tracks the scout's RENDER. On a file with huge
        // interleaved audio chunks the tap runs a permanent chunk-deep ahead,
        // the floor NEVER drains (w1-tim-engine: 20-39s from the very first
        // window, every 25s, all film long), and every "correction" dragged
        // CORRECT cues earlier — six totalling -23s of early shift, each one
        // swapping the line mid-read (F-3). Seeing the floor drain once is the
        // proof the envelope is a valid instrument for THIS file.
        if err < 5 { envelopeValidated = true }
        guard let oldest = driftSamples.first, now - oldest.wall >= 25,
              let floorErr = driftSamples.map(\.err).min(), floorErr > 15 else { return }
        guard envelopeValidated || sessionBeganSeeked else {
            if !envelopeWithheldLogged {
                envelopeWithheldLogged = true
                awdiag("[AWCAP] drift correction WITHHELD (floor \(fmt(floorErr))s but "
                      + "the envelope never drained this session — chunk-deep tap "
                      + "decode-ahead, not an injection; from-zero sessions cannot "
                      + "carry one)")
            }
            driftSamples.removeAll()
            return
        }
        var delta = -(floorErr - 8)   // stay conservatively LATE, never early
        // A correction may not rewind the CAPTIONS PAST THE VIEWER. Measured on
        // The Incredible Machine (a film with no subtitle file, the owner's
        // "undependable generated captions"): correction #3 re-anchored by
        // -12.4s, and the very next cue — LATER audio, raw 192.0 against the
        // previous 190.8 — mapped to film 339.5 where its predecessor had
        // mapped to 349.5. Ten seconds backwards, so fragments displayed out
        // of order and a third of the ticks went blank while the schedule
        // re-crossed ground the playhead had left.
        //
        // The mapping being 20s ahead is real and worth fixing; dragging cues
        // behind the playhead to fix it is not. Clamp so the earliest
        // not-yet-shown cue still lands at or after where the viewer is.
        let floor = lastPlayhead
        if let nextUnshown = cues.first(where: { $0.start > floor })?.start {
            let floorDelta = floor - nextUnshown               // <= 0
            if delta < floorDelta {
                awdiag("[AWCAP] drift correction clamped \(fmt(delta))s -> "
                      + "\(fmt(floorDelta))s (would have rewound past the viewer at "
                      + "\(fmt(floor)))")
                delta = floorDelta
            }
        }
        guard delta < -0.05 else { driftSamples.removeAll(); return }
        contentOffset += delta
        mappingAnchorFilm += delta
        // The correction is a STEP in the err series and a least-squares
        // slope over a sawtooth reads ~flat — but CLEARING the window starved
        // it to 1-2 samples between corrections (driftCheck's cadence is
        // slower than assumed; w8-timing-ghosttrain7 never printed a single
        // fit). Shift the retained samples by the correction instead: the
        // series stays continuous AND populated.
        for i in slopeSamples.indices { slopeSamples[i].err += delta }
        for i in cues.indices { cues[i].start += delta; cues[i].end += delta }
        for i in rawCues.indices { rawCues[i].start += delta; rawCues[i].end += delta }
        driftCorrections += 1
        driftSamples.removeAll()
        awdiag("[AWCAP] drift correction #\(driftCorrections): mapping floor ran "
              + "\(fmt(floorErr))s ahead of the scout at \(fmt(pos)) — re-anchored by \(fmt(delta))s")
    }

    /// Is this session HOPELESS for where the viewer actually is?
    ///
    /// Two ways it happens, both observed live on His Girl Friday:
    /// - A backward seek/restart puts the playhead BEFORE the session began
    ///   (resumed at 560, playback restarted at 0 — nothing to show for nine
    ///   minutes).
    /// - The scout falls BEHIND the viewer (its stream stalled around film
    ///   time 330 while playback sailed on; the engine then ground at 2x
    ///   through 700s of already-watched film — never catching up, burning
    ///   the very bandwidth playback needed, which WAS the stutter).
    ///
    /// The reference is the SCOUT'S OWN POSITION, not the last cue: during a
    /// silent or musical passage the scout advances without producing cues,
    /// and that must not read as "behind". The caller restarts the engine
    /// from the playhead when this holds STEADILY (a rebuild passes through
    /// t=0 for a moment; one glimpse must not trigger a resync).
    func needsResync(at playhead: CMTime) -> Bool {
        let t = playhead.seconds
        guard isRunning, t.isFinite, t >= 0 else { return false }
        if pendingIgnition != nil { return false }   // armed, not yet running
        if t < contentOffset - 30 { return true }              // seeked behind the session
        let scoutAt = scoutPlayer?.currentTime().seconds
        let reached = max(cues.last?.end ?? contentOffset,
                          (scoutAt?.isFinite == true ? scoutAt! : contentOffset))
        // The viewer is 45s past everything the scout has even REACHED: it can
        // close a gap it is ahead of, never one it is behind.
        guard t > reached + 45 else { return false }
        // Far behind — but while the throttle holds the scout down for
        // playback health, a resync buys nothing: the fresh session would be
        // paused the same way. Measured on TtCRB-4K: restart churn every
        // ~48s, with playback stalls clustered 10-32s after each rebuild.
        // Once trouble has been quiet for 30s a resync is worth it (and
        // cheap — `resync(to:)` seeks the existing scout, no new asset).
        if scoutPlayer?.rate == 0, let trouble = lastTroubleAt,
           Date().timeIntervalSince(trouble) < 30 { return false }
        return true
    }

    /// Move the LIVE session to a new position: seek the existing scout and
    /// restart the analyzer from there. This replaces the stop()+start()
    /// resync, whose fresh player item cost a moov + preload fetch storm
    /// through the badly-muxed file — the collision behind every stall in
    /// scenario runs ttcrb2/ttcrb3. One asset per playback, however many
    /// resyncs. Returns false when there is no live scout to move (caller
    /// falls back to a full start).
    func resync(to playhead: CMTime) async -> Bool {
        guard let scout = scoutPlayer, playhead.seconds.isFinite,
              playhead.seconds >= 0 else { return false }
        task?.cancel(); task = nil
        sink.finish()
        sink.reset()
        driftSamples.removeAll()
        contentOffset = max(0, playhead.seconds)
        resetMapping()
        // Drop cues at or beyond the new anchor. A resync re-bases the mapping
        // on the playhead and restarts the transcriber, so everything from here
        // is about to be produced again — and leaving the old ones in place
        // makes the array UNSORTED, since fresh cues map earlier than stale
        // ones still sitting further down the list. The display picks the first
        // cue bracketing the playhead, so an unsorted list is how a line
        // already read gets followed by an earlier one. That is the residual
        // reordering the shown-cue gate measured after Decision 081's clamp:
        // small (~2s), intermittent, and NOT the clamp's doing.
        let dropped = cues.filter { $0.end > contentOffset }.count
        cues.removeAll { $0.end > contentOffset }
        rawCues.removeAll { $0.end > contentOffset }
        if dropped > 0 {
            awdiag("[AWCAP] resync dropped \(dropped) cue(s) at/after \(fmt(contentOffset))s "
                  + "— they will be re-transcribed from the new anchor")
        }
        scout.pause()
        await scout.seek(to: CMTime(seconds: contentOffset, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero)
        scout.rate = Self.scoutRate
        // A resynced session is definitionally seek-started: The Ghost Train
        // (w8-timing-ghosttrain2) resumed at 345s via THIS path after starting
        // near zero, and the envelope gate then withheld a sorely-needed 17.4s
        // drift correction as "from-zero".
        sessionBeganSeeked = true
        slopeSamples.removeAll()                // new anchor, re-measure
        awdiag("[AWCAP] scout resynced by seek to \(fmt(contentOffset))s")
        #if canImport(Speech)
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            task = Task { [weak self] in await self?.consume() }
        }
        #endif
        return true
    }

    private let trace = ProcessInfo.processInfo.environment["AW_CAPTION_TRACE"] == "1"
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Split a finalized span into caption-sized lines, filed by time.
    ///
    /// A Result can cover a long stretch; a caption should be one or two short
    /// lines (~32 characters is the broadcast convention). Long spans are divided
    /// proportionally so each piece still lands when it is spoken.
    private func appendCue(start: Double, end: Double, text: String) {
        let chunks = Self.wrap(text, limit: Self.maxCharsPerLine * Self.visibleLines)
        guard !chunks.isEmpty else { return }
        everProducedCue = true
        let span = max(end - start, 0.4)

        // KEEP THE RECOGNIZER'S OWN TIMES. Everything below re-times these cues
        // for DISPLAY — floored at reading time, pushed apart so none overlaps —
        // which is right for a viewer and wrong for a measurement. The pacing
        // only ever moves a cue LATER, so judging a subtitle file against the
        // paced transcript makes the file look early and under-corrects it. That
        // is the residual the owner felt after The Night Stalker was corrected:
        // still ~1s behind, because the correction was measured against a
        // transcript that had itself been nudged forward.
        rawCues.append((start: start, end: end, text: text))
        if rawCues.count > 2000 { rawCues.removeFirst(rawCues.count - 2000) }

        // Divide the span by CHARACTER COUNT, not evenly by chunk.
        //
        // Splitting evenly gave a short trailing sentence the same time as a long
        // leading one, so the second caption appeared while the first was still
        // being spoken — the reader is then racing the audio. Characters are a
        // decent proxy for how long a line takes to say.
        let total = max(chunks.reduce(0) { $0 + $1.count }, 1)
        var cursor = start
        for chunk in chunks {
            let share = span * Double(chunk.count) / Double(total)
            // Floor each caption at the time it takes to READ, not a flat
            // minimum. A recognizer span can be much shorter than its text is to
            // read — one 13-word line was on screen for 1.7s — and a caption you
            // cannot finish is the same as no caption.
            let end0 = cursor + max(share, Self.readingTime(chunk))
            // TESTED AND REJECTED: clamping a cue's start to the playhead
            // (dropping ones whose moment had passed) to stop late-finalized
            // results from landing behind a line already shown. It measured the
            // WORST result yet — 3 backwards steps at -9.9s against -2.2s
            // without it — most likely because `lastPlayhead` is written by the
            // display timer and reading it here couples the append path to that
            // race. The mechanism is still the best explanation for the
            // residual; the fix has to be one that does not read display state
            // from the analyzer thread.
            cues.append((start: cursor, end: end0, text: chunk))
            cursor = end0
        }
        cues.sort { $0.start < $1.start }

        // A caption must never be replaced before its own words are finished, so
        // no cue may begin before the previous one ends. Where the recognizer's
        // spans overlap, the later cue is pushed back rather than cutting the
        // earlier one short.
        for i in 1..<max(cues.count, 1) where cues[i].start < cues[i - 1].end {
            // NEVER RE-TIME A CAPTION THAT IS ALREADY ON SCREEN. The recognizer
            // can finalize a result whose span starts before one already being
            // displayed; pushing cues apart then moved the visible caption out
            // from under the playhead, and `line(at:)` switched to a different
            // one mid-read. Measured: a 13-word line shown for 0.2 seconds —
            // paced correctly on paper, unreadable in fact.
            guard cues[i].start > lastPlayhead else { continue }
            let shift = cues[i - 1].end - cues[i].start
            cues[i].start += shift
            cues[i].end += shift
        }

        // Merge rapid-fire fragments — the corpus pace_vtt fix applied live.
        // A run of short utterances each at its 1.0s reading floor is legal
        // under every rule above and still reads as a BURST from the sofa
        // (Suspense "On a Country Road": 3 windows of 3+ lines in 3s, every
        // line individually readable). The scout works ahead of playback, so
        // pending cues can coalesce before they are ever drawn. Only cues not
        // yet on screen are touched, same guard as the push-apart loop.
        var i = 0
        while i < cues.count - 1 {
            let c = cues[i], n = cues[i + 1]
            let joined = c.text + " " + n.text
            if c.start > lastPlayhead,
               n.start - c.start < Self.readingTime(c.text) + 0.2,
               n.start - c.end <= 0.75,
               joined.count <= Self.maxCharsPerLine * Self.visibleLines {
                cues[i] = (start: c.start, end: max(c.end, n.end), text: joined)
                cues.remove(at: i + 1)
            } else {
                i += 1
            }
        }
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
        pendingIgnition = nil
        armedAt = nil
        task?.cancel(); task = nil
        sink.finish()
        silenceScout()
        tap = nil
        isRunning = false
        cues.removeAll()
        pendingWords.removeAll()
        rawCues.removeAll()
        startedAt = nil
        everProducedCue = false
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
        // ASK THE FRAMEWORK WHICH LOCALE IT MEANS. A hand-written
        // `Locale(identifier: "en-US")` is not guaranteed to be the same object
        // the transcriber allocates against — Apple's own guidance is to resolve
        // it through `supportedLocale(equivalentTo:)` — and a near-miss fails as
        // "not subscribed to transcription.en" or "unallocated locales", i.e. it
        // looks exactly like a missing model. A device that has never installed
        // one (an Apple TV; nothing else on tvOS asks) has no second chance to
        // paper over the mismatch, which is why this bit first there.
        guard let locale = await AutoCaptions.resolvedLocale() else {
            awdiag("[AWCAP] no supported transcription locale on this device")
            await MainActor.run {
                self.failure = "Automatic captions aren't available on this device."
            }
            return
        }
        awdiag("[AWCAP] locale \(locale.identifier(.bcp47))")
        let transcriber = SpeechTranscriber(locale: locale,
                                            preset: .timeIndexedProgressiveTranscription)
        do {
            // Reserve the locale + install the model. Without the reservation
            // the analyzer reports "not subscribed to transcription.en" and no
            // format is ever available (see AutoCaptions.prepareModel).
            try await AutoCaptions.prepareModel(
                for: transcriber,
                locale: locale,
                onProgress: { [weak self] fraction in self?.modelProgress = fraction })
            await MainActor.run { self.modelProgress = nil }
            guard let want = await SpeechAnalyzer
                .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                awdiag("[AWCAP] NO speech model available — cannot transcribe")
                await MainActor.run { self.failure = "No speech model is available." }
                return
            }
            awdiag("[AWCAP] analyzer format \(want.sampleRate)Hz ch=\(want.channelCount)")
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
                // SCALE BY THE SCOUT RATE — the one mapping verified against
                // ground truth on BOTH platforms. The analyzer clocks by
                // samples consumed, and at 2x the audio is time-compressed, so
                // film time = offset + analyzer × 2 ("From cave wall to
                // billboard" at raw 6.7 → 13.4 in-clip on the Apple TV AND on
                // macOS; "Temple of the Soul" at raw 151.6 → 1108.0, matching
                // the film exactly).
                //
                // DO NOT "improve" this by anchoring to the tap's presentation
                // timestamps. That was tried: on macOS those stamps are FILM
                // time (anchors agree with ×2), but on tvOS they are the
                // COMPRESSED timeline — identical to the analyzer's own clock —
                // so anchoring silently halved every cue there and captions ran
                // minutes early. The two platforms stamp the same callback in
                // different timelines; the rate formula is the only mapping
                // that holds on both, because it never reads those stamps.
                // TRIED AND REVERTED (w8-timing-ghosttrain3): mapping with a
                // rate measured from (scoutPos - offset)/rawAudio. The two
                // clocks — tap delivery and render position — are separated
                // by a decode-ahead gap that VARIES, so the estimate
                // oscillated and the median swung from +58s late to -38s
                // early in one run. The D069 trap in a new coat. The nominal
                // formula stays (ground-truth exact on healthy files); a
                // sustained rate shortfall is the DRIFT CORRECTION's job,
                // which the envelope gate had wrongly withheld on resumed
                // sessions — that is the fix that stands.
                let s0 = filmTime(result.range.start.seconds)
                let e0 = filmTime(result.range.end.seconds)
                guard s0.isFinite, e0.isFinite, e0 > s0 else { continue }
                await MainActor.run {
                    if self.cues.count < 3 {
                        awdiag("[AWCAP] cue \(String(format: "%.1f", s0))-\(String(format: "%.1f", e0))s: \(text.prefix(40))")
                    } else if self.trace {
                        // The full mapping, every cue: the analyzer's own range
                        // AND the film time it became, plus where the scout
                        // actually is — so a replay, a clock jump, or a bad
                        // scaling shows itself in one console read.
                        awdiag("[AWCAP] trace cue raw \(fmt(result.range.start.seconds))-"
                              + "\(fmt(result.range.end.seconds)) -> film \(fmt(s0))-\(fmt(e0)) "
                              + "(scout at \(fmt(self.scoutPlayer?.currentTime().seconds ?? -1))): "
                              + "\(text.prefix(34))")
                    }
                    self.appendCue(start: s0, end: e0, text: text)
                }
            }
        } catch {
            // The raw error stays in the log for a device console; the viewer
            // gets a sentence about their situation, not our API's — plus what
            // the device itself reports, because on an Apple TV that line is
            // the only way this ever gets diagnosed.
            awdiag("[AWCAP] FAILED: \(error)")
            let report = await AutoCaptions.availabilityReport(for: transcriber)
            awdiag("[AWCAP] \(report)")
            await MainActor.run {
                self.failure = Self.viewerMessage(for: error) + "  (\(report))"
                // Nothing will consume this audio now — stop paying for it.
                self.silenceScout()
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
    /// High-water mark of the tap's presentation clock, for the replay guard
    /// in `append` — see the comment there.
    private var highWater = -Double.infinity
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
        if Self.diag {
            awdiag("[AWCAP] tap prepared: \(d.mSampleRate)Hz ch=\(d.mChannelsPerFrame)")
        }
    }

    /// `AW_CAPTION_DIAG=1` reports whether decoded audio is actually reaching us.
    ///
    /// This is the layer that cannot be seen from a screenshot or inferred from a
    /// caption that never appears: if the tap never fires, no amount of work on
    /// the recognizer or the label matters.
    static let diag = ProcessInfo.processInfo.environment["AW_CAPTION_DIAG"] == "1"
    private var tapCalls = 0

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

    /// Seconds of converted audio handed to the analyzer so far — the
    /// analyzer's raw clock, readable from outside. `LiveCaptions.driftCheck`
    /// compares it against the scout's own position to catch a mapping that
    /// has come unmoored from the film.
    func deliveredSeconds() -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let dst = targetFormat, dst.sampleRate > 0 else { return 0 }
        return Double(elapsedFrames) / dst.sampleRate
    }

    /// Fresh-session state. WITHOUT this, a backward resync is silently dead:
    /// `highWater` carries the OLD session's film position, so every buffer of
    /// the new session (earlier in the film by definition) is dropped as a
    /// "replay" and the engine produces nothing at all — the exact shape of
    /// silent failure the replay guard was built to prevent, inverted.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        highWater = -Double.infinity
        anchored = false
        baseFrames = 0
        elapsedFrames = 0
        converter = nil
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

        if Self.diag {
            tapCalls += 1
            if tapCalls == 1 || tapCalls % 200 == 0 {
                awdiag("[AWCAP] tap callback #\(tapCalls) frames=\(frames) "
                      + "src=\(sourceFormat != nil) dst=\(targetFormat != nil) "
                      + "sink=\(continuation != nil)")
            }
        }

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
        // REPLAY GUARD. Under the platform-default time-pitch algorithm, an
        // Apple TV re-delivered already-tapped audio around the throttle's
        // rate transitions — the analyzer then transcribed the same minute of
        // narration three times over, each copy stamped later than the last,
        // and the viewer read the film's dialogue in triplicate. The tap's
        // presentation clock only ever moves forward in legitimate playback
        // (the scout never seeks backward), so audio that arrives with an
        // older stamp is a re-delivery and must not reach the analyzer — nor
        // advance its clock, which would shift every later cue.
        if start.isValid, start.isNumeric {
            if start.seconds < highWater - 0.05 { return }
            highWater = max(highWater, start.seconds)
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
