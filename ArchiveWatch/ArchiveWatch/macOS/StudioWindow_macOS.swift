#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import CoreVideo

// WATCH TOGETHER STUDIO — the window (macOS-DESIGN §D1).
//
// Owner: "You should have a lot of controls on MacOS to determine exactly how
// the stream looks and which inputs/outputs are being managed. You had
// researched OBS, so you should be able to take anything you need from that
// open source project to make sure this feature is fully built out."
//
// §D1: a real window rather than the sheet that used to hold these controls.
// A host runs a broadcast for two hours alongside the player, and a sheet is
// modal to one window and vanishes when the player goes full-screen — which
// is exactly when the controls are most wanted.
//
// §D6 build order, and this file is step 1: the window, the preview, and the
// controls that already existed moved into it. Device pickers (§D2), output
// settings (§D4) and the call-audio input (§D3) follow, each on its own.

// MARK: - The controls, shared between the player and the Studio window

/// The host's choices, in ONE place because there are now two surfaces that
/// show them. They lived as `@State` inside `PlayerWindow` when the panel was
/// a sheet over that window; a second window makes that a bug rather than a
/// simplification — two copies of "where the camera goes" is how a host ends
/// up looking at a control that does not describe the broadcast.
///
/// Each setter pushes into the engine AND arms the session, so a choice made
/// before a show starts is the one the show starts with.
@MainActor
@Observable
final class StudioControls {
    static let shared = StudioControls()

    var layout: StudioLayout = .corner {
        didSet {
            guard layout != oldValue else { return }
            StudioSession.shared.armLayout(layout)
            Task { await StudioSession.shared.setLayout(layout) }
        }
    }
    var filmGain: Double = 1.0 {
        didSet { Task { await StudioSession.shared.setAudio(filmGain: Float(filmGain)) } }
    }
    var micGain: Double = 1.0 {
        didSet { Task { await StudioSession.shared.setAudio(micGain: Float(micGain)) } }
    }
    var filmMuted = false {
        didSet { Task { await StudioSession.shared.setAudio(filmMuted: filmMuted) } }
    }
    var micMuted = false {
        didSet { Task { await StudioSession.shared.setAudio(micMuted: micMuted) } }
    }
    var duckEnabled = true {
        didSet { Task { await StudioSession.shared.setAudio(duckEnabled: duckEnabled) } }
    }
    var showLowerThird = true {
        didSet { Task { await StudioSession.shared.setLowerThird(showLowerThird) } }
    }
    /// WHICH CARD THE HOST HAS CHOSEN, which is not the same as which card is
    /// ON AIR — and conflating the two made the free-text card unreachable.
    ///
    /// Found on the glass, 2026-09-22, immediately after writing it: the
    /// picker read its value back out of `card`, and §D10 says an EMPTY custom
    /// card is never shown, so choosing "My own words" set `card` to nil, the
    /// picker re-derived "No card" and snapped back, and the editor — shown
    /// only when the custom card was selected — never appeared. A host could
    /// not write the words because the editor needed the words.
    ///
    /// The choice is therefore its own state. `card` stays what the ENGINE is
    /// drawing, which is exactly the distinction §D5 draws between what a host
    /// has asked for and what an audience can see.
    var cardChoice: MacCardChoice = .none {
        didSet { applyCard() }
    }
    private(set) var card: StudioOverlay.Card? {
        didSet { Task { await StudioSession.shared.setCard(card) } }
    }

    private func applyCard() {
        switch cardChoice {
        case .custom:
            card = customCardHasWords ? .custom(lines: customCardLines) : nil
        default:
            card = cardChoice.value
        }
    }
    /// The call's fader (§D3). Defaults to the same 1.0 the others do, so a
    /// conversation arrives at the level it was spoken.
    var callGain: Double = 1.0 {
        didSet { Task { await StudioSession.shared.setAudio(callGain: Float(callGain)) } }
    }
    var callMuted = false {
        didSet { Task { await StudioSession.shared.setAudio(callMuted: callMuted) } }
    }

    /// THE HOST'S OWN CARD (macOS-DESIGN §D10), kept whether or not it is on
    /// screen — a host who writes an intermission notice, shows it, takes it
    /// down and shows it again should not have to type it twice.
    ///
    /// Four slots exist from the start so there is somewhere to type; the
    /// renderer drops the empty ones, so a one-line card is one line and not
    /// one line with three bands of black under it.
    var customCardLines: [StudioOverlay.CardLine] = [
        .init(id: 0, text: "", rank: .display),
        .init(id: 1, text: "", rank: .body),
        .init(id: 2, text: "", rank: .body),
        .init(id: 3, text: "", rank: .caption),
    ] {
        didSet {
            // ONLY WHEN IT IS THE CARD THE HOST HAS CHOSEN. Editing the words
            // while the "Intermission" card is up must not silently swap the
            // audience onto a half-typed sentence — but editing them while the
            // custom card IS chosen must reach the audience as you type, which
            // is the whole point of a free-text card. It also crosses the
            // empty/non-empty line, which is what turns the card on.
            guard cardChoice == .custom else { return }
            applyCard()
        }
    }

    /// True when at least one line has words in it. §D10: an empty custom card
    /// is not shown, because a black frame over the film with nothing on it is
    /// a fault rather than a choice.
    var customCardHasWords: Bool {
        customCardLines.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private init() {}
}

// MARK: - The Studio's show (§D7)

/// WHICH FILM THE STUDIO IS PRODUCING, and where its picture is drawn.
///
/// Owner, 2026-09-22: *"There doesn't seem to be any way to 'add a movie' to
/// the studio from the studio itself. You should be able to search for a movie
/// to stream directly from the studio."*
///
/// Until now the Studio had no film of its own: it rehearsed whatever the
/// PLAYER WINDOW happened to be playing, and with nothing playing it told the
/// host to go and start a film somewhere else. §D7 makes the Studio the owner
/// of the show — it holds the film, it hosts the player, and the ordinary
/// player window becomes a PROJECTION the host may ask for.
///
/// It also holds the go-live form, which used to be `@State` inside a sheet
/// that was destroyed every time it was dismissed. A host who signs in, types
/// a title, changes their mind about the platform and comes back should find
/// their title where they left it.
@MainActor
@Observable
final class StudioMacShow {
    static let shared = StudioMacShow()

