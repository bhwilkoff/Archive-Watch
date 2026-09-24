#if os(iOS)
import AVFoundation
import SwiftUI

// Watch Together Studio, hosted — iOS-DESIGN §8.8.
//
// This is the player, with the Studio's affordances over it. It is NOT a
// second player surface (§8.2) and NOT a new §3 shape: `PlayerView` builds and
// owns the transport exactly as it does for ordinary playback, and the engine
// only adds OUTPUTS to the item it already has — a video output for frames and
// an audio tap for sound.
//
// What this container owns is the part that is genuinely the Studio's: the
// engine's lifecycle, the host's controls, and the health the host is
// responsible for.
struct StudioPlayerContainer: View {
    let item: Catalog.Item
    let request: GoLiveRequest
    let onExit: () -> Void

    @Environment(AppStore.self) private var store

    @State private var engine: StudioEngine?
    @State private var health = StudioHealth()
    @State private var filmFPS = 0
    @State private var cameraFPS = 0
    /// Retained for the show's life — a released capture session stops
    /// delivering and the tile simply goes black (§9.kkkkk).
    @State private var hostCapture: AVCaptureSession?
    @State private var showControls = false
    @State private var startError: String?
    /// Three different things reach the one alert — a refused start, a film
    /// that will not play, and a show that ENDED ITSELF after it was live —
    /// and the last used to be titled "Could not go live" over a show that
    /// had been live for an hour.
    @State private var alertTitle = "Could not go live"

    // Controls, bound into the sheet.
    @State private var layout: StudioLayout
    @State private var filmGain = 1.0
    @State private var micGain = 1.0
    @State private var duckEnabled = true
    @State private var filmMuted = false
    /// §D26 — mirrored from the engine once a second.
    @State private var shoutOut: StudioOverlay.ShoutOut?
    @State private var showDoorTicks = 0
    @State private var onAirTicks = 0
    @State private var micMuted = false
    @State private var card: StudioOverlay.Card?
    @State private var showLowerThird = true
    @Environment(\.scenePhase) private var scenePhase
    /// The Intermission card this container raised when the host left the
    /// app — so returning takes down only THAT card, never the host's own.
    @State private var awayCard = false

    init(item: Catalog.Item, request: GoLiveRequest, onExit: @escaping () -> Void) {
        self.item = item
        self.request = request
        self.onExit = onExit
        _layout = State(initialValue: request.layout)
    }

