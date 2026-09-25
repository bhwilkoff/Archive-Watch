#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// NavigationSplitView shell (docs/macOS-DESIGN.md §7): sidebar sections + a detail column
// that drills into Detail / Person / Collection. The player presents as a sheet over the
// detail column. Creation Studio gets its own DocumentGroup scene in a later phase.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    /// The Studio is its own scene (§D1), so reaching it is `openWindow`.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The player REPLACES the browse UI as the window root while playing (not an overlay on the
        // split view) — otherwise the split view keeps owning the window toolbar, so its sidebar toggle
        // + the previous view's title bled through over the player. As the root, the player's own
        // NavigationStack title (the movie) + its X button are the only window chrome.
        Group {
            if let item = router.nowPlaying {
                PlayerWindow(item: item)
            } else if let ctx = router.nowPlayingEpisode {
                EpisodePlayer(context: ctx)
            } else {
                browse
            }
        }
        // Rule B13g's GO-LIVE SHEET IS GONE (macOS-DESIGN §D9). It was
        // presented by the window root, over the player, and configured a
        // Studio that lives in a different window — which is how the owner
        // came to find it by accident: "I think I may have found it hidden
        // behind a button on the video player (rather than in the studio for
        // some reason)." Everything it carried is now the Studio's Output
        // column, in the order a host reads it. The menu command and the
        // player's toolbar button remain and both OPEN THE STUDIO.
        .overlay {
            if !store.isReady {
                ProgressView("Loading catalog…").controlSize(.large)
            }
        }
        // Screensaver: a real full-window, full-screen poster wall (not a nav push that keeps the
        // sidebar). Covers everything; click / Esc / the ✕ exits + leaves macOS full-screen.
        .overlay {
            if router.screensaverActive {
                ScreensaverView(onExit: { exitScreensaver() })
                    .transition(.opacity)
                    .onAppear { setFullScreen(true) }
                    .onExitCommand { exitScreensaver() }   // Esc
            }
        }
        // Screenshot/test launch hooks (the macOS analogue of the iOS/tvOS AW_START_* hooks) — inert
        // unless the env vars are set, so the shipping app is unaffected. Lets the screenshot driver
        // land on any sidebar section (AW_START_TAB) or open a specific title's Detail (AW_START_ITEM)
        // deterministically, since SwiftUI's AX tree isn't reliably scriptable from the shell.
        .task { await applyLaunchOverrides() }
        .task { CaptionCapability.shared.probe() }
        // On-device end-to-end audit of offline downloads (AW_DOWNLOAD_AUDIT=1).
        // No-op otherwise; see tools/download_audit.py.
        .task {
            guard DownloadAudit.enabled else { return }
            await DownloadAudit.run(store: store, container: modelContext.container)
        }
        // The Studio's read-only DEBUG probes; absent here until §D27 needed one.
        .task { _ = await StudioDoors.runStateProbeIfAsked() }
        #if DEBUG
        // `AW_STUDIO_SIGNIN=youtube,twitch` — puts the SAME sign-in flows the
        // Studio's rows run in front of the owner, so the Mac Studio can be
        // proved on the real platforms (owner, 2026-09-23: "Just load up the
        // login screens and I can run them"). Nothing is approved for them.
        .task {
            let wanted = (ProcessInfo.processInfo.environment["AW_STUDIO_SIGNIN"] ?? "")
                .split(separator: ",").map(String.init)
            for w in wanted {
                do {
                    switch w {
                    case "youtube":
                        awdiag("AWSIGNIN youtube: opening Google's sign-in sheet")
                        try await StudioPlatformAuth.signInToYouTube()
                        awdiag("AWSIGNIN youtube: signed in")
                    case "twitch":
                        let p = try await StudioPlatformAuth.beginTwitchSignIn()
                        awdiag("AWSIGNIN twitch: go to %@ and enter %@", p.verificationURI, p.userCode)
                        if let url = URL(string: p.verificationURI) { NSWorkspace.shared.open(url) }
                        try await StudioPlatformAuth.completeTwitchSignIn(p)
                        awdiag("AWSIGNIN twitch: signed in")
                    default: break
                    }
                } catch {
                    awdiag("AWSIGNIN %@ failed — %@", w, "\(error)")
                }
            }
        }
        #endif
        .task { WatchTogether.shared.listen() }
        // THE RED BUTTON STOPS THE FILM (§D12). Closing this window is not a
        // quit, so SwiftUI keeps the scene's state — including a playing
        // `AVPlayer` with no visible transport left to pause it, and a
        // `nowPlaying` that would re-present the film on the next open as a
        // second copy over the first. Clearing it here means re-opening lands
        // on browse, which is what the host actually left.
        .background(AWWindowCloseWatcher {
            // ONLY THE SHOW THIS WINDOW WAS CARRYING (§D12). A broadcast run
            // from the Studio window plays its film in the Studio's own SOURCE
            // pane, and `nowPlaying` is nil — so ending the show here would
            // take a host off air because they tidied away the browse window
            // they were not using. The Studio has its own close watcher for
            // the case that IS its own.
            if router.nowPlaying != nil || router.nowPlayingEpisode != nil {
                Task { await StudioSession.shared.end() }
            }
            router.nowPlaying = nil
            router.nowPlayingEpisode = nil
        })
        // A SharePlay session someone else started names a film; open it and
        // start playing so the coordinator has a player to sync. Without this the
        // Mac joined the group and then sat there — it could only ever be a
        // passive member of a session it never showed.
        //
        // Keyed on dbVersion as well as the id: a session arriving during a cold
        // launch sets pendingJoin before this view exists, and onChange only
        // fires for changes it was present for — which is exactly the
        // continuation case. Re-reading on each catalog swap also covers a film
        // held only in the full catalog, not the bundled seed.
        .task(id: store.dbVersion) { routeSharePlayJoin() }
        .onChange(of: WatchTogether.shared.pendingJoin) { routeSharePlayJoin() }
    }

    private func routeSharePlayJoin() {
        guard let id = WatchTogether.shared.pendingJoin,
              let item = store.itemsByIDs([id]).first else { return }
        WatchTogether.shared.consumePendingJoin()
        router.openDetail(item)
        router.play(item)
    }

    private func applyLaunchOverrides() async {
        let env = ProcessInfo.processInfo.environment
        // WHAT A SIGNED, SANDBOXED APP GETS FROM SCREEN RECORDING
        // (§D23). The same unknown as the process tap, answered the
        // same way: measure it on the PRODUCT path and print what
        // macOS says. A CLI probe under the terminal's own grants
        // would answer a different question (Decision 130).
        //
        //   AW_STUDIO_SCREEN=list           — what can be captured
        //   AW_STUDIO_SCREEN="Google Chrome" — try that app's window
        if let want = env["AW_STUDIO_SCREEN"], !want.isEmpty {
            Task { @MainActor in
                let windows = await StudioScreenSource.windows()
                // COUNT AND APP NAMES, NEVER TITLES. The first version of
                // this printed every capturable window's title into a log,
                // which on the owner's machine meant a Slack DM naming a
                // colleague, a Drive PDF and two admin pages. A window title
                // is other people's business; a harness only needs to know
                // whether capture WORKS.
                awdiag("AWSCREEN %d capturable window(s) across %d app(s)",
                       windows.count, Set(windows.map(\.app)).count)
                guard want != "list" else { return }
                // EXACT, and one match or none. Asked for "Google Chrome" by
                // substring this took the owner's REAL browser instead of the
                // isolated test instance and captured their screen. If an app
                // has several windows the door refuses rather than guessing.
                // A TITLE NARROWS IT, for the case the refusal below exists
                // for: several windows of one app, only one of which is the
                // call. Still exact on the APP, still refusing to guess among
                // what remains — the narrowing is the host's, not ours.
                let titleWant = env["AW_STUDIO_SCREEN_TITLE"] ?? ""
                let matches = windows.filter {
                    $0.app == want && (titleWant.isEmpty || $0.title.contains(titleWant))
                }
                guard matches.count <= 1 else {
                    awdiag("AWSCREEN %@ has %d windows — refusing to guess which",
                           want, matches.count)
                    return
                }
                guard let target = matches.first else {
                    awdiag("AWSCREEN no window for %@ — is it open and on screen?", want)
                    return
                }
                // THE PRODUCT'S OWN CHAIN, not a standalone source: the menu
                // calls `startGuests`, so this does too. A door that drives a
                // different chain cannot find the product's bugs (Decision
                // 133) — the macOS go-live door had exactly that fault.
                //
                // It waits for the engine, because `startGuests` attaches the
                // sink to it and an engine built afterwards would have none.
                var waited = 0.0
                while StudioSession.shared.engineForHarness == nil, waited < 25 {
                    try? await Task.sleep(for: .milliseconds(250)); waited += 0.25
                }
                // THE PID TOO, because the MENU passes it and §D25's audio
                // hookup is keyed on it. Without this the door started the
                // picture and no audio, which is the product's own bug
                // reproduced in the harness rather than found by it.
                let ok = await StudioSession.shared.startGuests(windowID: target.id,
                                                                label: target.app,
                                                                ownerPID: target.pid,
                                                                ownerBundleID: target.bundleID)
                awdiag("AWSCREEN start=%@ app=%@ waited=%.1fs problem=%@",
                       ok ? "true" : "FALSE", target.app, waited,
                       StudioSession.shared.guestProblem ?? "none")
                guard ok else { return }
                let src = StudioScreenSource()   // unused; kept for the reads below
                _ = src
                // FRAMES, not merely a started stream. A permitted
                // stream that delivers nothing and a refused one look
                // the same from the start call alone.
                try? await Task.sleep(for: .seconds(4))
                // READ IT AT THE ENGINE, which is where the value lands.
                let attached = await StudioSession.shared.engineForHarness?.health.guestsAttached
                awdiag("AWSCREEN engine guestsAttached=%@ problem=%@",
                       attached == true ? "true" : "FALSE",
                       StudioSession.shared.guestProblem ?? "none")
            }
        }
        guard env["AW_START_TAB"] != nil || env["AW_START_ITEM"] != nil else { return }
        for _ in 0..<160 where !store.isReady { try? await Task.sleep(for: .milliseconds(250)) }
        if let tab = env["AW_START_TAB"], let s = AppRouter.Section(rawValue: tab) {
            router.section = s
        }
        if let id = env["AW_START_ITEM"] {
            // Wait for the full DB to swap in (richer metadata + designed art than the seed).
            for _ in 0..<80 where store.itemsByIDs([id]).first == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if let it = store.itemsByIDs([id]).first {
                router.openDetail(it)
                #if DEBUG
                // `AW_ROOM_JOIN=<code>` + AW_AUTOPLAY: join a room the way the
                // join sheet hands it over (the iOS door's twin), muted.
                if let code = env["AW_ROOM_JOIN"], !code.isEmpty {
                    RoomJoin.shared.pending = code
                    RoomJoin.shared.pendingFilm = it.archiveID
                    awdiag("AWFOLLOW door will join room %@", code)
                }
                #endif
                // AW_AUTOPLAY starts playback too, so a test can reach the PLAYER
                // without clicking — the same reason the other hooks exist, and
                // the only way to verify live captions in the real app (SwiftUI
                // exposes no scriptable Play button, as noted above).
                if ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1" {
                    router.play(it)
                }
                // AW_STUDIO_MAC=1 arms Watch Together Studio and plays, so the
                // §B13d readout can be SEEN without clicking — the same reason
                // AW_AUTOPLAY exists (SwiftUI exposes no scriptable menu).
                //
                // Bounded and muted, both deliberately. A dev door that polls
                // until something clears is how a film was left playing for an
                // hour on the owner's Apple TV and routed to every HomePod
                // (WATCH-TOGETHER §9); this one ends itself and never makes a
                // sound IN THE ROOM — the PROGRAM keeps its audio, or this door
                // could never measure any. AW_STUDIO_MAC_SECONDS overrides the
                // 120 s default.
                // AW_GOLIVE_MAC=1 puts the film in the STUDIO on launch, so
                // §D9's checklist can be SEEN without a click — the same
                // reason AW_AUTOPLAY exists (SwiftUI exposes no scriptable
                // menu). It opened Rule B13g's sheet until §D9 removed it.
                if env["AW_GOLIVE_MAC"] == "1" {
                    StudioMacShow.shared.take(it, from: router)
                    openWindow(id: StudioWindowID.studio)
                }
                // THE STAGED CARD (§D19), and deliberately OUTSIDE the
                // go-live branch. Staging is a rehearsal-time act — a host
                // prepares the intermission card while the film is running —
                // so the door that exercises it must work on the path that
                // publishes NOTHING, or the only way to photograph it would be
                // to broadcast. It writes the control the PICKER writes, and it
                // is a SEPARATE variable from AW_STUDIO_CARD on purpose: a door
                // that could only set both at once could never show they are
                // two different facts.
                // REHEARSAL, through the button's own call (§D5). The doors
                // above either publish or play in the router's window; neither
                // is the path a host takes when the film stays IN the Studio,
                // which is the arrangement §D7's "the program preview beside
                // this one is unaffected" is a promise about. Without this
                // there was no way to compare the two.
                if env["AW_STUDIO_MAC_PREVIEW"] == "1" {
                    Task { @MainActor in
                        StudioMacShow.shared.take(it, from: router)
                        // THE PLACEMENT, which only the go-live door read
                        // until now. A door that ignores a variable the
                        // neighbouring door honours is a trap: it read
                        // `guestsAttached=true` and drew no tile, because
                        // `.corner` shows no guests and nothing said so.
                        if let l = StudioLayout(rawValue: env["AW_STUDIO_LAYOUT"] ?? "") {
                            StudioControls.shared.layout = l
                            StudioSession.shared.armLayout(l)
                        }
                        // The Studio's own surface needs to exist and register
                        // its player before a show can attach to it — the
                        // window has just been asked to open.
                        for _ in 0..<40 where !StudioSession.shared.isLive {
                            _ = await StudioSession.shared.beginShow(film: it, destination: nil)
                            if StudioSession.shared.isLive { break }
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                        // SILENT, like every other door — and this one was
                        // not, for nine launches. `AW_STUDIO_MAC` and the
                        // go-live door both call this; I wrote a third door
                        // and did not, so every rehearsal played the film's
                        // soundtrack out loud on the owner's Mac while they
                        // were working. The PROGRAM keeps its audio (or this
                        // door could measure none); only the room goes quiet.
                        // AW_STUDIO_MAC_SOUND=1 opts back in, matching the
                        // other doors rather than inventing a fourth spelling.
                        if env["AW_STUDIO_MAC_SOUND"] != "1" {
                            StudioSession.shared.muteLocalMonitorForHarness()
                        }
                        awdiag("AWMACDOOR preview live=%@ monitor=%@",
                               StudioSession.shared.isLive ? "true" : "FALSE",
                               env["AW_STUDIO_MAC_SOUND"] == "1" ? "audible" : "muted")
                    }
                }
                // §D24's framing, as numbers. A drag is not a repeatable
                // measurement; "tile 40% x 30%, zoom 2x" is.
                //   AW_STUDIO_GUEST_FRAME=x,y,w,h,zoom   (fractions of frame)
                if let g = env["AW_STUDIO_GUEST_FRAME"] {
                    let p = g.split(separator: ",").compactMap { Double($0) }
                    if p.count >= 5 {
                        var f = StudioCameraFraming()
                        f.tile = CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
                        f.zoom = CGFloat(p[4])
                        StudioControls.shared.guestFraming = f
                        awdiag("AWMACDOOR guest framing tile=%.2f,%.2f %.2fx%.2f zoom=%.1f",
                               p[0], p[1], p[2], p[3], p[4])
                    }
                }
                if let stage = env["AW_STUDIO_STAGE"],
                   let choice = MacCardChoice(rawValue: stage) {
                    StudioControls.shared.stagedCard = choice
                    awdiag("AWMACDOOR staged=%@", stage)
                }
                // THE macOS GO-LIVE DOOR (§9.xxxx).
                //
                // `AW_STUDIO_MAC` arms the session so the readout can be SEEN —
                // it resolves no destination and publishes nothing, which is why
                // a bench run against a local server recorded not one byte and
                // mediamtx never logged a connection. macOS could only go live
                // by hand, through the sheet, so the one thing nobody could do
                // was TEST it. This drives the same commit chain the sheet does:
                // request → StudioGoLive.destination → armDestination → arm.
                //
                //   AW_STUDIO_MAC_GOLIVE = 1 | twitch | youtube
                //   AW_STUDIO_LAYOUT     = film | corner | theatre | side | host
                //
                // Real platforms are gated exactly as the sheet gates them —
                // signed in AND ready — and every refusal NAMES itself, because
                // the tvOS version of this door returned in silence and cost a
                // round of guessing between three causes.
                let macDoor = env["AW_STUDIO_MAC_GOLIVE"] ?? ""
                if !macDoor.isEmpty {
                    // ARM BEFORE PLAYING. `arm()` only records INTENT; the
                    // engine is built in `attachIfArmed`, which the player
                    // window calls ONCE when it appears and which returns
                    // immediately unless `armedFilmID` is already set. Playing
                    // first meant the player attached to nothing, the engine
                    // was never built, and the door still logged "live" — it
                    // was reporting the intent it had just recorded. The first
                    // run this way published nothing and wrote no AWCAM line at
                    // all, which is what gave it away.
                    Task { @MainActor in
                        let layout = StudioLayout(rawValue: env["AW_STUDIO_LAYOUT"] ?? "")
                            ?? .corner
                        var dest: URL?
                        switch macDoor {
                        case "1":
                            guard let base = env["AW_STUDIO_DEST"].flatMap(URL.init(string:)) else {
                                awdiag("AWMACDOOR REFUSED: AW_STUDIO_DEST is not set")
                                return
                            }
                            dest = base.appendingPathComponent(env["AW_STUDIO_KEY"] ?? "bench")
                        case "twitch", "youtube":
                            let p: StudioPlatformAuth.Platform =
                                macDoor == "twitch" ? .twitch : .youtube
                            guard StudioPlatformAuth.isSignedIn(p) else {
                                awdiag("AWMACDOOR REFUSED: not signed in to %@", macDoor)
                                return
                            }
                            let r = try? await StudioPlatformAuth.readiness(for: p)
                            guard case .ready? = r else {
                                awdiag("AWMACDOOR REFUSED: %@ readiness=%@", macDoor,
                                       String(describing: r))
                                return
                            }
                            let req = GoLiveRequest(
                                archiveID: it.archiveID,
                                platform: macDoor == "twitch" ? .twitch : .youtube,
                                title: it.title, category: "",
                                privacy: .unlisted, layout: layout,
                                customServer: nil, customKey: nil)
                            do {
                                let d = try await StudioGoLive.destination(for: req, film: it)
                                dest = d.url
                                StudioSession.shared.armYouTubeChat(d.liveChatID)
                                StudioSession.shared.armBroadcast(d.broadcast)
                            } catch {
                                awdiag("AWMACDOOR %@ go-live FAILED: %@", macDoor,
                                       "\(error)".split(whereSeparator: { $0 == "\n" })
                                           .joined(separator: " "))
                                return
                            }
                        default:
                            awdiag("AWMACDOOR REFUSED: unknown door value %@", macDoor)
                            return
                        }
                        StudioSession.shared.armDestination(dest)
                        // AW_STUDIO_EXTRA=rtmp://… — a second destination, as
                        // the simulcast checkbox adds, so an extra's own
                        // reconnect can be proved on a bench.
                        if let x = env["AW_STUDIO_EXTRA"].flatMap(URL.init(string:)) {
                            StudioSession.shared.armExtras([StudioExtraDestination(name: "Bench 2", url: x)])
                        }
                        // ARM the layout, do not SET it after going live. The
                        // door used to wait for `isLive` and then call
                        // `setLayout`, which is a path the product does not
                        // have — and that difference is exactly why the door's
                        // runs looked correct while the SHEET dropped the
                        // host's choice entirely. A door that drives a
                        // different chain from the product cannot find the
                        // product's bugs.
                        StudioSession.shared.armLayout(layout)
                        guard StudioSession.shared.arm(film: it) else {
                            awdiag("AWMACDOOR arm refused: %@",
                                   StudioSession.shared.refusal ?? "no reason given")
                            return
                        }
                        router.play(it)                 // now the player finds it armed
                        // AND SILENCE THE LOCAL MONITOR NOW, not in twenty
                        // seconds. This door already muted — but only AFTER
                        // the wait for `isLive` below — so every run of it
                        // played the film out loud for as long as the engine
                        // took to start. Same opt-out as the other doors,
                        // which the first version of this line dropped and
                        // would have made an audio measurement impossible.
                        if env["AW_STUDIO_MAC_SOUND"] != "1" {
                            StudioSession.shared.muteLocalMonitorForHarness()
                        }
                        // WAIT FOR THE ENGINE, don't guess at it. A fixed sleep
                        // read `isLive` before the engine had finished starting
                        // and logged `engineLive=FALSE` for a run that was in
                        // fact publishing — the server's recording proved it.
                        // A readout that races the thing it reports is the
                        // fault this feature keeps repeating, so this waits for
                        // the state instead of assuming a duration.
                        var waited = 0.0
                        while !StudioSession.shared.isLive, waited < 20 {
                            try? await Task.sleep(for: .milliseconds(250))
                            waited += 0.25
                        }
                        // The CARDS, so "custom overlays" can be exercised and
                        // MEASURED rather than described. A card is a still
                        // graphic over the film, so it shows up in the
                        // recording as a collapse in temporal variation — the
                        // same reading that proved the camera tiles.
                        switch env["AW_STUDIO_CARD"] ?? "" {
                        case "startingSoon":
                            await StudioSession.shared.setCard(.startingSoon(secondsRemaining: 60))
                            awdiag("AWMACDOOR card=startingSoon")
                        case "intermission":
                            await StudioSession.shared.setCard(.intermission)
                            awdiag("AWMACDOOR card=intermission")
                        case "ending":
                            await StudioSession.shared.setCard(.ending)
                            awdiag("AWMACDOOR card=ending")
                        default:
                            break
                        }
                        if env["AW_STUDIO_MAC_SOUND"] != "1" {
                            StudioSession.shared.muteLocalMonitorForHarness()
                        }
                        // SAY WHAT IS TRUE. `isLive` is the session's own state
                        // once the engine has started, not the intent recorded a
                        // moment earlier. The HOST only — §5, a stream key is
                        // never printed.
                        awdiag("AWMACDOOR door=%@ layout=%@ host=%@ engineLive=%@ after=%.1fs",
                               macDoor, layout.rawValue, dest?.host ?? "?",
                               StudioSession.shared.isLive ? "true" : "FALSE", waited)
                        let seconds = Int(env["AW_STUDIO_MAC_SECONDS"] ?? "") ?? 120
                        try? await Task.sleep(for: .seconds(seconds))
                        await StudioSession.shared.end()
                        router.nowPlaying = nil
                        awdiag("AWMACDOOR ended after %ds", seconds)
                    }
                }
                if env["AW_STUDIO_MAC"] == "1" {
                    if StudioSession.shared.arm(film: it) {
                        router.play(it)
                        StudioSession.shared.muteLocalMonitorForHarness()
                        let seconds = Int(env["AW_STUDIO_MAC_SECONDS"] ?? "") ?? 120
                        Task {
                            try? await Task.sleep(for: .seconds(seconds))
                            await StudioSession.shared.end()
                            router.nowPlaying = nil
                        }
                    } else {
                        // The refusal path is worth reaching too: it is the
                        // branch a host hits on most of the catalog.
                        print("[AWSTUDIOMAC] refused: \(StudioSession.shared.refusal ?? "nil")")
                    }
                }
            }
        }
    }

    /// The browse UI (sidebar + detail). Shown as the window root EXCEPT while a title is playing.
    private var browse: some View {
        @Bindable var router = router
        return NavigationSplitView {
            List(AppRouter.Section.allCases, selection: $router.section) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .navigationTitle("Archive Watch")
        } detail: {
            NavigationStack(path: $router.path) {
                sectionContent
                    .navigationDestination(for: Catalog.Item.self) { DetailView(item: $0) }
                    .navigationDestination(for: PersonRoute.self) {
                        GridView(title: $0.name, items: store.byPerson($0.name))
                    }
                    .navigationDestination(for: CollectionRoute.self) {
                        GridView(title: $0.title, items: store.byCollection($0.id), sortable: true)
                    }
                    .navigationDestination(for: SeriesRef.self) { SeriesDetailView(card: $0.card) }
                    .navigationDestination(for: BrowseFilterRoute.self) { FilteredGridView(route: $0) }
                    .navigationDestination(for: SharedListRoute.self) { SharedListView(shared: $0.shared) }
                    .navigationDestination(for: PublicDomainRoute.self) { _ in PublicDomainView() }
                    .navigationDestination(for: CartoonRoute.self) { _ in CartoonView() }
                    .navigationDestination(for: PartyRoute.self) { _ in PartyPlayView() }
            }
        }
    }

    private func exitScreensaver() {
        setFullScreen(false)
        router.screensaverActive = false
    }
    private func setFullScreen(_ on: Bool) {
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        if w.styleMask.contains(.fullScreen) != on { w.toggleFullScreen(nil) }
    }

    @ViewBuilder private var sectionContent: some View {
        switch router.section {
        case .home:        HomeView()
        case .movies:      BrowseView(contentType: nil, title: "Movies")
        case .tv:          TVBrowseView()
        case .channels:    ChannelsView()
        case .collections: CollectionsList()
        case .surprise:    SurpriseView()
        case .search:      SearchView()
        case .library:     LibraryView()
        case .watchTogether: WatchTogetherLanding()
        case .create:      CreationStudioLanding()
        }
    }
}

