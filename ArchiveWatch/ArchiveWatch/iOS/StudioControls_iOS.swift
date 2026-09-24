#if os(iOS)
import SwiftUI

// The Studio's in-player affordances — iOS-DESIGN §8.8, in the §8.5 overlay
// pattern (the same capsule shape EpisodePlayerContainer uses for episode
// navigation). NOT a new surface, NOT a second player.
//
// Two pieces, and the split is the design:
//
//   · `StudioHealthCapsule` is ALWAYS on screen while live. Bitrate, dropped
//     frames, thermal state and the connection are never hidden to make the
//     screen calmer (docs/WATCH-TOGETHER.md §4) — a host is responsible for a
//     broadcast and cannot be responsible for something they cannot see. It is
//     also the only honest way to notice the failure this feature is most
//     exposed to: a program that looks healthy while carrying a frozen film
//     (§9's two faults), which is why `film` has its own counter here.
//   · `StudioControlsSheet` is a §4.5 medium-detent picker so the program
//     stays visible behind it while the host changes layout or rides a fader.
//     Changing what the audience sees without being able to see it is not a
//     control; it is a guess.

// MARK: - Health capsule

struct StudioHealthCapsule: View {
    let health: StudioHealth
    /// Frames the film delivered in the last second — 0 while the program is
    /// still running is the frozen-picture signature.
    let filmFramesPerSecond: Int
    /// Camera frames in the last second — 0 while live, for a camera that HAS
    /// delivered, is the tile-went-dark signature. A phone's camera stops
    /// whenever a call arrives, so this is not a television's problem.
    let cameraFramesPerSecond: Int
    /// The HOST paused the film. A still picture is then their choice, not a
    /// fault, and "the film has stopped" would say otherwise.
    var filmPausedByHost = false
    /// The cause, once one has been named (StudioFilmStall).
    var filmStallReason: String? = nil
    let onOpenControls: () -> Void

    private var isLive: Bool { health.showState.isOnAir }

    private var thermalColor: Color {
        switch health.thermalState {
        case "serious": return .orange
        case "critical": return .red
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // LIVE, or what is wrong instead. Never a silent dot.
            HStack(spacing: 5) {
                Circle()
                    .fill(isLive ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(health.showState.label)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }

            Divider().frame(height: 12).overlay(.white.opacity(0.3))

            stat("\(kbps) kbps")

            // §D27 — how many are watching, once the platform says so. The
            // icon carries the noun: a phone's capsule has no room for it.
            if let n = StudioSession.shared.audienceCount {
                Label("\(n.formatted())", systemImage: "person.2.fill")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(n == 1 ? "1 watching" : "\(n) watching")
            }

            // ONE warning chip, not a row of them. Health is never hidden
            // (§4) — but "not hidden" does not mean "all on one line": a
            // capsule that runs the width of the screen collides with the
            // player's own chrome and truncates on a small phone (seen on the
            // glass, 2026-09-17). The summary is always on screen and every
            // number is one tap away in the sheet's Health section.
            if !warnings.isEmpty {
                Button(action: onOpenControls) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        if warnings.count > 1 { Text("\(warnings.count)").font(.caption2.weight(.bold)) }
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(warnings.joined(separator: ", "))
            }

            Button(action: onOpenControls) {
                Image(systemName: "slider.horizontal.3")
            }
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.55), in: .capsule)
        .padding(.top, 8).padding(.leading, 16)
    }