    // Split deliberately: one chain of this many modifiers defeated the
    // SwiftUI type-checker outright ("unable to type-check this expression in
    // reasonable time"). Sub-expressions are not a style choice here.
    var body: some View {
        player
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    StudioHealthCapsule(health: health, filmFramesPerSecond: filmFPS,
                                        cameraFramesPerSecond: cameraFPS) {
                        showControls = true
                    }
                    // §6.2, DEBUG only, and BELOW the capsule rather than
                    // inside it: the capsule already truncates on a small
                    // phone when a warning chip joins it (seen on the glass).
                    //
                    // The iOS branch of §6.2 is the one that has to RECORD —
                    // tvOS only ever needs `.playback` — and it had never been
                    // read on a device, because the iPhone numbers in §9 came
                    // from `StudioLab`, which sets its OWN session.
                    #if DEBUG
                    Text("audio: \(health.audioSessionState)")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                    // The encoder's identity, as tvOS shows it (§9.vv). Android
                    // spent days at a third of its frame rate on a software
                    // encoder nobody had thought to ask about (§9.uu), so every
                    // platform now SAYS which one it got rather than assuming.
                    Text("encoder: \(health.encoderIsHardware.map { $0 ? "hardware" : "SOFTWARE" } ?? "-")")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                    #endif
                }
            }
            .sheet(isPresented: $showControls) { controlsSheet }
            .alert(alertTitle, isPresented: .constant(startError != nil)) {
                Button("OK") { startError = nil; Task { await end() } }
            } message: {
                Text(startError ?? "")
            }
            .task { await pollHealth() }
            // LEAVING THE APP MID-SHOW (launch audit, iOS). iOS suspends the
            // camera and the encoder in the background, so the audience would
            // be left on a frozen frame with no explanation. The moment the
            // app stops being active the program switches to Intermission, so
            // the last picture sent says "we'll be right back"; coming back
            // takes that card down again.
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .inactive, .background:
                    guard engine != nil, card == nil else { return }
                    awayCard = true
                    card = .intermission
                    awdiag("AWAWAY host left the app — Intermission up")
                case .active:
                    guard awayCard else { return }
                    awayCard = false
                    card = nil
                    awdiag("AWAWAY host is back — Intermission down")
                @unknown default: break
                }
            }
            // However the Studio closes — End, the alert, or the cover being
            // dismissed — the camera and microphone stop with it.
            .onDisappear { StudioSession.stopHostCapture() }
            .modifier(StudioBindings(
                layout: $layout, filmGain: $filmGain, micGain: $micGain,
                filmMuted: $filmMuted, micMuted: $micMuted,
                card: $card, showLowerThird: $showLowerThird,
                apply: { await applyControls() }))
    }

    private var player: some View {
        PlayerView(item: item, autoplayIn: nil, onUnplayable: { msg in
            alertTitle = "This film cannot be played"
            startError = msg
        }, captionChoice: nil, onPlayerReady: { p in
            Task { await attach(player: p) }
        })
        .ignoresSafeArea()
    }

    private var controlsSheet: some View {
        StudioControlsSheet(
            layout: $layout, filmGain: $filmGain, micGain: $micGain,
            filmMuted: $filmMuted, micMuted: $micMuted,
            duckEnabled: $duckEnabled,
            card: $card, showLowerThird: $showLowerThird,
            audio: health.audio, health: health, filmFramesPerSecond: filmFPS,
            cameraFramesPerSecond: cameraFPS,
            shoutOut: shoutOut,
            onShow: { line in showShoutOut(line) },
            onTakeDown: {
                shoutOut = nil
                Task { await engine?.clearShoutOut() }
            },
            onShareFilm: shareFilmAction,
            onEnd: { Task { await end() } })
    }

    /// One place that pushes every control into the engine, so the view has
    /// one `onChange` family instead of seven.
    private func applyControls() async {
        guard let e = engine else { return }
        await e.setLayout(layout)
        await e.setAudio(filmGain: Float(filmGain), micGain: Float(micGain),
                         filmMuted: filmMuted, micMuted: micMuted,
                         duckEnabled: duckEnabled)
        await pushOverlay()
    }

    // MARK: Lifecycle

    private func attach(player: AVPlayer) async {
        #if DEBUG
        // A door launch makes no sound in the room the phone sits in (the
        // macOS rule, v1.42.507). On iOS this silences the BROADCAST's film
        // audio too — the tap is inside the player — so measure audio with
        // AW_STUDIO_IOS_SOUND=1.
        let env = ProcessInfo.processInfo.environment
        if env["AW_STUDIO_IOS"] != nil || env["AW_STUDIO_GOLIVE"] != nil,
           env["AW_STUDIO_IOS_SOUND"] != "1" {
            player.isMuted = true
            awdiag("AWMUTE iOS door player muted (AW_STUDIO_IOS_SOUND=1 to hear it)")
        }
        #endif
        // Re-entrant by design: a Decision-077 copy fallback rebuilds the
        // player, and the engine must follow it to the new item.
        let e = engine ?? StudioEngine(configuration: .benchDoored())
        engine = e
        await e.attachFilm(player: player)
        // THE HOST'S OWN CAMERA AND VOICE. This was missing entirely: an
        // iPhone broadcast the film and nothing else, while the Apple TV had
        // had a Continuity camera for days. The helper is shared with macOS
        // and REPORTS rather than REQUESTS — the go-live sheet does the
        // asking, which is the only place a viewer has chosen to broadcast.
        hostCapture = await StudioSession.attachHostCamera(to: e)
        #if DEBUG
        // The INVENTED conversation (never a real channel), so §D26's phone
        // surface can be exercised on a bench broadcast.
        if ProcessInfo.processInfo.environment["AW_STUDIO_CHAT_DEMO"] == "1" {
            await e.setDemoChat(StudioSession.demoConversation)
        }
        #endif
        // EVERY control, not only layout and overlay: the audio was left
        // out, so an engine built after the host touched the mixer started
        // at defaults — the macOS defect of 2026-09-23 (§D23a) on this path.
        await applyControls()
        guard await !e.health.isRunning else { return }
        do {
            let dest = try await destination()
            // Read the chat too — iOS armed the id and never read it.
            await StudioSession.shared.attachYouTubeChatIfArmed(to: e)
            // Chat the program carries (§6.4) — named by the surface, read by the
            // engine. No credential is needed to read Twitch.
            // The host's OWN channel (§D22). This surface read AW_STUDIO_CHAT and
            // nothing else until 2026-09-22 — see StudioSession for why that meant
            // the product had no Twitch chat and a test showed a stranger's.
            if StudioSession.shared.showGoesToTwitch,
               let account = try? await StudioPlatformAuth.twitchAccount() {
                await e.attachTwitchChat(channel: account.login)
            } else if let channel = ProcessInfo.processInfo.environment["AW_STUDIO_CHAT"],
                      !channel.isEmpty {
                // Debug door only; never a host's path.
                await e.attachTwitchChat(channel: channel)
            }

            try await e.start(destination: dest)
        } catch {
            // The platform's own words, or ours about what is missing. Never
            // a dead capsule (§5).
            alertTitle = "Could not go live"
            startError = studioSentence(for: error)
        }
    }

    /// Where the program goes — resolved by shared code, so every platform
    /// can reach it (§9.lll). This wrapper keeps the call site unchanged.
    private func destination() async throws -> URL? {
        let d = try await StudioGoLive.destination(for: request, film: item)
        // iOS runs its OWN engine and poll loop (Decision 133), so the chat id
        // is armed on the shared session here rather than assumed to have been
        // armed by a macOS code path this platform never executes.
        StudioSession.shared.armYouTubeChat(d.liveChatID)
        StudioSession.shared.armBroadcast(d.broadcast)
        return d.url
    }

    /// §D32 — offered only on air with a YouTube chat to post in.
    private var shareFilmAction: (() async -> String?)? {
        guard StudioSession.shared.armedYouTubeChatID?.isEmpty == false,
              health.showState.isOnAir else { return nil }
        let film = item
        let meta = [film.year.map(String.init), film.director]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return {
            await StudioSession.shared.shareFilmInChat(
                archiveID: film.archiveID, title: film.title, meta: meta)
        }
    }

    private func showShoutOut(_ line: StudioOverlay.ChatLine) {
        guard !StudioOverlay.ShoutOut.tooLong(line.text) else { return }
        shoutOut = StudioOverlay.ShoutOut(author: line.author, text: line.text)
        Task { await engine?.showShoutOut(author: line.author, text: line.text) }
    }

    private func pushOverlay() async {
        var o = StudioOverlay()
        o.title = item.title
        o.subtitle = [item.year.map(String.init), item.director]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if item.rightsBucket == "safe_pd_age", let y = item.year {
            o.provenance = "Public domain — published \(y), before 1930"
        }
        o.showLowerThird = showLowerThird
        o.card = card
        // A FRESH overlay would take a viewer's message off the air every
        // time the host touched a control. It keeps what is up.
        o.shoutOut = await engine?.currentShoutOut
        await engine?.setOverlay(o)
    }

    /// One second, the same cadence the capsule reads at. The film counter is
    /// a DELTA, because the absolute total says nothing about whether frames
    /// are arriving right now — which is the whole point of it (§9).
    private func pollHealth() async {
        var lastFilmFrames = 0
        var lastCameraFrames = 0
        // THE SAME RULE THE OTHER TWO PLATFORMS USE. It is here, and not only
        // in `StudioSession`'s pump, because iOS does not run that pump: this
        // container owns the engine and this loop. Adding the behaviour to the
        // shared session and calling it done put it on macOS alone.
        var stall = CameraStallRecovery()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let e = engine else { continue }
            await e.refreshHealth()
            let h = await e.health
            filmFPS = max(0, h.filmFramesPulled - lastFilmFrames)
            lastFilmFrames = h.filmFramesPulled
            cameraFPS = max(0, h.cameraFramesReceived - lastCameraFrames)
            lastCameraFrames = h.cameraFramesReceived
            // §4's provenance line, which iOS showed for the whole broadcast
            // because the rule lived only in tvOS's own loop.
            _ = await e.expireProvenanceIfDue()
            // §D26's twelve seconds, on THIS loop: the macOS expiry lives in
            // StudioSession's pump, which iOS does not run (Decision 133).
            await e.expireShoutOutIfDue()
            shoutOut = await e.currentShoutOut
            health = h
            #if DEBUG
            // `AW_STUDIO_IOS_SHOW="2@25"`: 25 s into the show, open the
            // controls sheet and press Show on chat line 2 (oldest first),
            // through the same function the button calls.
            if h.showState.isOnAir { onAirTicks += 1 }
            let env = ProcessInfo.processInfo.environment
            // PLATFORM PROOF DOORS (owner, 2026-09-23: "make sure anything we
            // are adding can actually work on the systems we are building
            // for"). Each fires once, at T seconds on air.
            if let t = env["AW_STUDIO_IOS_READBACK"].flatMap(Int.init), onAirTicks == t {
                Task { await StudioSession.shared.debugLogBroadcast() }
            }
            if let t = env["AW_STUDIO_IOS_SHARECHAT"].flatMap(Int.init), onAirTicks == t {
                let meta = [item.year.map(String.init), item.director]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                Task {
                    let problem = await StudioSession.shared.shareFilmInChat(
                        archiveID: item.archiveID, title: item.title, meta: meta)
                    awdiag("AWCHATSHARE door result=%@", problem ?? "posted")
                }
            }
            if let t = env["AW_STUDIO_IOS_END"].flatMap(Int.init), onAirTicks == t {
                awdiag("AWDOOR ending the show at %d s on air", t)
                Task { await end() }
            }
            if let v = env["AW_STUDIO_IOS_SHOW"], h.showState.isOnAir {
                showDoorTicks += 1
                let parts = v.split(separator: "@")
                if let n = Int(parts.first ?? ""), let at = parts.count > 1 ? Int(parts[1]) : 0,
                   showDoorTicks == at {
                    showControls = true
                    if n >= 1, n <= h.chatRecent.count {
                        awdiag("AWSHOUT door showing line %d (%@)", n, h.chatRecent[n - 1].author)
                        showShoutOut(h.chatRecent[n - 1])
                    } else {
                        awdiag("AWSHOUT door: only %d chat lines", h.chatRecent.count)
                    }
                }
            }
            #endif

            // RECOVER A CAMERA THAT STOPPED — a phone's camera stops whenever
            // a call arrives, so this platform needs it at least as much as a
            // television does.
            if stall.tick(attached: h.cameraAttached,
                          framesReceived: h.cameraFramesReceived,
                          framesPerSecond: cameraFPS,
                          onAir: h.showState.isOnAir) {
                awdiag("AWCAM camera stopped at %d frames — recovery attempt %d of %d",
                       h.cameraFramesReceived, stall.attempts,
                       CameraStallRecovery.maximumAttempts)
                hostCapture = await StudioSession.attachHostCamera(to: e)
                awdiag("AWCAM recovery %d: %@", stall.attempts,
                       hostCapture != nil ? "re-attached" : "no camera")
            }

            // IS THE FILM'S AUDIO GOING OUT? `StudioControls_iOS` reads this
            // from the shared session, and on this platform nothing was
            // writing it.
            StudioSession.shared.publishFilmAudioProblem(
                await e.filmAudioProblem(sourceHasAudio: e.sourceHasAudio))

            // The publisher's own numbers, in the file a device harness can
            // pull. §9.zzzzz: they existed and were unreachable here.
            let p = h.publisher
            // `thermal` too: a proof run on YouTube (yY2hfXeb5fE) stepped
            // 6000 -> 3600 kbps two minutes in and this line never said why.
            awdiag("AWSTUDIOHEALTH state=%@ fps=%d queued=%d vsent=%d vdrop=%d asent=%d reconnects=%d kbps=%d thermal=%@",
                   h.showState.label, h.encodedFramesPerSecond, p.queuedBytes,
                   p.videoFramesSent, p.videoFramesDropped, p.audioFramesSent,
                   p.reconnects, h.videoBitrateNow / 1000, h.thermalState)
            // THE ENCODER'S IDENTITY. SCRATCHPAD item 9a has had this open as
            // "iOS still waits — they need only a screenshot of the DEBUG
            // readout", which framed a number the app already knows as a
            // photography problem. It is a log line.
            awdiag("AWENC hardware=%@",
                   h.encoderIsHardware.map { $0 ? "true" : "false" } ?? "unknown")

            // A show that ENDS ITSELF says why (§6.5's `.critical`, §6.6's
            // expired deadline). It reuses the existing alert rather than
            // inventing a second one: the host's question is the same either
            // way — why am I not live? — and `endedReason` was read by nothing
            // on Apple until now, so the Studio just vanished.
            if let why = h.endedReason {
                alertTitle = "The broadcast ended"
                startError = why.prefix(1).uppercased() + why.dropFirst() + "."
                return
            }
        }
    }

    private func end() async {
        await StudioSession.shared.completeArmedBroadcast()
        await engine?.stop()
        engine = nil
        StudioSession.stopHostCapture()
        hostCapture = nil
        onExit()
    }
}

/// The Studio's control bindings, as one modifier. Seven `onChange`s inline
/// is what broke the type-checker; it is also seven places to forget one.
private struct StudioBindings: ViewModifier {
    @Binding var layout: StudioLayout
    @Binding var filmGain: Double
    @Binding var micGain: Double
    @Binding var filmMuted: Bool
    @Binding var micMuted: Bool
    @Binding var card: StudioOverlay.Card?
    @Binding var showLowerThird: Bool
    let apply: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: layout) { _, _ in Task { await apply() } }
            .onChange(of: filmGain) { _, _ in Task { await apply() } }
            .onChange(of: micGain) { _, _ in Task { await apply() } }
            .onChange(of: filmMuted) { _, _ in Task { await apply() } }
            .onChange(of: micMuted) { _, _ in Task { await apply() } }
            .onChange(of: card) { _, _ in Task { await apply() } }
            .onChange(of: showLowerThird) { _, _ in Task { await apply() } }
    }
}
#endif
