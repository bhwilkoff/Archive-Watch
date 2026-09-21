#if os(macOS)
import SwiftUI

// The Studio's health readout on macOS — macOS-DESIGN §B13d.
//
// Pinned top-leading OVER the player, deliberately outside AVPlayerView's own
// floating HUD (§B3a): the HUD auto-hides after a few seconds and health may
// never be hidden (docs/WATCH-TOGETHER.md §4). A host is responsible for a
// broadcast and cannot be responsible for something they cannot see.
//
// It also states the ONE current problem in words rather than as a chip. On a
// phone the capsule has a tap target to open a sheet; a Mac host is often
// looking at another window entirely, so the sentence has to be on the glass.

struct StudioMacReadout: View {
    let health: StudioHealth
    let filmFramesPerSecond: Int
    /// Camera frames in the last second — 0 while live, for a camera that HAS
    /// delivered, is the tile-went-dark signature.
    let cameraFramesPerSecond: Int
    let onEnd: () -> Void
    let onOpenControls: () -> Void

    private var isLive: Bool { health.showState.isOnAir }
    /// `Brand` is iOS-only; the Mac views spell the marquee orange out, as
    /// ChannelsView_macOS already notes.
    private let marquee = Color(hex: "#FF5C35") ?? .orange

    /// Same order as the tvOS readout: the show's own state first, because
    /// `notEncoding` outranks anything a counter can say (§9).
    private var problem: String? {
        if let d = health.showState.detail { return d }
        if isLive && filmFramesPerSecond == 0 { return "The film has stopped — your audience sees a still picture" }
        // A CAMERA THAT DIED MID-SHOW — the guard the television has carried
        // since 2026-09-19, when a Continuity camera ran a clean 30/s for ten
        // seconds and then stopped dead for eighty while every other number
        // stayed healthy. `cameraFramesReceived > 0` matters: between the
        // attach and the first delivered frame a camera is legitimately
        // attached at zero, and without it this flashes during every normal
        // start. The word is STOPPED, so it may only appear for a camera that
        // had started.
        // BEFORE the camera: an audience hearing nothing is worse off than an
        // audience not seeing the host. tvOS has shown this since §9.jjjj and
        // macOS asked for it nowhere.
        if isLive, let audio = StudioSession.shared.filmAudioProblem { return audio }
        if isLive, health.cameraAttached, health.cameraFramesReceived > 0,
           cameraFramesPerSecond == 0 {
            return "The camera has stopped — your audience sees the film without you"
        }
        if let f = health.encoderFault { return f }
        if health.thermalState == "critical" { return "This Mac is too hot to keep streaming" }
        if health.thermalState == "serious" { return "This Mac is getting hot" }
        if let e = health.publisher.lastError { return e }
        if health.publisher.videoFramesDropped > 30 { return "Dropping frames — the connection is struggling" }
        return nil
    }

    private var kbps: Int {
        let seconds = max(1, health.programFramesEncoded / 30)
        return max(0, health.encodedBytes * 8 / 1000 / seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isLive ? Color.red : Color.secondary)
                    .frame(width: 9, height: 9)
                Text(health.showState.label)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Divider().frame(height: 11)
                Text("\(kbps) kbps")
                    .font(.caption).monospacedDigit()
                Text("\(String(format: "%.1f", health.averageRenderMilliseconds)) ms")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                Divider().frame(height: 11)
                Button("Controls", action: onOpenControls)
                    .font(.caption)
                    .buttonStyle(.borderless)
                Button("End", action: onEnd)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(marquee)
            }
            // §5's adaptive step, on its OWN line rather than folded into
            // `problem`: "no destination is set" and "the picture is being
            // sent at 3600 instead of 6000 kbps" can both be true, and
            // whichever won a single slot would hide the other.
            if let note = health.qualityNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The width belongs to the CONTAINER, not to the problem text. With it
        // on the text, the two rows sized independently and the capsule drew
        // as a ragged two-tone box with "is set." hanging off a narrower
        // second tier (seen on the glass, macOS 27, 2026-09-17).
        .frame(width: 330, alignment: .leading)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: 10))
        .padding(16)
    }
}

// MARK: - The program panel (macOS-DESIGN §B13c)

// A native `Form` in a sheet, NOT an inspector rail: a rail reflows the
// player, and §B8/§B7 own the wide surfaces. It mirrors the iOS §4.5 controls
// sheet so a host who learned one already knows the other.
//
// What belongs here and what does not: the FILM's transport stays on
// AVPlayerView's own floating HUD (§B13b) — this panel is for the PROGRAM.
// Layout, the two faders, and the cards.

struct StudioMacPanel: View {
    @Environment(\.dismiss) private var dismiss

    let health: StudioHealth
    let audio: StudioAudioHealth
    let filmFramesPerSecond: Int
    let cameraFramesPerSecond: Int

    @Binding var layout: StudioLayout
    @Binding var filmGain: Double
    @Binding var micGain: Double
    @Binding var filmMuted: Bool
    @Binding var micMuted: Bool
    @Binding var duckEnabled: Bool
    @Binding var showLowerThird: Bool
    @Binding var card: StudioOverlay.Card?
    let onEnd: () -> Void

    private let marquee = Color(hex: "#FF5C35") ?? .orange