// WATCH TOGETHER, WHERE SOMEBODY CAN FIND IT.
//
// Owner, 2026-09-21: "Is it easy for a human to understand how to trigger the
// studio? Does it need its own left navigation page?" It was not, and it did.
// The Studio window was reachable from File > Watch Together Studio and from a
// Controls button that only exists once a show is already running — the same
// shape as the Go Live command that "existed, greyed until a film played, in a
// menu, invisible from the surface it acts on" (Rule B13g, amended once
// already for exactly this).
//
// Creation Studio is the precedent: a Mac-exclusive feature with a sidebar
// entry whose landing page explains it and opens its real window. Watch
// Together is its peer.
//
// AND IT IS WHERE DECISION 131 BELONGS. "Every surface must state which of the
// three THIS device can do, and why it cannot do the others." A Mac is the
// only platform that can do all three, and there has been nowhere to say so.
private struct WatchTogetherLanding: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @Environment(AppStore.self) private var store
    @State private var joining = false
    private var studio: StudioSession { StudioSession.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 60)).foregroundStyle(.tint)
                Text("Watch Together").font(.largeTitle.bold())
                Text(WatchTogetherHere.summary)
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 520)

                // §D13: three controls, each at its ideal width, none of
                // them abbreviated. They fit at the window's 960-point
                // minimum, so this needs no collapse — the rule is that a
                // label is never squeezed, not that every row must have a
                // fallback it will never reach.
                HStack(spacing: 12) {
                    Button {
                        openWindow(id: StudioWindowID.studio)
                    } label: {
                        Label("Open the Studio", systemImage: "slider.horizontal.3")
                            .padding(.horizontal, 6)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent).fixedSize()

                    // "Go Live…" USED TO PRESENT THE SHEET HERE and was
                    // disabled with nothing playing. §D9 folded the form into
                    // the Studio's Output column, so this button and the one
                    // beside it would now do the identical thing — and a
                    // second control for one action is how a host presses the
                    // wrong one (§B13d's reasoning). It is gone; "Open the
                    // Studio" is the whole answer, and it is never disabled,
                    // because §D7 lets a host choose the film in there.

                    // JOIN, which needs no camera and no microphone (§11.10).
                    // Decision 132 gates HOSTING on being able to be in the
                    // show; a joiner contributes nothing to the program and
                    // is simply watching in step.
                    // "Start a room…" WAS HERE, disabled whenever no film was
                    // playing in a player window — which, since §D7 put the
                    // film inside the Studio, was always. §11.13 puts hosting
                    // where the broadcast is, and the Studio's "Friends on
                    // your call" is that place.

                    Button {
                        joining = true
                    } label: {
                        Label("Join a room…", systemImage: "person.badge.plus")
                            .padding(.horizontal, 6)
                    }
                    .controlSize(.large)
                    .fixedSize()
                }

                // HOSTING A ROOM. The code is the whole interface: it is read
                // aloud on the call everyone is already on (§11.8), so what
                // this surface owes a host is a number large enough to say
                // across a room and a way to stop.
                if let code = RoomJoin.shared.hostCode {
                    VStack(spacing: 6) {
                        Text("Your room code").font(.headline)
                        Text(code)
                            .font(.system(size: 46, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Read it out on your call.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 460)
                        Button("Close the room", role: .destructive) {
                            StudioRoomHost.shared.stop()
                            RoomJoin.shared.hostCode = nil
                        }
                    }
                    .padding(.top, 4)
                }
                // "Open a film to go live." stood here; §D7 lets the host
                // choose the film inside the Studio, so it was untrue.

                // ONLY WHAT THIS DEVICE CAN DO. Owner: "You shouldn't
                // advertise features that don't exist on the platform you are
                // currently on." So the list is DERIVED rather than written —
                // five surfaces each describing the feature in their own words
                // is five chances to promise something that is not here.
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(WatchTogetherHere.modes) { m in
                        mode(m.title, m.systemImage, m.detail)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 6)

                Divider().frame(maxWidth: 520)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(StudioRights.hostWarning)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
        .navigationTitle("Watch Together")
        .sheet(isPresented: $joining) {
            JoinRoomSheet { code, filmID in
                joining = false
                // The room names the film; open it and the follower takes
                // over from there. If this device does not have that film in
                // its catalog there is nothing to play, and saying so beats
                // an empty player.
                if let item = store.item(filmID) {
                    RoomJoin.shared.pending = code
                    RoomJoin.shared.pendingFilm = item.archiveID
                    router.play(item)
                } else {
                    RoomJoin.shared.problem =
                        "This room is watching a film that is not in this device's catalog yet."
                }
            }
        }
    }

    private func mode(_ title: String, _ icon: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 26)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The code entry (§11.8). Four characters, normalized as they are typed, so
