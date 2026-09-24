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
            // CHOOSING A PLACEMENT GIVES YOU THAT PLACEMENT (§D14a).
            //
            // The tile's rect is cleared, the zoom and pan are kept. §D14a
            // says framing "is not per-layout — the crop follows the person,
            // the preset follows the show", and that is right about the CROP
            // and wrong about the TILE: deciding where the tile goes is the
            // placement's entire job, so a custom rect surviving the change
            // would make the picker look broken. A host who framed their face
            // keeps that face; a host who asks for "Side by side" gets it.
            if framing.tile != nil {
                var f = framing
                f.tile = nil
                framing = f
            }
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
    // WHICH LINES THE LOWER THIRD CARRIES (§D15). One toggle used to draw all
    // three or none; the host chooses each.
    var showLowerThird = true { didSet { pushLowerThird() } }
    var showFilmTitle = true { didSet { pushLowerThird() } }
    var showFilmMeta = true { didSet { pushLowerThird() } }
    var showProvenance = true { didSet { pushLowerThird() } }

    private func pushLowerThird() {
        let on = showLowerThird
        Task {
            await StudioSession.shared.setLowerThird(title: on && showFilmTitle,
                                                     meta: on && showFilmMeta,
                                                     provenance: on && showProvenance)
        }
    }

    /// §D14 — how the host sits in the show. Armed rather than set, so a
    /// choice made before the engine exists is the one the show starts with.
    var framing = StudioCameraFraming() {
        didSet {
            guard framing != oldValue else { return }
            StudioSession.shared.armFraming(framing)
        }
    }
    /// §D24 — the guests' framing, same type, separate value.
    var guestFraming = StudioCameraFraming() {
        didSet {
            guard guestFraming != oldValue else { return }
            StudioSession.shared.armGuestFraming(guestFraming)
        }
    }
    /// WHICH TILE THE HANDLES DRIVE. One box at a time: two sets of handles
    /// would make a drag ambiguous wherever the tiles overlap, and §D23
    /// stacks them deliberately in one column.
    var framingTarget: StudioFramingTarget = .camera

    /// The framing the handles are currently driving. The gesture code reads
    /// and writes THIS and never names a tile — otherwise every drag, resize,
    /// crop, zoom and pan would need its own `if target ==` and the sixth one
    /// would be the one somebody forgets (Decision 133).
    var activeFraming: StudioCameraFraming {
        get { framingTarget == .camera ? framing : guestFraming }
        set {
            if framingTarget == .camera { framing = newValue } else { guestFraming = newValue }
        }
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
    /// §D19 — a card being COMPOSED, which is not on air. Staging is a
    /// separate value from `cardChoice` for the same reason `cardChoice` is
    /// separate from `card`: what a host has chosen, what they are preparing,
    /// and what the audience can see are three different facts, and every
    /// time this feature collapsed two of them it produced a defect.
    var stagedCard: MacCardChoice = .none

    // MARK: Chat (§D22)

    var showChat = true {
        didSet { guard showChat != oldValue else { return }; pushChat() }
    }
    var chatSide: StudioChatSide = .left {
        didSet { guard chatSide != oldValue else { return }; pushChat() }
    }
    var chatHideCommands = true {
        didSet { guard chatHideCommands != oldValue else { return }; pushChat() }
    }
    var chatHideLinks = true {
        didSet { guard chatHideLinks != oldValue else { return }; pushChat() }
    }
    var chatBlocked = "" {
        didSet { guard chatBlocked != oldValue else { return }; pushChat() }
    }

    /// ONE writer, so the four controls cannot disagree about what the engine
    /// holds. Decision 133's rule: a control is proved where its value lands,
    /// and five separate pushes are five chances for one of them to be missed.
    private func pushChat() {
        let f = StudioChatFilter(hideCommands: chatHideCommands,
                                 hideLinks: chatHideLinks,
                                 blockedText: chatBlocked)
        let on = showChat, side = chatSide
        Task { await StudioSession.shared.setChat(enabled: on, side: side, filter: f) }
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

    /// Roadmap #4 — the microphone gate. OFF by default: a host who has never
    /// had one should not suddenly find their quiet asides cut off, and Rule
    /// 8.8c's "manual means manual" applies to a gate exactly as it does to
    /// the duck. The reason to turn it on is written beside it.
    var micGateEnabled = false {
        didSet { Task { await StudioSession.shared.setAudio(micGateEnabled: micGateEnabled) } }
    }
    var micGateThreshold: Double = 0.02 {
        didSet { Task { await StudioSession.shared.setAudio(micGateThreshold: Float(micGateThreshold)) } }
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
    /// SIMULCAST (roadmap #2) — also send this show to the OTHER platform.
    /// One checkbox rather than StreamYard's list of eight, because two is
    /// what this app can reach: YouTube and Twitch are the platforms it holds
    /// credentials for, and a custom server is a diagnostic path.
    var alsoSimulcast = false
    /// DECISION 136 — connect with a pasted stream key instead of signing in.
    /// No API, so none of the app's shared YouTube quota. The key is held in
    /// memory for this session only: never written to disk, never logged.
    var connectWithKey = false
    var platformKey = ""

    private init() {
        #if DEBUG
        // The diagnostic door `GoLiveSheetMac` carried, moved rather than
        // dropped: AW_GOLIVE_CUSTOM pre-seeds a custom destination so the
        // whole go-live path can be driven without the owner's client ids.
        if let u = ProcessInfo.processInfo.environment["AW_GOLIVE_CUSTOM"], !u.isEmpty {
            platform = .custom
            customURL = u
            customKey = "macbench"
        }
        #endif
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
/// color conversion, no second render of a picture that has already been
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
    /// §D23 — rebuilt each time the menu opens and held only while this
    /// view is alive. NEVER written to disk or to defaults: a window list is
    /// the host's whole working day, and a remembered one would outlive the
    /// call it was for.
    @State private var guestWindows: [StudioScreenSource.Window] = []
    private var studio: StudioSession { StudioSession.shared }
    @Bindable private var controls = StudioControls.shared
    @Bindable private var show = StudioMacShow.shared
    @Bindable private var scenes = StudioScenes.shared
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
                column("Mixer", scope: scenes.selected.useShowAudio ? "shared" : "this scene") { mixer }
                Divider()
                // §D20 — a graphic is not an input.
                column("On screen") { onScreen }
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
        .frame(minWidth: 1120, minHeight: 660)
        .onAppear {
            // THE STUDIO OPENS IN THE SCENE IT WAS LEFT IN (§D31).
            StudioScenes.shared.applySelected()
            #if DEBUG
            if ProcessInfo.processInfo.environment["AW_STUDIO_LAYOUT"] != nil {
                controls.layout = studio.armedLayout
            }
            #endif
            show.choosing = show.film == nil
            refreshDevices()
        }
        // A BROADCAST NEVER OUTLIVES ITS STUDIO (§D12). This is Rule B13a's one
        // genuinely load-bearing objection to a second window — that a host
        // could close the window their audience is watching through — kept as
        // a rule now that the window exists.
        // §D37: while ON AIR the close button is disabled, so ⌘W cannot end
        // the show by accident; End the broadcast is the way out.
        .background(AWWindowCloseWatcher(preventClose: studio.isOnAir) {
            // What the host edited in the current scene is kept (§D31).
            StudioScenes.shared.capture()
            StudioScenes.shared.save()
            // AND STOP CAPTURING THE HOST'S SCREEN (§D23). `end()` cannot do
            // this itself, because going live ENDS the rehearsal and the
            // guests must survive that. Closing the Studio is the one moment
            // that unambiguously means the show is over — and a window
            // capture that outlived its Studio would be this app quietly
            // reading somebody's screen with nothing on screen to say so.
            StudioSession.shared.stopGuests()
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
            // STREAM STARTS LARGEST (§D29). It is the picture the audience
            // gets and the one a host must be able to read chat and framing
            // on; the film is followed, not inspected. The host can still
            // drag the dividers.
            sourcePane
                .frame(minWidth: 320, idealWidth: 420)
                .layoutPriority(0)
            programPane
                .frame(minWidth: 420, idealWidth: 680)
                .layoutPriority(1)
            // §D26 — THE AUDIENCE IS PART OF THE SHOW, so it sits up here
            // beside the film and the stream rather than down among the
            // controls. It appears when a broadcast does: chat comes from
            // YouTube and Twitch, so before one exists this pane would be an
            // empty box explaining itself, which is exactly the noise the
            // owner's caption rule is about. The chat controls already say
            // "Appears once you go live."
            if studio.isOnAir {
                audiencePane
                    .frame(minWidth: 220, idealWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230, idealHeight: 340, maxHeight: 460)
    }

    // MARK: AUDIENCE (§D26)

    /// The host's own copy of the conversation, and the one place a viewer can
    /// reach the screen.
    ///
    /// It is NOT the chat burned into the stream. That one is eight lines
    /// because eight is what fits beside a film, it obeys the host's Show
    /// chat switch, and it is made of pixels nobody can click. A host reading
    /// along wants more lines, wants them whether or not the audience is
    /// being shown any, and wants to be able to answer one.
    private var audiencePane: some View {
        VStack(spacing: 0) {
            paneHeader("AUDIENCE", trailing: audienceBadge)
            if studio.canShareFilmInChat { shareFilmRow }
            if let s = studio.shoutOut {
                onScreenNow(s)
                Divider()
            }
            if studio.chatRecent.isEmpty {
                // Not a fault, and not the same sentence as "chat is off":
                // the broadcast is out there and nobody has said anything yet.
                VStack {
                    Spacer()
                    Text("Nobody has said anything yet.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(studio.chatRecent) { line in
                                AudienceRow(line: line) { studio.showShoutOut(line) }
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Newest last, like every chat client, so the host's eye
                    // already knows where a new line lands.
                    .onChange(of: studio.chatRecent.last?.id) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// §D32. One press, one line in chat; it says when it was last done
    /// rather than disabling itself, because a host may want to say it again
    /// for the people who arrived since.
    @State private var shareProblem: String?
    private var shareFilmRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button("Share the film in chat") {
                    Task { shareProblem = await studio.shareFilmInChat() }
                }
                .controlSize(.small)
                if let at = studio.sharedFilmAt {
                    Text("shared \(at.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let p = shareProblem {
                Text(p).font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The header says NOTHING when there is nothing to say. A count of chat
    /// lines is not a fact a host needs — they are looking at the lines —
    /// and the first version of this printed a stray caret beside it.
    ///
    /// HOW MANY PEOPLE ARE WATCHING is (§D27): most of an audience never
    /// types, and without it a host talks into silence not knowing whether
    /// anyone is there. Shown only once the platform reports it — never a
    /// zero we assumed.
    @ViewBuilder private var audienceBadge: some View {
        if let n = studio.audienceCount {
            Label(n == 1 ? "1 watching" : "\(n.formatted()) watching", systemImage: "person.2.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Reported by the platform, about every 30 seconds")
        }
    }

    /// What is on air right now, with the way to take it down. It counts DOWN
    /// rather than saying "12 seconds": a host mid-sentence needs to know how
    /// long they have left, which is not a fact they can get by looking at the
    /// stream.
    private func onScreenNow(_ s: StudioOverlay.ShoutOut) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.author).font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.361, blue: 0.208))
                Text(s.text).font(.caption).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Take down") { studio.clearShoutOut() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(red: 1.0, green: 0.361, blue: 0.208).opacity(0.14))
    }

    // MARK: SOURCE (§D7, §D8)

    private var sourcePane: some View {
        VStack(spacing: 0) {
            // §D17 — FILM, not "SOURCE". Plain words: this pane is the film.
            paneHeader("FILM", trailing: sourceHeaderControls)
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
                        Button("Bring it back into the Studio") { router.nowPlaying = nil }
                            // The header's copy of this button was disabled
                            // while live and this one was NOT (seen
                            // 2026-09-23) — one press froze the audience's
                            // picture. It lives only here now.
                            .disabled(studio.isLive)
                        if studio.isLive {
                            Text("The film cannot change windows during a show.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
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
                                  publishedVTT: film.publishedVTTURL,
                                  feedsProgram: true)
                        .id(film.archiveID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sourceHeaderControls: some View {
        if let film = show.film, !show.choosing {
            // §D13 — two DESIGNED arrangements, never an abbreviation: both
            // buttons when they fit, otherwise the second folds into a native
            // menu that still says every word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    changeFilmButton
                    if !projecting { projectButton(film) }
                }
                HStack(spacing: 8) {
                    changeFilmButton
                    if !projecting {
                        Menu("More") {
                            projectButton(film)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .font(.caption)
        }
    }

    private var changeFilmButton: some View {
        Button("Change film") { show.choosing = true }
            .fixedSize()
            .disabled(studio.isLive)
    }

    private func projectButton(_ film: Catalog.Item) -> some View {
        Button("Open in a separate window") { router.play(film) }
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

    // MARK: PROGRAM (§D5, unchanged in substance)

    private var programPane: some View {
        VStack(spacing: 0) {
            // §D17 — STREAM, not "PROGRAM". Owner: *"'Program' doesn't make
            // sense as a label. I think Stream or Preview makes a lot more
            // sense."* "Program" is vision-gallery jargon, taken from OBS
            // along with the split itself, and it names the right thing to
            // someone who already runs a mixer and nothing to anyone else.
            // The BADGE still says whether it is actually being sent, so the
            // pane's name and its state stay two separate questions — the
            // distinction that stopped `isLive` and `isOnAir` being confused.
            paneHeader("STREAM", trailing: previewBadge)
            // §D31 — the scenes sit on the picture they change.
            StudioSceneBar()
            ZStack {
                Color.black
                StudioProgramPreview()
                // §D14 — FRAME THE CAMERA BY DRAGGING IT, on OBS's own
                // canvas pattern: drag the box to move it, a corner to resize
                // it, a side to reshape it (which IS the crop, because the
                // tile is aspect-filled), scroll to zoom the source inside it
                // and Option-drag to pan that zoom.
                //
                // The handles sit on the rect the ENGINE says it composited,
                // never on a re-derivation of the layout in this view — the
                // "two descriptions of one picture" Decision 133 keeps
                // finding.
                if studio.isLive, controls.framingTarget == .camera,
                   controls.layout.cameraIsTile,
                   let tile = studio.health.cameraTile {
                    StudioTileHandles(tile: tile,
                                      programAspect: StudioOutputSettings.programAspect,
                                      controls: controls)
                }
                if studio.isLive, controls.framingTarget == .guests,
                   let tile = studio.health.guestTile {
                    StudioTileHandles(tile: tile,
                                      programAspect: StudioOutputSettings.programAspect,
                                      controls: controls)
                }
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
                Text("Nothing is sent until you go live.")
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
                Text("Choose a film on the left.")
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
            // reads the authorization status and returns silently when it is
            // not yet `.authorized` — which on macOS it always was.
            let started = await studio.beginShow(film: film, destination: nil)
            if !started { previewRefusal = studio.refusal }
            refreshDevices()
        }
    }

    private func paneHeader<T: View>(_ title: String, trailing: T) -> some View {
        HStack(spacing: 10) {
            // A pane's NAME is never the thing that gives way: narrowing the
            // FILM pane (§D29) let its buttons squeeze "FILM" to nothing.
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .layoutPriority(1)
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
            if studio.isOnAir, let since = studio.onAirSince {
                onAirClock(since: since)
            } else {
                Text(studio.isOnAir ? "connecting"
                     : (studio.isRehearsing ? "nothing is being sent" : "idle"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// §D28 — what OBS's status bar tells a host, in the one header they are
    /// always looking at: how long the audience has been able to see this,
    /// and what is actually leaving the Mac. Dropped frames appear only when
    /// there are some; a zero is not information.
    private func onAirClock(since: Date) -> some View {
        let dropped = studio.health.publisher.videoFramesDropped
        return HStack(spacing: 8) {
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                Text("LIVE  " + Self.elapsed(from: since, to: ctx.date))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            Text(Self.megabits(studio.sendingBitsPerSecond))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary)
            if dropped > 0 {
                Text("\(dropped.formatted()) dropped")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.orange)
            }
            if studio.health.publisher.isReconnecting {
                Text("reconnecting")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func megabits(_ bps: Int) -> String {
        String(format: "%.1f Mbps", Double(bps) / 1_000_000)
    }

    // MARK: Columns

    private func column<Content: View>(_ title: String, scope: String? = nil,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 6)
                if let scope { scopeBadge(scope) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// §D31 — the one caption scenes add: whether an edit here reaches every
    /// scene that inherits it ("shared") or only the one on screen.
    private func scopeBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(text == "shared" ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .help(text == "shared"
                  ? "Changes here apply to every scene that uses the show's settings"
                  : "Changes here apply to this scene only")
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
                if studio.isLive, studio.filmHasNoSoundtrack {
                    Text("No soundtrack on this transfer").font(.caption2)
                        .foregroundStyle(.orange)
                }
                // §4: health is never hidden. "no new frames" is the symptom
                // and the host can already see it; this is the cause, which
                // nothing on any surface has ever said.
                if let why = studio.filmProblem {
                    Text(why).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Text("The app your call is in — Zoom, Meet, FaceTime.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // §D23 — THE CALL'S PICTURE. Beside its audio, because they are
            // the same call and a host thinks of them as one thing.
            VStack(alignment: .leading, spacing: 6) {
                inputRow(name: studio.guestWindowLabel ?? "Your guests",
                         role: "A window",
                         // THE ROW ASKS THE CAPTURE, not whether an object
                         // exists. `guestsAttached` stays true for a source
                         // whose window has closed, so it said "live" over a
                         // tile that had just disappeared.
                         state: studio.guestWindowLabel == nil ? "not shown"
                                : (studio.guestProblem != nil ? "stopped"
                                   : (studio.health.guestsAttached ? "live" : "starting")),
                         healthy: studio.guestWindowLabel == nil
                                  || (studio.guestProblem == nil && studio.health.guestsAttached),
                         icon: "person.2")
                // NO REMEMBERED CHOICE (§D23): the menu is built when it opens,
                // and nothing is pre-selected. A stale selection is how a host
                // broadcasts the window they had open last week.
                Menu(studio.guestWindowLabel == nil ? "Show your guests" : "Change window") {
                    ForEach(guestWindows) { w in
                        Button(w.label) {
                            Task {
                                _ = await studio.startGuests(windowID: w.id, label: w.label,
                                                             ownerPID: w.pid,
                                                             ownerBundleID: w.bundleID)
                                controls.layout = .guests
                            }
                        }
                    }
                    if guestWindows.isEmpty { Text("No windows to show") }
                }
                .menuStyle(.borderlessButton).font(.caption).fixedSize()
                .onHover { if $0 { Task { guestWindows = await StudioScreenSource.windows() } } }
                // FILLED WITHOUT A POINTER TOO (audit B). The list was built
                // only on hover, so opening the menu from the keyboard or
                // VoiceOver showed "No windows to show". Nothing is selected
                // by this — §D23's rule is about choices, not the list.
                // ONLY where access is already granted: CGPreflight asks
                // without prompting, so opening the Studio can never raise
                // the Screen Recording dialog unasked. Before the grant, the
                // host's own hover still fills the list as it always did.
                .task {
                    while !Task.isCancelled {
                        if CGPreflightScreenCaptureAccess() {
                            guestWindows = await StudioScreenSource.windows()
                        }
                        try? await Task.sleep(for: .seconds(4))
                    }
                }
                if studio.guestWindowLabel != nil {
                    Button("Stop showing them") { studio.stopGuests() }
                        .font(.caption).buttonStyle(.borderless).fixedSize()
                }
                if let why = studio.guestProblem {
                    Text(why).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    // MARK: On screen (§D20)

    /// WHAT THE AUDIENCE SEES, as against what is being sent IN.
    ///
    /// These lived at the bottom of `inputs` until a screenshot of the
    /// running Studio showed the column running off the window at "Crop",
    /// with the card picker and the whole NEXT panel below the fold and the
    /// Mixer column beside it half empty (§D20). The controls a host
    /// reaches for DURING a show were the ones furthest down.
    private var onScreen: some View {
        Group {

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

            // §D14 — HOW THE HOST SITS IN IT. Below Placement, because the
            // preset decides the arrangement and this is how you fit yourself
            // into the one you picked.
            cameraFraming

            VStack(alignment: .leading, spacing: 6) {
                Text("On screen").font(.subheadline.weight(.semibold))
                Toggle("Show the lower third", isOn: $controls.showLowerThird)
                // §D15 — WHICH LINES. The host chooses which of the
                // catalog's own verified facts appear; never what they say.
                // §2.1's whole argument is that the audience learns what the
                // film IS, and hand-typed metadata over a public-domain film
                // is how an audience learns something false.
                Group {
                    Toggle("Title", isOn: $controls.showFilmTitle)
                    Toggle("Year and director", isOn: $controls.showFilmMeta)
                    Toggle("Public-domain provenance", isOn: $controls.showProvenance)
                    Text("Clears itself 20 seconds into a broadcast.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(!controls.showLowerThird)
                .padding(.leading, 14)
                Picker("Card", selection: $controls.cardChoice) {
                    ForEach(MacCardChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if controls.cardChoice == .custom || controls.stagedCard == .custom {
                    StudioCustomCardEditor(controls: controls)
                }
                // §D19 — PREPARE ONE WITHOUT SHOWING IT. Offered only while a
                // show is running: staging a card with nothing on air is just
                // choosing one, and the picker above already does that.
                if studio.isLive {
                    Picker("Prepare", selection: $controls.stagedCard) {
                        ForEach(MacCardChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if controls.stagedCard != .none {
                        StudioNextCard(controls: controls,
                                       filmTitle: show.film?.title ?? "")
                    }
                }
                chatControls
            }
        }
    }
    // MARK: Chat (§D22)

    /// THREE CONTROLS, because chat is the only text in this app written by
    /// strangers and the only text BURNED INTO the video. A host who cannot
    /// turn it off, move it off a face, or drop the bot spam is not in control
    /// of their own show.
    @ViewBuilder
    private var chatControls: some View {
        Divider().padding(.vertical, 2)
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Show chat", isOn: $controls.showChat)
            // §D22a — SAY WHY IT IS EMPTY. A column that never appears looks
            // broken; "there is no audience yet" is the actual reason and it
            // is not a fault. Decision 128's rule: an absence is a state with
            // words, not a missing thing.
            if !studio.isOnAir {
                Text(studio.isRehearsing
                     ? "Appears once you go live."
                     : "Appears while you are live.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
            Group {
                Picker("Side", selection: $controls.chatSide) {
                    ForEach(StudioChatSide.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Hide bot commands", isOn: $controls.chatHideCommands)
                Toggle("Hide links", isOn: $controls.chatHideLinks)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide these people").font(.caption)
                    TextField("Hide these people", text: $controls.chatBlocked,
                              prompt: Text("names, separated by commas"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                // SAY WHAT THIS IS NOT. Calling it moderation would promise
                // safety we cannot provide: it cannot see what the platform's
                // own AutoMod already dropped, and it does not judge language.
                Text("Not moderation — whatever shows is in the recording.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if studio.isLive, studio.chatLinesFiltered > 0 {
                    // A filter quietly eating a conversation looks exactly like
                    // an audience that stopped talking (§D21's lesson, one
                    // layer up), so it says how many it took.
                    Text("\(studio.chatLinesFiltered) hidden")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .disabled(!controls.showChat)
            .padding(.leading, 14)
        }
    }

    // MARK: Framing (§D14)

    /// FOUR SLIDERS ARE GONE. They could size the tile and move it and never
    /// change its SHAPE, which is what cropping a camera means — and the owner
    /// met them as *"clunky implementation with four different sliders"*. The
    /// controls are now the tile itself, in the stream preview; this column
    /// says what the gestures are and offers the way back.
    @ViewBuilder
    private var cameraFraming: some View {
        // §D24 — the guests' tile is framed exactly as the host's is, so
        // everything below reads `activeFraming` and the picker decides which
        // tile that is. A second copy of this section would be a second place
        // to fix the next gesture bug.
        let showingGuests = controls.framingTarget == .guests
        let tiled = showingGuests ? studio.health.guestTile != nil
                                  : controls.layout.cameraIsTile
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Framing").font(.subheadline.weight(.semibold))
                scopeBadge(scenes.selected.useShowTiles ? "shared" : "this scene")
                Spacer(minLength: 6)
                if !controls.activeFraming.isDefault {
                    Button("Reset") { controls.activeFraming = StudioCameraFraming() }
                        .font(.caption).buttonStyle(.borderless).fixedSize()
                }
            }
            // Offered only when there IS a second tile to frame — a picker
            // with one real option is furniture.
            if studio.guestWindowLabel != nil {
                Picker("Framing", selection: $controls.framingTarget) {
                    ForEach(StudioFramingTarget.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            if !studio.isLive {
                Text(showingGuests ? "Start the preview to frame your guests."
                                   : "Start the preview to frame yourself.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if showingGuests && studio.health.guestTile == nil {
                Text("Choose a window under Inputs to show your guests.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if tiled {
                // ONE SENTENCE, NOT A FIVE-ROW TABLE (§D20). The table read as
                // documentation and cost four rows of the column, which was
                // exactly the distance by which the NEXT panel below it fell
                // off the bottom of the window. A legend for a direct-
                // manipulation gesture is read once; the control it explains is
                // reached during a show.
                Text("Drag inside the box to move it, a corner to resize, an edge to crop to "
                     + (showingGuests ? "your guests' faces" : "your face")
                     + "; scroll inside it to zoom."
                     + (controls.activeFraming.zoom > 1
                        ? " Hold \u{2325} and drag to pan what you have zoomed into." : ""))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controls.layout == .film {
                Text("No camera in this placement.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Scroll over the stream to zoom; hold \u{2325} to pan.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // THE NUMBERS ARE SHOWN, NOT EDITED. OBS pairs its canvas with an
            // Edit Transform dialog for precision; a watch-along needs to know
            // the zoom it is at far more than it needs to type one, and a
            // readout costs no control.
            if studio.isLive, !controls.activeFraming.isDefault {
                Text(framingReadout)
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var framingReadout: String {
        let f = controls.activeFraming
        var parts: [String] = []
        if let t = f.tile {
            parts.append(String(format: "tile %.0f%% x %.0f%%", t.width * 100, t.height * 100))
        }
        if f.zoom > 1 { parts.append(String(format: "zoom %.1fx", f.zoom)) }
        return parts.joined(separator: "  \u{00B7}  ")
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
            // §D16 — A DEAD METER SAYS WHY. Three faders with still meters
            // over a film that is visibly playing reads as a broken mixer, and
            // a host has no way to know the meters belong to the PROGRAM and
            // the program has not started. Owner: *"I don't see any audio from
            // the film coming through on the source or preview."*
            if !studio.isLive {
                Text(show.film == nil
                     ? "Levels appear once there is a show to measure."
                     : "Levels appear once you start the preview \u{2014} these meters read the stream, not this Mac's speakers.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StudioMacFader(label: "Film", icon: "film", level: audio.filmLevel,
                           gain: $controls.filmGain, muted: $controls.filmMuted)
            // §D16 — THIS FILM HAS NO SOUNDTRACK. Not a fault: a transfer with
            // no audio track is real and legitimate here, and the CONSEQUENCE
            // is the host's. Measured on the product path before it was
            // written (Buster Keaton's "The Scarecrow", 1920:
            // `filmHasAudio=false sourceAudioTracks=0`) \u2014 and it is the
            // exception rather than the rule, since six other silent-era
            // transfers all carry AAC, which is exactly why it must be SAID
            // for the one that does not rather than assumed for all of them.
            if studio.isLive, studio.filmHasNoSoundtrack {
                Text("This film has no soundtrack.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StudioMacFader(label: "Your microphone", icon: "mic", level: audio.micLevel,
                           gain: $controls.micGain, muted: $controls.micMuted)
            micGate(audio)
            // §D3: one channel per AUDIBLE input. The call's channel appears
            // when there IS a call — a third fader over nothing would show a
            // dead meter and read as broken.
            if audio.callAttached {
                StudioMacFader(label: studio.callAppName ?? "A call",
                               icon: "person.wave.2", level: audio.callLevel,
                               gain: $controls.callGain, muted: $controls.callMuted)
                // §D18 — OPEN AND DELIVERING NOTHING. A level of zero is a
                // legitimate reading (a quiet room); no SAMPLES at all is an
                // absence, and a still meter draws them identically.
                if studio.callDeliveringNothing {
                    Text("No audio is arriving from \(studio.callAppName ?? "that app"). macOS may not be allowing Archive Watch to capture it \u{2014} check Privacy & Security \u{25B8} Audio Recording.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// THE GATE, and the sentence that says why it exists (roadmap #4).
    @ViewBuilder
    private func micGate(_ audio: StudioAudioHealth) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Toggle("Cut room noise between sentences", isOn: $controls.micGateEnabled)
                Spacer(minLength: 6)
                // §D3 EXTENDED: a gate that is CLOSED must say so, next to a
                // meter that is deliberately still showing sound. "Your
                // microphone hears this much" and "none of it is being sent"
                // are two facts, and collapsing them is how a host spends a
                // show wondering why nobody can hear them.
                if controls.micGateEnabled, studio.isLive {
                    Text(audio.micGateOpen ? "open" : "closed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(audio.micGateOpen ? .secondary : Color.orange)
                }
            }
            if controls.micGateEnabled {
                HStack(spacing: 8) {
                    Text("Opens above").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                    Slider(value: $controls.micGateThreshold, in: 0.002...0.12)
                    // IN dB, which is the unit a level is argued about in. A
                    // raw 0.02 means nothing to anybody.
                    Text(String(format: "%.0f dB",
                                20 * log10(max(0.0001, controls.micGateThreshold))))
                        .font(.caption).monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
                Text("Your speakers are feeding the film into your microphone, so the stream carries it twice. This sends your microphone only while you talk.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Output (§D4)

    private var output: some View {
        let health = studio.health
        // §D33: ON AIR the summary above already says "Live on …", so this
        // block keeps only what the summary does not — a warning, and each
        // simulcast destination's own health — and is absent when neither.
        let onAir = studio.isOnAir
        let quietOnAir = onAir && health.showState.detail == nil && health.extraDestinations.isEmpty
        return Group {
            if !quietOnAir {
            VStack(alignment: .leading, spacing: 3) {
                if !onAir {
                    HStack(spacing: 8) {
                        Circle().fill(health.showState.isOnAir ? Color.red : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(health.showState.label).font(.subheadline.weight(.semibold))
                    }
                }
                if let detail = health.showState.detail {
                    Text(detail).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // "Sending to" only while something IS being sent: after a show
                // ends the destination is still remembered, and the column
                // read "OFF · Sending to 127.0.0.1" (seen 2026-09-23).
                if !onAir, studio.isLive {
                    Text(destinationName)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                // EACH EXTRA BY NAME (§4). An average across destinations
                // describes none of them and hides a dead one; these say
                // which is which.
                ForEach(studio.health.extraDestinations) { extra in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(extra.health.lastError == nil ? Color.secondary : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(extra.name).font(.caption2)
                        Spacer(minLength: 6)
                        Text(extra.health.lastError == nil
                             ? byteText(extra.health.bytesSent)
                             : "not reached")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(extra.health.lastError == nil
                                             ? .secondary : Color.orange)
                    }
                    if let why = extra.health.lastError {
                        Text(why).font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().padding(.vertical, 2)
            }

            if studio.isLive {
                recordRow
                // THE STREAM ENDS WHEN THE HOST SAYS SO. Owner: "There should
                // be an easy way to end a stream from every platform that can
                // start one." ONE button, beside Record, as OBS keeps its two
                // stops together — it used to be drawn twice, once above the
                // room and once below the fold (seen 2026-09-23).
                // No shortcut here: ⇧⌘E belongs to Broadcast ▸ End the Broadcast.
                Button(role: .destructive) {
                    guard StudioEndConfirmation.confirm() else { return }
                    Task {
                        await studio.end()
                        RoomJoin.shared.hostCode = nil
                    }
                } label: {
                    Text(onAir ? "End the broadcast" : "Stop the preview")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                Divider().padding(.vertical, 2)
            }

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
                    Text("Size and frame rate are fixed during a broadcast.")
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
                    Text("The film has ended — your audience sees a still.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if controls.card == nil {
                        Button("Show the \u{201C}Thanks for watching\u{201D} card") {
                            // THE CHOICE, not the card. Writing `card` directly
                            // would put a card on air that the picker two
                            // columns away still described as "No card" — the
                            // control that disagrees with the program, which
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

    /// §D35 — OBS's other button. The Save panel is where the file goes,
    /// because the sandbox grants only user-selected locations.
    @ViewBuilder
    private var recordRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let since = studio.recordingSince {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    TimelineView(.periodic(from: since, by: 1)) { ctx in
                        let t = max(0, Int(ctx.date.timeIntervalSince(since)))
                        Text(String(format: "Recording %d:%02d", t / 60, t % 60))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    Button("Stop recording") { Task { await studio.stopRecording() } }
                        .controlSize(.small).fixedSize()
                }
            } else {
                HStack {
                    Button("Record…") { chooseRecordingFile() }.controlSize(.small).fixedSize()
                    if let last = studio.lastRecording {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([last]) }
                            .controlSize(.small).fixedSize()
                    }
                }
            }
            if let p = studio.recordingProblem {
                Text(p).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    private func chooseRecordingFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        let film = StudioMacShow.shared.film?.title ?? "Watch Together"
        let day = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        panel.nameFieldStringValue = "\(film) — watch-along \(day).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await studio.startRecording(to: url) }
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
    @AppStorage(StudioSession.readYouTubeChatKey) private var readYouTubeChat = false

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
                Text("Choose a film first.")
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
            } else if studio.isOnAir {
                onAir
            } else {
                form
            }
        }
        #if DEBUG
        // AW_STUDIO_MAC_PREVIEW_LIVE="youtube@90": the path a host takes —
        // Start the Preview, then THIS view's own goLive(), then end() after
        // 90 s on air. The older go-live door arms and begins directly, which
        // is why a preview-then-live defect that deleted the new broadcast
        // was never seen (Decision 133, from the door's side).
        .task {
            let env = ProcessInfo.processInfo.environment
            guard let v = env["AW_STUDIO_MAC_PREVIEW_LIVE"] else { return }
            let parts = v.split(separator: "@")
            guard parts.count == 2, let secs = Int(parts[1]),
                  let platform = GoLivePlatform.allCases.first(where: { "\($0)" == parts[0] })
            else { return }
            for _ in 0..<30 where show.film == nil { try? await Task.sleep(for: .seconds(1)) }
            guard let film = show.film else { awdiag("AWPREVLIVE no film"); return }
            try? await Task.sleep(for: .seconds(6))
            _ = await studio.beginShow(film: film, destination: nil)
            try? await Task.sleep(for: .seconds(10))
            awdiag("AWPREVLIVE rehearsing=%@ — pressing Go Live", studio.isRehearsing ? "y" : "n")
            show.platform = platform
            if show.streamTitle.isEmpty { show.streamTitle = "\(film.title) — preview-then-live test" }
            goLive()
            for _ in 0..<60 where !studio.isOnAir { try? await Task.sleep(for: .seconds(1)) }
            awdiag("AWPREVLIVE onAir=%@ broadcast=%@ problem=%@",
                   studio.isOnAir ? "y" : "n",
                   studio.armedBroadcast.map { "\($0)" } ?? "NONE",
                   problem ?? "none")
            try? await Task.sleep(for: .seconds(secs))
            await studio.end()
            awdiag("AWPREVLIVE ended")
        }
        #endif
    }

    // MARK: §D33 — on air, the Output column is about THE SHOW, not a form

    @State private var onAirAccount: String?
    @State private var copiedAt: Date?

    /// Where the audience watches, when the platform gives it a public
    /// address: a YouTube broadcast id IS its video id; a Twitch show is the
    /// channel. Nil for a bench or custom server.
    private var audienceURL: URL? {
        switch studio.armedBroadcast {
        case .youtube(let id)?: return URL(string: "https://www.youtube.com/watch?v=\(id)")
        case .twitch?:
            return onAirAccount.flatMap { URL(string: "https://www.twitch.tv/\($0)") }
        case nil: return nil
        }
    }

    private var platformName: String {
        switch studio.armedBroadcast {
        case .youtube?: return "YouTube"
        case .twitch?: return "Twitch"
        case nil: return studio.armedDestination?.host ?? "a custom server"
        }
    }

    private var onAir: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Live on \(platformName)").font(.subheadline.weight(.semibold))
            }
            if let who = onAirAccount {
                Text("as \(who)").font(.caption).foregroundStyle(.secondary)
            }
            if !show.streamTitle.isEmpty {
                Text(show.streamTitle).font(.callout).lineLimit(2)
            }
            if case .youtube? = studio.armedBroadcast {
                Text(show.privacy.label).font(.caption).foregroundStyle(.secondary)
            }
            // A WARNING FROM GOING LIVE SURVIVES GOING LIVE (launch audit B).
            // "Going out to YouTube only — Twitch could not be reached" was set
            // a moment before this view replaced the form, so no host ever
            // read it.
            if let problem {
                Text(problem).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = audienceURL {
                // THE INVITATION. "With your friends" means somebody has to be
                // told where to come; this is the one address to send them.
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        Button(copiedAt == nil ? "Copy link" : "Copied") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            copiedAt = Date()
                        }
                        .fixedSize()
                        Button("Open") { NSWorkspace.shared.open(url) }
                            .fixedSize()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }
            friendsRoom
                #if DEBUG
                // AW_STUDIO_MAC_ROOM=1 — press "Open a room" through the same
                // function, once, when the show goes on air.
                .task {
                    if ProcessInfo.processInfo.environment["AW_STUDIO_MAC_ROOM"] == "1",
                       room.hostCode == nil { await openRoom() }
                }
                #endif
        }
        .task(id: platformName) {
            onAirAccount = nil
            switch studio.armedBroadcast {
            case .youtube?: onAirAccount = try? await StudioPlatformAuth.accountName(for: .youtube)
            case .twitch?: onAirAccount = try? await StudioPlatformAuth.accountName(for: .twitch)
            case nil: break
            }
        }
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedAt = nil
        }
    }

    // MARK: §D34 — the friends on the host's call

    @Bindable private var room = RoomJoin.shared
    @State private var roomWorking = false
    @State private var roomProblem: String?

    /// The audience link is for the WORLD; a room is for the people on the
    /// host's call, who watch the film itself in step — at full quality, on
    /// their own device — instead of a compressed stream seconds behind.
    private var friendsRoom: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Friends on your call").font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let code = room.hostCode {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    // Who has arrived — an anonymous count (owner, 2026-09-23).
                    if let n = StudioRoomHost.shared.present {
                        Label(n == 1 ? "1 friend here" : "\(n) friends here",
                              systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(n == 0 ? Color.secondary : Color.primary)
                    }
                }
                Text("Friends enter it under Watch Together in Archive Watch.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Close the room") {
                    StudioRoomHost.shared.stop()
                    room.hostCode = nil
                }
                .controlSize(.small)
            } else {
                Button(roomWorking ? "Opening…" : "Open a room") { Task { await openRoom() } }
                .controlSize(.small)
                .disabled(roomWorking)
                if let p = roomProblem {
                    Text(p).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func openRoom() async {
        roomWorking = true
        let r = await studio.openFriendsRoom()
        room.hostCode = r.code
        roomProblem = r.code == nil ? (r.problem ?? "The room could not be opened.") : nil
        roomWorking = false
        awdiag("AWROOM studio room %@", r.code ?? "FAILED — \(roomProblem ?? "")")
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Platform", selection: $show.platform) {
                ForEach(GoLivePlatform.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(studio.isOnAir)

            if show.platform != .custom {
                // TWO WAYS IN (Decision 136). Signing in creates the broadcast
                // and reads its chat; a stream key needs nothing from the
                // platform's API, so it works however busy the app's shared
                // YouTube quota is — exactly as OBS connects.
                Picker("Connect", selection: $show.connectWithKey) {
                    Text("Sign in").tag(false)
                    Text("Stream key").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if show.platform != .custom, show.connectWithKey {
                labeled("Stream key") { SecureField("", text: $show.platformKey) }
                if let page = show.platform.streamKeyPage {
                    Link("Find your stream key", destination: page).font(.caption)
                }
                Text("Chat and the viewer count need sign-in.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if show.platform != .custom, !show.connectWithKey {
                StudioSignInRow(platform: authPlatform) { signedIn = $0 }
                    // ONE ROW PER PLATFORM. Without this SwiftUI reuses the
                    // row when the picker changes, carrying its @State across:
                    // the owner saw YouTube and Twitch "as the same account",
                    // and signing out of one looked like signing out of both
                    // (2026-09-23, Mac). The tokens were separate all along.
                    // tvOS has had this `.id` since the same bug there.
                    .id(authPlatform)
                    .task(id: signedIn) {
                        guard signedIn, show.platform != .custom, readiness == nil else { return }
                        readiness = try? await StudioPlatformAuth.readiness(for: authPlatform)
                    }
                    .onChange(of: show.platform) { _, _ in readiness = nil }
            }

            // ALSO SEND IT TO THE OTHER ONE. Only offered when there IS
            // another one — a custom destination has no sibling, and offering
            // a checkbox that cannot do anything is §5's disabled-control
            // problem in checkbox form.
            if show.platform != .custom, !show.connectWithKey {
                Toggle("Also send to \(show.platform == .youtube ? "Twitch" : "YouTube")",
                       isOn: $show.alsoSimulcast)
                if show.alsoSimulcast {
                    Text(simulcastNote)
                        .font(.caption2)
                        .foregroundStyle(simulcastFitsUplink ? .secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch show.platform {
            case .youtube where show.connectWithKey, .twitch where show.connectWithKey:
                // The title, privacy and category are set on the platform's
                // own page for a keyed stream — this app has no call to set them.
                EmptyView()
            case .youtube:
                labeled("Stream title") { TextField("", text: $show.streamTitle) }
                Picker("Privacy", selection: $show.privacy) {
                    ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show chat from YouTube", isOn: $readYouTubeChat)
            case .twitch:
                labeled("Stream title") { TextField("", text: $show.streamTitle) }
                labeled("Category") { TextField("", text: $show.category) }
            case .custom:
                // The diagnostic path. A real destination is never typed.
                labeled("rtmps://host/app") { TextField("", text: $show.customURL) }
                labeled("Stream key") { SecureField("", text: $show.customKey) }
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

    /// TWO DESTINATIONS IS TWICE THE UPLOAD, and the feature says so rather
    /// than letting a host discover it mid-show.
    ///
    /// This is not a hypothetical: the owner's own line measured 68.3 Mbps
    /// down but **854 ms responsiveness under load**, and Twitch dropped
    /// frames at ~4.2 Mbps — bufferbloat on the local path, not the encoder
    /// and not Twitch (WATCH-TOGETHER §9). A second destination doubles the
    /// number that was already the problem.
    private var simulcastFitsUplink: Bool {
        StudioOutputSettings.bitrateKbps * 2 <= 8000
    }

    private var simulcastNote: String {
        let each = StudioOutputSettings.bitrateKbps
        let total = each * 2
        let base = "Two destinations send the same picture twice — about "
            + "\(total / 1000) Mbps up, not \(each / 1000)."
        return simulcastFitsUplink
            ? base + " The video is encoded once, so this costs upload rather than CPU."
            : base + " That is more than this connection has held steadily; "
                   + "lower the bitrate, or send to one."
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
        if show.connectWithKey {
            return show.platformKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Paste your \(show.platform.label) stream key." : nil
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
                customKey: show.platform == .custom ? show.customKey : nil,
                typedKey: show.platform != .custom && show.connectWithKey ? show.platformKey : nil)
            do {
                let resolved = try await StudioGoLive.destination(for: request, film: film)
                let dest = resolved.url
                // A REHEARSAL MUST END BEFORE A BROADCAST BEGINS. `beginShow`
                // guards on `!isLive`, and §D5's preview leaves the engine
                // RUNNING with no destination — so arming for a real broadcast
                // would be silently ignored and the host would have pressed Go
                // Live to no effect.
                //
                // AND IT MUST END BEFORE ANYTHING IS ARMED. `end()` completes
                // the armed broadcast, and a YouTube one still in `ready` is
                // DELETED as an orphan — so ending the preview after arming
                // deleted the broadcast Go Live had just created, and dropped
                // its chat and the Twitch channel with it (audit, 2026-09-23).
                // After the destination resolves, so a refusal keeps the preview.
                if studio.isRehearsing { await studio.end() }
                // THE BROADCAST'S OWN CHAT, carried rather than dropped. This
                // is the value `destination()` used to read and throw away.
                studio.armYouTubeChat(resolved.liveChatID)
                studio.armBroadcast(resolved.broadcast)
                studio.armLayout(controls.layout)

                // THE SECOND DESTINATION, resolved the same way as the first:
                // its own request through the same shared `StudioGoLive`, so
                // a Twitch simulcast creates a real Twitch stream with a real
                // key and is not a copy of the YouTube address.
                //
                // BEST EFFORT, and said rather than thrown. A host who asked
                // for two and got one should be told which one — not have the
                // broadcast they DID reach refused because the other platform
                // was unreachable.
                var extras: [StudioExtraDestination] = []
                if show.alsoSimulcast, show.platform != .custom, !show.connectWithKey {
                    let other: GoLivePlatform = show.platform == .youtube ? .twitch : .youtube
                    let second = GoLiveRequest(
                        archiveID: film.archiveID, platform: other,
                        title: request.title, category: request.category,
                        privacy: request.privacy, layout: request.layout,
                        customServer: nil, customKey: nil)
                    do {
                        let r = try await StudioGoLive.destination(for: second, film: film)
                        if let url = r.url {
                            extras.append(StudioExtraDestination(name: other.label, url: url))
                        }
                        // The SECOND platform's chat is not read: the overlay
                        // draws one column and merging two audiences into it
                        // without saying which is which would misattribute
                        // every line. Naming that is better than guessing.
                    } catch {
                        problem = "Going out to \(show.platform.label) only — "
                                + "\(other.label) could not be reached: \(studioSentence(for: error))"
                    }
                }

                let started = await studio.beginShow(film: film, destination: dest,
                                                     additional: extras)
                if !started { problem = studio.refusal }
                onStarted()
            } catch {
                problem = "The broadcast could not start — \(studioSentence(for: error))"
            }
        }
    }

    /// A label above its field rather than beside it. The Output column is
    /// ~300 points wide, and macOS's own leading-label form layout gives a
    /// `TextField` whatever is left — which at this width is a slot too narrow
    /// to read a film title in.
    @ViewBuilder
    private func labeled<T: View>(_ title: String, @ViewBuilder field: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            // The fields are built with an empty label so the title above
            // can be styled; VoiceOver hears the title (audit B).
            field().textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }
}

// MARK: - Choosing a film, in the Studio (§D7)

/// Search the catalog from inside the Studio.
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
            // nil means the catalog has no file for it — a series spine, or
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
                    Text("Only cleared public-domain titles can be broadcast.")
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
/// typeface, color, position and ground, which is what makes a custom card
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
                Text("Write at least one line.")
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
                // "On, switch" said nothing about WHICH channel (audit B).
                .accessibilityLabel(label)
                .accessibilityValue(muted ? "Muted" : "On")
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
            .accessibilityElement()
            .accessibilityLabel("\(label) meter")
            .accessibilityValue("\(Int(min(1, max(0, MixLevel.meterFraction(rms: level))) * 100)) percent")
            HStack(spacing: 10) {
                Slider(value: Binding(get: { MixLevel.level(Float(gain)) },
                                      set: { gain = Double(MixLevel.gain($0)) }),
                       in: 0...MixLevel.maximum)
                    .disabled(muted)
                    .accessibilityLabel("\(label) level")
                    .accessibilityValue(MixLevel.text(MixLevel.level(Float(gain))))
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
// The raw values exist for ONE reason: a harness door names a card in an
// environment variable (§D19), and a hand-written string table would be a
// second place to forget a case.
enum MacCardChoice: String, CaseIterable, Hashable {
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
// MARK: - One line of the audience (§D26)

/// A row a host can put on the broadcast.
///
/// The button appears on hover rather than sitting on every row: forty rows
/// each carrying a permanent "Show" is a wall of controls, and the thing a
/// host is doing here most of the time is READING.
///
/// A message too long to draw is shown and NOT offered, with the reason. It is
/// not hidden — a host reading along should see everything the audience said —
/// and it is not truncated, because cutting a stranger's sentence in half and
/// putting their name under the remainder is worse than declining to show it.
private struct AudienceRow: View {
    let line: StudioOverlay.ChatLine
    let show: () -> Void
    @State private var hovering = false

    private var tooLong: Bool { StudioOverlay.ShoutOut.tooLong(line.text) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line.author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(line.isEvent
                                     ? Color(red: 1.0, green: 0.361, blue: 0.208)
                                     : .secondary)
                Text(line.text)
                    .font(.callout)
                    // A 500-character Twitch message is legal and took ELEVEN
                    // lines of the reader on the glass, pushing the rest of
                    // the conversation off the pane. Four here; the full text
                    // is in the tooltip, and it is refused on air anyway.
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if tooLong {
                if hovering {
                    Text("too long to show")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if hovering {
                Button("Show", action: show)
                    .controlSize(.small)
                    .help("Put this on the broadcast for \(Int(StudioOverlay.ShoutOut.seconds)) seconds")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .help(line.text)
        .onHover { hovering = $0 }
        // HOVER AND DOUBLE-CLICK ARE NOT THE ONLY WAYS IN (audit B): VoiceOver
        // reads the row as one message and offers the action by name.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: tooLong ? "Too long to show" : "Show on the broadcast") {
            if !tooLong { show() }
        }
        // A DOUBLE-CLICK DOES IT TOO, because the button is the discoverable
        // way and the gesture is the fast one — a host answering a comment
        // aloud is not aiming at a 40-point target.
        .onTapGesture(count: 2) { if !tooLong { show() } }
    }
}
#endif
