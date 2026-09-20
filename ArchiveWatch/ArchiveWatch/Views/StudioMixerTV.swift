// The live mixer — tvOS-DESIGN Rule 8.8c.
//
// Two channels, Film and Microphone, adjusted by ROLLING the Siri Remote's
// clickpad. Up/down moves between channels, left/right nudges 1 dB for a host
// who would rather not roll, play/pause pauses the film without ending the
// broadcast, and the Film channel carries auto-duck as a third state.
//
// Owner, 2026-09-20, having rejected a preset list: "I'd much rather granular
// control ... the outer circle can be rolled around clockwise and
// counterclockwise and I would like to be able to use that gesture to turn up
// the movie or the microphone."

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

    /// Rule 8.8c: roughly 0.5 dB per 10 degrees, clamped to -inf…+6 dB.
    private func adjusted(_ gain: Float, byRadians r: CGFloat) -> Float {
        let degrees = Float(r * 180 / .pi)
        let dB = 20 * log10(max(gain, 0.0001)) + degrees * 0.05
        return min(pow(10, min(dB, 6) / 20), pow(10, 6.0 / 20))
    }

    private func dB(_ gain: Float) -> String {
        gain <= 0.0001 ? "−∞" : String(format: "%+.1f dB", 20 * log10(gain))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Text("WATCH TOGETHER")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.361, blue: 0.208))
            Text("Live mixer")
                .font(.system(size: 58, weight: .bold))

            channelRow(.film, name: "Film", gain: filmGain, level: health.audio.filmLevel)
            channelRow(.microphone, name: "Microphone", gain: micGain,
                       level: health.audio.micLevel)

            // §4: never hide health numbers — and never hide what the controls do.
            Text("Roll the remote's pad to set the focused channel · up and down to "
                 + "switch · left and right for 1 dB · play/pause pauses the film "
                 + "without ending the broadcast · Menu to go back")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 1100, alignment: .leading)

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
            case .film: onFilmGain(adjusted(filmGain, byRadians: d))
            case .microphone: onMicGain(adjusted(micGain, byRadians: d))
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: channel = .film
            case .down: channel = .microphone
            case .left: step(-1)
            case .right: step(+1)
            @unknown default: break
            }
        }
        .onExitCommand { onDone() }
        .onPlayPauseCommand { onTogglePause() }
    }

    private func step(_ dB: Float) {
        let apply: (Float) -> Float = { g in
            min(pow(10, min(20 * log10(max(g, 0.0001)) + dB, 6) / 20), pow(10, 6.0 / 20))
        }
        switch channel {
        case .film: onFilmGain(apply(filmGain))
        case .microphone: onMicGain(apply(micGain))
        }
    }

    @ViewBuilder
    private func channelRow(_ c: Channel, name: String, gain: Float, level: Float) -> some View {
        let focused = channel == c
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Text(name)
                    .font(.system(size: 40, weight: focused ? .bold : .medium))
                Text(dB(gain))
                    .font(.system(size: 40, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(focused ? 1 : 0.6))
                if c == .film {
                    Button(duckEnabled ? "Auto-duck on" : "Auto-duck off") {
                        onDuck(!duckEnabled)
                    }
                    .font(.system(size: 26, weight: .medium))
                }
            }
            // The meter is the honest part: it says what the audience hears,
            // whatever the fader claims.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(focused
                              ? Color(red: 1.0, green: 0.361, blue: 0.208)
                              : Color.white.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
                }
            }
            .frame(height: 16)
            .frame(maxWidth: 900)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 22)
        .background(focused ? .white.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif
