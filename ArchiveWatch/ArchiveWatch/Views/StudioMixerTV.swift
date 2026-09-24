// The live mixer — tvOS-DESIGN Rule 8.8c.
//
// Two channels, Film and Microphone, adjusted by ROLLING the Siri Remote's
// clickpad. Up/down moves between channels, left/right nudges half a level for
// a host who would rather not roll, play/pause pauses the film without ending
// the broadcast, and auto-duck is a setting so that manual means manual.
//
// Owner, 2026-09-20, having rejected a preset list: "I'd much rather granular
// control ... the outer circle can be rolled around clockwise and
// counterclockwise and I would like to be able to use that gesture to turn up
// the movie or the microphone."
//
// And then, having used it: "the visual is not right. It should look like a
// level you are adjusting from right to left (or top to bottom) on a scale of
// 0 to 10 rather than on a scale of decibles that most people won't
// understand. Please use Apple TV design patterns to get this right rather
// than trying to make one up yourself."

#if os(tvOS)
import SwiftUI
import GameController

/// Reads the clickpad as a continuous dial.
///
/// `UIRotationGestureRecognizer` is `API_UNAVAILABLE(tvos)`, so the rotation
/// is derived rather than recognised: `GCMicroGamepad.dpad` with
/// `reportsAbsoluteDpadValues = true` reports the finger's ABSOLUTE position
/// on the pad in -1…1, and `atan2(y, x)` differenced between samples is a true
/// signed rotation. Samples near the centre are discarded — there the angle is
/// noise, not intent, and a thumb crossing the middle would otherwise jump the
/// gain by half a turn.
// `@Observable`, not `ObservableObject`: this project's model layer is Swift
// Observation throughout and Combine is imported nowhere (CLAUDE.md, and
// `StudioContinuity`'s own header says so).
@MainActor
@Observable
final class ClickpadDial {
    /// Signed radians since the last read, consumed by the view.
    private(set) var delta: CGFloat = 0

    private var lastAngle: CGFloat?
    private var observers: [Any] = []
    /// Below this radius the angle is meaningless.
    private let deadZone: CGFloat = 0.35

    func start() {
        attach(to: GCController.controllers())
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach(to: GCController.controllers()) }
            })
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        lastAngle = nil
    }

    private func attach(to controllers: [GCController]) {
        for c in controllers {
            guard let micro = c.microGamepad else { continue }
            // Absolute values are what make this a dial rather than a d-pad.
            micro.reportsAbsoluteDpadValues = true
            micro.dpad.valueChangedHandler = { [weak self] _, x, y in
                MainActor.assumeIsolated { self?.sample(x: CGFloat(x), y: CGFloat(y)) }
            }
        }
    }

    private func sample(x: CGFloat, y: CGFloat) {
        let r = sqrt(x * x + y * y)
        guard r >= deadZone else { lastAngle = nil; return }   // thumb lifted or centred
        let a = atan2(y, x)
        defer { lastAngle = a }
        guard let previous = lastAngle else { return }
        var d = a - previous
        // Shortest way round, so crossing ±π does not read as a full turn.
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        // A whole turn in one sample is a glitch, not a gesture.
        guard abs(d) < .pi / 2 else { return }
        delta = d
    }

    func consume() -> CGFloat { defer { delta = 0 }; return delta }
}

struct StudioMixerTV: View {

    enum Channel: Int { case film, microphone }

    let health: StudioHealth
    /// Current gains, read back from the mixer so this surface never keeps a
    /// copy that can drift from what the audience hears (Rule 8.8c).
    let filmGain: Float
    let micGain: Float
    let duckEnabled: Bool
    let filmPaused: Bool

    var onFilmGain: (Float) -> Void
    var onMicGain: (Float) -> Void
    var onDuck: (Bool) -> Void
    var onTogglePause: () -> Void
    var onDone: () -> Void

    @State private var channel: Channel = .film
    @State private var dial = ClickpadDial()

    private let accent = Color(red: 1.0, green: 0.361, blue: 0.208)

    /// A whole level per 45 degrees of roll — a full turn sweeps eight of the
    /// ten, which is the range a host actually moves through mid-show.
    private func rolled(_ level: Double, byRadians r: CGFloat) -> Double {
        clamp(level + Double(r * 180 / .pi) / 45)
    }

