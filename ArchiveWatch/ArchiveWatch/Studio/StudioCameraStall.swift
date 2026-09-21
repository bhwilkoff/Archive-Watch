import Foundation

/**
 Should a camera that stopped delivering be re-attached?

 A camera stops mid-show more often than one might expect: a Continuity phone
 takes a call, a USB camera is unplugged, a Mac sleeps a display. It was
 observed FOUR times on an Apple TV on 2026-09-19 — a clean 30/s for ten
 seconds, then dead for eighty while every other number stayed healthy.

 THE DECISION LIVES HERE because the implementation lived in
 `Views/DetailView.swift` — the tvOS view — and therefore existed on exactly
 one platform. `PARITY.md` said as much in plain sight ("no recovery yet" for
 iOS and macOS) while the same doc noted that macOS can use an iPhone as its
 camera too, so it can drop in precisely the way the television does. That is
 this project's most repeated fault in one line: a behaviour written into one
 platform's view and believed to be the product's (§6.3's idle timer, §6.2's
 audio session, Android's studio bench door, the iOS auth door — all of them
 the same shape).

 A pure value type, so the RULE can be tested without a camera, a show or a
 device — which is the only reason the thresholds below are checkable at all.
 */
public struct CameraStallRecovery: Sendable, Equatable {

    /// Consecutive ticks with a camera attached, on air, and no new frames.
    public private(set) var stallTicks = 0
    /// Re-attach attempts made during this show.
    public private(set) var attempts = 0

    /// Four seconds, not one: a camera legitimately misses a tick, and a
    /// rebuild is disruptive enough that it must not fire on a hiccup.
    public static let ticksBeforeRecovery = 4
    /// Three, then stop. A rebuild that cannot succeed must not be attempted
    /// once a second for the length of a show.
    public static let maximumAttempts = 3

    public init() {}

    /// Feed one health tick. Returns true when the caller should re-attach.
    ///
    /// - Parameters:
    ///   - attached: the host asked for a camera and one was attached.
    ///   - framesReceived: total frames the tap has ever seen.
    ///   - framesPerSecond: frames in the last tick.
    ///   - onAir: the show is actually live; a paused or ended show is not a
    ///     stall, and rebuilding into one wastes the attempt budget.
    public mutating func tick(attached: Bool, framesReceived: Int,
                              framesPerSecond: Int, onAir: Bool) -> Bool {
        // ONLY A CAMERA THAT HAD STARTED. One that never delivered a frame is
        // a different problem with a different sentence on the readout, and
        // re-attaching it in a loop would hide that.
        guard attached, framesReceived > 0, onAir, framesPerSecond == 0 else {
            if framesPerSecond > 0 { stallTicks = 0 }
            return false
        }
        stallTicks += 1
        guard stallTicks >= Self.ticksBeforeRecovery, attempts < Self.maximumAttempts else {
            return false
        }
        stallTicks = 0
        attempts += 1
        return true
    }

    /// A new show starts with a fresh budget.
    public mutating func reset() { stallTicks = 0; attempts = 0 }
}