/// a host reading "oh" and a guest typing O never diverge — the mapping is
/// `StudioRoom.normalize`, the same function the Worker runs (§8.29).
private struct JoinRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onJoin: (String, String) -> Void

    @State private var typed = ""
    @State private var problem: String?
    @State private var working = false

    private var canJoin: Bool { StudioRoom.normalize(typed) != nil && !working }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Join a room").font(.title2).bold()
            Text("Enter the code your host reads out. The film plays here in step with theirs.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Code", text: $typed)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onChange(of: typed) { _, new in
                    // Uppercase as typed, and stop at the code's length so a
                    // stray keystroke cannot silently invalidate a code the
                    // host just read out.
                    let cleaned = new.uppercased().filter { !$0.isWhitespace && $0 != "-" }
                    typed = String(cleaned.prefix(StudioRoom.codeLength))
                }

            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Join") { attempt() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canJoin)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func attempt() {
        guard let code = StudioRoom.normalize(typed) else { return }
        working = true
        problem = nil
        Task {
            let client = StudioSyncClient()
            do {
                let state = try await client.join(code: code)
                await client.leave()
                working = false
                onJoin(code, state.filmID)
                dismiss()
            } catch {
                working = false
                problem = StudioSyncFollower.sentence(for: error)
            }
        }
    }
}

