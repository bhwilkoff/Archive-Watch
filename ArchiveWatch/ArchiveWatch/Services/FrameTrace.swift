#if os(tvOS)
import Foundation
import QuartzCore

/// Frame-time sampler for the "it's very, very slow" reports.
///
/// A viewer on an Apple TV 4K (2nd generation) told us on 2026-09-11 that the
/// app was "very, very s l o w", and the owner had independently noticed that
/// scrolling drags on the older unit while the 3rd generation is fine. Before
/// this there was NO way to measure that claim on tvOS: the Creation Studio
/// has benchmarks, the Android TV app has a focus trace, and the Apple TV had
/// launch prints and nothing else.
///
/// Two earlier attempts to measure it from OUTSIDE failed, and both failures
/// are the argument for this file:
///   * Comparing launch logs across the two units compared DIFFERENT events —
///     "swapped to full DB" is a catalog DOWNLOAD, so a 10.9s reading on one
///     unit against 5.8s on the other was network weather, not silicon.
///   * Screenshot-diff timing cannot resolve a dropped frame: a 4K capture
///     pressures the device's own screenshot daemon hard enough that the
///     harness already samples no faster than every 4 seconds.
///
/// So the measurement has to come from inside the render loop. `CADisplayLink`
/// fires once per displayed frame; the gaps between fires ARE the smoothness
/// the viewer is describing. A frame that takes longer than 1.5 display
/// intervals is one the viewer can see.
///
/// OFF unless `AW_FRAME_TRACE=1`, and it allocates nothing per frame.
@MainActor
final class FrameTrace {
    static let shared = FrameTrace()
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["AW_FRAME_TRACE"] == "1" }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var longFrames = 0
    private var worst: Double = 0
    /// The display's own frame budget, read from the link rather than assumed:
    /// an Apple TV may be driving a 60Hz panel or a 50Hz one, and a hard-coded
    /// 16.7ms would report a 50Hz display as permanently dropping frames.
    private var budget: Double = 1.0 / 60.0

    func start(label: String) {
        guard Self.isEnabled, link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        last = 0; frames = 0; longFrames = 0; worst = 0
        windowStart = CACurrentMediaTime()
        print("[AWFRAME] start \(label)")
    }

    func stop() {
        guard link != nil else { return }
        report(final: true)
        link?.invalidate(); link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if l.duration > 0 { budget = l.duration }
        defer { last = now }
        guard last > 0 else { return }
        let dt = now - last
        frames += 1
        if dt > budget * 1.5 { longFrames += 1 }
        if dt > worst { worst = dt }
        if now - windowStart >= 2.0 { report(final: false) }
    }

    private func report(final: Bool) {
        let now = CACurrentMediaTime()
        let span = now - windowStart
        guard span > 0, frames > 0 else { return }
        let fps = Double(frames) / span
        let pct = Double(longFrames) / Double(frames) * 100
        print(String(format: "[AWFRAME] %@ fps=%.1f frames=%d long=%d (%.1f%%) worst=%.0fms budget=%.1fms",
                     final ? "final" : "window", fps, frames, longFrames, pct,
                     worst * 1000, budget * 1000))
        windowStart = now; frames = 0; longFrames = 0; worst = 0
    }
}
#endif
