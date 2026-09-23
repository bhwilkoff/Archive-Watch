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

/// Which platform's broadcast a show is on, and the id that platform reads it
/// by: a YouTube broadcast (= video) id, or the Twitch broadcaster's user id.
public enum StudioBroadcastRef: Sendable, Equatable {
    case youtube(String)
    case twitch(userID: String)

    var platformName: String {
        switch self { case .youtube: "youtube"; case .twitch: "twitch" }
    }
}

/// Reads the live audience from the platform. Nil means "not reported" —
/// the stream is not live yet, the read failed, or the platform hides it.
enum StudioAudience {
    /// The count, or nil. In DEBUG every read SAYS what it got — a number,
    /// "absent", or the error — because the first real YouTube run
    /// (2026-09-23, broadcast GYAQsLMDwho) showed "1 watching now" on
    /// YouTube's page for over a minute while this logged nothing at all,
    /// and `try?` had thrown away which layer said no.
    static func count(_ ref: StudioBroadcastRef) async -> Int? {
        do {
            let n: Int?
            switch ref {
            case .youtube(let id):
                let token = try await StudioPlatformAuth.token(for: .youtube)
                n = try await YouTubeLive(token: token).concurrentViewers(videoID: id)
            case .twitch(let userID):
                guard let clientID = StudioPlatformAuth.clientID(for: .twitch) else { return nil }
                let token = try await StudioPlatformAuth.token(for: .twitch)
                n = try await TwitchLive(token: token, clientID: clientID).viewerCount(userID: userID)
            }
            #if DEBUG
            awdiag("AWAUDIENCE read %@ -> %@", ref.platformName, n.map(String.init) ?? "absent")
            #endif
            return n
        } catch {
            #if DEBUG
            awdiag("AWAUDIENCE read %@ failed — %@", ref.platformName, "\(error)")
            #endif
            return nil
        }
    }
}

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

    /// The broadcast's own chat id, armed for the same reason the destination
    /// is: `arm` records intent and the engine is built later. YouTube only —
    /// Twitch chat is read anonymously by channel name.
    public private(set) var armedYouTubeChatID: String?
    public func armYouTubeChat(_ id: String?) { armedYouTubeChatID = id }

    /// The YouTube broadcast this show is going out on, so ending the show can
    /// end the BROADCAST.
    ///
    /// `liveBroadcasts.insert` returns an id, `prepare` read it into
    /// `StreamCredentials.broadcastID`, `YouTubeLive.complete(broadcastID:)`
    /// was written to transition it — and the id was dropped by the same bare
    /// `URL?` return that dropped the chat id. So `complete()` has never been
    /// called, and every YouTube show this app has ended has left its
    /// broadcast open on the host's channel.
    ///
    /// `enableAutoStop` covers the ordinary case — YouTube ends a broadcast
    /// when the bytes stop — so this is belt and braces rather than the only
    /// path. It is still worth having: auto-stop waits for a timeout, and a
    /// host who pressed End expects it ended.
    ///
    /// It carries its PLATFORM. It used to be a bare id, and Twitch armed its
    /// USER id through the same field — so a host signed in to both who ended
    /// a Twitch show sent YouTube a `complete` for a Twitch user.
    public private(set) var armedBroadcast: StudioBroadcastRef?
    public var armedBroadcastID: String? {
        if case .youtube(let id) = armedBroadcast { return id }
        return nil
    }
    public func armBroadcast(_ ref: StudioBroadcastRef?) {
        armedBroadcast = ref
        startAudiencePolling()
    }

    /// HOW MANY PEOPLE ARE WATCHING (§D27). Nil until the platform reports a
    /// live stream — never a zero we made up, which would tell a host nobody
    /// came when the truth is that we have not been told yet.
    ///
    /// The poller is started by `armBroadcast` and stopped by
    /// `completeArmedBroadcast`, because those are the two calls every
    /// platform's go-live and end already make (Decision 133: a shared PATH,
    /// not a shared type — iOS and tvOS run their own engine loops).
    public private(set) var audienceCount: Int?

    /// When the platform's server accepted the stream (§D28). Nil until then
    /// and after the show ends.
    /// A chapter on the replay (§D30). Twitch only: YouTube's `cuepoints`
    /// are ad breaks, not chapters. Twitch refuses when the channel does not
    /// keep VODs or the stream is not live yet; that is said and not retried.
    func markMoment(_ description: String) async {
        guard case .twitch(let userID) = armedBroadcast else { return }
        do {
            guard let cid = StudioPlatformAuth.clientID(for: .twitch) else { return }
            let tw = TwitchLive(token: try await StudioPlatformAuth.token(for: .twitch), clientID: cid)
            try await tw.createMarker(userID: userID, description: description)
            awdiag("AWMARKER placed \"%@\"", description)
        } catch {
            awdiag("AWMARKER not placed \"%@\" — %@", description, "\(error)")
        }
    }

    public private(set) var onAirSince: Date?
    /// What actually left the Mac in the last second, from the publisher's
    /// byte counter — not the configured target, which the encoder delivers
    /// only ~70-75% of and §6.5 can lower.
    public private(set) var sendingBitsPerSecond = 0
    private var lastBytesSent = 0
    #if DEBUG
    private var proofTicks = 0
    private var recordTicks = 0
    #endif
    private var audienceTask: Task<Void, Never>?
    /// YouTube charges 1 unit a read; 30 s is 240 units for a two-hour film
    /// against 10,000 a day, and a count is not a thing that needs seconds.
    static let audiencePollSeconds: UInt64 = 30

    private func startAudiencePolling() {
        audienceTask?.cancel(); audienceTask = nil
        audienceCount = nil
        guard let ref = armedBroadcast else { return }
        audienceTask = Task { [weak self] in
            while !Task.isCancelled {
                let n = await StudioAudience.count(ref)
                guard !Task.isCancelled else { return }
                if let self, self.audienceCount != n {
                    self.audienceCount = n
                    awdiag("AWAUDIENCE %@ watching=%@", ref.platformName,
                           n.map(String.init) ?? "unknown")
                }
                try? await Task.sleep(nanoseconds: Self.audiencePollSeconds * 1_000_000_000)
            }
        }
    }

    /// Simulcast destinations beyond the first (roadmap #2). Armed for the
    /// same reason everything else here is: the engine does not exist yet.
    public private(set) var armedExtras: [StudioExtraDestination] = []
    public func armExtras(_ extras: [StudioExtraDestination]) { armedExtras = extras }

    /// §D22: TWITCH CHAT BELONGS ONLY ON A SHOW THAT IS GOING TO TWITCH —
    /// as the primary broadcast, or as a simulcast extra. Signed in to Twitch
    /// is not the same fact: a proof run on YouTube (5shlTXfHNUA, 2026-09-23)
    /// logged "reading this broadcast's own channel #licbhwilkoff", which
    /// would have put the host's Twitch chat over a YouTube audience.
    public var showGoesToTwitch: Bool {
        if case .twitch = armedBroadcast { return true }
        return armedExtras.contains { $0.name == GoLivePlatform.twitch.label }
    }

    /// The placement the host chose, remembered until the engine exists.
    ///
    /// `arm` records INTENT and the engine is built later, when the player
    /// appears — so a caller that sets the layout at arm time is setting it on
    /// nothing, and one that sets it after must first wait for `isLive`. Every
    /// caller getting that right independently is precisely what did not
    /// happen: the macOS SHEET armed and never applied `request.layout` at all
    /// (a host who picked "Side by side" got `corner`), while the macOS DOOR
    /// waited and applied it — which is why the door's runs looked correct and
    /// the product's path was wrong. tvOS had the same defect one layer down.
    /// Arming the layout beside the destination removes the timing question
    /// from every caller.
    public func armLayout(_ layout: StudioLayout) { armedLayout = layout }

    /// §D14 — the host's framing, armed for the same reason the layout is.
    /// `arm` records intent and the engine is built later, so a caller that
    /// sets framing before a show starts is setting it on nothing. This is
    /// Decision 133's lesson applied in advance rather than after the defect.
    public private(set) var armedFraming = StudioCameraFraming()
    public private(set) var armedGuestFraming = StudioCameraFraming()
    public func armFraming(_ f: StudioCameraFraming) {
        armedFraming = f
        Task { await engine?.setCameraFraming(f) }
    }

    /// §D24 — the guests' framing, armed for the same reason the camera's is:
    /// a choice made before the engine exists is the one the show starts with.
    public func armGuestFraming(_ f: StudioCameraFraming) {
        armedGuestFraming = f
        Task { await engine?.setGuestFraming(f) }
    }

    /// Readable, so a panel can OPEN on the placement the show is actually
    /// using. It is `@State`-backed on macOS and defaulted to `.corner`, so a
    /// host who chose "Side by side" in the sheet would have seen the engine
    /// do the right thing while the control claimed otherwise — a readout that
    /// lies, which §4 forbids as firmly for a picker as for a bitrate.
    public private(set) var armedLayout: StudioLayout = .corner

    public private(set) var armedFilmID: String?
    public private(set) var armedTitle: String = ""
    public private(set) var armedSubtitle: String = ""
    public private(set) var armedProvenance: String?

    /// THE ENGINE IS RUNNING. Not the same as being on air, and the
    /// difference became load-bearing the moment §D5 added a preview: this is
    /// set whenever the engine starts, INCLUDING with no destination, which is
    /// exactly what a rehearsal is.
    public private(set) var isLive = false

    /// Whether anything is actually being SENT to anybody.
    ///
    /// A surface that says "live" must ask THIS. `isLive` has meant "the
    /// engine is running" since it was written, and on macOS the engine has
    /// always run with no destination while a film is armed — so a red dot
    /// keyed to `isLive` would tell a host they were broadcasting during a
    /// rehearsal that goes nowhere.
    public var isOnAir: Bool { isLive && health.hasDestination }

    /// Whether this is a rehearsal: producing a program, sending nothing.
    public var isRehearsing: Bool { isLive && !health.hasDestination }
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
    /// "The film's audio is not being sent" — the warning that existed on tvOS
    /// ALONE. macOS and iOS use the `MTAudioProcessingTap`, which is exactly
    /// the path that can fail to attach, so they were the two platforms that
    /// could broadcast a silent program with nothing on screen saying so.
    public private(set) var filmAudioProblem: String?

    /// THE FILM HAS ENDED AND THE SHOW HAS NOT (owner item 13, §9.bbbbbb).
    /// Read from the ENGINE, which is the one code path all three platforms
    /// share — see `StudioEngine.attachFilm`.
    public var filmHasEnded: Bool { health.filmEnded }

    /// Set by whichever loop is actually running. **iOS does not run this
    /// object's pump at all** — `StudioPlayerContainer_iOS` builds its own
    /// engine and polls it — so a value written only in `startPump` reaches
    /// macOS and nothing else. That is how the warning and the camera-stall
    /// recovery were both committed as "macOS and iOS" on 2026-09-20 while
    /// being inert on the phone; the shared TYPE looked like shared BEHAVIOUR.
    public func publishFilmAudioProblem(_ problem: String?) { filmAudioProblem = problem }
    /// Why the Studio refused, for the surface that asked.
    public var refusal: String?

    /// §D16 — this film's asset carries NO audio track. Not a fault; a fact
    /// with a consequence the host owns.
    public private(set) var filmHasNoSoundtrack = false

    /// WHY the film has stopped reaching the program, in words, when it has.
    ///
    /// On 2026-09-22 the Studio's program went black on two runs out of
    /// eight while the FILM pane beside it played perfectly. Both were silent:
    /// the row said "no new frames", which is the SYMPTOM, and nothing
    /// anywhere said what the player was doing. The camera has had a stall
    /// detector with a named cause since it drifted the same way; the film
    /// — the thing the audience is actually here for — had none.
    ///
    /// It asks the PLAYER rather than counting frames, which is §9.bbbbbb's
    /// lesson from telling "ended" from "buffering": a counter can only say
    /// that nothing arrived, and every cause looks identical from there.
    public private(set) var filmProblem: String?

    /// The demo door's conversation. Deliberately includes an EVENT line and
    /// one message past `maxCharacters`, so a run of the door reaches the two
    /// rows that look different.
    static let demoConversation: [StudioOverlay.ChatLine] = [
        .init(id: "d1", author: "ora331", text: "first time seeing this one!"),
        .init(id: "d2", author: "marguerite_b", text: "the clock stunt still holds up"),
        .init(id: "d3", author: "newfollower", text: "followed", isEvent: true),
        .init(id: "d4", author: "crazyspecz",
              text: "my grandmother saw this in a theater in 1924"),
        .init(id: "d5", author: "longwinded",
              text: String(repeating: "and another thing about this picture ", count: 9)),
        .init(id: "d6", author: "kt_projects", text: "what's the print source?"),
    ]

    /// §D26 — what is on screen right now, so the surface can offer to take
    /// it down, and the lines the host can put up. Mirrored off the engine on
    /// the once-a-second beat: the engine is an actor and a SwiftUI row
    /// cannot await it.
    public private(set) var shoutOut: StudioOverlay.ShoutOut?
    public private(set) var chatRecent: [StudioOverlay.ChatLine] = []

    /// Puts somebody in the audience on the broadcast, under their own name.
    /// Refused above `maxCharacters` rather than truncated — cutting a
    /// stranger's sentence in half and putting their name on the remainder is
    /// worse than declining to show it.
    public func showShoutOut(_ line: StudioOverlay.ChatLine) {
        guard !StudioOverlay.ShoutOut.tooLong(line.text) else { return }
        let author = line.author, text = line.text
        shoutOut = StudioOverlay.ShoutOut(author: author, text: text)
        guard let engine else { return }
        Task { await engine.showShoutOut(author: author, text: text) }
    }

    /// §D32 — the film, posted into YouTube chat by the host's own hand.
    /// Returns what went wrong, or nil. Never automatic: a host decides when
    /// the room hears about the film, as they decide whose message is shown.
    public private(set) var sharedFilmAt: Date?
    public var canShareFilmInChat: Bool {
        isOnAir && armedYouTubeChatID?.isEmpty == false && surfaceArchiveID != nil
    }

    /// Reads the armed YouTube broadcast's chat into `e`. ONE method, called
    /// by every platform's start path: this lived inline in macOS's attach,
    /// and iOS and tvOS — which arm the chat id and run their own engines
    /// (Decision 133) — never read YouTube chat at all. Found 2026-09-23 when
    /// the owner asked for every feature to be proved on the real platforms.
    public func attachYouTubeChatIfArmed(to e: StudioEngine) async {
        guard let chatID = armedYouTubeChatID, !chatID.isEmpty else { return }
        if let token = try? await StudioPlatformAuth.token(for: .youtube) {
            await e.attachYouTubeChat(liveChatID: chatID) { id, page in
                try await YouTubeLive(token: token).chat(liveChatID: id, pageToken: page)
            }
            diag("[AWSTUDIOCHAT] reading YouTube live chat")
        } else {
            // A chat that stays empty because a token could not be refreshed
            // looks exactly like an audience that is not talking.
            diag("[AWSTUDIOCHAT] no YouTube token — chat will stay empty")
        }
    }

    #if DEBUG
    public func debugLogBroadcast() async {
        guard let id = armedBroadcastID,
              let token = try? await StudioPlatformAuth.token(for: .youtube) else {
            awdiag("AWYTREAD no YouTube broadcast armed"); return
        }
        do { awdiag("AWYTREAD %@ %@", id, try await YouTubeLive(token: token).debugReadBack(broadcastID: id)) }
        catch { awdiag("AWYTREAD failed — %@", "\(error)") }
    }
    #endif

    /// `archiveID`/`title`/`meta` for the platforms that register no
    /// surface (iOS, tvOS) — macOS reads its own.
    public func shareFilmInChat(archiveID: String? = nil, title: String? = nil,
                                meta: String? = nil) async -> String? {
        guard let chatID = armedYouTubeChatID, !chatID.isEmpty,
              let id = archiveID ?? surfaceArchiveID else { return "There is no YouTube chat to post in." }
        let text = StudioChatShare.message(title: title ?? armedTitle,
                                           meta: meta ?? armedSubtitle, archiveID: id)
        do {
            try await YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
                .postChat(liveChatID: chatID, text: text)
            sharedFilmAt = Date()
            awdiag("AWCHATSHARE posted %d characters", text.count)
            return nil
        } catch {
            awdiag("AWCHATSHARE refused — %@", "\(error)")
            return "YouTube did not accept the message (\(error))."
        }
    }

    public func clearShoutOut() {
        shoutOut = nil
        guard let engine else { return }
        Task { await engine.clearShoutOut() }
    }

    /// What the host's filter dropped this second (§D22), for the surface.
    public var chatLinesFiltered: Int { health.chatLinesFiltered }

    /// The host's three chat controls, in ONE call so they cannot arrive
    /// apart. Armed as well as set: a host who configures chat BEFORE going
    /// live must not have it reset by the engine being built afterwards,
    /// which is the timing defect `armLayout` exists for (Decision 133).
    private var armedChat: (enabled: Bool, side: StudioChatSide, filter: StudioChatFilter)?

    #if os(macOS)
    /// §D23 — the call's picture. The SOURCE lives here rather than in the
    /// window, because a Studio window that is closed and reopened must not
    /// drop the call out of a live broadcast (§D12 ends the SHOW when the
    /// window closes; it does not end it when a view redraws).
    private var screenSource: StudioScreenSource?
    public private(set) var guestWindowLabel: String?
    public var guestProblem: String? { screenSource?.problem }

    @discardableResult
    public func startGuests(windowID: CGWindowID, label: String,
                            ownerPID: pid_t? = nil,
                            ownerBundleID: String? = nil) async -> Bool {
        stopGuests()
        let src = StudioScreenSource()
        screenSource = src
        guestWindowLabel = label
        let ok = await src.start(windowID: windowID,
                                 size: CGSize(width: 1280, height: 720))
        guard ok else {
            screenSource = nil
            guestWindowLabel = nil
            return false
        }
        await engine?.attachGuests(src.sink)
        // §D25 — ONE CALL IS ONE CHOICE. The same app's audio, without asking
        // the host to name it again in another column. Matched on pid, which
        // is exact, rather than on the display name, which two apps can share.
        //
        // A FAILURE HERE DOES NOT FAIL THE PICTURE. Half a call is better
        // than a refusal as long as the missing half is named, and
        // `callProblem` names it (§D18).
        if callAppName == nil, ownerPID != nil || ownerBundleID != nil {
            // MATCH ON THE BUNDLE ID, NOT THE PID. `StudioAudioProcesses`
            // groups every audio object an app owns into one row and keeps
            // the LOWEST pid, which for a browser is a HELPER — and a browser
            // is the app most calls happen in. So the window's pid and the
            // audio row's pid genuinely differ for the case this feature
            // exists to serve. Measured 2026-09-23: Chrome's window pid found
            // nothing, and the host got faces with no voices and an orange
            // line blaming the app.
            //
            // The prefix test is the helper convention: `com.google.Chrome`
            // against `com.google.Chrome.helper`, either way round.
            let procs = StudioAudioProcesses.all()
            let match = procs.first { p in
                if let b = ownerBundleID, !b.isEmpty {
                    if p.bundleID == b { return true }
                    if p.bundleID.hasPrefix(b + ".") || b.hasPrefix(p.bundleID + ".") { return true }
                }
                if let pid = ownerPID, p.pid == pid { return true }
                return false
            }
            if let match {
                _ = await startCallAudio(process: match)
            } else {
                callProblem = "\(guestWindowLabel ?? "That app") is not playing any "
                    + "audio macOS can capture yet — its voices will not be in the mix."
            }
        }
        return true
    }

    public func stopGuests() {
        screenSource?.stop()
        screenSource = nil
        guestWindowLabel = nil
        Task { await engine?.attachGuests(nil) }
        // §D25: one choice, so one undo. A host who stops showing their
        // guests does not expect their voices to keep arriving.
        stopCallAudio()
    }
    #endif

    /// The engine, for harnesses that must read a value where it LANDS
    /// (Decision 133) rather than where it was set. Not for product code.
    public var engineForHarness: StudioEngine? { engine }

    public func setChat(enabled: Bool, side: StudioChatSide, filter: StudioChatFilter) async {
        armedChat = (enabled, side, filter)
        guard let e = engine else { return }
        await e.setChatControls(enabled: enabled, side: side, filter: filter)
    }

    /// §D18 — the call tap has been open for three seconds and delivered no
    /// samples at all. A level of zero is a quiet room; no samples is an
    /// absence, and the two may not draw the same.
    public private(set) var callDeliveringNothing = false

    private func updateCallSilence() {
        #if os(macOS)
        guard #available(macOS 14.2, *), let tap = callTap as? StudioCallAudioTap else {
            callDeliveringNothing = false
            return
        }
        if tap.samplesReceived > 0 {
            callSilentSince = nil
            callDeliveringNothing = false
            return
        }
        // THREE SECONDS. A tap that is going to deliver starts within one
        // callback; three is enough that a slow start cannot raise this, and
        // short enough that a host learns before they begin talking.
        let since = callSilentSince ?? Date()
        callSilentSince = since
        callDeliveringNothing = Date().timeIntervalSince(since) >= 3
        #endif
    }

    private var engine: StudioEngine?
    private var pump: Task<Void, Never>?
    /// Weak: the player belongs to the surface that built it, and a show must
    /// never be the reason a player outlives its window.
    private weak var localPlayer: AVPlayer?
    /// Retained for the show's lifetime — a capture session that is released
    /// stops delivering, and the tile simply goes black.
    private var capture: AVCaptureSession?

    private init() {
        // §D30: the engine reports card moments here; see `StudioMoments`.
        StudioMoments.sink = { [weak self] moment in await self?.markMoment(moment) }
        StudioMoments.still = { [weak self] jpeg in await self?.uploadThumbnail(jpeg) }
    }

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

    /// REHEARSE: run the program with no destination (§D5).
    ///
    /// Owner's §D5: "Before going live the preview still runs. A host should
    /// be able to frame themselves, set levels and pick a placement with
    /// nothing being broadcast — which is what OBS's preview is for, and what
    /// no Archive Watch platform offers today."
    ///
    /// This is the SAME path a broadcast takes, with `armedDestination` nil,
    /// rather than a second render loop — §D5's whole point is that the
    /// preview cannot diverge from the program, and two loops is how it
    /// would. The rights gate still applies: a film that may not be streamed
    /// may not be rehearsed either, because the rehearsal IS the program.
    ///
    /// It is EXPLICIT, never automatic. Starting it attaches the camera and
    /// the microphone, and a camera light that comes on because somebody
    /// opened a window is a surprise, not a feature.
    @discardableResult
    func startPreview(film: Catalog.Item) -> Bool {
        guard !isLive else { return true }
        armDestination(nil)
        return arm(film: film)
    }

    // MARK: - A surface that already has a player (macOS-DESIGN §D7)

    /// The player the visible surface is driving, whether or not a show is
    /// armed, and which film it is playing.
    ///
    /// WHY THIS EXISTS. `attachIfArmed` is called once, when a player is
    /// BUILT, and it is a no-op unless the session was armed before that
    /// moment. That was exactly right while the only way to reach the Studio
    /// was to arm from Detail and then start playing — arm, then build, then
    /// attach, in that order every time.
    ///
    /// §D7 reverses the order: the Studio window holds the film, so the player
    /// exists first and the host decides to produce a show second. Without a
    /// record of the running player, pressing Start preview would set
    /// `armedFilmID` and nothing would ever come to collect it — the engine
    /// would never be built, and the Studio would report "not attached" for
    /// every input while looking entirely healthy. That is the shape of
    /// Decision 133's defect (a value that lands nowhere), and the fix is the
    /// same one: remove the timing question rather than ask each caller to get
    /// it right.
    private weak var surfacePlayer: AVPlayer? {
        didSet { observeFilmPlayback() }
    }
    private var surfaceArchiveID: String?

    /// Whether the film is playing, OBSERVABLY — a menu title that says
    /// "Pause" over a paused film is a control that lies about itself.
    public private(set) var filmIsPlaying = false
    @ObservationIgnored private var filmPlaybackObserver: NSKeyValueObservation?
    public private(set) var hasFilm = false

    /// THE PAUSE FOR TALKING. Stopping the film to discuss a scene is the
    /// moment a watch-along exists for, and it should not need the pointer.
    /// A room follows on its own: `StudioRoomHost` observes this same player.
    public func toggleFilmPlayback() {
        guard let p = surfacePlayer ?? localPlayer, p.currentItem != nil else { return }
        if p.timeControlStatus == .paused { p.play() } else { p.pause() }
    }

    private func observeFilmPlayback() {
        filmPlaybackObserver = nil
        hasFilm = surfacePlayer != nil
        guard let p = surfacePlayer else { filmIsPlaying = false; return }
        filmPlaybackObserver = p.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in self?.filmIsPlaying = playing }
        }
    }

    /// Called by every macOS/iOS player surface as soon as it has a player.
    /// Carries the old `attachIfArmed` behavior unchanged, and remembers the
    /// player so a show armed LATER can still find it.
    public func registerSurfacePlayer(_ player: AVPlayer, archiveID: String) async {
        // WHICH PLAYER, by identity. The Studio's program went black on some
        // runs and not others with identical logs, and the only difference a
        // log could show was WHICH AVPlayer each step was talking about — a
        // surface rebuild hands the engine's player to a teardown that nils its
        // item, and every line up to that point reads healthy.
        awdiag("AWSURFACE register player=%lx film=%@",
               UInt(bitPattern: ObjectIdentifier(player).hashValue), archiveID)
        surfacePlayer = player
        surfaceArchiveID = archiveID
        #if DEBUG
        // EVERY DOOR IS SILENT IN THE ROOM, including the one that only opens
        // the Studio. `muteLocalMonitorForHarness` reaches `localPlayer`, which
        // exists once a show is armed — so `AW_GOLIVE_MAC=1` alone played The
        // Man Who Laughs out loud at the owner on 2026-09-23. Every door's
        // player passes through here, so this is where it is silenced.
        let env = ProcessInfo.processInfo.environment
        if env["AW_GOLIVE_MAC"] == "1", env["AW_STUDIO_MAC_SOUND"] != "1" {
            player.isMuted = true
            awdiag("AWMUTE door surface muted (AW_STUDIO_MAC_SOUND=1 to hear it)")
        }
        #endif
        await attachIfArmed(player: player, archiveID: archiveID)
    }

    /// The surface is going away; forget its player rather than keep a stale
    /// one that a later `beginShow` would try to broadcast.
    ///
    /// IT COMPARES THE PLAYER, NOT THE FILM. Moving a film between the Studio
    /// and the projection window (§D7) tears one surface down and builds
    /// another for the SAME archive id, and SwiftUI does not promise that the
    /// old one's `onDisappear` runs before the new one's `onAppear`. Keyed on
    /// the id alone, a late teardown would forget the registration the new
    /// surface had just made — and `beginShow` would then arm a show with no
    /// player to attach, which looks exactly like the Studio doing nothing.
    /// Is a LIVE show pulling frames from this exact player?
    ///
    /// Asked by a surface BEFORE it tears its player down (§D12a). This is the
    /// black-programme fault: `teardown()` calls `replaceCurrentItem(with:
    /// nil)` on the player it owns, and the engine may be holding that same
    /// object — which leaves the compositor pulling from a player with no
    /// item, so the programme goes black while every readout stays healthy.
    /// Reproduced twice in eight runs on 2026-09-22 with no signature,
    /// because whether SwiftUI rebuilds that view during a show is timing.
    public func engineIsUsing(_ player: AVPlayer?) -> Bool {
        guard let player, isLive else { return false }
        return localPlayer === player
    }

    public func forgetSurfacePlayer(_ player: AVPlayer?) {
        awdiag("AWSURFACE forget player=%lx registered=%@ engineHolds=%@",
               player.map { UInt(bitPattern: ObjectIdentifier($0).hashValue) } ?? 0,
               surfacePlayer === player ? "yes" : "no",
               localPlayer === player ? "YES" : "no")
        guard let player, surfacePlayer === player else { return }
        surfacePlayer = nil
        surfaceArchiveID = nil
    }

    /// Arm a show for a film that is ALREADY playing (§D7).
    ///
    /// `destination` nil is §D5's rehearsal — the same path a broadcast takes,
    /// sending nowhere, because the preview must not be able to diverge from
    /// the program. Returns false when the rights gate refused, and
    /// `refusal` carries the sentence.
    @discardableResult
    func beginShow(film: Catalog.Item, destination: URL?,
                   additional: [StudioExtraDestination] = []) async -> Bool {
        guard !isLive else { return true }
        armDestination(destination)
        armExtras(additional)
        guard arm(film: film) else { return false }
        // THE CAMERA AND THE MICROPHONE ARE ASKED FOR HERE (§D11), before the
        // engine is built, because `attachCameraIfAvailable` reads the
        // authorization status and returns silently when it is not yet
        // `.authorized` — which on macOS it always was, since nothing in the
        // product path had ever asked.
        _ = await requestCaptureAccess()
        if let p = surfacePlayer, surfaceArchiveID == film.archiveID {
            await attachIfArmed(player: p, archiveID: film.archiveID)
        }
        return isLive
    }

    /// Called by the player surface once it has an `AVPlayer` for the armed
    /// film. A no-op unless this is the film the host armed — a host who goes
    /// live on one title and then plays another has not armed the second.
    public func attachIfArmed(player: AVPlayer, archiveID: String) async {
        guard armedFilmID == archiveID, !isLive else { return }
        armedFilmID = nil
        localPlayer = player
        awdiag("AWSURFACE engine attaching to player=%lx",
               UInt(bitPattern: ObjectIdentifier(player).hashValue))

        let e = StudioEngine(configuration: .benchDoored())
        engine = e
        // §D22 — a host who set up chat before pressing anything keeps it.
        // §D24 — the guests' framing survives going live, like every other
        // armed value (§8.46).
        await e.setGuestFraming(armedGuestFraming)
        if let c = armedChat {
            await e.setChatControls(enabled: c.enabled, side: c.side, filter: c.filter)
        }
        #if os(macOS)
        // §D23 — AND THE GUESTS. Going live ENDS the rehearsal and builds a
        // second engine, so a source attached to the first one reaches
        // nothing: a host who framed their call during the preview would have
        // pressed Go Live and silently dropped it, with the capture still
        // running and the tile simply gone from the broadcast. Decision 133
        // in its purest form, and the same shape as `armedChat` two lines up
        // — which is the argument for every armed value being re-applied in
        // ONE place rather than remembered by each caller.
        if let src = screenSource {
            await e.attachGuests(src.sink)
        }
        #endif
        await e.attachFilm(player: player)
        // SAY WHETHER THE FILM'S AUDIO ACTUALLY ATTACHED. A file played through
        // AW_PLAY_URL reaches the video output and its audio does not reach the
        // tap, and nothing on this path said so — picture and sound take
        // different routes here, and only one of them was reporting.
        let srcTracks = ((try? await player.currentItem?.asset
            .loadTracks(withMediaType: .audio)) ?? [])?.count ?? -1
        // WHEN the tap is installed, not just whether. A local file is playing
        // within milliseconds; a catalog film is still loading for seconds.
        // If `item.audioMix` only takes effect before audio begins rendering,
        // that difference alone would explain why films carry audio through the
        // tap and an AW_PLAY_URL file does not — same code, different timing.
        awdiag("AWMACAUDIO filmHasAudio=%@ sourceAudioTracks=%d rate=%.2f at=%.2f url=%@",
               await e.filmHasAudio ? "true" : "false", srcTracks,
               player.rate, player.currentTime().seconds.isFinite
                   ? player.currentTime().seconds : -1,
               (player.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? "?")
        await e.setLayout(armedLayout)
        await e.setCameraFraming(armedFraming)
        // A FRESH OVERLAY, but not a forgetful one: the card a scene put up
        // before the engine existed, and the lower-third lines the host
        // turned off, both used to vanish here (measured: a Studio opened on
        // Intermission broadcast the film with no card).
        let card = overlay.card
        overlay = StudioOverlay()
        overlay.title = lowerThirdLines.title ? armedTitle : ""
        overlay.subtitle = lowerThirdLines.meta ? armedSubtitle : ""
        overlay.provenance = lowerThirdLines.provenance ? (armedProvenance ?? "") : ""
        overlay.card = card
        await e.setOverlay(overlay)
        await e.setAudio(filmGain: mix.filmGain, micGain: mix.micGain,
                         filmMuted: mix.filmMuted, micMuted: mix.micMuted,
                         duckEnabled: mix.duckEnabled,
                         callGain: mix.callGain, callMuted: mix.callMuted,
                         micGateEnabled: mix.micGateEnabled,
                         micGateThreshold: mix.micGateThreshold)
        awdiag("AWARMED re-applied card=%@ micMuted=%@ filmGain=%@",
               card == nil ? "none" : "yes",
               mix.micMuted.map { $0 ? "yes" : "no" } ?? "default",
               mix.filmGain.map { String(format: "%.2f", $0) } ?? "default")

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
            // REDACTED: this line printed the full stream key for every platform
            // show (found 2026-09-23 on a YouTube run) — §5 says never.
            diag("[AWSTUDIOSTART] starting engine destination=\(dest.map { redactingKey($0) } ?? "none")")
            #if DEBUG
            // AW_STUDIO_FAIL_START=1 — a start that fails AFTER the platform
            // broadcast was created, to prove the never-live tidy-up.
            if ProcessInfo.processInfo.environment["AW_STUDIO_FAIL_START"] == "1" {
                throw StudioPlatformError.badResponse("forced start failure (AW_STUDIO_FAIL_START)")
            }
            #endif
            try await e.start(destination: dest, additional: armedExtras)
            diag("[AWSTUDIOSTART] engine started")
        } catch {
            // SAY IT. This set `refusal` and returned, logging NOTHING — so a
            // Studio that failed to start looked identical in the log to one
            // that started fine and published nothing: camera attached, film
            // attached, and then silence. Found 2026-09-21 running the macOS
            // bench door against a local server, where the whole run produced
            // zero AWPUB and zero AWSTUDIOHEALTH lines and no reason for it.
            // The same hole as AWPUB (§9.19) and AWAUTH.
            diag("[AWSTUDIOSTART] FAILED: \(error)")
            // The broadcast was CREATED before the engine failed to start;
            // left alone it is an orphan in the host's "Upcoming".
            await completeArmedBroadcast()
            refusal = "The Studio could not start — \(error)"
            engine = nil
            return
        }
        // YOUTUBE CHAT, if this broadcast has one. The id came back from the
        // `liveBroadcasts.insert` that created it and rode here on
        // `StudioGoLive.Destination` — before that it was read and dropped in
        // the same function, which is why the renderer has been drawing a
        // chat column that only Twitch could ever fill.
        await attachYouTubeChatIfArmed(to: e)
        // TWITCH CHAT IS THE HOST'S OWN CHANNEL, and there is no other
        // acceptable source (§D22).
        //
        // Until 2026-09-22 this read `AW_STUDIO_CHAT` and NOTHING ELSE, on all
        // three surfaces, with a comment saying the channel would come from
        // the host's account "once sign-in exists". Sign-in has existed since
        // 09-18. So the product had no Twitch chat at all, and the only way to
        // see the column was to name somebody else's channel — which is what
        // a test of mine did, putting strangers' messages over the owner's
        // film. Their question is what found it: *"shouldn't it only display
        // the chat coming through on that particular stream?"* Yes. YouTube
        // could not get this wrong — its `liveChatId` comes back from the
        // insert that CREATED this broadcast — and Twitch takes a channel by
        // name, which is exactly why it needed the account asked for.
        //
        // `twitchAccount()` is the same read the readiness gate already makes,
        // so this costs no new call shape and no new credential.
        if showGoesToTwitch, let account = try? await StudioPlatformAuth.twitchAccount() {
            await e.attachTwitchChat(channel: account.login)
            diag("[AWSTUDIOCHAT] reading this broadcast's own channel #\(account.login)")
        } else if let channel = ProcessInfo.processInfo.environment["AW_STUDIO_CHAT"],
                  !channel.isEmpty {
            // A DEBUG DOOR, and §D22a now means it can only ever fill a column
            // on a show that is REALLY ON AIR — the pump refuses otherwise. It
            // survives because reading Twitch needs no credential and a bench
            // destination is still a broadcast, so the column can be measured
            // against a local server without a platform account.
            //
            // It must never be the path a host takes: somebody else's chat
            // over your film is not your show. That is not a hypothetical —
            // it is what this door did on 2026-09-22, and the owner caught it.
            let name = channel.replacingOccurrences(of: "#", with: "")
            await e.attachTwitchChat(channel: name)
            diag("[AWSTUDIOCHAT] DEBUG DOOR reading somebody else's channel #\(name) "
                 + "— not signed in to Twitch, so this is NOT what a host would see")
        }
        // §D26's audience, INVENTED rather than borrowed. See `setDemoChat`.
        if ProcessInfo.processInfo.environment["AW_STUDIO_CHAT_DEMO"] == "1" {
            await e.setDemoChat(StudioSession.demoConversation)
            diag("[AWSTUDIOCHAT] DEMO DOOR — an invented conversation, nobody's real words")
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
        selectCallAudioIfAsked()
    }

    /// THE CALL TAP, DRIVEN WITHOUT CLICKING — DEBUG only.
    ///
    ///   AW_STUDIO_CALL="Google Chrome"
    ///
    /// §D18's question is whether a SIGNED, SANDBOXED Archive Watch actually
    /// receives another app's audio, and that cannot be answered by a harness
    /// (§8.21 ran as a command-line tool under the terminal's grants — the
    /// exact gap Decision 130 names). It has to be the product, and the
    /// product's own picker is a two-coordinate click into a popup menu, which
    /// is not a repeatable measurement. This is the same door `AW_STUDIO_CARD`
    /// and `AW_STUDIO_DEST` are, for the same reason.
    private func selectCallAudioIfAsked() {
        #if DEBUG && os(macOS)
        guard #available(macOS 14.2, *),
              let want = ProcessInfo.processInfo.environment["AW_STUDIO_CALL"],
              !want.isEmpty else { return }
        let apps = StudioAudioProcesses.all()
        awdiag("AWCALL door wants=%@ offered=[%@]", want,
               apps.map(\.name).joined(separator: ", "))
        guard let match = apps.first(where: { $0.name == want })
                ?? apps.first(where: { $0.name.localizedCaseInsensitiveContains(want) }) else {
            awdiag("AWCALL door: nothing in the list matches %@", want)
            return
        }
        Task {
            let problem = await startCallAudio(process: match)
            awdiag("AWCALL door selected=%@ pid=%d objects=%d problem=%@",
                   match.name, match.pid, match.objectIDs.count, problem ?? "none")
        }
        #endif
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

    // MARK: - Permission, and changing a device mid-show (macOS-DESIGN §D11)

    /// What macOS/iOS will let the Studio see and hear, as four distinct
    /// states rather than one silent `return`.
    ///
    /// THE RULE THIS REPLACES: every Apple path here said "the Studio REPORTS,
    /// never REQUESTS", and that came from tvOS, where raising a system prompt
    /// on a television in someone's living room is a real intrusion. Carried
    /// to the Mac it meant `authorizationStatus` sat at `.notDetermined` for
    /// the life of the product, because nothing in the macOS product path has
    /// ever called `requestAccess` — only `StudioLab` (DEBUG), the iOS go-live
    /// sheet and the tvOS one do. So the Studio's camera row read
    /// **"not attached"** forever and there was no way for a host to change
    /// that from inside the app. Owner, 2026-09-22: *"I cannot seem to attach
    /// any cameras (not even the facetime camera) to the studio."*
    public enum CaptureAccess: Sendable, Equatable {
        case notAsked, granted, denied, restricted
    }

    public static func access(for media: AVMediaType) -> CaptureAccess {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notAsked
        @unknown default: return .denied
        }
    }

    /// Ask for the camera and the microphone, then rebuild whatever is running.
    ///
    /// EXPLICIT, never on opening a window: this is called when the host starts
    /// a preview, goes live, or presses the row's own "Allow" button. A camera
    /// light that comes on because somebody opened a window is a surprise, not
    /// a feature — that reasoning stands; what did not stand was never asking
    /// at all.
    @discardableResult
    public func requestCaptureAccess() async -> (camera: CaptureAccess, microphone: CaptureAccess) {
        #if os(macOS) || os(iOS)
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        // A grant that arrives DURING a show has to reach the show. Without
        // this, allowing the camera mid-broadcast would store a TCC answer and
        // change nothing visible until the next one.
        if isLive { await rebuildCapture() }
        #endif
        return (Self.access(for: .video), Self.access(for: .audio))
    }

    /// Swap the camera or the microphone while the show is running (§D11).
    ///
    /// §D2 used to say "device changes take effect on the next broadcast", and
    /// the Studio disabled both pickers while live on the strength of it. The
    /// fact behind that sentence is true — an `AVCaptureSession` is configured
    /// once — and the conclusion drawn from it was not. **The capture session
    /// is not the encoder.** The camera tile is COMPOSITED into the program, so
    /// the wire never learns which device produced those pixels; §D4's
    /// "not while live" belongs to resolution and frame rate, which an RTMP
    /// ingest genuinely will not accept mid-publish, and does not reach here.
    ///
    /// So this tears the session down and builds a new one in place. The
    /// engine keeps running throughout: `attachCamera(tap:)` and
    /// `attachMicrophone(tap:)` REPLACE the tap rather than adding one, and a
    /// program with no camera frames for a moment draws the film alone, which
    /// is Rule 8.8's normal state rather than a fault.
    public func rebuildCapture() async {
        #if os(macOS) || os(iOS)
        guard let engine else { return }
        capture?.stopRunning()
        capture = nil
        await attachCameraIfAvailable(to: engine)
        #endif
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
        // THE HOST'S CHOSEN CAMERA (macOS-DESIGN §D2), resolved in ONE place.
        //
        // This used to be `AVCaptureDevice.default(for: .video)` with an iOS
        // front-camera special case inline. `StudioDevices.resolveCamera()`
        // owns both, so the picker's value lands HERE — at the capture
        // session — rather than in a preference nothing reads, which is the
        // defect Decision 133 is entirely about.
        let (preferred, cameraFellBack) = StudioDevices.resolveCamera()
        if cameraFellBack {
            awdiag("AWCAM chosen camera is GONE — falling back to the system default")
        }
        guard let cam = preferred,
              let input = try? AVCaptureDeviceInput(device: cam) else {
            awdiag("AWCAM no camera tile: %@",
                   StudioDevices.chosenCameraID == StudioDevices.noneID
                   ? "the host chose None" : "authorized but no usable capture device")
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        // THE PRESET GOES AFTER THE INPUT, AND A BORROWED PHONE GETS NONE.
        //
        // This path set `.hd1280x720` BEFORE any input existed, which is the
        // exact sequence that killed every Continuity broadcast on tvOS
        // (2026-09-19, reproduced twice): the failure does not surface at the
        // assignment but later, when something forces the device to
        // renegotiate, as an ObjC exception no Swift `try` can catch —
        // `-[AVCaptureDevice _setActiveFormat:…sessionPreset:] Unsupported
        // format ((null))`, signal 6. tvOS was fixed in `StudioContinuity`;
        // this path was not, and macOS reaches the SAME device class, because
        // an iPhone used as a Mac's camera is a Continuity Camera.
        // `canSetSessionPreset` is not the gate — it answered TRUE for
        // .hd1280x720 on a Continuity camera and threw anyway.
        //
        // A built-in camera keeps the preset: the tile is never full-frame, so
        // capturing 1080p to draw a corner box is work nobody sees. Only the
        // borrowed-phone case surrenders format control, and it costs nothing
        // — the tile is scaled to its layout slot downstream regardless.
        var borrowedPhone = false
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            borrowedPhone = cam.deviceType == .continuityCamera || cam.deviceType == .external
        }
        //
        // `.inputPriority` IS UNAVAILABLE ON macOS, which is the platform this
        // fix is most for. The macOS equivalent of "stop dictating a format"
        // is to leave the preset alone: the default `.high` NEGOTIATES the
        // best the device offers instead of demanding a specific size, so it
        // has no exact format to fail to find. Same intent, different verb.
        let presetName: String
        if borrowedPhone {
            #if os(macOS)
            presetName = "high (negotiated)"      // leave it at the default
            #else
            session.sessionPreset = .inputPriority
            presetName = "inputPriority"
            #endif
        } else {
            session.sessionPreset = .hd1280x720
            presetName = "hd1280x720"
        }
        awdiag("AWCAM preset=%@ device=%@", presetName, cam.localizedName)
        // The host's chosen MICROPHONE, same rule (§D2).
        let (chosenMic, micFellBack) = StudioDevices.resolveMicrophone()
        if micFellBack { awdiag("AWCAM chosen microphone is GONE — using the system default") }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = chosenMic,
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            awdiag("AWCAM microphone=%@", mic.localizedName)
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

    /// Ends the armed YouTube broadcast, if any. EVERY platform's End calls
    /// this BEFORE its engine stops: YouTube accepts `complete` only from
    /// `live`, and it used to run after the publisher had closed, so every
    /// End answered 403 `invalidTransition` and left an unlisted broadcast in
    /// the host's "Live now". iOS and tvOS arm the id here and run their own
    /// engines (Decision 133), so they never reached it at all.
    ///
    /// It may not fail an end: telling YouTube is a courtesy that can fail for
    /// a dozen reasons, and none of them should leave a show half torn down.
    /// §D34 — a room for the friends on the host's call, opened on the
    /// player the SHOW is using. SHAREPLAY §11.13: "hosting stays where the
    /// broadcast is", and on macOS the broadcast is the Studio.
    public func openFriendsRoom() async -> (code: String?, problem: String?) {
        guard let p = surfacePlayer, let id = surfaceArchiveID else {
            return (nil, "There is no film in the Studio to share.")
        }
        let code = await StudioRoomHost.shared.start(player: p, filmID: id)
        return (code, StudioRoomHost.shared.problem)
    }

    /// The program still as this YouTube broadcast's thumbnail (owner,
    /// 2026-09-23: broadcasts without one "look like a failed video").
    func uploadThumbnail(_ jpeg: Data) async {
        guard let id = armedBroadcastID else { return }
        do {
            try await YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
                .setThumbnail(videoID: id, jpeg: jpeg)
            awdiag("AWTHUMB set %@ (%d KB)", id, jpeg.count / 1024)
        } catch {
            awdiag("AWTHUMB not set %@ — %@", id, "\(error)")
        }
    }

    // MARK: §D35 — recording

    public private(set) var recordingSince: Date?
    public private(set) var lastRecording: URL?
    public private(set) var recordingProblem: String?

    public func startRecording(to url: URL) async {
        guard let engine else { recordingProblem = "Start the preview or go live first."; return }
        do {
            try await engine.startRecording(to: url)
            recordingSince = Date()
            recordingProblem = nil
            awdiag("AWRECORD started %@", url.lastPathComponent)
        } catch {
            recordingProblem = "\(error)"
            awdiag("AWRECORD refused — %@", "\(error)")
        }
    }

    public func stopRecording() async {
        guard let engine else { recordingSince = nil; return }
        let url = await engine.stopRecording()
        recordingSince = nil
        lastRecording = url
        awdiag("AWRECORD finished %@", url?.lastPathComponent ?? "(nothing written)")
    }

    public func completeArmedBroadcast() async {
        audienceTask?.cancel(); audienceTask = nil
        audienceCount = nil
        let armed = armedBroadcastID
        armedBroadcast = nil
        guard let broadcast = armed, !broadcast.isEmpty else { return }
        do {
            let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
            do {
                try await yt.complete(broadcastID: broadcast)
                diag("[AWSTUDIOEND] YouTube broadcast \(broadcast) marked complete")
            } catch {
                let state = (try? await yt.lifeCycleStatus(broadcastID: broadcast)) ?? "unknown"
                // A BROADCAST THAT NEVER WENT LIVE IS DELETED, not left. YouTube
                // refuses `complete` except from `live`, so a go-live that
                // failed — or a show ended before any video arrived — left a
                // scheduled broadcast in the host's "Upcoming" forever (owner,
                // 2026-09-23: "some videos that are set for the future are
                // orphaned"). Only THIS show's own id is ever touched.
                if ["created", "ready", "testStarting", "testing"].contains(state) {
                    do {
                        try await yt.delete(broadcastID: broadcast)
                        diag("[AWSTUDIOEND] YouTube broadcast \(broadcast) never went live (\(state)) — deleted")
                    } catch {
                        diag("[AWSTUDIOEND] could not delete never-live broadcast \(broadcast) — \(error)")
                    }
                } else {
                    diag("[AWSTUDIOEND] could not end the YouTube broadcast (status=\(state)) — \(error)")
                }
            }
        } catch {
            diag("[AWSTUDIOEND] could not end the YouTube broadcast — \(error)")
        }
    }

    public func end() async {
        // A room exists to serve the stream (SHAREPLAY §11.13); it closes with it.
        StudioRoomHost.shared.stop()
        // THE BROADCAST ENDS WITH THE SHOW. Taken BEFORE the teardown so the
        // id cannot be lost by anything below, and awaited rather than fired
        // into a Task: a host who presses End and quits should not race a
        // network call that ends their broadcast.
        await completeArmedBroadcast()
        armedYouTubeChatID = nil
        armedExtras = []

        capture?.stopRunning()
        capture = nil
        pump?.cancel(); pump = nil
        // THE PLAYER THE SURFACE LEFT ALONE (§D12a). A surface that is torn
        // down during a live show no longer destroys its player, because the
        // engine may be reading it — so the show has to, or the owner's
        // original complaint comes back: "the movie seems to keep playing in
        // the background ... and there is no way to stop the audio at all".
        // Only when the surface is already gone: a show that ends while the
        // player is still on screen must leave it playing.
        if surfacePlayer !== localPlayer {
            localPlayer?.pause()
            localPlayer?.replaceCurrentItem(with: nil)
        }
        localPlayer = nil
        if recordingSince != nil { recordingSince = nil }
        if let engine { await engine.stop() }
        engine = nil
        isLive = false
        onAirSince = nil
        sendingBitsPerSecond = 0
        lastBytesSent = 0
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
        // AND THE FILE, or this is unreadable on a device. stderr is captured
        // when the Mac app is launched from a terminal and NOWHERE on a phone:
        // `devicectl ... copy from` pulls `DiagFile`, and `--console` captures
        // stdout only. So the publisher's queue depth and drop counters — the
        // only numbers that can tell congestion from a comfortable stream —
        // existed on every platform and could be read on exactly one.
        //
        // Found 2026-09-20 by running §6.4 against an iPhone, watching the
        // stream sail through a 400 kbps window, and having no way to ask the
        // publisher whether it had noticed (§9.zzzzz).
        DiagFile.log(line)
        #endif
    }

    private func startPump() {
        pump?.cancel()
        pump = Task { [weak self] in
            var lastFilmFrames = 0
            var lastCameraFrames = 0
            var stall = CameraStallRecovery()
            var filmStalled = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let engine = self.engine else { return }
                await engine.refreshHealth()
                let h = await engine.health
                self.filmFramesPerSecond = max(0, h.filmFramesPulled - lastFilmFrames)
                // §4's provenance line — macOS never had the 20-second rule
                // either; it lived in tvOS's view loop alone.
                _ = await engine.expireProvenanceIfDue()
                // §D26 — twelve seconds, on the same beat. The MIRROR is
                // updated whether or not it expired, because the host's Clear
                // button has to disappear when the clock takes the banner
                // down on its own.
                await engine.expireShoutOutIfDue()
                self.shoutOut = await engine.currentShoutOut
                self.chatRecent = h.chatRecent
                self.cameraFramesPerSecond = max(0, h.cameraFramesReceived - lastCameraFrames)
                // RECOVER A CAMERA THAT STOPPED — macOS and iOS had the
                // WARNING and no recovery, while tvOS had both. macOS can use
                // an iPhone as its camera exactly as the television can, so it
                // drops in exactly the same way; the difference was only that
                // the rebuild had been written inside tvOS's own view loop.
                if stall.tick(attached: h.cameraAttached,
                              framesReceived: h.cameraFramesReceived,
                              framesPerSecond: self.cameraFramesPerSecond,
                              onAir: h.showState.isOnAir) {
                    awdiag("AWCAM camera stopped at %d frames — recovery attempt %d of %d",
                           h.cameraFramesReceived, stall.attempts,
                           CameraStallRecovery.maximumAttempts)
                    let session = await StudioSession.attachHostCamera(to: engine)
                    awdiag("AWCAM recovery %d: %@", stall.attempts,
                           session != nil ? "re-attached" : "no camera")
                }
                // THE FILM'S OWN STALL, named. Three seconds, because one is
                // a hiccup on a 24 fps transfer and the readout already shows
                // the rate; and never while the film has simply ended, which
                // has its own sentence (§D13).
                if self.filmFramesPerSecond == 0, !h.filmEnded {
                    filmStalled += 1
                } else {
                    filmStalled = 0
                    if self.filmProblem != nil { self.filmProblem = nil }
                }
                if filmStalled == StudioFilmStall.secondsBeforeNaming {
                    let p = self.localPlayer
                    let item = p?.currentItem
                    let why = StudioFilmStall.reason(.init(
                        hasPlayer: p != nil,
                        hasItem: item != nil,
                        rate: p?.rate ?? 0,
                        likelyToKeepUp: item?.isPlaybackLikelyToKeepUp ?? false,
                        errorDescription: item?.error?.localizedDescription))
                    self.filmProblem = why
                    awdiag("AWFILM stalled: %@ (rate=%.2f item=%@ player=%lx)",
                           why, p?.rate ?? -1, item == nil ? "nil" : "present",
                           p.map { UInt(bitPattern: ObjectIdentifier($0).hashValue) } ?? 0)
                    if let engine = self.engine {
                        awdiag("AWFILM stalled output: %@", await engine.filmDiagnostics())
                    }
                }
                lastCameraFrames = h.cameraFramesReceived
                lastFilmFrames = h.filmFramesPulled
                // THE ON-AIR CLOCK starts when the server accepts the stream,
                // not when the host pressed Go Live — the minutes a host
                // counts are the ones the audience could see. A reconnect
                // does not restart it; the show did not start over.
                if onAirSince == nil, h.hasDestination, h.publisher.state == .publishing {
                    onAirSince = Date()
                }
                let sent = h.publisher.bytesSent
                sendingBitsPerSecond = sent >= lastBytesSent ? (sent - lastBytesSent) * 8 : 0
                lastBytesSent = sent
                self.health = h
                #if DEBUG
                // macOS PLATFORM PROOF DOORS — the iPhone's, on the loop
                // macOS actually runs (Decision 133). Each fires once, at T s
                // on air: AW_STUDIO_MAC_READBACK logs what YouTube HOLDS;
                // AW_STUDIO_MAC_SHARECHAT presses the Studio's own
                // "Share the film in chat" path.
                // AW_STUDIO_MAC_RECORD="5@40": record from 5 s to 40 s of the
                // engine running, into the app's own tmp (the sandbox's only
                // unasked-for writable place), through startRecording itself.
                if let v = ProcessInfo.processInfo.environment["AW_STUDIO_MAC_RECORD"] {
                    recordTicks += 1
                    let parts = v.split(separator: "@").compactMap { Int($0) }
                    if parts.count == 2 {
                        if recordTicks == parts[0] {
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("aw-record-proof.mp4")
                            Task { await self.startRecording(to: url) }
                        }
                        if recordTicks == parts[1] { Task { await self.stopRecording() } }
                    }
                }
                if h.hasDestination, h.publisher.state == .publishing {
                    proofTicks += 1
                    let env = ProcessInfo.processInfo.environment
                    if let t = env["AW_STUDIO_MAC_READBACK"].flatMap(Int.init), proofTicks == t {
                        Task { await self.debugLogBroadcast() }
                    }
                    // AW_STUDIO_MAC_PAUSE="20@35": Broadcast ▸ Pause the Film's
                    // own function at each tick, so a room's paused flag can be
                    // read back from the Worker, from outside the app.
                    if let v = env["AW_STUDIO_MAC_PAUSE"],
                       v.split(separator: "@").compactMap({ Int($0) }).contains(proofTicks) {
                        self.toggleFilmPlayback()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1))
                            awdiag("AWPAUSE door toggled at %d filmIsPlaying=%@ room=%@",
                                   self.proofTicks, self.filmIsPlaying ? "y" : "n",
                                   StudioRoomHost.shared.code ?? "none")
                        }
                    }
                    if let t = env["AW_STUDIO_MAC_SHARECHAT"].flatMap(Int.init), proofTicks == t {
                        Task {
                            let problem = await self.shareFilmInChat()
                            awdiag("AWCHATSHARE door result=%@", problem ?? "posted")
                        }
                    }
                }
                #endif

                // IS THE FILM'S AUDIO ACTUALLY GOING OUT? Asked every tick,
                // because the answer changes: the warning is true only until
                // audio starts arriving. Detected once — the asset does not
                // grow an audio track mid-show — and treated as "say nothing"
                // when it cannot be determined.
                self.filmAudioProblem = await engine.filmAudioProblem(
                    sourceHasAudio: engine.sourceHasAudio)
                // §D16 — DOES THIS FILM HAVE A SOUNDTRACK AT ALL?
                //
                // Separate from `filmAudioProblem`, which is about the tap
                // failing to attach. This one is not a fault: a transfer with
                // no audio track is a real and legitimate thing in this
                // catalog, and the host needs to know because the
                // CONSEQUENCE is theirs — their voice will be the only sound
                // the audience hears.
                //
                // Measured on the product path before it was written: Buster
                // Keaton's "The Scarecrow" (1920) reports
                // `filmHasAudio=false sourceAudioTracks=0`. Most transfers of
                // silent films DO carry a score (six probed, six with AAC), so
                // this is the exception rather than the rule — which is
                // exactly why it has to be said rather than assumed.
                self.filmHasNoSoundtrack = (await engine.sourceHasAudio) == false
                // §D18 — the call tap is OPEN and delivering NOTHING.
                self.updateCallSilence()
                // AND SAY IT IN A LINE A HARNESS CAN READ. The mixer's meter
                // answers "is there sound"; it cannot answer "did ANY sample
                // ever arrive", which is the question a process tap's TCC
                // outcome actually turns on. A photograph of a still meter has
                // never distinguished the two.
                #if os(macOS)
                if #available(macOS 14.2, *), let t = self.callTap as? StudioCallAudioTap {
                    awdiag("AWCALL app=%@ samples=%d level=%.4f running=%@",
                           self.callAppName ?? "?", t.samplesReceived,
                           h.audio.callLevel, t.isRunning ? "true" : "false")
                }
                #endif


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
    /// Everything the host set that a NEW engine must be given (§D23a):
    /// the mix, and which lower-third lines are on. The card rides `overlay`.
    private struct Mix {
        var filmGain: Float?, micGain: Float?, callGain: Float?
        var filmMuted: Bool?, micMuted: Bool?, callMuted: Bool?
        var duckEnabled: Bool?, micGateEnabled: Bool?, micGateThreshold: Float?
    }
    private var mix = Mix()
    private var lowerThirdLines = (title: true, meta: true, provenance: true)

    /// WHICH LINES THE LOWER THIRD CARRIES (§D15).
    ///
    /// Owner, 2026-09-22: *"you should be able to choose the information that
    /// shows up on the lower third."* One toggle used to draw all three lines
    /// or none.
    ///
    /// What a host may choose is WHICH of the catalog's own verified facts
    /// to show — never to retype them. §2.1's argument is that the audience
    /// learns what the film IS, and a free-text title over a public-domain
    /// film is how an audience learns something false.
    ///
    /// The provenance line keeps §4's 20-second expiry, which stays gated on
    /// a real broadcast rather than a rehearsal (owner: *"it is fine to leave
    /// it as only expiring on a 'live stream', but it should be able to be
    /// manipulated as a part of the lower third"*). So this toggle is the
    /// override in both directions: off means never drawn, on means drawn
    /// until the rule takes it away.
    public func setLowerThird(title: Bool, meta: Bool, provenance: Bool) async {
        lowerThirdLines = (title, meta, provenance)
        overlay.title = title ? armedTitle : ""
        overlay.subtitle = meta ? armedSubtitle : ""
        overlay.provenance = provenance ? (armedProvenance ?? "") : ""
        await engine?.setOverlay(overlay)
    }

    public func setCard(_ card: StudioOverlay.Card?) async {
        overlay.card = card
        await engine?.setOverlay(overlay)
    }

    public func setLayout(_ layout: StudioLayout) async { await engine?.setLayout(layout) }
    public func beginTransition(seconds: Double) async { await engine?.beginTransition(seconds: seconds) }
    /// §D4: the bitrate is the only output setting a live show accepts.
    public func setVideoBitrate(_ bps: Int) async { await engine?.setVideoBitrate(bps) }
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
                         duckEnabled: Bool? = nil,
                         callGain: Float? = nil, callMuted: Bool? = nil,
                         micGateEnabled: Bool? = nil,
                         micGateThreshold: Float? = nil) async {
        // KEPT, not only forwarded (§D23a). `engine?` drops a value when no
        // engine exists, and going live builds a SECOND one — so a host who
        // muted their microphone during the preview went out unmuted.
        if let v = filmGain { mix.filmGain = v }
        if let v = micGain { mix.micGain = v }
        if let v = filmMuted { mix.filmMuted = v }
        if let v = micMuted { mix.micMuted = v }
        if let v = duckEnabled { mix.duckEnabled = v }
        if let v = callGain { mix.callGain = v }
        if let v = callMuted { mix.callMuted = v }
        if let v = micGateEnabled { mix.micGateEnabled = v }
        if let v = micGateThreshold { mix.micGateThreshold = v }
        await engine?.setAudio(filmGain: filmGain, micGain: micGain,
                               filmMuted: filmMuted, micMuted: micMuted,
                               duckEnabled: duckEnabled,
                               callGain: callGain, callMuted: callMuted,
                               micGateEnabled: micGateEnabled,
                               micGateThreshold: micGateThreshold)
    }

