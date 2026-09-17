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
        var o = StudioOverlay()
        o.title = armedTitle
        o.subtitle = armedSubtitle
        o.provenance = armedProvenance ?? ""
        await e.setOverlay(o)

        do {
            // No destination yet: the engine composites and encodes and sends
            // nowhere, which is what every platform does until a client id
            // exists (Decision 128). `showState` reports NOT SENDING rather
            // than pretending, so this is an honest production mode and not a
            // stub.
            try await e.start(destination: nil)
        } catch {
            refusal = "The Studio could not start — \(error)"
            engine = nil
            return
        }
        isLive = true
        startPump()
    }

    public func end() async {
        pump?.cancel(); pump = nil
        if let engine { await engine.stop() }
        engine = nil
        isLive = false
        filmFramesPerSecond = 0
        health = StudioHealth()
    }

    /// One health sample a second — the rate the `notEncoding` and
    /// frozen-film guards are defined against (§9).
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