/// Carries a joined room from the landing page to the player, which is the one
/// place an `AVPlayer` exists. A single value rather than a notification: two
/// surfaces, one hand-off, and nothing to unsubscribe.
@MainActor
@Observable
final class RoomJoin {
    static let shared = RoomJoin()
    /// A code the landing page accepted, waiting for the player to exist.
    var pending: String?
    /// The room's film: only a player for it takes the code (audit A16).
    var pendingFilm: String?
    /// The code THIS Mac is hosting, so the landing page can show it.
    /// ONE SOURCE OF TRUTH: the room host itself (launch audit B). This was a
    /// stored copy cleared only by the Studio's End button, so ⇧⌘E, the
    /// readout's End or closing a window left a dead code on screen — and the
    /// landing page refusing to open another room. Writes are ignored: the
    /// host's own start and stop are what change it.
    var hostCode: String? {
        get { StudioRoomHost.shared.code }
        set { }
    }
    /// Set by the landing page; consumed where the player is built.
    var wantsToHost = false
    var problem: String?
    private init() {}
}

// Creation Studio is a Mac-exclusive DocumentGroup editor (Decision 042). This in-app landing
// makes it reachable from the main window (not just File ▸ New): start a new project or reopen
// a recent one — each opens its own editor window.
private struct CreationStudioLanding: View {
    @State private var recents: [URL] = []

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "movieclapper.fill")
                .font(.system(size: 60)).foregroundStyle(.tint)
            Text("Creation Studio").font(.largeTitle.bold())
            Text("Cut public-domain films from the archive into clips, montages, and supercuts — then export to share. A Mac-only editor.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 480)

            // §D13: two controls at their ideal widths.
            HStack(spacing: 12) {
                Button { NSDocumentController.shared.newDocument(nil) } label: {
                    Label("New Project", systemImage: "plus").padding(.horizontal, 6)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut("n").fixedSize()
                Button { openProject() } label: {
                    Label("Open Project…", systemImage: "folder").padding(.horizontal, 6)
                }
                .controlSize(.large).keyboardShortcut("o").fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Projects").font(.headline).padding(.bottom, 2)
                if recents.isEmpty {
                    Text("Projects you save will appear here. Use New Project to start one, or Open Project… to load an existing .archiveproj.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(recents.prefix(10), id: \.self) { url in
                        Button {
                            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "movieclapper")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("Creation Studio")
        .onAppear { recents = NSDocumentController.shared.recentDocumentURLs }
        // Refresh after a save in a document window (recents update when the app re-activates).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recents = NSDocumentController.shared.recentDocumentURLs
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.archiveProject]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }
}
#endif
