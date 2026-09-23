#if os(macOS)
import SwiftUI
import AVKit
import SwiftData

// Native macOS player: AVPlayerView (AppKit) wrapped in NSViewRepresentable, fed by the
// SHARED ResilientStreamLoader (resume-on-reset + node failover) for MP4 or the native
// HLS master when the title has subtitles. Resume + progress via the SwiftData
// WatchProgress model (same store the other platforms write).
//
// PlayerSurface is the reusable engine; PlayerWindow plays a Catalog.Item and
// EpisodePlayer plays a series Episode with prev/next transport (TV drill-in).

struct PlayerWindow: View {
    /// The live show, if there is one (§B13a).
    private var studio: StudioSession { StudioSession.shared }
    /// `AW_STUDIO_MAC_PANEL=1` opens the Studio window on launch so §D1 can be
    /// SEEN without clicking — §B11's reason again (SwiftUI exposes no
    /// scriptable control). Inert unless set.
    private let openStudioOnLaunch =
        ProcessInfo.processInfo.environment["AW_STUDIO_MAC_PANEL"] == "1"
    @Environment(\.openWindow) private var openWindow
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        // NavigationStack hosts the native NSToolbar (Done) + window title; the AVPlayerView fills the
        // rest with its OWN native controls (transport, scrubber, volume, PiP, full-screen, speed). No
        // hand-drawn controls.
        NavigationStack {
            PlayerSurface(archiveID: item.archiveID,
                          // Honour the viewer's chosen copy (ArchiveVersions).
                          // Rebuilt from the stored file name, so it costs no
                          // network and cannot delay playback.
                          videoURL: item.videoURLParsed.map {
                              ArchiveVersions.preferredURL(for: item.archiveID, default: $0)
                          },
                          // The sheet's caption-type choice (owner 2026-08-26):
                          // Automatic/Off drop the captioned-HLS wrapper so the
                          // engine (or nothing) captions; File keeps it.
                          subtitleHLS: {
                              let c = CaptionChoiceSession.byItem[item.archiveID]
                              return (c == .automatic || c == .off) ? nil : item.subtitleHLSURL
                          }(),
                          captionsOff: CaptionChoiceSession.byItem[item.archiveID] == .off,
                          publishedVTT: item.publishedVTTURL,
                          onEnded: autoplayNext,
                          // Live, rehearsing, or ARMED for this film — the
                          // projection a show is about to attach to feeds the
                          // program as surely as one already attached.
                          feedsProgram: studio.isLive || studio.armedFilmID == item.archiveID)
                // §B13d: health is pinned over the player, OUTSIDE
                // AVPlayerView's floating HUD, because the HUD auto-hides and
                // health may not (WATCH-TOGETHER §4).
                .overlay(alignment: .topLeading) {
                    if studio.isLive {
                        StudioMacReadout(health: studio.health,
                                         filmFramesPerSecond: studio.filmFramesPerSecond,
                                         cameraFramesPerSecond: studio.cameraFramesPerSecond,
                                         onEnd: { Task { await studio.end() } },
                                         onOpenControls: { openWindow(id: StudioWindowID.studio) })
                        .transition(.opacity)
                    }
                }
                // The controls themselves now live in `StudioControls`
                // (§D1), which pushes each change into the engine, so the
                // player pushes nothing. It used to hold seven `@State`s and
                // seven `onChange`s; a second surface showing the same
                // choices made two copies of them a bug rather than a
                // simplification.
                .onAppear {
                    if openStudioOnLaunch { openWindow(id: StudioWindowID.studio) }
                }
                // FOLLOW A ROOM (§11). The landing page hands the code over
                // here because this is the one place an `AVPlayer` exists;
                // everything the follower does after that is silent (§11.2a).
                .onDisappear { StudioSyncFollower.shared.leaveIfFollowing() }
                .navigationTitle(item.year.map { "\(item.title) (\($0))" } ?? item.title)
                .toolbar {
                    // GO LIVE, WHERE SOMEONE CAN SEE IT (Rule B13g, amended
                    // 2026-09-20). B13g made this a MENU COMMAND for reasons
                    // that still hold — §B13a forbids a second window, §B13b
                    // forbids hand-drawing into the player's chrome — but it
                    // did not consider that a host has to FIND it. Owner,
                    // looking at the Mac: "it seems to lack the ability to set
                    // a destination or any settings for livestreaming at all.
                    // It just starts playing the movie." The command existed,
                    // greyed until a film played, in a menu, invisible from
                    // the surface it acts on.
                    //
                    // A NATIVE TOOLBAR ITEM is neither forbidden thing: not a
                    // second window, not hand-drawn chrome, but what macOS
                    // itself offers on a window that already has a toolbar.
                    // The menu command and its shortcut stay; this is the same
                    // command given somewhere to be seen.
                    //
                    // HIDDEN while live rather than disabled: §B13d already
                    // pins the health readout over the player then, and that
                    // readout owns ending the show. Two controls for one state
                    // is how a host presses the wrong one.
                    ToolbarItem(placement: .primaryAction) {
                        // HIDDEN ONLY WHEN ON AIR. This read `!studio.isLive`,
                        // and §D5's preview leaves the engine running with no
                        // destination — so a host who pressed Start preview
                        // would have watched the Go Live button disappear,
                        // which is the opposite of what a rehearsal is for.
                        if !studio.isOnAir {
                            // §D9 — THIS OPENS THE STUDIO, it does not present a
                            // sheet. Owner, 2026-09-22: "I think I may have
                            // found it hidden behind a button on the video
                            // player (rather than in the studio for some
                            // reason). This should all be in the studio." The
                            // sheet was an answer to "where does a host PRESS
                            // Go Live"; it never asked where a host DECIDES to,
                            // and a form floating over a different window from
                            // the controls it configures is the whole complaint.
                            Button {
                                StudioMacShow.shared.take(item, from: router)
                                openWindow(id: StudioWindowID.studio)
                            } label: {
                                Label("Go Live…",
                                      systemImage: "dot.radiowaves.left.and.right")
                            }
                            .help("Set this film up to stream in the Watch Together Studio")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            // Closing the window ends the show. A broadcast
                            // must never outlive the surface that was
                            // producing it — that is how a harness ended up
                            // playing into someone's living room (§9).
                            guard StudioEndConfirmation.confirm() else { return }
                            Task { await studio.end() }
                            router.nowPlaying = nil
                        } label: { Image(systemName: "xmark") }
                            .keyboardShortcut(.cancelAction).help("Close")
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// When a film ends and Autoplay is on, swap the player to the next title
    /// (router.nowPlaying drives the overlay, so changing it re-presents the player).
    private func autoplayNext() {
        // Not while live (launch audit A11): the Studio's engine is attached
        // to THIS film, and the next one never passed the rights gate.
        guard !StudioSession.shared.isLive, store.autoplayMode != .off,
              let next = ContinuousPlayback.next(after: item, mode: store.autoplayMode, store: store)
        else { return }
        router.play(next)
    }
}

// Shared speed control for the macOS players (AVPlayerView has no built-in speed
// menu; the tvOS/iOS AVPlayerViewController does). Drives the player's rate.
struct SpeedMenu: View {
    @Binding var speed: Double
    private let speeds: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]
    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { s in
                Button {
                    speed = s
                } label: {
                    if speed == s { Label(label(s), systemImage: "checkmark") }
                    else { Text(label(s)) }
                }
            }
        } label: { Label("Speed", systemImage: "speedometer") }
        .help("Playback speed")
    }
    private func label(_ s: Double) -> String {
        s == 1.0 ? "Normal" : (s == floor(s) ? "\(Int(s))×" : "\(s)×")
    }
}

