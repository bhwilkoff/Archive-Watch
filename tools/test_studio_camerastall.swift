// §8.23 — the camera-stall recovery RULE, which existed on tvOS only.
import Foundation

@main
struct StallTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        print("=== 8.23 camera-stall recovery ===")

        // A healthy camera never triggers one.
        var r = CameraStallRecovery()
        var fired = false
        for _ in 0..<30 { if r.tick(attached: true, framesReceived: 900, framesPerSecond: 30, onAir: true) { fired = true } }
        check("8.23.1 a camera delivering frames is never rebuilt", !fired)

        // A stall fires on the FOURTH tick, not the first.
        r = CameraStallRecovery()
        let firings = (1...4).map { _ in r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true) }
        check("8.23.2 three dead ticks are tolerated", firings[0] == false && firings[1] == false && firings[2] == false)
        check("8.23.3 the fourth dead tick recovers", firings[3] == true)

        // Budget: three attempts, then it stops asking.
        r = CameraStallRecovery()
        var count = 0
        for _ in 0..<100 where r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true) { count += 1 }
        check("8.23.4 at most three attempts in a show", count == 3, "\(count)")

        // CONTROL: a camera that NEVER delivered is a different problem and
        // must not be rebuilt — otherwise a device with no camera at all
        // rebuilds three times every show.
        r = CameraStallRecovery()
        var never = false
        for _ in 0..<40 { if r.tick(attached: true, framesReceived: 0, framesPerSecond: 0, onAir: true) { never = true } }
        check("8.23.5 CONTROL a camera that never started is NOT rebuilt", !never)

        // CONTROL: off air. A paused or ended show is not a stall.
        r = CameraStallRecovery()
        var offAir = false
        for _ in 0..<40 { if r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: false) { offAir = true } }
        check("8.23.6 CONTROL an off-air show is NOT rebuilt", !offAir)

        // CONTROL: no camera asked for at all.
        r = CameraStallRecovery()
        var none = false
        for _ in 0..<40 { if r.tick(attached: false, framesReceived: 0, framesPerSecond: 0, onAir: true) { none = true } }
        check("8.23.7 CONTROL no camera attached is NOT rebuilt", !none)

        // Frames RESUMING clears the count, so a later stall gets its full
        // grace again rather than firing on the first dead tick.
        r = CameraStallRecovery()
        _ = r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true)
        _ = r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true)
        _ = r.tick(attached: true, framesReceived: 930, framesPerSecond: 30, onAir: true)
        let after = (1...3).map { _ in r.tick(attached: true, framesReceived: 930, framesPerSecond: 0, onAir: true) }
        check("8.23.8 recovered frames reset the grace period", after.allSatisfy { $0 == false })

        // A new show gets a fresh budget.
        r = CameraStallRecovery()
        for _ in 0..<100 { _ = r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true) }
        r.reset()
        var afterReset = 0
        for _ in 0..<100 where r.tick(attached: true, framesReceived: 900, framesPerSecond: 0, onAir: true) { afterReset += 1 }
        check("8.23.9 a new show gets a fresh budget", afterReset == 3, "\(afterReset)")

        print(failures == 0 ? "\n8.23 OK" : "\n8.23 \(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