    /// Everything currently wrong, in the words the sheet will repeat.
    var warnings: [String] {
        var w: [String] = []
        if let d = health.showState.detail { w.append(d) }
        // §5's adaptive step, with its numbers. Written by the engine and
        // rendered by nothing until now on any platform.
        if let note = health.qualityNote { w.append(note) }
        if isLive && filmFramesPerSecond == 0 && !filmPausedByHost {
            w.append(filmStallReason.map { "the film has stopped arriving — \($0)" } ?? "the film has stopped arriving")
        }
        // A CAMERA THAT DIED MID-SHOW — the guard the television has carried
        // since 2026-09-19, when a Continuity camera ran a clean 30/s for ten
        // seconds and then stopped dead for eighty while every other number
        // stayed healthy. `cameraFramesReceived > 0` matters: between the
        // attach and the first delivered frame a camera is legitimately
        // attached at zero, and without it this fires during every normal
        // start. The word is STOPPED, so it may only appear for a camera that
        // had started. A phone's camera stops whenever a call arrives, so
        // this was never a television's problem.
        // FIRST: an audience hearing nothing is worse off than one not seeing
        // the host. This existed on tvOS alone, and iOS is one of the two
        // platforms that uses the tap path — the very thing that can fail to
        // attach — so it was a platform that could broadcast a silent
        // programme with nothing on screen saying so.
        if isLive, let audio = StudioSession.shared.filmAudioProblem {
            w.append(audio.replacingOccurrences(of: "The film's", with: "the film's"))
        }
        if isLive, health.cameraAttached, health.cameraFramesReceived > 0,
           cameraFramesPerSecond == 0 {
            w.append("the camera has stopped — your audience sees the film without you")
        }
        // The opposite fault, and the one that hid for five minutes on an
        // Apple TV (WATCH-TOGETHER §9): the film keeps arriving and the
        // ENCODER stops, so every other number looks healthy.
        if let f = health.encoderFault { w.append(f) }
        if health.publisher.videoFramesDropped > 0 {
            w.append("\(health.publisher.videoFramesDropped) dropped frames")
        }
        if health.thermalState == "serious" { w.append("the device is getting hot") }
        if health.thermalState == "critical" { w.append("the device is too hot to continue") }
        if let e = health.publisher.lastError { w.append(e) }
        return w
    }

    private var kbps: Int {
        // Encoded bytes are the program's real rate whether or not a
        // destination is attached — over the last seconds, not the whole
        // show, or a collapse an hour in would still read as healthy.
        if health.encodedKbpsRecent > 0 { return health.encodedKbpsRecent }
        let seconds = max(1, health.programFramesEncoded / max(1, StudioOutputSettings.frameRate))
        return max(0, health.encodedBytes * 8 / 1000 / seconds)
    }

    private func stat(_ text: String, tint: Color = .white) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}

// MARK: - Controls sheet

struct StudioControlsSheet: View {
    @Binding var layout: StudioLayout
    @Binding var filmGain: Double
    @Binding var micGain: Double
    @Binding var filmMuted: Bool
    @Binding var micMuted: Bool
    @Binding var duckEnabled: Bool
    @Binding var card: StudioOverlay.Card?
    @Binding var showLowerThird: Bool
    let audio: StudioAudioHealth
    let health: StudioHealth
    /// Film frames delivered in the last second; 0 while live is the
    /// frozen-picture signature and gets said out loud.
    let filmFramesPerSecond: Int
    let cameraFramesPerSecond: Int
    /// The host paused the film — a still is their choice, not a fault.
    var filmPausedByHost = false
    var filmStallReason: String? = nil
    /// §D26 on the phone: what is on air, and the way to put somebody there.
    var shoutOut: StudioOverlay.ShoutOut? = nil
    var onShow: (StudioOverlay.ChatLine) -> Void = { _ in }
    var onTakeDown: () -> Void = {}
    /// §D32 on the phone. Nil when there is no YouTube chat to post in.
    var onShareFilm: (() async -> String?)? = nil
    @State private var shareResult: String?
    @State private var sharedAt: Date?
    /// Closes the panel. Explicit because it is an INSPECTOR on iPad
    /// (IPAD-DESIGN §5b), and a column is closed by its binding, not by
    /// `dismiss`, which is a sheet's word.
    var onClose: (() -> Void)? = nil
    let onEnd: () -> Void