// Episode player with manual prev/next (parity §3 "prev/next episode in player").
// Switching recreates the surface via .id, so each episode keeps its own resume
// position; the chevrons live in a small overlay capsule.
struct EpisodePlayer: View {
    let context: EpisodeContext
    @Environment(AppRouter.self) private var router
    @State private var episode: Episode

    init(context: EpisodeContext) {
        self.context = context
        _episode = State(initialValue: context.episode)
    }

    private var series: Series { context.series }
    private var prev: Episode? { series.episode(before: episode) }
    private var next: Episode? { series.episode(after: episode) }

    var body: some View {
        NavigationStack {
            PlayerSurface(archiveID: episode.archiveID,
                          videoURL: episode.videoURLParsed,
                          subtitleHLS: nil,
                          onEnded: { if let n = next { episode = n } })   // binge auto-advance
                .id(episode.archiveID)
                .navigationTitle(episode.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { router.nowPlayingEpisode = nil } label: { Image(systemName: "xmark") }
                            .keyboardShortcut(.cancelAction).help("Close")
                    }
                    // Native prev/next episode controls in the toolbar (binge transport).
                    ToolbarItemGroup(placement: .navigation) {
                        Button { if let p = prev { episode = p } } label: { Image(systemName: "backward.end.fill") }
                            .disabled(prev == nil).help("Previous episode")
                        Button { if let n = next { episode = n } } label: { Image(systemName: "forward.end.fill") }
                            .disabled(next == nil).help("Next episode")
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// The shared playback surface: builds the AVPlayer (HLS or resilient MP4), resumes
// from + persists WatchProgress keyed by archiveID. archiveID is the resume key for
// both films and episodes (an episode's archiveID is a real archive.org item).
//
// INTERNAL, not private, since macOS-DESIGN §D7: the Watch Together Studio hosts
// the film itself now, and it hosts THIS — the same surface, with the same
// resilient loader, the same resume, the same caption paths and the same
// `attachIfArmed` hand-off to the engine. A second player written for the
// Studio would be a second copy of every one of those decisions, and the
// project has already paid for that mistake once per platform.
struct PlayerSurface: View {
    let archiveID: String
    let videoURL: URL?
    let subtitleHLS: URL?
    var captionsOff: Bool = false
    /// The published WebVTT, so the track can be CHECKED rather than trusted.
    var publishedVTT: URL? = nil
    var onEnded: (() -> Void)? = nil
    /// This player's frames are COMPOSITED INTO A BROADCAST. Such a player
    /// skips Decision 067's plain-URL path: that path exists so the system can
    /// caption the film in AVPlayerView, and system captions never reach the
    /// program. It measured as a stall ten seconds into The Man Who Laughs,
    /// then a swap to the loader (`AWPLAYER ... reason=stall`) — a visible
    /// hitch on the wire bought for captions nobody watching could see.
    var feedsProgram: Bool = false

    @Environment(\.modelContext) private var ctx
    @State private var player: AVPlayer?
    @State private var loader: ResilientStreamLoader?     // retained for the asset's lifetime
    @State private var endObserver: NSObjectProtocol?
    @State private var timeObserver: Any?                 // periodic progress save (Continue Watching)
    // Part (c): captioned titles play native HLS (bypassing ResilientStreamLoader).
    // On a persistent mid-stream stall — or a hard load failure — drop CC and
    // rebuild on the resilient MP4 (smooth-without-CC beats stutter-with-CC).
    @State private var captionStall = CaptionStallMonitor()
    /// The Decision-067 plain-URL branch was taken (no loader on the item).
    @State private var usedDirectURL = false
    /// The playing asset IS the resilient loader. It still needs the failure
    /// observer — a rebuild re-pins a storage node — but not the caption-stall
    /// monitor, which exists to trade captions away for resilience we have.
    @State private var loaderIsPrimary = false
    @State private var statusObs: NSKeyValueObservation?
    /// How many times playback may be rebuilt through the resilient loader
    /// before the film is declared unplayable (iOS twin: `maxRecovery`).
    @State private var recoveryAttempts = 0
    @State private var recoveryReset: DispatchWorkItem?
    private static let maxRecovery = 5
    @State private var unplayableObs: NSKeyValueObservation?
    @State private var loadWatchdog: DispatchWorkItem?
    @State private var loadError: String?
    @State private var liveCaptions: LiveCaptions?
    @State private var liveLine: String = ""
    /// Drives the downloaded-subtitle overlay; cancelled with the window.
    @State private var offlineSubtitleTask: Task<Void, Never>?
    /// Drives the overlay for an ONLINE captioned film (see startPublishedSubtitles).
    @State private var publishedSubtitleTask: Task<Void, Never>?
    @State private var drawsCaptions = true
    /// The FILE renderer's own gate, separate from the engine's `drawsCaptions`.
    /// The two used to share one flag because they never ran together; an online
    /// captioned film now draws its published file WHILE the engine listens to
    /// judge it, and one flag for two writers is a fight over `liveLine`.
    @State private var drawsPublished = true
    // AirPlay. The `.floating` HUD below carries a route button, but every path
    // here builds a CUSTOM-SCHEME resource-loader asset, and Apple does not
    // support video AirPlay for those (see AirPlayRouting) — so choosing a route
    // failed on every title, exactly as it did on iOS before this was fixed
    // there. macOS never got the fix; this is it.
    @State private var externalObs: NSKeyValueObservation?
    @State private var resumeObs: NSKeyValueObservation?
    @State private var isExternalActive = false

    var body: some View {
        ZStack {
            Color.black
            if let loadError {
                // A dead source is a fact worth stating, not a spinner to sit in.
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Can't play this title").font(.title3.weight(.semibold))
                    Text(loadError)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Close") { onEnded?() }.keyboardShortcut(.defaultAction)
                }
                .foregroundStyle(.white)
            } else if let player {
                // `.floating` = the native macOS TV-app HUD (centre play/skip, scrubber + timecodes,
                // volume, PiP + AirPlay, full-screen, speed) — the interface the owner asked to mimic.
                VideoPlayerNS(player: player, controlsStyle: .floating).ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        // Live captions for a film with no subtitle track of its
                        // own. Non-interactive so it never intercepts the HUD.
                        if !liveLine.isEmpty {
                            Text(liveLine)
                                .font(.system(size: 18, weight: .medium))
                                .lineLimit(4)   // two stacked cues, each may wrap
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.black.opacity(0.6), in: .rect(cornerRadius: 7))
                                .padding(.bottom, 72)
                                .frame(maxWidth: 760)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    private func setup() {
        guard player == nil else { return }
        let playerItem: AVPlayerItem
        // DEBUG door: play a given file instead of resolving the catalog item.
        //
        // The A/V sync stimulus — a black clip with a white flash and a 1 kHz
        // beep on the same frame every five seconds — is not in the catalogue
        // and never will be. macOS takes film audio through
        // `MTAudioProcessingTap` where tvOS pulls it by film position, so the
        // television's sync figure says nothing about this platform, and
        // "the tap is inline, so it must be aligned" is an assumption rather
        // than a measurement.
        let playURLOverride: URL? = {
            #if DEBUG
            guard let s = ProcessInfo.processInfo.environment["AW_PLAY_URL"],
                  !s.isEmpty else { return nil }
            return s.hasPrefix("file://") ? URL(string: s) : URL(fileURLWithPath: s)
            #else
            return nil
            #endif
        }()
        if let playURLOverride {
            playerItem = AVPlayerItem(url: playURLOverride)
        }
        // DOWNLOADED FIRST (Decision 099): a plain local file, with none of the
        // resilience machinery — a `file://` URL has no connection to lose.
        else if let local = OfflineLibrary.videoURL(for: archiveID) {
            playerItem = AVPlayerItem(url: local)
        } else if subtitleHLS != nil, let mp4 = videoURL {
            // A CAPTIONED FILM PLAYS LIKE ANY OTHER ONE (Decision 070, carried
            // from tvOS). The wrapper this replaces declares the whole MP4 as
            // ONE segment, and a segment is AVFoundation's atomic buffering
            // unit, so `preferredForwardBufferDuration` below was ignored and
            // the entire film came into memory. Measured on The Grapes of Wrath
            // (2.19 GB) by tools/test_captioned_buffer_growth.swift: 4,195s
            // buffered against 300s asked and 1,368 MB still climbing at 90
            // seconds, against 193s and a flat 55 MB through the loader. A Mac
            // survives that; the iPhone that reported it does not.
            let (asset, l) = ResilientStreamLoader.makeAsset(for: mp4)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
            loaderIsPrimary = true
        } else if let hls = subtitleHLS {
            playerItem = AVPlayerItem(url: hls)                 // no MP4 to resolve; native HLS
        } else if let mp4 = videoURL, SubtitleStore.cachedVTT(for: archiveID) != nil {
            // Subtitles fetched or transcribed on this device (SubtitleFinder).
            // These were served as a local HLS wrapper, which writes the film as
            // ONE segment exactly as the published one does — the same bomb,
            // one directory over. The cues render in the overlay instead.
            let (asset, l) = ResilientStreamLoader.makeAsset(for: mp4)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
            loaderIsPrimary = true
        } else if let url = videoURL, !feedsProgram,
                  SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
            // From 27 the system captions video that carries none — but only for
            // an ordinary asset. Through `aw-stream://` no subtitle track is
            // ever offered (measured on macOS 27, one shape per process), so the
            // resilient loader gives way for films with no subtitles of their
            // own.
            playerItem = AVPlayerItem(url: url)
            usedDirectURL = true
        } else if let url = videoURL {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
            loaderIsPrimary = true
        } else {
            return
        }
        playerItem.preferredForwardBufferDuration = 300
        awdiag("AWPLAYER source path=%@ feedsProgram=%@ captionedHLS=%@",
               loaderIsPrimary ? "loader" : usedDirectURL ? "direct" : "other",
               feedsProgram ? "yes" : "no", subtitleHLS != nil ? "yes" : "no")
        // Title rides the native window title bar (navigationTitle "Title (Year)"). macOS AVPlayerItem
        // has NO externalMetadata (iOS/tvOS only — verified in the SDK), and the only way to override
        // the MP4's own embedded title is to wrap the asset, which over our custom-scheme resilient
        // asset renders BLANK video — so we DON'T. Speed/PiP/AirPlay/full-screen are AVPlayerView's
        // native HUD controls.

        let p = AVPlayer(playerItem: playerItem)
        #if DEBUG
        // Silent from its first frame under a Studio door — registration
        // (which also mutes) comes ~0.4 s after `play()` below.
        if ProcessInfo.processInfo.environment["AW_GOLIVE_MAC"] == "1",
           ProcessInfo.processInfo.environment["AW_STUDIO_MAC_SOUND"] != "1" {
            p.isMuted = true
        }
        #endif
        // SharePlay: main player only — never the caption scout (see
        // WatchTogether.attach). Re-attached on every build because a rebuilt
        // player carries a new coordinator.
        WatchTogether.shared.attach(p, archiveID: archiveID)
        // NOT FOR AN OVERRIDE FILE. The resume position belongs to the
        // CATALOGUE ITEM, and applying it to a file played through
        // `AW_PLAY_URL` seeks into something it has nothing to do with —
        // clamped to the end when the file is shorter. Measured: a 120 s
        // stimulus clip opened at `at=119.00`, so every run through this door
        // was broadcasting its final second. That produced four separate
        // "findings" — vanished beeps, lost video markers, 97.7% silent audio —
        // none of which were about the Studio at all (§9.fffff).
        if playURLOverride == nil, let resume = savedProgress(), resume > 5 {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        p.play()
        player = p
        // Watch Together Studio (§B13a): Detail armed the session before this
        // player existed, because the player REPLACES the split view as the
        // window root (§B2a) and Detail is gone by now. A no-op unless this is
        // the film the host armed.
        // REGISTER rather than attach (§D7). `attachIfArmed` is still what
        // runs when a show was armed before this player existed — the Detail
        // path — but the Studio window now holds the film itself, so the
        // player can exist BEFORE the host decides to produce a show, and the
        // session needs to know which player to reach for when they do.
        Task { await StudioSession.shared.registerSurfacePlayer(p, archiveID: archiveID) }
        // FOLLOW A ROOM (§11), if the host joined one on the Watch Together
        // page. Here rather than in `PlayerWindow`, because this is where the
        // `AVPlayer` is actually built — the same reason `attachIfArmed` is
        // here. Everything the follower does after this is silent (§11.2a):
        // the viewer simply sees the film do what the host's film is doing.
        if let code = RoomJoin.shared.pending,
           RoomJoin.shared.pendingFilm.map({ $0 == archiveID }) ?? true {
            RoomJoin.shared.pending = nil
            RoomJoin.shared.pendingFilm = nil
            Task { await StudioSyncFollower.shared.join(code: code, player: p) { _ in } }
        }
        // HOSTING, the same hand-off in the other direction: the landing page
        // asks, and the room can only be opened where the player is.
        if RoomJoin.shared.wantsToHost {
            RoomJoin.shared.wantsToHost = false
            Task {
                let code = await StudioRoomHost.shared.start(player: p, filmID: archiveID)
                RoomJoin.shared.hostCode = code
                RoomJoin.shared.problem = StudioRoomHost.shared.problem
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        // AirPlay route engaged/disengaged — see externalPlaybackChanged.
        externalObs = p.observe(\.isExternalPlaybackActive, options: [.new]) { pl, _ in
            let active = pl.isExternalPlaybackActive
            MainActor.assumeIsolated { externalPlaybackChanged(active) }
        }
        // Part (c): recover to the resilient MP4 on a hard load failure OR a
        // persistent stutter — for captioned (HLS) titles AND the Decision-067
        // direct-URL path. The old premise ("non-captioned MP4 already streams
        // through ResilientStreamLoader, so it needs no fallback") died the day
        // D067 gave uncaptioned films a plain AVPlayerItem(url:) so the system
        // could caption them: that item has NO loader, so one archive.org idle
        // reset froze it forever (F-8: reproduced twice on macOS 27 within the
        // first minute — 38s and 55s — while the scout streamed the same file
        // happily on its own loader).
        // The plain resilient-loader path was NOT in this condition, and
        // `reportUnplayable` below refuses to speak until recovery is spent —
        // so on the path most films take, a mid-film failure armed nothing,
        // recoveryAttempts stayed 0, and the window span forever saying
        // nothing at all. Every shape gets the failure observer; only the
        // shapes that can trade captions away get the stall monitor.
        if (subtitleHLS != nil || usedDirectURL || loaderIsPrimary), videoURL != nil {
            statusObs = playerItem.observe(\.status, options: [.new]) { item, _ in
                MainActor.assumeIsolated { if item.status == .failed { fallbackToResilientMP4(reason: "load failed") } }
            }
            if !loaderIsPrimary {
                captionStall.attach(player: p, item: playerItem) { fallbackToResilientMP4(reason: "stall") }
            }
        }
        // EVERY item is watched for "this will never play", not just captioned
        // ones — the same gap iOS had. An archive.org item removed since the last
        // catalog build 503s, and with no observer on the plain-MP4 path the
        // window just spins forever. 60s matches the tvOS backstop.
        unplayableObs = playerItem.observe(\.status, options: [.new]) { item, _ in
            MainActor.assumeIsolated {
                if item.status == .readyToPlay { loadWatchdog?.cancel(); loadWatchdog = nil }
                // A captioned item gets its CC-dropping fallback first; only
                // report once that has been spent.
                // This test was true from the first frame for a film with no
                // subtitles, so the error was shown on the very `.failed` that
                // was kicking off a recovery — the viewer read "unavailable"
                // while the app was still trying. Report only once spent.
                if item.status == .failed, recoveryAttempts >= Self.maxRecovery {
                    reportUnplayable()
                }
            }
        }
        loadWatchdog?.cancel()
        let watchdog = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard player?.currentItem?.status != .readyToPlay else { return }
                guard recoveryAttempts >= Self.maxRecovery else { return }
                reportUnplayable()
            }
        }
        loadWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: watchdog)
        // Periodic save (every 5s) — macOS previously saved ONLY on window close, so a crash /
        // force-quit lost the whole session and nothing synced mid-playback (owner 2026-06-29).
        // Live captions when the film carries no subtitle track of its own:
        // transcribe the audio that is ALREADY streaming (no download).
        if captionsOff {
            // Captions Off means NOTHING caption-shaped runs: not the engine,
            // and not the subtitle review either — the review starts its own
            // scout (a second player + tap + recognizer) to judge a file that
            // will never display. Measured 2026-08-26: with Off, the else-if
            // below started the scout anyway ("scout playing at 2.0x").
        } else if let local = OfflineLibrary.videoURL(for: archiveID) {
            // Offline. The published WebVTT came down with the film, so render
            // those human words; with no file, the engine transcribes the local
            // audio — which needs no network either (see OfflineSubtitles).
            if let subs = OfflineSubtitles(archiveID: archiveID) {
                startOfflineSubtitles(subs, on: p)
            } else {
                startLiveCaptions(on: p, source: local)
            }
        } else if subtitleHLS == nil, let local = SubtitleStore.cachedVTT(for: archiveID) {
            startPublishedSubtitles(vtt: local, on: p)   // on-device subtitles, same overlay
        } else if subtitleHLS == nil {
            startLiveCaptions(on: p)
        } else if let vtt = publishedVTT {
            // The published human words, drawn in the overlay — there is no
            // native track to carry them any more (see setup()). Still CHECKED
            // against what is being said: a published file can belong to a
            // different cut, or be right and land seconds late, and the review
            // now decides which renderer keeps the line rather than whether to
            // deselect a track.
            startPublishedSubtitles(vtt: vtt, on: p)
            reviewPublishedSubtitles(vtt: vtt, on: p)
        }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { _ in
            MainActor.assumeIsolated { persist() }
        }
    }

    /// Replace the current item and resume at `pos` EXACTLY.
    ///
    /// A seek issued straight after `replaceCurrentItem` is DROPPED — the new
    /// item has no loaded timeline yet — so playback restarted at 0 on every
    /// AirPlay engage/disengage and on every caption-stall fallback. Wait for
    /// `.readyToPlay`, seek with ZERO tolerance, then play.
    private func swap(to newItem: AVPlayerItem, resumingAt pos: CMTime, on p: AVPlayer) {
        newItem.preferredForwardBufferDuration = 300
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: newItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
        resumeObs = nil
        p.replaceCurrentItem(with: newItem)
        guard pos.isNumeric, pos.seconds > 1 else { p.play(); return }
        resumeObs = newItem.observe(\.status, options: [.initial, .new]) { it, _ in
            guard it.status == .readyToPlay else { return }
            MainActor.assumeIsolated {
                resumeObs = nil
                p.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
            }
        }
    }

    /// Swap between a receiver-fetchable asset (AirPlay engaged) and the
    /// resilient on-device path (disengaged), preserving position and the end
    /// observer. Mirrors the iOS coordinator; the routing decision itself is
    /// shared (AirPlayRouting) so both platforms cannot drift.
    private func externalPlaybackChanged(_ active: Bool) {
        guard active != isExternalActive, let p = player else { return }
        isExternalActive = active
        awdiag("AWPLAYER swapping item for AirPlay active=%@", active ? "yes" : "no")
        let newItem: AVPlayerItem
        if active {
            // The stall/failure machinery watches the LOCAL loader paths; it must
            // not fire against a stream the receiver now owns.
            captionStall.detach()
            statusObs = nil
            if PlaybackDiag.enabled {
                print(AirPlayRouting.describe(hls: subtitleHLS, mp4: videoURL))
            }
            guard let url = AirPlayRouting.receiverURL(hls: subtitleHLS, mp4: videoURL) else {
                isExternalActive = false
                return          // nothing fetchable — leave playback as it is
            }
            newItem = AVPlayerItem(url: url)
        } else {
            // Restore the same path playback started on (Decision 021/031/034
            // resilience only matters once we own the connection again).
            guard let item = makeLocalItem() else { return }
            newItem = item
        }
        swap(to: newItem, resumingAt: p.currentTime(), on: p)
    }

    /// Rebuild the on-device item, mirroring `setup`'s branch.
    private func makeLocalItem() -> AVPlayerItem? {
        // The captioned shape is no longer a distinct ASSET — a captioned film
        // streams through the resilient loader like every other one and draws
        // its cues in the overlay. Rebuilding the wrapper here would restore
        // the whole-film buffering on every AirPlay return.
        if let mp4 = videoURL {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: mp4)
            loader = l
            return AVPlayerItem(asset: asset)
        }
        if let hls = subtitleHLS { return AVPlayerItem(url: hls) }
        return nil
    }

    /// Part (c): swap the failed/stuttering native-HLS item for the resilient MP4
    /// (resume-on-reset + node failover), preserving the play position. Fires once.
    private func reportUnplayable() {
        guard loadError == nil else { return }
        loadWatchdog?.cancel(); loadWatchdog = nil
        player?.pause()
        // A film that PLAYED and then stopped lost its connection; it is not a
        // missing copy, and saying so sends the viewer looking for another film.
        loadError = (player?.currentTime().seconds ?? 0) > 5
            ? "Playback stopped — the connection to archive.org was lost. Your place is saved; try playing again in a moment."
            : "The copy on archive.org may have been removed or is temporarily unavailable."
    }

    /// Rebuild through the resilient loader and STAY ARMED to do it again.
    /// See the iOS twin for the incident: one retry per film is not a policy
    /// when archive.org resets idle connections as a matter of course.
    private func fallbackToResilientMP4(reason: String) {
        guard recoveryAttempts < Self.maxRecovery, let url = videoURL,
              let p = player else { return }
        recoveryAttempts += 1
        // A swap is a visible event on a broadcast (the engine follows it,
        // §8.50), so it says why it happened.
        awdiag("AWPLAYER swapping to the resilient loader reason=%@ attempt=%d at=%.1fs",
               reason, recoveryAttempts, p.currentTime().seconds)
        captionStall.detach()
        statusObs = nil
        let pos = p.currentTime()
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let rebuilt = AVPlayerItem(asset: asset)
        swap(to: rebuilt, resumingAt: pos, on: p)
        // Watch the REBUILT item too, or a second interruption has nothing
        // listening for it; and forgive the budget once playback has held, so
        // resets an hour apart do not share an allowance with a burst.
        statusObs = rebuilt.observe(\.status, options: [.new]) { item, _ in
            MainActor.assumeIsolated {
                if item.status == .failed { scheduleRecovery() }
            }
        }
        captionStall.attach(player: p, item: rebuilt) { scheduleRecovery() }
        recoveryReset?.cancel()
        let reset = DispatchWorkItem { MainActor.assumeIsolated { recoveryAttempts = 0 } }
        recoveryReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: reset)
        // The subtitle track went with the HLS path — caption the audio instead.
        // Unless the engine is already running (the direct-URL branch started
        // it at setup) or the viewer chose captions Off.
        if liveCaptions == nil, !captionsOff { startLiveCaptions(on: p) }
    }

    /// Back off between attempts so a genuinely dead source is not hammered.
    private func scheduleRecovery() {
        guard recoveryAttempts < Self.maxRecovery else { return }
        let delay = min(Double(recoveryAttempts) * 2.0, 8.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { fallbackToResilientMP4(reason: "retry") }
        }
    }

    /// Check the published track against what is actually being said.
    private func reviewPublishedSubtitles(vtt: URL, on p: AVPlayer) {
        startLiveCaptions(on: p, draws: false)
        Task { @MainActor in
            guard let captions = liveCaptions,
                  let outcome = await SubtitleReview.review(vttURL: vtt, captions: captions)
            else { return }
            // WHICH RENDERER KEEPS THE LINE. There is no native track to
            // deselect on a captioned film any more (see setup()), so the
            // verdict lands one level down: a file that fails review stops
            // drawing and the engine's cues take over; a file that passes keeps
            // the line and the engine stands down. Exactly one of them draws.
            if outcome.replacesNativeTrack {
                publishedSubtitleTask?.cancel(); publishedSubtitleTask = nil
                offlineSubtitleTask?.cancel(); offlineSubtitleTask = nil
                drawsPublished = false
                drawsCaptions = true
            } else {
                liveCaptions?.stop(); liveCaptions = nil
            }
        }
    }

    /// Transcribe the streaming audio and publish it to `liveLine`.
    ///
    /// `draws` is false while a published track is only being JUDGED: the
    /// player is already showing its own subtitles, and a second set underneath
    /// them is the double-caption bug in miniature.
    private func startLiveCaptions(on p: AVPlayer, draws: Bool = true, source: URL? = nil) {
        drawsCaptions = draws
        // `source` overrides the catalog URL for a downloaded film: transcribing
        // the copy on disk works with no network, the remote one does not.
        guard liveCaptions == nil, LiveCaptions.isSupported,
              let src = source ?? videoURL else { return }
        Task { @MainActor in
            // From macOS 27 the system captions this film itself; ours would
            // double up on it. But ONLY when the film has no track of its own:
            // `draws == false` means the job is to JUDGE a published track
            // (Decision 062), and running the handover first killed that judge
            // on every 27 device — the published track emits text, handOver
            // reports "captioning", and the review never ran.
            if draws, await SystemCaptions.handOver(to: p, directURL: src) { return }
            let lc = LiveCaptions()
            liveCaptions = lc
            await lc.start(url: src, from: p.currentTime())
            while lc.isRunning, player != nil {
                let now = p.currentTime()
                lc.throttle(playhead: now)
                // Between captions, say why there are none.
                let line = lc.line(at: now)
                liveLine = drawsCaptions ? (line.isEmpty ? lc.notice : line) : ""
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            liveLine = ""
        }
    }

    /// Render a DOWNLOADED subtitle file against the playhead (Decision 099).
    ///
    /// Publishes into the SAME `liveLine` the engine writes, so the overlay,
    /// its styling and its teardown are one thing rather than two.
    /// Draw a PUBLISHED WebVTT through the same overlay the downloaded case uses.
    private func startPublishedSubtitles(vtt: URL, on p: AVPlayer) {
        publishedSubtitleTask?.cancel()
        publishedSubtitleTask = Task { @MainActor in
            guard let subs = await OfflineSubtitles.published(vtt), !Task.isCancelled else { return }
            startOfflineSubtitles(subs, on: p)
        }
    }

    private func startOfflineSubtitles(_ subs: OfflineSubtitles, on p: AVPlayer) {
        drawsPublished = true
        offlineSubtitleTask?.cancel()
        offlineSubtitleTask = Task { @MainActor in
            while !Task.isCancelled, player != nil {
                liveLine = drawsPublished ? subs.line(at: p.currentTime().seconds) : ""
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            liveLine = ""
        }
    }

    private func teardown() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        captionStall.detach()
        statusObs = nil
        externalObs = nil
        resumeObs = nil
        unplayableObs = nil
        loadWatchdog?.cancel(); loadWatchdog = nil
        liveCaptions?.stop(); liveCaptions = nil
        offlineSubtitleTask?.cancel(); offlineSubtitleTask = nil
        publishedSubtitleTask?.cancel(); publishedSubtitleTask = nil
        persist()
        // A SURFACE THAT GOES AWAY STOPS ITS PLAYER (macOS-DESIGN §D12).
        //
        // Owner, 2026-09-22: "the movie seems to keep playing in the background
        // even if I do close the movie with the x on the top right corner of
        // the playing video window and there is no way to stop the audio at all
        // at that point."
        //
        // This function did everything EXCEPT the one thing its name implies.
        // It removed observers, cancelled tasks and saved progress, and left
        // the `AVPlayer` playing — and on macOS a closed `WindowGroup` window
        // keeps its scene's `@State`, so the player survived with no view left
        // to pause it. Re-opening then built a SECOND player over the first,
        // which is the "a new copy of the movie started playing" half of the
        // same report.
        //
        // `replaceCurrentItem(with: nil)` as well as `pause()`: a paused player
        // still holds the item, the item still holds the asset, and the asset
        // is a resource-loader delegate with a live connection to archive.org.
        let mine = player
        // BUT NOT OUT FROM UNDER A LIVE SHOW (§D12a). The engine may be
        // pulling frames from this exact player, and nilling its item leaves
        // the compositor reading nothing: the programme goes black while the
        // film pane, the camera, the meters and the health line all stay
        // correct. That is the fault reproduced twice in eight runs on
        // 2026-09-22 with no signature — a view being REBUILT is not a window
        // being CLOSED, and only the second one means the film should stop.
        //
        // When the show is live the player outlives this surface and
        // `StudioSession.end()` releases it, so the owner's original complaint
        // ("the movie seems to keep playing in the background") stays fixed.
        if !StudioSession.shared.engineIsUsing(mine) {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        player = nil
        loader = nil
        StudioSession.shared.forgetSurfacePlayer(mine)
    }

    private func savedProgress() -> Double? {
        let id = archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        guard let wp = try? ctx.fetch(d).first, !wp.isComplete else { return nil }
        return wp.positionSeconds
    }

    private func persist() {
        guard let p = player, let cur = p.currentItem else { return }
        let pos = p.currentTime().seconds
        // Save even a brief view (>1s) and even before duration is known (backfill it later) — the
        // old `pos>3 && dur>0` gate dropped early saves entirely (owner 2026-06-29).
        guard pos.isFinite, pos > 1 else { return }
        let d0 = cur.duration.seconds
        let dur = (d0.isFinite && d0 > 0) ? d0 : 0
        // Shared write path — watch-history semantics live in ONE place.
        WatchProgress.record(in: ctx, archiveID: archiveID, position: pos, duration: dur)
        SyncNudge.nudge(ctx)   // push progress promptly (debounced) so other devices converge fast
    }
}

// MARK: - Channel lineup player (Channels tune-in)
//
// Plays an ordered lineup (programs + woven commercials) straight through, joining
// the first program in progress at `startOffset` (#92). Live TV semantics: NO resume,
// NO WatchProgress writes (persistsProgress=false on the other platforms). On
// end-of-item it swaps the next playable item onto the same player. Mirrors the iOS
// LineupQueue advance, AppKit-side.
struct ChannelPlayer: View {
    let lineup: [Catalog.Item]
    let startOffset: TimeInterval
    var muted: Bool = false           // Party Play starts muted (background eye-candy)
    @Environment(\.dismiss) private var dismiss
    @State private var engine = ChannelEngine()

    var body: some View {
        ZStack {
            Color.black
            if let player = engine.player {
                VideoPlayerNS(player: player).ignoresSafeArea()
            } else if engine.failed {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear { engine.start(lineup: lineup, startOffset: startOffset, muted: muted) }
        .onDisappear { engine.stop() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .navigation) {
                Text(engine.nowTitle).font(.headline).lineLimit(1)
            }
        }
    }
}

@MainActor
@Observable
final class ChannelEngine {
    var player: AVPlayer?
    var nowTitle = ""
    var failed = false

    private var items: [Catalog.Item] = []
    private var idx = 0
    private var loader: ResilientStreamLoader?   // retained for the asset's lifetime
    private var endObserver: NSObjectProtocol?

    func start(lineup: [Catalog.Item], startOffset: TimeInterval, muted: Bool = false) {
        guard player == nil else { return }   // onAppear can fire more than once
        items = lineup
        idx = lineup.firstIndex { $0.videoURLParsed != nil } ?? 0
        guard idx < items.count, let url = items[idx].videoURLParsed else { failed = true; return }
        let p = AVPlayer(playerItem: makeItem(for: url))
        p.isMuted = muted
        nowTitle = items[idx].title
        if startOffset > 5 { p.seek(to: CMTime(seconds: startOffset, preferredTimescale: 600)) }
        p.play()
        player = p
    }

    private func makeItem(for url: URL) -> AVPlayerItem {
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 300
        registerEnd(for: item)
        return item
    }

    private func registerEnd(for item: AVPlayerItem) {
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func advance() {
        guard let player else { return }
        idx += 1
        while idx < items.count {
            if let url = items[idx].videoURLParsed {
                player.replaceCurrentItem(with: makeItem(for: url))
                nowTitle = items[idx].title
                player.play()
                return
            }
            idx += 1
        }
        // Lineup exhausted — let it sit on the final frame; the user dismisses.
    }

    func stop() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        player?.pause()
        player = nil
    }
}

struct VideoPlayerNS: NSViewRepresentable {
    let player: AVPlayer
    /// Default `.inline` for the main player; the clip-marking sheet passes `.none` and
    /// supplies its own compact transport (AVKit's inline overlay is too heavy for a sheet).
    var controlsStyle: AVPlayerViewControlsStyle = .inline

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = controlsStyle
        let chrome = controlsStyle != .none
        v.allowsPictureInPicturePlayback = chrome
        v.showsFullScreenToggleButton = chrome
        v.videoGravity = .resizeAspect
        if chrome {
            // Native playback-speed control in the HUD (the speedometer in the TV app) — the HIG-correct
            // speed UI, so we don't bolt a custom Speed menu onto the toolbar.
            v.speeds = AVPlaybackSpeed.systemDefaultSpeeds
            v.allowsVideoFrameAnalysis = false   // Live Text/subject-lookup on film frames isn't wanted
        }
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
        if v.controlsStyle != controlsStyle { v.controlsStyle = controlsStyle }
    }
}
#endif