    private(set) var film: Catalog.Item?
    /// The chooser is open — either because there is no film, or because the
    /// host pressed "Change film".
    var choosing = false

    // The go-live form (§D9), formerly `GoLiveSheetMac`'s `@State`.
    var platform: GoLivePlatform = .youtube
    var streamTitle = ""
    var category = ""
    var privacy: YouTubePrivacy = .unlisted
    var customURL = ""
    var customKey = ""

    private init() {
        // The diagnostic door `GoLiveSheetMac` carried, moved rather than
        // dropped: AW_GOLIVE_CUSTOM pre-seeds a custom destination so the
        // whole go-live path can be driven without the owner's client ids.
        if let u = ProcessInfo.processInfo.environment["AW_GOLIVE_CUSTOM"], !u.isEmpty {
            platform = .custom
            customURL = u
            customKey = "macbench"
        }
    }

    /// The Studio takes a film — from the chooser, or from a player window
    /// whose host pressed Go Live.
    ///
    /// ONE FILM, ONE PLAYER (§D7). Clearing `nowPlaying` tears down the player
    /// window's surface, which now genuinely stops its player (§D12), so the
    /// Studio's own surface is the only thing decoding. Two `AVPlayer`s on one
    /// film is the defect in the owner's sixth item, not a feature.
    func take(_ item: Catalog.Item, from router: AppRouter) {
        // The OLD film, read before it is replaced. Written the other way
        // round the test is against the value just assigned and can never be
        // true, so a host who changed films would keep the previous film's
        // stream title — the same silent-no-op shape as Decision 133.
        let changed = film?.archiveID != item.archiveID
        film = item
        choosing = false
        if changed || streamTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            streamTitle = Self.suggestedTitle(for: item)
        }
        router.nowPlaying = nil
        router.nowPlayingEpisode = nil
    }

    func suggestTitleIfEmpty() {
        guard streamTitle.trimmingCharacters(in: .whitespaces).isEmpty, let film else { return }
        streamTitle = Self.suggestedTitle(for: film)
    }

    static func suggestedTitle(for film: Catalog.Item) -> String {
        var t = film.title
        if let y = film.year { t += " (\(y))" }
        return t + " \u{2014} a public domain watch-along"
    }

    static func metaLine(for film: Catalog.Item) -> String? {
        var parts: [String] = []
        if let y = film.year { parts.append(String(y)) }
        if let d = film.director, !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    static func provenanceLine(for film: Catalog.Item) -> String? {
        guard film.rightsBucket == "safe_pd_age", let y = film.year else { return nil }
        return "Public domain \u{2014} published \(y), before 1930"
    }
}

// MARK: - The preview (§D5)

/// The composed PROGRAM, drawn from the engine's own output.
///
/// §D5: not the film with an overlay re-drawn in SwiftUI. The engine publishes
/// each frame it hands the encoder into `StudioProgramMirror`, and this view
/// puts that very frame on screen, so "what I see" and "what they see" cannot
/// diverge — the failure Decision 133 is about.
struct StudioProgramPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> ProgramLayerView { ProgramLayerView() }
    func updateNSView(_ view: ProgramLayerView, context: Context) {}
}

/// The frame is a `CVPixelBuffer` from an IOSurface-backed pool, so it reaches
/// the screen by being handed to a `CALayer` as its contents — no copy, no
/// colour conversion, no second render of a picture that has already been
/// composited once.
final class ProgramLayerView: NSView {
    private var timer: Timer?
    private var lastGeneration: UInt64 = 0
    /// THE DISPLAYED BUFFER IS HELD, and that is not a leak.
    ///
    /// `CVPixelBufferPool` recycles a buffer when the last reference to it
    /// goes, so a pool buffer that is only on screen can be handed straight
    /// back to the renderer and drawn into while the display is still reading
    /// it — a tear that would appear only under load and look like an encoder
    /// fault. One retained frame out of a pool of six costs nothing.
    private var displayed: CVPixelBuffer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        // 30 Hz, and on `.common` so the picture keeps moving while the host
        // is dragging the window's edge — a preview that freezes during a
        // resize reads as a broadcast that froze.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawLatest() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func drawLatest() {
        guard let (buffer, generation) = StudioProgramMirror.shared.latest(),
              generation != lastGeneration else { return }
        lastGeneration = generation
        guard let surface = CVPixelBufferGetIOSurface(buffer) else { return }
        displayed = buffer
        // Without this the layer animates every frame into the next and the
        // preview smears.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface.takeUnretainedValue()
        CATransaction.commit()
    }
}

// MARK: - The window

struct StudioWindowView: View {
    private var studio: StudioSession { StudioSession.shared }
    @Bindable private var controls = StudioControls.shared
    @Bindable private var show = StudioMacShow.shared
    /// The device lists, read once on appear and on demand rather than every
    /// redraw: `AVCaptureDevice.DiscoverySession` is not free, and this view
    /// redraws at the health tick.
    @State private var cameras: [StudioDevices.Device] = []
    @State private var microphones: [StudioDevices.Device] = []
    @State private var callApps: [StudioAudioProcesses.Process] = []
    @State private var chosenCallBundleID = ""
    @State private var previewRefusal: String?
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    /// Redraw the numbers on the same second the engine publishes them.
    /// `StudioSession` is `@Observable`, so `health` alone would do it — the
    /// timer is for the two derived per-second rates it recomputes in place.
    @State private var tick = 0

    private let marquee = Color(hex: "#FF5C35") ?? .orange

    /// The film's picture is in the ORDINARY player window, not in here (§D7).
    /// Derived rather than stored: one film has one player, so "is the main
    /// window playing" IS the answer, and a second flag could disagree with it.
    private var projecting: Bool { router.nowPlaying != nil }

