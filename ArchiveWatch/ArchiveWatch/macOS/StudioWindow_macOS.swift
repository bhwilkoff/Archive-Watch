#if os(macOS)
import SwiftUI
import AppKit
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
    var card: StudioOverlay.Card? {
        didSet { Task { await StudioSession.shared.setCard(card) } }
    }
    /// The call's fader (§D3). Defaults to the same 1.0 the others do, so a
    /// conversation arrives at the level it was spoken.
    var callGain: Double = 1.0 {
        didSet { Task { await StudioSession.shared.setAudio(callGain: Float(callGain)) } }
    }
    var callMuted = false {
        didSet { Task { await StudioSession.shared.setAudio(callMuted: callMuted) } }
    }

    private init() {}
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
    /// The device lists, read once on appear and on demand rather than every
    /// redraw: `AVCaptureDevice.DiscoverySession` is not free, and this view
    /// redraws at the health tick.
    @State private var cameras: [StudioDevices.Device] = []
    @State private var microphones: [StudioDevices.Device] = []
    @State private var callApps: [StudioAudioProcesses.Process] = []
    @State private var chosenCallBundleID = ""
    @State private var previewRefusal: String?
    @Environment(AppRouter.self) private var router
    /// Redraw the numbers on the same second the engine publishes them.
    /// `StudioSession` is `@Observable`, so `health` alone would do it — the
    /// timer is for the two derived per-second rates it recomputes in place.
    @State private var tick = 0

    private let marquee = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            HStack(alignment: .top, spacing: 0) {
                column("Inputs") { inputs }
                Divider()
                column("Mixer") { mixer }
                Divider()
                column("Output") { output }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 940, minHeight: 660)
        .onAppear {
            controls.layout = studio.armedLayout
            refreshDevices()
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            Color.black
            StudioProgramPreview()
            if !studio.isLive {
                // §D5: a host frames themselves, sets levels and picks a
                // placement BEFORE anything is broadcast. Explicit, never
                // automatic — starting it switches the camera on, and a
                // camera light that comes on because somebody opened a window
                // is a surprise rather than a feature.
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Nothing is being produced yet")
                        .font(.headline).foregroundStyle(.white)
                    if let film = router.nowPlaying {
                        Text("Rehearse with \(film.title) — you will see exactly what an audience would, and nothing is sent anywhere.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        Button("Start preview") {
                            if !studio.startPreview(film: film) {
                                previewRefusal = studio.refusal
                            }
                        }
                        .controlSize(.large)
                        if let previewRefusal {
                            Text(previewRefusal).font(.caption2)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                        }
                    } else {
                        Text("Open a film in the player, and you can rehearse the whole show here before anything is broadcast.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        // A CEILING, not the usual size. At the default 1080x860 the VStack
        // already settles the preview at 648x364 on its own — measured on the
        // glass, macOS 27 — because the columns ask for the rest. The cap is
        // for the other direction: full-screened on a large display, an
        // uncapped 16:9 preview takes 900 points and leaves the mixer a
        // letterbox slot at the bottom of the screen.
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 420)
        .overlay(alignment: .topLeading) { previewBadge }
    }

    /// The preview says WHAT IT IS (§D5). A picture with no label is one a
    /// host can mistake for a rehearsal when it is a broadcast.
    private var previewBadge: some View {
        HStack(spacing: 7) {
            // RED MEANS ON AIR. `isLive` means the engine is running, which
            // includes a rehearsal that goes nowhere — a red dot keyed to it
            // would tell a host they were broadcasting when they were not.
            Circle().fill(studio.isOnAir ? Color.red : Color.secondary)
                .frame(width: 8, height: 8)
            Text(studio.isOnAir ? "PROGRAM — this is going out"
                 : (studio.isRehearsing ? "PREVIEW — nothing is being sent" : "PROGRAM"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.black.opacity(0.6), in: .capsule)
        .padding(10)
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

    // MARK: Inputs (§D2)

    private var inputs: some View {
        let health = studio.health
        return Group {
            inputRow(name: studio.armedTitle.isEmpty ? "No film chosen" : studio.armedTitle,
                     role: "Film",
                     state: studio.isLive
                        ? (studio.filmFramesPerSecond > 0
                           ? "\(studio.filmFramesPerSecond) fps"
                           : "no new frames")
                        // "ready" over "No film" is a claim the row cannot
                        // make: nothing is ready until a film is playing.
                        : (studio.armedTitle.isEmpty ? "open a film" : "ready"),
                     healthy: !studio.isLive || studio.filmFramesPerSecond > 0,
                     icon: "film")

            // EVERY INPUT IS NAMED, AND ITS DEVICE IS CHOSEN (§D2).
            //
            // This Mac reports FOUR cameras — the built-in FaceTime camera,
            // two virtual ones, and the host's iPhone over Continuity — and
            // `AVCaptureDevice.default` silently took the first of them. A
            // host who wanted their phone as the camera had no way to say so.
            deviceRow(role: "Camera", icon: "video",
                      devices: cameras,
                      selection: Binding(
                        get: { StudioDevices.chosenCameraID ?? "" },
                        set: { StudioDevices.chosenCameraID = $0.isEmpty ? nil : $0 }),
                      state: health.cameraAttached
                        ? (health.cameraFramesReceived == 0
                           ? "starting"
                           : (studio.cameraFramesPerSecond > 0
                              ? "\(studio.cameraFramesPerSecond) fps"
                              : "stopped"))
                        : "not attached",
                      healthy: !health.cameraAttached || health.cameraFramesReceived == 0
                        || studio.cameraFramesPerSecond > 0)

            deviceRow(role: "Microphone", icon: "mic",
                      devices: microphones,
                      selection: Binding(
                        get: { StudioDevices.chosenMicrophoneID ?? "" },
                        set: { StudioDevices.chosenMicrophoneID = $0.isEmpty ? nil : $0 }),
                      state: controls.micMuted ? "muted"
                        : (studio.isLive ? "live" : "ready"),
                      healthy: true)

            // NOT CHANGEABLE MID-SHOW, and said rather than hidden (§D4's
            // rule, which applies to inputs too): an `AVCaptureSession` is
            // built once when the show starts, so a picker that appeared to
            // work while live would be the "value that never lands" defect
            // Decision 133 is about.
            if studio.isLive {
                Text("Device changes take effect on the next broadcast — the capture session is built when a show starts.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                Picker("Card", selection: Binding(
                    get: { MacCardChoice.from(controls.card) },
                    set: { controls.card = $0.value })) {
                    ForEach(MacCardChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("A card covers the film completely — your audience sees only the card.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    private func deviceRow(role: String, icon: String,
                           devices: [StudioDevices.Device],
                           selection: Binding<String>,
                           state: String, healthy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(role).font(.subheadline.weight(.medium))
                Spacer(minLength: 6)
                Text(state).font(.caption).monospacedDigit()
                    .foregroundStyle(healthy ? .secondary : Color.orange)
            }
            Picker(role, selection: selection) {
                Text("System default").tag("")
                Text("None").tag(StudioDevices.noneID)
                Divider()
                ForEach(devices) { d in Text(d.name).tag(d.id) }
            }
            .labelsHidden()
            .disabled(studio.isLive)
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
                            controls.card = .ending
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
    case none, startingSoon, intermission, ending

    var label: String {
        switch self {
        case .none: return "No card"
        case .startingSoon: return "Starting soon"
        case .intermission: return "Intermission"
        case .ending: return "Thanks for watching"
        }
    }
    var value: StudioOverlay.Card? {
        switch self {
        case .none: return nil
        case .startingSoon: return .startingSoon(secondsRemaining: 0)
        case .intermission: return .intermission
        case .ending: return .ending
        }
    }
    static func from(_ card: StudioOverlay.Card?) -> MacCardChoice {
        guard let card else { return .none }
        switch card {
        case .startingSoon: return .startingSoon
        case .intermission: return .intermission
        case .ending: return .ending
        }
    }
}
#endif