    private var healthNote: String {
        if health.showState == .notEncoding {
            return "The picture has stopped being encoded, so your audience is not receiving the show. Ending and restarting the broadcast is the reliable fix."
        }
        if filmFramesPerSecond == 0 && health.showState.isOnAir {
            return "The film has stopped sending new frames — your audience is seeing a still picture. The sound and your camera are unaffected."
        }
        // A CAMERA THAT DIED MID-SHOW — the same guard the television carries
        // (tvOS `StudioTV.swift`). `cameraFramesReceived > 0` matters:
        // between the attach and the first delivered frame a camera is
        // legitimately attached at zero, and without it the readout flashes
        // "stopped" during every normal start. The word is STOPPED, so it may
        // only appear for a camera that had started.
        if health.showState.isOnAir, health.cameraAttached,
           health.cameraFramesReceived > 0, cameraFramesPerSecond == 0 {
            return "The camera has stopped — your audience sees the film without you."
        }
        return "These numbers are what your audience is actually receiving."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                // ONE LINE, not the six rows this started as. A sheet cannot
                // grow past its parent window, and at six rows the Sound
                // faders — the controls a host actually reaches for — were
                // below the fold on open (seen on the glass, macOS 27).
                // Density comes from removing chrome (CLAUDE.md), and these
                // numbers are not hidden: the always-on readout (§B13d)
                // carries the state, the bitrate and the problem sentence, so
                // what belongs HERE is only what the readout has no room for.
                Section("Health") {
                    LabeledContent("Program", value: String(
                        format: "%.1f ms per frame · %d fps encoded",
                        health.averageRenderMilliseconds, health.encodedFramesPerSecond))
                    LabeledContent("Delivery", value:
                        "\(health.publisher.videoFramesDropped) dropped · \(health.thermalState)")
                    if let f = health.encoderFault {
                        Text(f).font(.footnote).foregroundStyle(.orange)
                    }
                    Text(healthNote).font(.footnote).foregroundStyle(.secondary)
                }

                // A POP-UP, not a radio group. Five exclusive options in a
                // radio group cost five rows in a sheet that cannot grow past
                // its parent window, and they pushed the Sound faders — the
                // controls a host actually reaches for mid-show — below the
                // fold. A pop-up button is what macOS uses for an exclusive
                // choice of this size, and it is one row.
                Section("Layout") {
                    Picker("Layout", selection: $layout) {
                        ForEach(StudioLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }

                Section("Sound") {
                    fader("Film", level: audio.filmLevel, gain: $filmGain, muted: $filmMuted, icon: "film")
                    fader("Your microphone", level: audio.micLevel, gain: $micGain, muted: $micMuted, icon: "mic")
                    // AUTO-DUCK IS A CONTROL, NOT A SENTENCE (Rule 8.8c).
                    // This section used to STATE that "the film drops 12 dB
                    // automatically while you are talking", which is exactly
                    // the problem the television found: a host who sets Film
                    // to 9 and then speaks hears it drop 12 dB anyway and
                    // reasonably concludes the fader is broken. Manual has to
                    // mean manual. Owner: "I like the idea of turning ducking
                    // on and off to allow manual control."
                    Toggle("Duck the film under my voice", isOn: $duckEnabled)
                    Text(duckEnabled
                         ? (audio.ducking
                            ? "The film is ducking under your voice."
                            : "The film drops 12 dB automatically while you are talking.")
                         : "The film stays where you set it. 8 is the level it already has.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("On screen") {
                    Toggle("Show the film's title on screen", isOn: $showLowerThird)
                    Picker("Card", selection: Binding(
                        get: { MacCardChoice.from(card) },
                        set: { card = $0.value })) {
                        ForEach(MacCardChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text("A card covers the film completely — your audience sees only the card.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            // What the gate cannot protect a host from (§3.4a). macOS has no
            // pre-flight sheet — Detail goes straight to the player — so this
            // is the first surface that can say it.
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(StudioRights.hostWarning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Divider()
            HStack {
                Button("End the broadcast", role: .destructive) { onEnd(); dismiss() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 470, height: 600)
    }

    /// One fader: a live meter, a slider and a mute. The meter is the point —
    /// a fader with no meter is a control whose effect you cannot hear until
    /// the audience already has.
    private func fader(_ label: String, level: Float, gain: Binding<Double>,
                       muted: Binding<Bool>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(label, systemImage: icon).font(.subheadline.weight(.medium))
                Spacer()
                Toggle(isOn: Binding(get: { !muted.wrappedValue },
                                     set: { muted.wrappedValue = !$0 })) {
                    Text(muted.wrappedValue ? "Muted" : "On")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            // The meter reads on the FADER'S scale, not linearly. A linear
            // 0-1 meter draws 2% for speech at RMS 0.02 and looks dead, which
            // is how a working microphone reads as a broken one.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule()
                        .fill(muted.wrappedValue ? Color.secondary : marquee)
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
            HStack(spacing: 10) {
                Slider(value: Binding(
                    get: { MixLevel.level(Float(gain.wrappedValue)) },
                    set: { gain.wrappedValue = Double(MixLevel.gain($0)) }),
                       in: 0...MixLevel.maximum)
                    .disabled(muted.wrappedValue)
                Text(MixLevel.text(MixLevel.level(Float(gain.wrappedValue))))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(muted.wrappedValue ? .secondary : .primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The cards, as a radio group: they are actions with consequences, not a
/// mode toggle, and macOS spells an exclusive choice this way.
private enum MacCardChoice: CaseIterable, Hashable {
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
