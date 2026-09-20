// The Studio's live state, shared across whatever surface is on screen.
//
// WHY THIS EXISTS, and it is a macOS problem first (macOS-DESIGN §B13a):
// §B2a makes the player the WINDOW ROOT while playing, so the Detail view
// that offered "go live" is gone by the time there is an `AVPlayer` to attach
// to. tvOS presents its player as a cover from Detail and can hold the engine
// there; the Mac cannot. Rather than thread the engine through the router,
// one observable session owns it, Detail arms it, and the player surface
// hands it the player it just built.
//
// It is deliberately NOT a singleton-with-global-state for the whole feature:
// it holds one show, because a device produces one show at a time — the
// engine, the film it is for, and the health a readout draws. Everything
// about layouts, audio and publishing stays in `StudioEngine`.

import AVFoundation
import Foundation

@MainActor
@Observable
public final class StudioSession {
    public static let shared = StudioSession()

    /// The film the host asked to broadcast, set by Detail BEFORE the player
    /// exists. Non-nil means "arm the Studio when a player shows up".
    /// Where the armed show will be SENT, once a surface has resolved it
    /// (§9.lll). Nil means the engine composites and encodes and reports NOT
    /// SENDING, which is what every platform did before there was a surface
    /// that could ask.
    public private(set) var armedDestination: URL?
    public func armDestination(_ url: URL?) { armedDestination = url }

    public private(set) var armedFilmID: String?
    public private(set) var armedTitle: String = ""
    public private(set) var armedSubtitle: String = ""
    public private(set) var armedProvenance: String?

    public private(set) var isLive = false
    public private(set) var health = StudioHealth()
    /// Film frames in the last second — 0 while live is the frozen-picture
    /// signature, and the readouts say so (WATCH-TOGETHER §4).
    public private(set) var filmFramesPerSecond = 0
    /// Camera frames in the last second. 0 while live, with a camera that HAS
    /// delivered, is the tile-went-dark signature — measured on tvOS
    /// 2026-09-19, where a Continuity camera ran a clean 30/s for ten seconds
    /// and then stopped dead for eighty while every other number stayed
    /// healthy. macOS can use an iPhone as its camera too, and an iOS host's
    /// camera stops whenever a call arrives, so this is not a television's
    /// problem.
    public private(set) var cameraFramesPerSecond = 0
    /// Why the Studio refused, for the surface that asked.
    public var refusal: String?

    private var engine: StudioEngine?
    private var pump: Task<Void, Never>?
    /// Weak: the player belongs to the surface that built it, and a show must
    /// never be the reason a player outlives its window.
    private weak var localPlayer: AVPlayer?
    /// Retained for the show's lifetime — a capture session that is released
    /// stops delivering, and the tile simply goes black.
    private var capture: AVCaptureSession?

    private init() {}

    /// Detail's entry point. Applies the rights gate and either refuses with a
    /// sentence the host can act on, or arms the session.
    /// Returns true when the caller should start playing the film.
    func arm(film: Catalog.Item) -> Bool {
        if let why = StudioRights.refusal(rightsBucket: film.rightsBucket,
                                          contentType: film.contentType,
                                          year: film.year) {
            refusal = why
            return false
        }
        armedFilmID = film.archiveID
        armedTitle = film.title
        armedSubtitle = [film.year.map(String.init), film.director]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        armedProvenance = (film.rightsBucket == "safe_pd_age" && film.year != nil)
            ? "Public domain — published \(film.year!), before 1930" : nil
        return true
    }

    public func disarm() {
        armedFilmID = nil
    }

