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
        if isLive && filmFramesPerSecond == 0 { w.append("the film has stopped arriving") }
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
        // destination is attached.
        max(0, health.encodedBytes * 8 / 1000 / max(1, secondsLive))
    }
    private var secondsLive: Int { max(1, health.programFramesEncoded / 30) }

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
    @Binding var card: StudioOverlay.Card?
    @Binding var showLowerThird: Bool
    let audio: StudioAudioHealth
    let health: StudioHealth
    /// Film frames delivered in the last second; 0 while live is the
    /// frozen-picture signature and gets said out loud.
    let filmFramesPerSecond: Int
    let onEnd: () -> Void

    private var healthFooter: String {
        if filmFramesPerSecond == 0 && health.showState.isOnAir {
            return "The film has stopped sending new frames — your audience is seeing a still picture. The sound and your camera are unaffected."
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

    var body: some View {
        NavigationStack {
            List {
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
                } header: {
                    Text("Sound")
                } footer: {
                    Text(audio.ducking
                         ? "The film is ducking under your voice."
                         : "The film drops 12 dB automatically while you are talking.")
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
                } footer: {
                    Text("A card covers the film completely — your audience sees only the card.")
                }

                Section {
                    Button("End the broadcast", role: .destructive) {
                        onEnd(); dismiss()
                    }
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule()
                        .fill(muted.wrappedValue ? Color.secondary : Brand.primary)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, level))), height: 4)
                }
            }
            .frame(height: 4)
            Slider(value: gain, in: 0...1.5)
                .disabled(muted.wrappedValue)
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