    private func clamp(_ l: Double) -> Double { min(MixLevel.maximum, max(0, l)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("WATCH TOGETHER")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent)
            Text("Live mixer")
                .font(.system(size: 58, weight: .bold))

            channelRow(.film, name: "Film", gain: filmGain, rms: health.audio.filmLevel)
            channelRow(.microphone, name: "Microphone", gain: micGain,
                       rms: health.audio.micLevel)

            // The one focusable control on the screen, deliberately: the focus
            // engine consumes arrow keys the moment it has two places to send
            // them, and `.onMoveCommand` — which is how up/down changes channel
            // and left/right nudges the level — would stop firing.
            Button(duckEnabled ? "Auto-duck is on" : "Auto-duck is off") {
                onDuck(!duckEnabled)
            }
            .font(.system(size: 29, weight: .medium))

            // §4: never hide health numbers — and never hide what the controls do.
            Text("Roll the remote's pad to set the highlighted channel · up and "
                 + "down to switch · left and right for half a level · play/pause "
                 + "pauses the film without ending the broadcast · Menu to go back")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 1200, alignment: .leading)
            Text("8 is the level the source already has.")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: 1200, alignment: .leading)

            if filmPaused {
                Label("Film paused — your audience sees a still picture",
                      systemImage: "pause.circle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.92))
        .onAppear { dial.start() }
        .onDisappear { dial.stop() }
        .onChange(of: dial.delta) { _, _ in
            let d = dial.consume()
            guard d != 0 else { return }
            switch channel {
            case .film: onFilmGain(MixLevel.gain(rolled(MixLevel.level(filmGain), byRadians: d)))
            case .microphone: onMicGain(MixLevel.gain(rolled(MixLevel.level(micGain), byRadians: d)))
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: channel = .film
            case .down: channel = .microphone
            case .left: step(-0.5)
            case .right: step(+0.5)
            @unknown default: break
            }
        }
        .onExitCommand { onDone() }
        .onPlayPauseCommand { onTogglePause() }
    }

    private func step(_ by: Double) {
        switch channel {
        case .film: onFilmGain(MixLevel.gain(clamp(MixLevel.level(filmGain) + by)))
        case .microphone: onMicGain(MixLevel.gain(clamp(MixLevel.level(micGain) + by)))
        }
    }

    // MARK: - One channel

    @ViewBuilder
    private func channelRow(_ c: Channel, name: String, gain: Float, rms: Float) -> some View {
        let selected = channel == c
        let level = MixLevel.level(gain)
        HStack(alignment: .center, spacing: 34) {
            Text(name)
                .font(.system(size: 38, weight: selected ? .bold : .medium))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                .frame(width: 260, alignment: .leading)

            fader(level: level, rms: rms, selected: selected)

            // Apple's own slider guidance: "Consider supplementing a slider
            // with a corresponding text field ... people may appreciate seeing
            // the exact slider value." On a television there is no field to
            // type into, so the value is simply shown, large enough to read
            // from the couch.
            Text(MixLevel.text(level))
                .font(.system(size: selected ? 64 : 52, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(selected ? accent : .white.opacity(0.55))
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
        .background(selected ? .white.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 22))
        // tvOS's focus system "gently highlight[s] and expand[s] onscreen
        // items as people move among them". This screen cannot use the real
        // focus engine (see the Auto-duck button), so the selected channel is
        // given the same read by hand — by the panel, the accent fill and the
        // size of the number, and NOT by scaling the row. A `scaleEffect` was
        // tried first and photographed on Ben Bedroom: anchored leading it
        // pulls the unselected row's right edge inward, so the two channels'
        // numbers no longer line up, and a column of numbers that does not
        // align is harder to read at eight feet than one that does not move.
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    /// A track that fills from the leading side, with a tick at every whole
    /// level and the live meter beneath it.
    ///
    /// Apple's slider guidance, which is the closest thing tvOS has to a rule
    /// here — `Slider` itself is `@available(tvOS, unavailable)` and the HIG
    /// says plainly "Not supported in tvOS", so the LOOK is borrowed and the
    /// INPUT is the remote's own:
    ///
    ///   "As a slider's value changes, the portion of track between the
    ///    minimum value and the thumb fills with color."
    ///   "People expect the minimum and maximum sides of sliders to be
    ///    consistent in all apps, with minimum values on the leading side and
    ///    maximum values on the trailing side."
    ///   "Sliders in macOS can also include tick marks, making it easier for
    ///    people to pinpoint a specific value within the range."
    ///
    /// The direction rule is why 0 sits on the left and 10 on the right: the
    /// owner asked for "a level you are adjusting from right to left", i.e.
    /// turning it DOWN moves leftward, which is the same arrangement.
    @ViewBuilder
    private func fader(level: Double, rms: Float, selected: Bool) -> some View {
        let fraction = level / MixLevel.maximum
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let knob = 26.0
                let travel = w - knob
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: 14)
                    Capsule()
                        .fill(selected ? accent : Color.white.opacity(0.45))
                        .frame(width: knob / 2 + travel * fraction, height: 14)
                    // Ticks at every whole level; the unity tick is taller,
                    // because it is the one position with a meaning a host can
                    // act on.
                    ForEach(0...Int(MixLevel.maximum), id: \.self) { i in
                        let isUnity = Double(i) == MixLevel.unity
                        // The unity tick is drawn TALLER THAN THE KNOB on
                        // purpose. Both channels default to 8, so the knob sits
                        // on this tick at rest and a shorter one is simply
                        // invisible exactly when a host is first looking for
                        // "where was it before I touched it".
                        Capsule()
                            .fill(.white.opacity(isUnity ? 0.85 : 0.35))
                            .frame(width: 3, height: isUnity ? 56 : 18)
                            .offset(x: knob / 2 - 1.5
                                    + travel * (Double(i) / MixLevel.maximum))
                    }
                    Capsule()
                        .fill(.white)
                        .frame(width: knob, height: selected ? 44 : 34)
                        .shadow(radius: selected ? 8 : 0)
                        .offset(x: travel * fraction)
                }
                .frame(height: 60, alignment: .center)
            }
            .frame(height: 60)

            // The meter is the honest part: it says what the audience hears,
            // whatever the fader claims. Drawn on the fader's own 0–10 scale
            // so the two can be read against each other.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule()
                        .fill(.white.opacity(selected ? 0.7 : 0.35))
                        .frame(width: geo.size.width
                               * CGFloat(min(1, max(0, MixLevel.meterFraction(rms: rms)))))
                }
            }
            .frame(height: 8)

            HStack {
                Text("0").foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("10").foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 23, weight: .medium))
            .monospacedDigit()
        }
        .frame(maxWidth: 880)
    }
}
#endif