#if os(macOS)
    // MARK: The call's audio (§D2, Decision 131)

    /// The app whose audio is being mixed into the show, and why it is not.
    ///
    /// `callProblem` exists for the same reason the camera's does: "no
    /// conversation is being captured" and "nobody is talking" are different
    /// facts, and a host must be able to tell them apart BEFORE they start
    /// speaking to an audience that cannot hear their guests.
    public private(set) var callAppName: String?
    public private(set) var callProblem: String?

    /// Begin capturing a named app's audio. Idempotent: choosing the same app
    /// twice does not stack two taps on it.
    @discardableResult
    public func startCallAudio(process: StudioAudioProcesses.Process) async -> String? {
        guard #available(macOS 14.2, *) else {
            callProblem = "Capturing another app's audio needs macOS 14.2 or later."
            return callProblem
        }
        stopCallAudio()
        let tap = StudioCallAudioTap(programRate: 44100)
        if let why = tap.start(process: process) {
            callProblem = why
            diag("[AWCALL] could not tap \(process.name): \(why)")
            return why
        }
        callTap = tap
        callAppName = process.name
        callProblem = nil
        callSilentSince = Date()
        // Synchronous, for the same reason the clear above is: the two must
        // not be able to land out of order (§D18).
        engine?.attachCallAudio(ring: tap.ring)
        diag("[AWCALL] capturing \(process.name) (\(process.bundleID))")
        return nil
    }

    public func stopCallAudio() {
        guard #available(macOS 14.2, *) else { return }
        (callTap as? StudioCallAudioTap)?.stop()
        callTap = nil
        callAppName = nil
        callSilentSince = nil
        // SYNCHRONOUSLY (§D18). This was `Task { await engine?.attachCallAudio(ring: nil) }`,
        // and `startCallAudio` calls `stopCallAudio()` FIRST — so the order
        // was: enqueue "clear the ring", attach the new ring, return, and THEN
        // the enqueued clear ran and took the channel away again. The owner
        // saw exactly that: "it appeared in the mixer for a second and then
        // disappeared."
        //
        // `attachCallAudio` is `nonisolated`, so there was never a reason to
        // wrap it — the `Task` bought nothing and cost the ordering.
        engine?.attachCallAudio(ring: nil)
    }

    /// When the call tap last had NO audio at all. Nil means it is delivering,
    /// or is not running. §D18: a level of zero is a legitimate reading (a
    /// quiet room); no SAMPLES at all is an absence, and the two must not draw
    /// the same.
    private var callSilentSince: Date?

    /// Held as `AnyObject` so this stored property needs no availability
    /// annotation — a `@available` stored property is not allowed here.
    private var callTap: AnyObject?
#endif
}