    private var healthFooter: String {
        // The film ENDING outranks "the film has stopped": both are true at
        // that moment and only one is the reason (owner item 13, §9.bbbbbb).
        if health.filmEnded && health.showState.isOnAir {
            return "The film has ended — your audience is watching a still. Your camera and microphone are still live, so the show goes on until you end it."
        }
        if filmFramesPerSecond == 0 && health.showState.isOnAir && !filmPausedByHost {
            let why = filmStallReason.map { " The cause: \($0)." } ?? ""
            return "The film has stopped sending new frames — your audience is seeing a still picture. The sound and your camera are unaffected." + why
        }
        if health.showState.isOnAir, health.cameraAttached,
           health.cameraFramesReceived > 0, cameraFramesPerSecond == 0 {
            return "The camera has stopped — your audience sees the film without you."
        }
        if health.showState == .notEncoding {
            return "The picture has stopped being encoded, so your audience is not receiving the show. Ending and restarting the broadcast is the reliable fix."
        }
        return "These numbers are what your audience is actually receiving."
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.subheadline)
    }

    @Environment(\.dismiss) private var dismiss
    private func close() { if let onClose { onClose() } else { dismiss() } }

    private var audienceSection: some View {
        Section {
            if let share = onShareFilm {
                // Proved on YouTube 2026-09-23 (GYAQsLMDwho): the line lands in
                // chat under the host's handle with the archive.org link whole.
                Button {
                    Task {
                        let problem = await share()
                        shareResult = problem
                        if problem == nil { sharedAt = Date() }
                    }
                } label: {
                    HStack {
                        Label("Share the film in chat", systemImage: "link")
                        Spacer()
                        if let at = sharedAt {
                            Text("shared \(at.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let r = shareResult {
                    Text(r).font(.footnote).foregroundStyle(.orange)
                }
            }
            if let s = shoutOut {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.author).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.361, blue: 0.208))
                        Text(s.text).font(.subheadline).lineLimit(3)
                    }
                    Spacer()
                    Button("Take down", action: onTakeDown).buttonStyle(.bordered)
                }
            }
            // Newest first: a phone list reads top-down, and the message a
            // host just heard read aloud is the one they are looking for.
            ForEach(Array(health.chatRecent.suffix(15).reversed())) { line in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.author).font(.caption.weight(.semibold))
                            .foregroundStyle(line.isEvent
                                             ? Color(red: 1.0, green: 0.361, blue: 0.208)
                                             : .secondary)
                        Text(line.text).font(.subheadline)
                    }
                    Spacer(minLength: 8)
                    // §D26a — SHOWN and REFUSED, never truncated.
                    if StudioOverlay.ShoutOut.tooLong(line.text) {
                        Text("too long to show").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Show") { onShow(line) }.buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Audience")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // §D26 — THE AUDIENCE FIRST. It is the one thing in this
                // sheet that is about somebody other than the host, and it
                // appears only when there is a conversation to show.
                if shoutOut != nil || !health.chatRecent.isEmpty || onShareFilm != nil {
                    audienceSection
                }
                Section {
                    row("Broadcast", health.showState.label)
                    row("Connection", health.publisher.state.rawValue)
                    // String(format:), not integer division — `Int(x * 100) / 100`
                    // is integer maths and rendered 10.13 ms as "10" and any
                    // sub-millisecond value as "0 ms per frame".
                    row("Program", String(format: "%.1f ms per frame", health.averageRenderMilliseconds))
                    row("Dropped frames", "\(health.publisher.videoFramesDropped)")
                    row("Encoded", "\(health.encodedFramesPerSecond) fps")
                    if let f = health.encoderFault {
                        Text(f).font(.footnote).foregroundStyle(.orange)
                    }
                    row("Device temperature", health.thermalState)
                    if let e = health.publisher.lastError {
                        Text(e).font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Health")
                } footer: {
                    Text(healthFooter)
                }

                Section("Layout") {
                    Picker("Layout", selection: $layout) {
                        ForEach(StudioLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    fader("Film", level: audio.filmLevel, gain: $filmGain, muted: $filmMuted,
                          icon: "film")
                    fader("Your microphone", level: audio.micLevel, gain: $micGain, muted: $micMuted,
                          icon: "mic")
                    // AUTO-DUCK IS A CONTROL, NOT A SENTENCE (Rule 8.8c).
                    // This section used to STATE that "the film drops 12 dB
                    // automatically while you are talking", which is exactly
                    // the problem the television found: a host who sets Film
                    // to 9 and then speaks hears it drop 12 dB anyway and
                    // reasonably concludes the fader is broken. Manual has to
                    // mean manual. Owner: "I like the idea of turning ducking
                    // on and off to allow manual control."
                    Toggle("Duck the film under my voice", isOn: $duckEnabled)
                } header: {
                    Text("Sound")
                } footer: {
                    Text(duckEnabled
                         ? (audio.ducking
                            ? "The film is ducking under your voice."
                            : "The film drops 12 dB automatically while you are talking.")
                         : "The film stays where you set it. 8 is the level it already has.")
                }

                Section {
                    Toggle("Show the film's title on screen", isOn: $showLowerThird)
                    ForEach(CardChoice.allCases, id: \.self) { choice in
                        Button {
                            card = (card == choice.value) ? nil : choice.value
                        } label: {
                            HStack {
                                Text(choice.label)
                                Spacer()
                                if card == choice.value {
                                    Image(systemName: "checkmark").foregroundStyle(Brand.primary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("On screen")
                }

                Section {
                    Button("End the broadcast", role: .destructive) {
                        onEnd(); close()
                    }
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// One fader: a live meter, a slider and a mute. The meter is the point —
    /// a fader without one is a control whose effect you cannot hear until the
    /// audience already has.
    private func fader(_ label: String, level: Float, gain: Binding<Double>,
                       muted: Binding<Bool>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    muted.wrappedValue.toggle()
                } label: {
                    Image(systemName: muted.wrappedValue ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(muted.wrappedValue ? Brand.primary : .secondary)
                }
                .buttonStyle(.borderless)
            }
            // The meter reads on the FADER'S scale, not linearly. A linear
            // 0-1 meter draws 2% for speech at RMS 0.02 and looks dead, which
            // is how a working microphone reads as a broken one.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule()
                        .fill(muted.wrappedValue ? Color.secondary : Brand.primary)
                        .frame(width: geo.size.width
                               * CGFloat(min(1, max(0, MixLevel.meterFraction(rms: level)))),
                               height: 4)
                }
            }
            .frame(height: 4)
            // THE SAME 0-10 SCALE THE TELEVISION USES (tvOS-DESIGN Rule 8.8c).
            //
            // This was `Slider(value: gain, in: 0...1.5)` with no number: a
            // raw linear amplitude, a ceiling of +3.5 dB where tvOS allows
            // +6, and nothing on screen a host could say out loud. Owner,
            // 2026-09-20, on the television's version: "a scale of 0 to 10
            // rather than ... decibles that most people won't understand" —
            // which is a statement about people, not about televisions.
            //
            // `Slider` IS the native control here (it is
            // `@available(tvOS, unavailable)`, which is why the television
            // draws its own), so the control stays native and only its SCALE
            // and its readout change.
            HStack(spacing: 12) {
                Slider(value: Binding(
                    get: { MixLevel.level(Float(gain.wrappedValue)) },
                    set: { gain.wrappedValue = Double(MixLevel.gain($0)) }),
                       in: 0...MixLevel.maximum)
                    .disabled(muted.wrappedValue)
                Text(MixLevel.text(MixLevel.level(Float(gain.wrappedValue))))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(muted.wrappedValue ? .secondary : .primary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The cards a host can raise, as a list rather than a segmented control —
/// they are actions with consequences, not a mode toggle.
private enum CardChoice: CaseIterable, Hashable {
    case startingSoon, intermission, ending

    var label: String {
        switch self {
        case .startingSoon: return "Starting soon"
        case .intermission: return "Intermission"
        case .ending: return "Thanks for watching"
        }
    }
    var value: StudioOverlay.Card {
        switch self {
        case .startingSoon: return .startingSoon(secondsRemaining: 0)
        case .intermission: return .intermission
        case .ending: return .ending
        }
    }
}
#endif