    /// Called by the player surface once it has an `AVPlayer` for the armed
    /// film. A no-op unless this is the film the host armed — a host who goes
    /// live on one title and then plays another has not armed the second.
    public func attachIfArmed(player: AVPlayer, archiveID: String) async {
        guard armedFilmID == archiveID, !isLive else { return }
        armedFilmID = nil
        localPlayer = player

        let e = StudioEngine(configuration: .benchDoored())
        engine = e
        await e.attachFilm(player: player)
        // SAY WHETHER THE FILM'S AUDIO ACTUALLY ATTACHED. A file played through
        // AW_PLAY_URL reaches the video output and its audio does not reach the
        // tap, and nothing on this path said so — picture and sound take
        // different routes here, and only one of them was reporting.
        let srcTracks = ((try? await player.currentItem?.asset
            .loadTracks(withMediaType: .audio)) ?? [])?.count ?? -1
        // WHEN the tap is installed, not just whether. A local file is playing
        // within milliseconds; a catalogue film is still loading for seconds.
        // If `item.audioMix` only takes effect before audio begins rendering,
        // that difference alone would explain why films carry audio through the
        // tap and an AW_PLAY_URL file does not — same code, different timing.
        awdiag("AWMACAUDIO filmHasAudio=%@ sourceAudioTracks=%d rate=%.2f at=%.2f url=%@",
               await e.filmHasAudio ? "true" : "false", srcTracks,
               player.rate, player.currentTime().seconds.isFinite
                   ? player.currentTime().seconds : -1,
               (player.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? "?")
        await e.setLayout(.corner)
        overlay = StudioOverlay()
        overlay.title = armedTitle
        overlay.subtitle = armedSubtitle
        overlay.provenance = armedProvenance ?? ""
        await e.setOverlay(overlay)

        await attachCameraIfAvailable(to: e)

        do {
            // No destination yet: the engine composites and encodes and sends
            // nowhere, which is what every platform does until a client id
            // exists (Decision 128). `showState` reports NOT SENDING rather
            // than pretending, so this is an honest production mode and not a
            // stub.
            //
            // AW_STUDIO_DEST is a DIAGNOSTIC door, not the product path: the
            // program is what gets ENCODED, and on macOS the window shows the
            // plain film, so no screenshot can ever prove the camera tile and
            // overlays are really in the broadcast. Publishing to a local
            // server and pulling a frame back is the only honest check.
            // A destination resolved by a go-live surface wins; the
            // environment door is the diagnostic fallback it always was.
            let dest = armedDestination
                ?? ProcessInfo.processInfo.environment["AW_STUDIO_DEST"]
                    .flatMap { URL(string: $0) }
            try await e.start(destination: dest)
        } catch {
            refusal = "The Studio could not start — \(error)"
            engine = nil
            return
        }
        // The channel is the SURFACE's to name; the reading and the overlay
        // belong to the engine (see `attachTwitchChat`).
        if let channel = ProcessInfo.processInfo.environment["AW_STUDIO_CHAT"], !channel.isEmpty {
            await e.attachTwitchChat(channel: channel)
            diag("[AWSTUDIOCHAT] reading #\(channel.replacingOccurrences(of: "#", with: ""))")
        }
        // HARNESS AUDIO STATE — applied HERE, where the engine is known to
        // exist. The first attempt set it from the launch door, one line after
        // `play()`, and the engine is built asynchronously: `engine?.setAudio`
        // was a no-op on nil, so the "control" that was supposed to prove a
        // muted program publishes silence proved nothing at all (§9.oo).
        let env = ProcessInfo.processInfo.environment
        // EITHER BENCH DOOR. The mute-unless-asked rule was keyed to
        // `AW_STUDIO_MAC` alone, so the new go-live door (§9.xxxx) would have
        // slipped past it and published whatever could be heard near the Mac —
        // which is the incident this guard was written for in the first place
        // (§9.oo, ~88 MB of recordings deleted). A guard that names one door by
        // hand stops guarding the moment a second door exists.
        if env["AW_STUDIO_MAC"] == "1" || !(env["AW_STUDIO_MAC_GOLIVE"] ?? "").isEmpty {
            // A BENCH RUN MUST NEVER CARRY THE OWNER'S ROOM. The mic tap is
            // attached whenever macOS has granted audio permission and
            // `micMuted` defaults to false, so an unattended harness broadcast
            // publishes whatever is being said near the Mac — to a local
            // server, and into a recording on disk. That is the same mistake
            // as a full-desktop screenshot: the instrument reaching past the
            // thing it was pointed at. AW_STUDIO_MIC=1 opts back in
            // deliberately, for a run that is actually testing the mic.
            if env["AW_STUDIO_MIC"] != "1" {
                await e.setAudio(micMuted: true)
            }
            // The host's own film mute (§B13c), scriptable so it can be a
            // real control rather than a line of code read aloud.
            if env["AW_STUDIO_MUTE_PROGRAM"] == "1" {
                await e.setAudio(filmMuted: true)
            }
        }
        isLive = true
        startPump()
        scheduleThermalInjectionIfAsked()
    }

    /// §6.5 on the PRODUCT path, DEBUG only.
    ///
    /// macOS has no equivalent of Android's `cmd thermalservice
    /// override-status`, so the engine's own seam is the only way to reach the
    /// rule on this platform — which is what the seam was written for. Without
    /// it, §6.5 on the Mac could only ever be argued from the code.
    ///
    ///   AW_STUDIO_THERMAL=serious|critical  AW_STUDIO_THERMAL_AT=<seconds>
    private func scheduleThermalInjectionIfAsked() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let want = env["AW_STUDIO_THERMAL"] else { return }
        // A SEQUENCE, comma-separated, because §6.5 has a return journey and a
        // single injection can only ever prove half of it:
        //   AW_STUDIO_THERMAL=serious,nominal  AW_STUDIO_THERMAL_AT=20,40
        let names = want.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let times = (env["AW_STUDIO_THERMAL_AT"] ?? "20")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        for (i, name) in names.enumerated() {
            let state: ProcessInfo.ThermalState? = switch name {
            case "serious": .serious
            case "critical": .critical
            case "fair": .fair
            case "nominal": .nominal
            default: nil
            }
            guard let state else { continue }
            let at = i < times.count ? times[i] : (times.last ?? 20) + Double(i) * 20
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(at))
                guard let engine = self?.engine else { return }
                self?.diag("[AWSTUDIOTHERMAL] injecting .\(name) at \(Int(at))s")
                await engine.overrideThermalState(state)
            }
        }
        #endif
    }

    /// The host's camera, when the platform has one and the viewer has
    /// already allowed it.
    ///
    /// REPORTED, NEVER REQUESTED. A permission prompt is a human action and
    /// the Studio must not raise one in the middle of going live — a host
    /// pressing "go live" is not a host answering a dialog. The camera tile is
    /// absent when it is absent, which §8.8 already treats as normal (a paired
    /// phone can be asleep or carried away mid-show).
    ///
    /// macOS needs `com.apple.security.device.camera` as well as TCC consent
    /// (macOS-DESIGN §B13e) — without the entitlement this silently finds
    /// nothing, which is indistinguishable from having no camera.
    /// Shared with iOS, which had NO camera or microphone on its Studio path
    /// at all until 2026-09-20 — `StudioPlayerContainer_iOS` never referenced
    /// either, so an iPhone broadcast the film and nothing else. Owner: *"There
    /// is no camera or microphone feed that goes to the live stream from the
    /// iphone. You have it working only with continuity camera on the Apple TV."*
    /// Same shape as Android's gap (§9.qqqqq): the engine supported it, the
    /// platform never wired it.
    static func attachHostCamera(to engine: StudioEngine) async -> AVCaptureSession? {
        await shared.attachCameraIfAvailable(to: engine)
        return await shared.capture
    }

    private func attachCameraIfAvailable(to engine: StudioEngine) async {
        #if os(macOS) || os(iOS)
        // SAY WHICH. The comment above notes that a missing entitlement "silently
        // finds nothing, which is indistinguishable from having no camera" — and
        // that is equally true of TCC consent not yet given, of consent denied,
        // and of a Mac with no camera at all. Four different states, one silent
        // `return`, and a bench run that reports the same nothing for all of
        // them. Each says its own name now.
        let vs = AVCaptureDevice.authorizationStatus(for: .video)
        let as_ = AVCaptureDevice.authorizationStatus(for: .audio)
        awdiag("AWCAM video=%@ audio=%@ device=%@",
               String(describing: vs), String(describing: as_),
               AVCaptureDevice.default(for: .video)?.localizedName ?? "none")
        guard vs == .authorized else {
            awdiag("AWCAM no camera tile: video authorization is %@ — the Studio REPORTS, never REQUESTS",
                   String(describing: vs))
            return
        }
        // THE FRONT CAMERA ON A PHONE. `AVCaptureDevice.default(for: .video)`
        // is the BACK camera on iOS, which points at the wall behind the
        // host — the one thing a watch-along tile must not show. macOS has
        // only one camera and is unaffected.
        #if os(iOS)
        let preferred = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
            .devices.first ?? AVCaptureDevice.default(for: .video)
        #else
        let preferred = AVCaptureDevice.default(for: .video)
        #endif
        guard let cam = preferred,
              let input = try? AVCaptureDeviceInput(device: cam) else {
            awdiag("AWCAM no camera tile: authorized but no usable capture device")
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        // 720p: the tile is never full-frame, so capturing 1080p to draw a
        // corner box is work nobody sees.
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        session.commitConfiguration()
        let camTap = CameraFrameTap()
        camTap.attach(to: session)
        await engine.attachCamera(tap: camTap)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            let micTap = MicAudioTap()
            micTap.attach(to: session)
            await engine.attachMicrophone(tap: micTap)
        }
        session.startRunning()
        awdiag("AWCAM attached camera=%@ mic=%@", cam.localizedName,
               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                   ? (AVCaptureDevice.default(for: .audio)?.localizedName ?? "yes") : "no")
        capture = session
        #endif
    }

    public func end() async {
        capture?.stopRunning()
        capture = nil
        pump?.cancel(); pump = nil
        if let engine { await engine.stop() }
        engine = nil
        isLive = false
        filmFramesPerSecond = 0
        cameraFramesPerSecond = 0
        health = StudioHealth()
    }

    /// One health sample a second — the rate the `notEncoding` and
    /// frozen-film guards are defined against (§9).
    /// Diagnostics go to STDERR, which is unbuffered.
    ///
    /// `print` writes to stdout, and stdout to a PIPE is fully buffered — so a
    /// run that is terminated before the buffer fills loses everything it
    /// said. That produced two runs of this harness reporting "zero health
    /// lines" from an app that was working perfectly (2026-09-17): the
    /// evidence existed and was killed with the process. An instrument that
    /// can lose its own output silently is worse than none.
    private func diag(_ line: String) {
        #if DEBUG
        FileHandle.standardError.write(Data((line + "\n").utf8))
        #endif
    }

    private func startPump() {
        pump?.cancel()
        pump = Task { [weak self] in
            var lastFilmFrames = 0
            var lastCameraFrames = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let engine = self.engine else { return }
                await engine.refreshHealth()
                let h = await engine.health
                self.filmFramesPerSecond = max(0, h.filmFramesPulled - lastFilmFrames)
                self.cameraFramesPerSecond = max(0, h.cameraFramesReceived - lastCameraFrames)
                lastCameraFrames = h.cameraFramesReceived
                lastFilmFrames = h.filmFramesPulled
                self.health = h


                // §6.5/§6.6 END the show on their own account — too hot, or a
                // link that could not be rebuilt inside the deadline — and
                // until now Apple read that reason NOWHERE. `endedReason` was
                // written by the engine and consumed by nothing, so a host
                // whose broadcast stopped saw only OFF. Measured on the Mac
                // product path, 2026-09-17 (§9.gg). Android already surfaced
                // it; this is the same move.
                if let why = h.endedReason, self.refusal == nil {
                    self.refusal = "The broadcast ended — \(why)."
                    #if DEBUG
                    // Printed as well as shown, so the fix is verifiable
                    // without capturing the owner's whole desktop.
                    self.diag("[AWSTUDIOENDED] \(self.refusal ?? "")")
                    #endif
                    await self.end()
                    return
                }

                // One machine-readable line a second, DEBUG only and only when
                // a diagnostic destination is set.
                //
                // This exists so a run's evidence can be READ rather than
                // photographed. A full-screen capture on the owner's own Mac
                // takes in whatever else they have open, which is the wrong
                // instrument for a broadcast test; and the numbers §6.4 turns
                // on — the send queue, video dropped, audio sent — are not on
                // the panel at all. Server-side evidence answers "did it
                // arrive"; this answers "what did the app decide".
                #if DEBUG
                if ProcessInfo.processInfo.environment["AW_STUDIO_DEST"] != nil {
                    let p = h.publisher
                    // Read through the non-optional local: optional-chaining
                    // into an actor is not an async access Swift 6 will take.
                    let hw = await engine.encoderIsHardware
                    // A/V SYNC ON THE PRODUCT PATH, with a real film and no
                    // stimulus: the tap reports the film time of the audio it
                    // handed over, the player reports the film time on screen,
                    // and `buffered` is the decoded audio still waiting in the
                    // ring — subtracted, because the ring is FIFO and that
                    // audio is encoded later rather than early (§9.tttt).
                    if let pos = await engine.filmAudioSourcePosition,
                       let now = self.localPlayer?.currentTime().seconds, now.isFinite {
                        let buf = await engine.filmAudioBuffered
                        self.diag(String(format:
                            "[AWMACSYNC] audioFilmPos=%.2f playhead=%.2f raw=%+.2f "
                            + "buffered=%.2f offset=%+.2f", pos, now, pos - now, buf,
                            pos - now - buf))
                    }
                    // IS THE FILM'S AUDIO ARRIVING AT ALL? macOS had no answer
                    // to that question. Measured 2026-09-19: the Mac publishes
                    // 43 audio packets a second — exactly the right rate — and
                    // they are SILENT (mean -87 to -39 dB, AAC at 2-8 kb/s,
                    // against tvOS's steady -22 dB and ~102 kb/s), and its
                    // broadcast correlates 0.000 with the source film. So the
                    // encoder is healthy and encoding nothing, which every
                    // number on the existing health line reports as fine.
                    //
                    // tvOS grew AWRING/AWMIX for exactly this; macOS is the
                    // platform where the film audio is actually broken, and it
                    // was the one with no counters.
                    let bedM = await engine.filmAudioBed
                    self.diag(String(format:
                        "[AWMACMIX] filmFrames=%d filmLevel=%.4f micLevel=%.4f "
                        + "ducking=%@ ringFill=%.2f ringOverflow=%d filmPadded=%d "
                        // `hlsBridge`, NOT "tapAttached". It reports
                        // `FilmAudioBridge`, which is the tvOS HLS pull path —
                        // macOS legitimately never uses it and legitimately
                        // reads NO. Labelled "tapAttached" it read as "the
                        // film's audio tap is not attached", which is a
                        // different and alarming claim about a platform the
                        // field does not describe. `filmLevel` above is the
                        // honest answer for macOS.
                        + "hlsBridge=%@ receivingExternal=%@",
                        h.audio.filmFramesWritten, h.audio.filmLevel, h.audio.micLevel,
                        h.audio.ducking ? "yes" : "no", bedM.filmRingFill,
                        bedM.filmRingOverflowed, h.audio.filmFramesPadded,
                        FilmAudioBridge.shared.isAttached ? "yes" : "NO",
                        bedM.isReceivingExternal ? "yes" : "no"))
                    self.diag("[AWSTUDIOHEALTH] state=\(h.showState.label) fps=\(h.encodedFramesPerSecond)"
                          + " queued=\(p.queuedBytes) vsent=\(p.videoFramesSent) vdrop=\(p.videoFramesDropped)"
                          + " asent=\(p.audioFramesSent) reconnects=\(p.reconnects)"
                          + " kbps=\(h.videoBitrateNow / 1000) thermal=\(h.thermalState)"
                          + " audio=\(h.audioSessionState) note=\(h.qualityNote ?? "-")"
                          + " hwenc=\(hw.map(String.init(describing:)) ?? "?")")
                }
                #endif
            }
        }
    }

    /// Silence a harness run — BOTH the program's film bus and the local
    /// player, because they are different things and only one of them is what
    /// a person in the room hears. Muting the mixer alone silences the
    /// broadcast and leaves the Mac's speakers playing, which is the exact
    /// mistake that left a film audible on the owner's Apple TV (§9).
    ///
    /// Not a product control — the panel's fader is.
    /// Silences the ROOM, never the program.
    ///
    /// It used to do both: `setAudio(filmMuted: true)` takes the film fader in
    /// the PROGRAM mix to zero (`StudioAudio` §465), so every broadcast this
    /// door ever produced went out with the film silent, and no Apple
    /// product-path audio had been measured through it. The two are different
    /// things wearing one word — the owner's speakers are protected by the
    /// LOCAL player's mute (that is the one that drove a film to every HomePod
    /// for an hour, §9), while the film fader is what the audience hears and
    /// is no business of a harness.
    public func muteLocalMonitorForHarness() {
        localPlayer?.isMuted = true
        // AND SAY SO, because this silences the BROADCAST too on any platform
        // that takes film audio through the tap (macOS, iOS). `isMuted` mutes
        // the player, and the tap lives inside that player's rendering path —
        // so a bench run with this on measures 96% digital silence and looks
        // like a broken audio pipeline. It cost a false "macOS audio is
        // intermittent" finding and its equally false refutation (§9.ddddd).
        // tvOS is unaffected: its audio comes from the pull path, upstream of
        // local output, which is why the same door is harmless there.
        awdiag("AWMUTE local monitor muted — on macOS/iOS this silences the "
               + "BROADCAST as well (the tap is inside the player). "
               + "Set AW_STUDIO_MAC_SOUND=1 before measuring audio.")
    }

    // MARK: Controls the panel drives

    /// The overlay the show is carrying, so a card or the lower third can be
    /// changed without the panel having to rebuild the title and provenance
    /// it never owned.
    private var overlay = StudioOverlay()

    public func setLowerThird(_ shown: Bool) async {
        overlay.title = shown ? armedTitle : ""
        overlay.subtitle = shown ? armedSubtitle : ""
        overlay.provenance = shown ? (armedProvenance ?? "") : ""
        await engine?.setOverlay(overlay)
    }

    public func setCard(_ card: StudioOverlay.Card?) async {
        overlay.card = card
        await engine?.setOverlay(overlay)
    }

    public func setLayout(_ layout: StudioLayout) async { await engine?.setLayout(layout) }
    public func setOverlay(_ overlay: StudioOverlay) async { await engine?.setOverlay(overlay) }
    /// One call, because that is the shape `StudioEngine` offers — every
    /// field optional so the panel can ride a single fader without restating
    /// the other three.
    /// `duckEnabled` IS PART OF THIS, and its absence is what "macOS has not
    /// learned everything from the Apple TV" looked like in practice. Rule
    /// 8.8c made auto-duck a setting because otherwise the fader lies — a
    /// host who sets Film to 9 and then speaks hears it drop 12 dB anyway —
    /// and the parameter was added to `StudioEngine` and stopped there. Every
    /// caller that goes through a `StudioSession`, which is macOS and iOS,
    /// could not reach it.
    ///
    /// It cost an hour to find, because of HOW Swift reports it: with five
    /// defaulted arguments, an unknown argument label makes the type-checker
    /// explore overloads until it gives up and says "unable to type-check
    /// this expression in reasonable time" — pointing at the enclosing view,
    /// not at the call. Four rounds of breaking up the view moved the error
    /// each time and fixed nothing. **When that error appears right after a
    /// call gained an argument, suspect the ARGUMENT before the expression.**
    public func setAudio(filmGain: Float? = nil, micGain: Float? = nil,
                         filmMuted: Bool? = nil, micMuted: Bool? = nil,
                         duckEnabled: Bool? = nil) async {
        await engine?.setAudio(filmGain: filmGain, micGain: micGain,
                               filmMuted: filmMuted, micMuted: micMuted,
                               duckEnabled: duckEnabled)
    }
}
