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
    public private(set) var armedFilmID: String?
    public private(set) var armedTitle: String = ""
    public private(set) var armedSubtitle: String = ""
    public private(set) var armedProvenance: String?

    public private(set) var isLive = false
    public private(set) var health = StudioHealth()
    /// Film frames in the last second — 0 while live is the frozen-picture
    /// signature, and the readouts say so (WATCH-TOGETHER §4).
    public private(set) var filmFramesPerSecond = 0
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

        let e = StudioEngine()
        engine = e
        await e.attachFilm(player: player)
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
            let dest = ProcessInfo.processInfo.environment["AW_STUDIO_DEST"]
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
    private func attachCameraIfAvailable(to engine: StudioEngine) async {
        #if os(macOS) || os(iOS)
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else { return }
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
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let engine = self.engine else { return }
                await engine.refreshHealth()
                let h = await engine.health
                self.filmFramesPerSecond = max(0, h.filmFramesPulled - lastFilmFrames)
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
                    self.diag("[AWSTUDIOHEALTH] state=\(h.showState.label) fps=\(h.encodedFramesPerSecond)"
                          + " queued=\(p.queuedBytes) vsent=\(p.videoFramesSent) vdrop=\(p.videoFramesDropped)"
                          + " asent=\(p.audioFramesSent) reconnects=\(p.reconnects)"
                          + " kbps=\(h.videoBitrateNow / 1000) thermal=\(h.thermalState)"
                          + " audio=\(h.audioSessionState) note=\(h.qualityNote ?? "-")")
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
    public func muteFilmForHarness() {
        localPlayer?.isMuted = true
        Task { await engine?.setAudio(filmMuted: true) }
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
    public func setAudio(filmGain: Float? = nil, micGain: Float? = nil,
                         filmMuted: Bool? = nil, micMuted: Bool? = nil) async {
        await engine?.setAudio(filmGain: filmGain, micGain: micGain,
                               filmMuted: filmMuted, micMuted: micMuted)
    }
}