    var body: some View {
        VStack(spacing: 0) {
            stage
            Divider()
            HStack(alignment: .top, spacing: 0) {
                column("Inputs") { inputs }
                Divider()
                column("Mixer") { mixer }
                Divider()
                column("Output") {
                    // §D9 — the pre-stream checklist, in the Studio rather
                    // than in a sheet over a different window.
                    StudioDestinationSection(onStarted: refreshDevices)
                    Divider().padding(.vertical, 2)
                    output
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 940, minHeight: 660)
        .onAppear {
            controls.layout = studio.armedLayout
            show.choosing = show.film == nil
            refreshDevices()
        }
        // A BROADCAST NEVER OUTLIVES ITS STUDIO (§D12). This is Rule B13a's one
        // genuinely load-bearing objection to a second window — that a host
        // could close the window their audience is watching through — kept as
        // a rule now that the window exists.
        .background(AWWindowCloseWatcher {
            Task { await StudioSession.shared.end() }
        })
    }

    // MARK: The stage — SOURCE and PROGRAM, side by side (§D8)

    /// §D5 gave the Studio ONE picture, the composed program. That is the
    /// picture that matters and it is not the picture a host watches the film
    /// on: following a story out of a 648-point preview with your own face in
    /// the corner of it is not watching a film.
    ///
    /// So the top of the Studio is OBS's preview/program split, for the same
    /// reason §D0 takes everything else from OBS — it is the arrangement hosts
    /// already know. `HSplitView` so the host decides which pane gets the room.
    private var stage: some View {
        HSplitView {
            sourcePane
                .frame(minWidth: 320, idealWidth: 520)
            programPane
                .frame(minWidth: 320, idealWidth: 520)
        }
        .frame(maxWidth: .infinity, minHeight: 230, idealHeight: 340, maxHeight: 460)
    }

    // MARK: SOURCE (§D7, §D8)

    private var sourcePane: some View {
        VStack(spacing: 0) {
            paneHeader("SOURCE", trailing: sourceHeaderControls)
            ZStack {
                Color.black
                if show.choosing || show.film == nil {
                    StudioFilmChooser(store: store) { pick in
                        show.take(pick, from: router)
                    } onCancel: {
                        // Only offerable when there is something to go back to.
                        show.choosing = false
                    }
                } else if projecting {
                    // §D7: the film MOVED, it was not copied. Two `AVPlayer`s
                    // on one title is the owner's sixth item, not a feature.
                    VStack(spacing: 10) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 26)).foregroundStyle(.secondary)
                        Text("Playing in a separate window")
                            .font(.headline).foregroundStyle(.white)
                        Text("Put that window on the screen you are projecting from. The program preview beside this one is unaffected.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 360)
                        Button("Bring it back into the Studio") { router.nowPlaying = nil }
                    }
                } else if let film = show.film {
                    // THE SAME SURFACE THE PLAYER WINDOW USES (§D7) — the same
                    // resilient loader, resume, caption paths and hand-off to
                    // the engine. A player written for the Studio would be a
                    // second copy of every one of those decisions.
                    PlayerSurface(archiveID: film.archiveID,
                                  videoURL: film.videoURLParsed.map {
                                      ArchiveVersions.preferredURL(for: film.archiveID, default: $0)
                                  },
                                  subtitleHLS: {
                                      let c = CaptionChoiceSession.byItem[film.archiveID]
                                      return (c == .automatic || c == .off) ? nil : film.subtitleHLSURL
                                  }(),
                                  captionsOff: CaptionChoiceSession.byItem[film.archiveID] == .off,
                                  publishedVTT: film.publishedVTTURL)
                        .id(film.archiveID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sourceHeaderControls: some View {
        if let film = show.film, !show.choosing {
            HStack(spacing: 8) {
                Button("Change film") { show.choosing = true }
                    .fixedSize()
                    .disabled(studio.isLive)
                Button(projecting ? "Bring it back" : "Open in a separate window") {
                    if projecting { router.nowPlaying = nil } else { router.play(film) }
                }
                .fixedSize()
                // §D7: the film cannot change windows mid-show. Moving it
                // rebuilds the `AVPlayer`, and the engine is attached to the
                // one it was given — so a move during a broadcast would leave
                // the audience on a frozen frame while everything else read
                // healthy. Disabled WITH THE REASON, never in silence.
                .disabled(studio.isLive)
                .help(studio.isLive
                      ? "Set this up before you start — the film cannot change windows during a show"
                      : "Show the film in its own window, to put on another screen")
            }
            .font(.caption)
        }
    }

    // MARK: PROGRAM (§D5, unchanged in substance)

    private var programPane: some View {
        VStack(spacing: 0) {
            paneHeader("PROGRAM", trailing: previewBadge)
            ZStack {
                Color.black
                StudioProgramPreview()
                if !studio.isLive { programIdle }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var programIdle: some View {
        // §D5: a host frames themselves, sets levels and picks a placement
        // BEFORE anything is broadcast. Explicit, never automatic — starting
        // it switches the camera on, and a camera light that comes on because
        // somebody opened a window is a surprise rather than a feature.
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing is being produced yet")
                .font(.headline).foregroundStyle(.white)
            if let film = show.film {
                Text("Rehearse with \(film.title) — you will see exactly what an audience would, and nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Start preview") { startPreview(film) }
                    .controlSize(.large)
                if let previewRefusal {
                    Text(previewRefusal).font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            } else {
                Text("Choose a film on the left, and you can rehearse the whole show here before anything is broadcast.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.horizontal, 12)
    }

    private func startPreview(_ film: Catalog.Item) {
        previewRefusal = nil
        Task {
            // §D11: ASK for the camera and the microphone. `beginShow` does it
            // before building the engine, because `attachCameraIfAvailable`
            // reads the authorisation status and returns silently when it is
            // not yet `.authorized` — which on macOS it always was.
            let started = await studio.beginShow(film: film, destination: nil)
            if !started { previewRefusal = studio.refusal }
            refreshDevices()
        }
    }

    private func paneHeader<T: View>(_ title: String, trailing: T) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// The preview says WHAT IT IS (§D5). A picture with no label is one a
    /// host can mistake for a rehearsal when it is a broadcast.
    private var previewBadge: some View {
        HStack(spacing: 6) {
            // RED MEANS ON AIR. `isLive` means the engine is running, which
            // includes a rehearsal that goes nowhere — a red dot keyed to it
            // would tell a host they were broadcasting when they were not.
            Circle().fill(studio.isOnAir ? Color.red : Color.secondary)
                .frame(width: 7, height: 7)
            Text(studio.isOnAir ? "going out"
                 : (studio.isRehearsing ? "nothing is being sent" : "idle"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(studio.isOnAir ? .primary : .secondary)
        }
    }

    // MARK: Columns

    private func column<Content: View>(_ title: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Inputs (§D2, §D11)

    private var inputs: some View {
        let health = studio.health
        return Group {
            // THE FILM IS CHOSEN HERE (§D7), and the row says which.
            VStack(alignment: .leading, spacing: 4) {
                inputRow(name: show.film?.title ?? "No film chosen",
                         role: show.film.flatMap(StudioMacShow.metaLine(for:)) ?? "Film",
                         state: studio.isLive
                            ? (studio.filmFramesPerSecond > 0
                               ? "\(studio.filmFramesPerSecond) fps"
                               : "no new frames")
                            // "ready" over "No film" is a claim the row cannot
                            // make: nothing is ready until a film is playing.
                            : (show.film == nil ? "choose one" : "ready"),
                         healthy: !studio.isLive || studio.filmFramesPerSecond > 0,
                         icon: "film")
                if show.film != nil, !studio.isLive {
                    Button("Choose a different film") { show.choosing = true }
                        .font(.caption).buttonStyle(.borderless).fixedSize()
                }
            }

            // EVERY INPUT IS NAMED, AND ITS DEVICE IS CHOSEN (§D2).
            //
            // This Mac reports FOUR cameras — the built-in FaceTime camera,
            // two virtual ones, and the host's iPhone over Continuity — and
            // `AVCaptureDevice.default` silently took the first of them. A
            // host who wanted their phone as the camera had no way to say so.
            deviceRow(role: "Camera", icon: "video",
                      media: .video,
                      devices: cameras,
                      selection: Binding(
                        get: { StudioDevices.chosenCameraID ?? "" },
                        set: { id in changeDevice { StudioDevices.chosenCameraID = id.isEmpty ? nil : id } }),
                      state: health.cameraAttached
                        ? (health.cameraFramesReceived == 0
                           ? "starting"
                           : (studio.cameraFramesPerSecond > 0
                              ? "\(studio.cameraFramesPerSecond) fps"
                              : "stopped"))
                        : (studio.isLive ? "not attached" : "ready"),
                      healthy: !health.cameraAttached || health.cameraFramesReceived == 0
                        || studio.cameraFramesPerSecond > 0)

            deviceRow(role: "Microphone", icon: "mic",
                      media: .audio,
                      devices: microphones,
                      selection: Binding(
                        get: { StudioDevices.chosenMicrophoneID ?? "" },
                        set: { id in changeDevice { StudioDevices.chosenMicrophoneID = id.isEmpty ? nil : id } }),
                      state: controls.micMuted ? "muted"
                        : (studio.isLive ? "live" : "ready"),
                      healthy: true)

            // §D11 REPLACED THE SENTENCE THAT USED TO BE HERE — "device changes
            // take effect on the next broadcast" — and the pickers above are
            // no longer disabled while live. The fact behind that sentence was
            // true (an `AVCaptureSession` is configured once) and the
            // conclusion drawn from it was not: the capture session is not the
            // encoder, the camera tile is COMPOSITED, and the wire never
            // learns which device produced those pixels. A host whose webcam
            // is pointing at the wall can now fix it mid-show.

            // THE FOURTH INPUT: a call's audio (§D2, Decision 131). The host
            // uses whatever calling service they already have and the Studio
            // captures that APP — which is what removes the guest-voice
            // transport, and with it the relay, the NAT traversal and the
            // running cost that failed the $0 constraint every other way.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "person.wave.2").frame(width: 16)
                        .foregroundStyle(.secondary)
                    Text("A call").font(.subheadline.weight(.medium))
                    Spacer(minLength: 6)
                    Text(studio.callAppName == nil ? "not captured"
                         : (studio.health.audio.callAttached ? "capturing" : "starting"))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(studio.callProblem == nil ? .secondary : Color.orange)
                }
                Picker("A call", selection: Binding(
                    get: { chosenCallBundleID },
                    set: { id in
                        chosenCallBundleID = id
                        if id.isEmpty { studio.stopCallAudio() }
                        else if let p = callApps.first(where: { $0.name == id }) {
                            Task { await studio.startCallAudio(process: p) }
                        }
                    })) {
                    Text("None").tag("")
                    Divider()
                    ForEach(callApps) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                if let why = studio.callProblem {
                    Text(why).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Zoom, Meet, FaceTime — whatever you are already on. Your guests are heard; the film is not captured twice.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().padding(.vertical, 2)

            // WHERE THE CAMERA GOES. It is an input question — how the
            // sources are arranged — so it belongs in this column rather
            // than beside the bitrate.
            VStack(alignment: .leading, spacing: 6) {
                Text("Placement").font(.subheadline.weight(.semibold))
                Picker("Placement", selection: $controls.layout) {
                    ForEach(StudioLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("On screen").font(.subheadline.weight(.semibold))
                Toggle("Show the film's title", isOn: $controls.showLowerThird)
                Picker("Card", selection: $controls.cardChoice) {
                    ForEach(MacCardChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if controls.cardChoice == .custom {
                    StudioCustomCardEditor(controls: controls)
                }
                Text("A card covers the film completely — your audience sees only the card.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Apply a device choice and make it LAND (§D11, Decision 133).
    ///
    /// Writing the preference is not choosing a camera: the capture session
    /// resolves the id when it is built, so a change made while a show is
    /// running reaches nothing until the session is rebuilt. This is the one
    /// place that pairs the two, so no caller has to remember.
    private func changeDevice(_ apply: () -> Void) {
        apply()
        Task {
            if studio.isLive { await studio.rebuildCapture() }
            refreshDevices()
        }
    }

    private func refreshDevices() {
        cameras = StudioDevices.cameras()
        microphones = StudioDevices.microphones()
        if #available(macOS 14.2, *) { callApps = StudioAudioProcesses.all() }
    }

    /// One input: what it IS, which device it uses, and what it is doing.
    /// The picker carries "System default" and "None" alongside the real
    /// devices — None is a deliberate choice and not the same as having none.
    ///
    /// AND IT CARRIES THE PERMISSION (§D11). The four TCC states used to
    /// collapse into a silent `return` inside `attachCameraIfAvailable`, so a
    /// Mac that had never been asked and a Mac with no camera at all drew the
    /// identical row — "not attached" — with nothing to press. Owner,
    /// 2026-09-22: *"I cannot seem to attach any cameras (not even the
    /// facetime camera) to the studio."* They could not: nothing in the macOS
    /// product path had ever called `requestAccess`, so the status was
    /// `.notDetermined` and would have stayed there for the life of the app.
    private func deviceRow(role: String, icon: String,
                           media: AVMediaType,
                           devices: [StudioDevices.Device],
                           selection: Binding<String>,
                           state: String, healthy: Bool) -> some View {
        let access = StudioSession.access(for: media)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(role).font(.subheadline.weight(.medium))
                Spacer(minLength: 6)
                Text(accessState(access, devices: devices, running: state))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(access == .granted && healthy ? .secondary : Color.orange)
            }
            Picker(role, selection: selection) {
                Text("System default").tag("")
                Text("None").tag(StudioDevices.noneID)
                Divider()
                ForEach(devices) { d in Text(d.name).tag(d.id) }
            }
            .labelsHidden()
            // §D11: LIVE AT ALL TIMES. `.disabled(studio.isLive)` used to be
            // here on the strength of §D2's "next broadcast" sentence, and it
            // is what the owner met — "the camera and microphone do not seem
            // to be able to be changed once the studio is up and running".
            .disabled(access != .granted)
            switch access {
            case .notAsked:
                Button("Allow the \(role.lowercased())") {
                    Task {
                        _ = await studio.requestCaptureAccess()
                        refreshDevices()
                    }
                }
                .font(.caption).fixedSize()
            case .denied, .restricted:
                Button("Open System Settings") {
                    // The one place macOS lets an app send a host to its own
                    // privacy pane. There is no API to re-ask once denied.
                    let pane = media == .video ? "Privacy_Camera" : "Privacy_Microphone"
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .font(.caption).fixedSize()
            case .granted:
                EmptyView()
            }
        }
    }

    /// The row's state sentence, permission first. A frame rate over a camera
    /// nobody has been asked about is a number describing nothing.
    private func accessState(_ access: StudioSession.CaptureAccess,
                             devices: [StudioDevices.Device],
                             running: String) -> String {
        switch access {
        case .notAsked:   return "not asked yet"
        case .denied:     return "not allowed"
        case .restricted: return "not permitted on this Mac"
        case .granted:    return devices.isEmpty ? "none on this Mac" : running
        }
    }

    private func inputRow(name: String, role: String, state: String,
                          healthy: Bool, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(role).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(state)
                .font(.caption).monospacedDigit()
                .foregroundStyle(healthy ? .secondary : Color.orange)
        }
    }

    // MARK: Mixer (§D3)

    private var mixer: some View {
        let audio = studio.health.audio
        return Group {
            StudioMacFader(label: "Film", icon: "film", level: audio.filmLevel,
                           gain: $controls.filmGain, muted: $controls.filmMuted)
            StudioMacFader(label: "Your microphone", icon: "mic", level: audio.micLevel,
                           gain: $controls.micGain, muted: $controls.micMuted)
            // §D3: one channel per AUDIBLE input. The call's channel appears
            // when there IS a call — a third fader over nothing would show a
            // dead meter and read as broken.
            if audio.callAttached {
                StudioMacFader(label: studio.callAppName ?? "A call",
                               icon: "person.wave.2", level: audio.callLevel,
                               gain: $controls.callGain, muted: $controls.callMuted)
            }
            Divider().padding(.vertical, 2)
            // AUTO-DUCK IS A CONTROL, NOT A SENTENCE (Rule 8.8c). A host who
            // sets Film to 9, speaks, and hears it drop 12 dB anyway will
            // reasonably conclude the fader is broken. Manual means manual.
            Toggle("Duck the film under my voice", isOn: $controls.duckEnabled)
            Text(controls.duckEnabled
                 ? (audio.ducking
                    ? "The film is ducking under the talking."
                    : "The film drops 12 dB automatically while you or your guests are talking.")
                 : "The film stays where you set it.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Output (§D4)

    private var output: some View {
        let health = studio.health
        return Group {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(health.showState.isOnAir ? Color.red : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(health.showState.label).font(.subheadline.weight(.semibold))
                }
                if let detail = health.showState.detail {
                    Text(detail).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(destinationName)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 2)

            // THE HOST'S SETTINGS (§D4), with the engine's own numbers below
            // them. Resolution and frame rate are disabled while live WITH
            // THE REASON ON SCREEN rather than hidden: an RTMP ingest will
            // not accept a change to either mid-publish, which is the
            // correction §6.5 already carries. The bitrate stays live,
            // because the encoder genuinely supports it — it is the same path
            // a thermal step uses.
            VStack(alignment: .leading, spacing: 8) {
                Picker("Size", selection: Binding(
                    get: { StudioOutputSettings.selectedSize.id },
                    set: { id in
                        if let s = StudioOutputSettings.sizes.first(where: { $0.id == id }) {
                            StudioOutputSettings.width = s.width
                            StudioOutputSettings.height = s.height
                        }
                    })) {
                    ForEach(StudioOutputSettings.sizes) { Text($0.label).tag($0.id) }
                }
                .disabled(studio.isLive)

                Picker("Frame rate", selection: Binding(
                    get: { StudioOutputSettings.frameRate },
                    set: { StudioOutputSettings.frameRate = $0 })) {
                    ForEach(StudioOutputSettings.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
                .disabled(studio.isLive)

                Picker("Bitrate", selection: Binding(
                    get: { StudioOutputSettings.bitrateKbps },
                    set: { kbps in
                        StudioOutputSettings.bitrateKbps = kbps
                        // AND IT LANDS AT THE ENCODER, not just in a
                        // preference (Decision 133).
                        Task { await studio.setVideoBitrate(kbps * 1_000) }
                    })) {
                    ForEach(StudioOutputSettings.bitratesKbps, id: \.self) {
                        Text("\($0 / 1000) Mbps").tag($0)
                    }
                }

                if studio.isLive {
                    Text("Size and frame rate cannot change during a broadcast — an RTMP ingest will not accept it. The bitrate can.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().padding(.vertical, 2)

            // WHAT THE ENGINE IS ACTUALLY DOING, beside what was asked for.
            stat("Picture", value: String(format: "%.1f ms per frame · %d fps",
                                          health.averageRenderMilliseconds,
                                          health.encodedFramesPerSecond))
            // ASKED vs ACTUAL, and the difference is the point (§D4): §6.5's
            // thermal step moves the real rate, and a single number would
            // hide that it had.
            stat("Bitrate asked", value: "\(StudioOutputSettings.bitrateKbps) kbps")
            stat("Bitrate actual", value: health.videoBitrateNow > 0
                 ? "\(health.videoBitrateNow / 1000) kbps"
                 : "\(measuredKbps) kbps measured")
            stat("Encoder", value: health.encoderIsHardware.map {
                $0 ? "hardware" : "software" } ?? "not started")
            stat("Dropped", value: "\(health.publisher.videoFramesDropped) frames")
            // §D0's "stats that name a fault". Dropped frames alone cannot
            // tell a struggling UPLINK from a struggling ENCODER: a backlog
            // means the network is not taking what we produce (§6.4), and a
            // reconnect count means the link has actually been lost and
            // rebuilt (§6.6). Both were measured and shown nowhere on macOS.
            stat("Waiting to send", value: backlogText)
            if health.publisher.reconnects > 0 || health.publisher.isReconnecting {
                stat("Reconnects", value: health.publisher.isReconnecting
                     ? "\(health.publisher.reconnects) · rebuilding now"
                     : "\(health.publisher.reconnects)")
            }
            stat("Sent", value: sentText)
            stat("This Mac", value: health.thermalState)
            // THE FILM ENDED AND THE SHOW DID NOT (owner item 13, §9.bbbbbb).
            //
            // Said, with the right answer one click away — NOT done
            // automatically. The owner's rule is that "the stream should only
            // end when the person streaming it decides that it should end",
            // and a card thrown up on its own would override a host who is
            // mid-sentence. The feature already owns the right graphic for
            // this moment and offered it automatically nowhere.
            if studio.isLive, studio.filmHasEnded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The film has ended. Your audience is watching a still — your camera and microphone are still live.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if controls.card == nil {
                        Button("Show the \u{201C}Thanks for watching\u{201D} card") {
                            // THE CHOICE, not the card. Writing `card` directly
                            // would put a card on air that the picker two
                            // columns away still described as "No card" — the
                            // control that disagrees with the programme, which
                            // is the whole of Decision 133.
                            controls.cardChoice = .ending
                        }
                        .font(.caption)
                    }
                }
            }
            if let note = health.qualityNote {
                Text(note).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fault = health.encoderFault {
                Text(fault).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = health.publisher.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 2)

            // §3.4a — what the rights gate cannot protect a host from.
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(StudioRights.hostWarning)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // THE STREAM ENDS WHEN THE HOST SAYS SO. Owner: "There should be
            // an easy way to end a stream from every platform that can start
            // one." On the Mac that is here, in the window that is open for
            // the whole show, as well as on the readout over the player.
            if studio.isLive {
                Button(studio.isOnAir ? "End the broadcast" : "Stop the preview",
                       role: .destructive) {
                    Task { await studio.end() }
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.caption).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    /// A backlog in BYTES means nothing to a host; in seconds it is the
    /// latency they are adding to their own show, which is what §6.4's cap is
    /// a budget for.
    private var backlogText: String {
        let queued = studio.health.publisher.queuedBytes
        guard queued > 0 else { return "nothing" }
        let bps = max(1, studio.health.videoBitrateNow > 0
                      ? studio.health.videoBitrateNow
                      : StudioOutputSettings.bitrateKbps * 1_000)
        let seconds = Double(queued * 8) / Double(bps)
        return String(format: "%@ · %.1f s behind", byteText(queued), seconds)
    }

    private var sentText: String { byteText(studio.health.publisher.bytesSent) }

    private func byteText(_ b: Int) -> String {
        if b >= 1_000_000 { return String(format: "%.1f MB", Double(b) / 1_000_000) }
        if b >= 1_000 { return String(format: "%.0f kB", Double(b) / 1_000) }
        return "\(b) B"
    }

    private var destinationName: String {
        guard let url = studio.armedDestination else { return "No destination set" }
        return url.host.map { "Sending to \($0)" } ?? "Destination set"
    }

    /// The measured rate, for before `videoBitrateNow` is known.
    private var measuredKbps: Int {
        let seconds = max(1, studio.health.programFramesEncoded / 30)
        return max(0, studio.health.encodedBytes * 8 / 1000 / seconds)
    }
}


// MARK: - The pre-stream checklist (§D9)

/// WHERE THE BROADCAST GOES, SET UP IN THE STUDIO.
///
/// This replaces Rule B13g's sheet — `GoLiveSheetMac`, presented by the window
/// ROOT over the player. Owner, 2026-09-22: *"There does[n't] seem to be any
/// way to set up Youtube or Twitch via the studio (or anywhere else in the
/// macos app). The whole pre-stream checklist that exists on the other
/// platforms doesn't seem to exist on the MacOS app. (I think I may have found
/// it hidden behind a button on the video player (rather than in the studio
/// for some reason.)"*
///
/// That is the honest verdict on a form that lived over a different window
/// from the controls it configures. B13g asked "where does a host PRESS Go
/// Live" and answered it twice — a menu command, then a toolbar button — and
/// never asked where a host DECIDES to go live.
///
/// The content is the sheet's, carried over rather than rewritten, because
/// §B13c's reasoning still holds: a host who learned the iPhone's version
/// should recognise this one, and a second copy of the rights and sign-in copy
/// is a second chance to get it wrong. `StudioSignInRow` is the same shared
/// row iOS and tvOS draw.
struct StudioDestinationSection: View {
    /// Called once a show actually starts, so the window can re-read the
    /// device lists — a capture session that has just opened knows things a
    /// `DiscoverySession` taken before it did not.
    var onStarted: () -> Void = {}

    private var studio: StudioSession { StudioSession.shared }
    @Bindable private var show = StudioMacShow.shared
    @Bindable private var controls = StudioControls.shared

    /// Mirrored from the sign-in row: `isSignedIn` is a Keychain read, not
    /// observable state, so asking it directly here would leave Go Live
    /// disabled behind a row that already says "Signed in".
    @State private var signedIn = false
    /// What the PLATFORM says about this channel, asked with a READ before the
    /// host presses anything (§9.zzz). Nil means "not asked yet" and
    /// deliberately does NOT block Go Live: a slow API must not gate a
    /// control, and a host who presses through an unknown meets the real error
    /// anyway. Only a KNOWN-bad answer stops them, and it stops them with a
    /// sentence.
    @State private var readiness: StudioPlatformAuth.Readiness?
    @State private var problem: String?
    @State private var working = false

    private var authPlatform: StudioPlatformAuth.Platform {
        show.platform == .twitch ? .twitch : .youtube
    }

    private var refusal: String? {
        guard let film = show.film else { return nil }
        return StudioRights.refusal(rightsBucket: film.rightsBucket,
                                    contentType: film.contentType,
                                    year: film.year)
    }

    /// Why a signed-in host still cannot broadcast, or nil.
    private var blockedReason: String? {
        guard show.platform != .custom, case .blocked(let why)? = readiness else { return nil }
        return why
    }

    var body: some View {
        Group {
            if show.film == nil {
                Text("Choose a film first — the rights gate decides what may be broadcast, and it needs a title to judge.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let refusal {
                // NOT a disabled control with no explanation (§5) — the same
                // sentence the iPhone and the television show.
                VStack(alignment: .leading, spacing: 5) {
                    Label("This film cannot be streamed", systemImage: "hand.raised")
                        .font(.subheadline.weight(.semibold))
                    Text(refusal).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Text(StudioRights.policy).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                form
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Platform", selection: $show.platform) {
                ForEach(GoLivePlatform.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(studio.isOnAir)

            if show.platform != .custom {
                StudioSignInRow(platform: authPlatform) { signedIn = $0 }
                    .task(id: signedIn) {
                        guard signedIn, show.platform != .custom, readiness == nil else { return }
                        readiness = try? await StudioPlatformAuth.readiness(for: authPlatform)
                    }
                    .onChange(of: show.platform) { _, _ in readiness = nil }
            }

            switch show.platform {
            case .youtube:
                labelled("Stream title") { TextField("", text: $show.streamTitle) }
                Picker("Privacy", selection: $show.privacy) {
                    ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            case .twitch:
                labelled("Stream title") { TextField("", text: $show.streamTitle) }
                labelled("Category") { TextField("", text: $show.category) }
            case .custom:
                // The diagnostic path. A real destination is never typed.
                labelled("rtmps://host/app") { TextField("", text: $show.customURL) }
                labelled("Stream key") { SecureField("", text: $show.customKey) }
            }
        }
        .disabled(studio.isOnAir)

        Text(StudioRights.policy).font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if let problem {
            Text(problem).font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        // DISABLED WITH THE REASON ABOVE IT, never in silence (§D9).
        if let why = cannotGoLive {
            Text(why).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !studio.isOnAir {
            Button(studio.isRehearsing ? "Go Live (ends the preview)" : "Go Live") { goLive() }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(cannotGoLive != nil || working)
        }
    }

    /// One reason, the most actionable first. A list of everything wrong is a
    /// list nobody reads; the next thing to do is one thing.
    private var cannotGoLive: String? {
        guard show.film != nil else { return "Choose a film first." }
        if show.platform == .custom {
            guard URL(string: show.customURL)?.host != nil, !show.customKey.isEmpty else {
                return "A custom destination needs a server and a stream key."
            }
            return nil
        }
        guard !show.streamTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Your broadcast needs a title."
        }
        // CONFIGURED IS NOT SIGNED IN, and SIGNED IN IS NOT READY. The first
        // was a real defect on this platform (§9.sss): the gate read
        // `configurationProblem == nil`, which was a fair proxy only while no
        // client id existed anywhere — the day both were registered it became
        // permanently nil and Go Live switched itself on for a Mac with no
        // token. The second is §9.zzz: going live is four WRITES whose first
        // creates a real object on the host's channel, so "will this work?"
        // is asked with a read, up front.
        guard signedIn else { return "Sign in to \(show.platform.label) to broadcast there." }
        if let blockedReason { return blockedReason }
        return nil
    }

    private func goLive() {
        guard let film = show.film, cannotGoLive == nil else { return }
        working = true
        problem = nil
        Task {
            defer { working = false }
            let request = GoLiveRequest(
                archiveID: film.archiveID,
                platform: show.platform,
                title: show.streamTitle.trimmingCharacters(in: .whitespaces),
                category: show.category.trimmingCharacters(in: .whitespaces),
                privacy: show.privacy,
                layout: controls.layout,
                customServer: show.platform == .custom ? URL(string: show.customURL) : nil,
                customKey: show.platform == .custom ? show.customKey : nil)
            do {
                let dest = try await StudioGoLive.destination(for: request, film: film)
                // A REHEARSAL MUST END BEFORE A BROADCAST BEGINS. `beginShow`
                // guards on `!isLive`, and §D5's preview leaves the engine
                // RUNNING with no destination — so arming for a real broadcast
                // would be silently ignored and the host would have pressed Go
                // Live to no effect.
                if studio.isRehearsing { await studio.end() }
                studio.armLayout(controls.layout)
                let started = await studio.beginShow(film: film, destination: dest)
                if !started { problem = studio.refusal }
                onStarted()
            } catch {
                problem = "The broadcast could not start — \(error)."
            }
        }
    }

    /// A label above its field rather than beside it. The Output column is
    /// ~300 points wide, and macOS's own leading-label form layout gives a
    /// `TextField` whatever is left — which at this width is a slot too narrow
    /// to read a film title in.
    @ViewBuilder
    private func labelled<T: View>(_ title: String, @ViewBuilder field: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            field().textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Choosing a film, in the Studio (§D7)

/// Search the catalogue from inside the Studio.
///
/// Owner, 2026-09-22: *"There doesn't seem to be any way to 'add a movie' to
/// the studio from the studio itself. You should be able to search for a movie
/// to stream directly from the studio."*
///
/// IT SHOWS WHAT CANNOT BE STREAMED, rather than hiding it. Filtering the
/// rights-refused titles out would leave a host searching for a film they can
/// see everywhere else in the app and finding nothing, with no way to learn
/// why — the "absence written where a screen was needed" mistake Decision 128
/// names. A refused row is drawn, unselectable, with its own reason.
struct StudioFilmChooser: View {
    let store: AppStore
    let onPick: (Catalog.Item) -> Void
    let onCancel: (() -> Void)?

    @State private var query = ""
    @State private var results: [Catalog.Item] = []
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search for a film to stream", text: $query)
                    .textFieldStyle(.plain)
                if let onCancel, StudioMacShow.shared.film != nil {
                    Button("Cancel") { onCancel() }.fixedSize()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.bar)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = []; searched = false; return }
            try? await Task.sleep(for: .milliseconds(180))   // debounce
            guard !Task.isCancelled else { return }
            // A TITLE WITH NO PLAYABLE COPY CANNOT BE A SHOW. `videoURLParsed`
            // nil means the catalogue has no file for it — a series spine, or
            // an item whose copy went away — and offering one here would fail
            // at the player rather than at the choice.
            results = store.search(q).filter { $0.videoURLParsed != nil }
            searched = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: searched ? "questionmark.circle" : "film.stack")
                    .font(.system(size: 26)).foregroundStyle(.secondary)
                Text(searched ? "Nothing matched \u{201C}\(query)\u{201D}"
                     : "Type a title to find something to stream")
                    .font(.callout).foregroundStyle(.secondary)
                if !searched {
                    Text("Only public-domain titles the rights audit clears can be broadcast — you will see which, and why, as you search.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 340)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { item in
                row(item)
                    .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
            }
            .listStyle(.inset)
        }
    }

    private func row(_ item: Catalog.Item) -> some View {
        let refusal = StudioRights.refusal(rightsBucket: item.rightsBucket,
                                           contentType: item.contentType,
                                           year: item.year)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                .frame(width: 44, height: 62)
                .overlay {
                    if let u = item.posterURLParsed {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                if let meta = StudioMacShow.metaLine(for: item) {
                    Text(meta).font(.caption2).foregroundStyle(.secondary)
                }
                if let refusal {
                    Text(refusal).font(.caption2).foregroundStyle(.orange)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if refusal == nil {
                Button("Use this film") { onPick(item) }.fixedSize()
            }
        }
        .opacity(refusal == nil ? 1 : 0.7)
    }
}

// MARK: - The host's own card (§D10)

/// Four lines, each with a rank. Owner, 2026-09-22: *"I'd like to be able to
/// have a 'free text' option for the Cards. Ideally with multiple lines of
/// different weights as the cards exist now."*
///
/// The ranks are the project's own hierarchy levels, not a font size control:
/// CLAUDE.md allows six levels and refuses a seventh, and a card uses four of
/// them. A host chooses the WORDS and their RANK; the design system keeps
/// typeface, colour, position and ground, which is what makes a custom card
/// look like the three fixed ones rather than like a different product.
struct StudioCustomCardEditor: View {
    @Bindable var controls: StudioControls

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($controls.customCardLines) { $line in
                HStack(spacing: 6) {
                    TextField("", text: $line.text, prompt: Text(prompt(for: line.rank)))
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $line.rank) {
                        ForEach(StudioOverlay.CardLine.Rank.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            // An empty custom card is not shown (§D10), and the editor says so
            // rather than letting a host press Show over a black frame.
            if !controls.customCardHasWords {
                Text("Write at least one line — an empty card would cover the film with nothing.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }

    private func prompt(for rank: StudioOverlay.CardLine.Rank) -> String {
        switch rank {
        case .display: return "Back in five"
        case .heading: return "A short heading"
        case .body:    return "A line of explanation"
        case .caption: return "A small note"
        }
    }
}

/// One mixer channel: a live meter, a fader on the shared 0–10 scale, a mute.
/// The meter is the point — a fader with no meter is a control whose effect
/// you cannot hear until the audience already has.
struct StudioMacFader: View {
    let label: String
    let icon: String
    let level: Float
    @Binding var gain: Double
    @Binding var muted: Bool

    private let marquee = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(label, systemImage: icon).font(.subheadline.weight(.medium))
                Spacer()
                Toggle(isOn: Binding(get: { !muted }, set: { muted = !$0 })) {
                    Text(muted ? "Muted" : "On")
                }
                .toggleStyle(.switch).controlSize(.mini)
            }
            // The meter reads on the FADER'S scale, not linearly. A linear
            // 0-1 meter draws 2% for speech at RMS 0.02 and looks dead, which
            // is how a working microphone reads as a broken one.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule()
                        .fill(muted ? Color.secondary : marquee)
                        .frame(width: geo.size.width
                               * CGFloat(min(1, max(0, MixLevel.meterFraction(rms: level)))),
                               height: 4)
                }
            }
            .frame(height: 4)
            HStack(spacing: 10) {
                Slider(value: Binding(get: { MixLevel.level(Float(gain)) },
                                      set: { gain = Double(MixLevel.gain($0)) }),
                       in: 0...MixLevel.maximum)
                    .disabled(muted)
                Text(MixLevel.text(MixLevel.level(Float(gain))))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(muted ? .secondary : .primary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

/// The cards, as an exclusive choice. They are actions with consequences,
/// not a mode toggle.
enum MacCardChoice: CaseIterable, Hashable {
    case none, startingSoon, intermission, ending, custom

    var label: String {
        switch self {
        case .none: return "No card"
        case .startingSoon: return "Starting soon"
        case .intermission: return "Intermission"
        case .ending: return "Thanks for watching"
        case .custom: return "My own words"
        }
    }
    /// The three FIXED cards are constants. The custom one is assembled from
    /// whatever the host has typed, so it has no value here and its caller
    /// builds it — a constant `.custom(lines: [])` returned from this switch
    /// would be an empty card, which §D10 says is never shown.
    var value: StudioOverlay.Card? {
        switch self {
        case .none, .custom: return nil
        case .startingSoon: return .startingSoon(secondsRemaining: 0)
        case .intermission: return .intermission
        case .ending: return .ending
        }
    }
}
#endif
