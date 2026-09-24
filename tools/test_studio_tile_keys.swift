// §8.69 — keyboard framing (macOS-DESIGN §D14a): a step moves or reshapes,
// and the clamp is the drag's — never out of the frame, never below minimum.
import Foundation
import CoreGraphics

@main
struct TileKeys {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 } }
        let near = { (a: CGFloat, b: CGFloat) in abs(a - b) < 1e-9 }
        let r = CGRect(x: 0.70, y: 0.05, width: 0.25, height: 0.25)
        let right = StudioCameraFraming.nudged(r, dx: 0.01, dy: 0, reshape: false)
        check(near(right.minX, 0.71) && near(right.width, 0.25), "a right arrow moves 1%, keeps the size")
        let pinned = StudioCameraFraming.nudged(r, dx: 0.10, dy: 0, reshape: false)
        check(near(pinned.maxX, 1.0), "Shift-right past the edge stops AT the edge (\(pinned.maxX))")
        let down = StudioCameraFraming.nudged(r, dx: 0, dy: -0.10, reshape: false)
        check(near(down.minY, 0), "down past the bottom stops at the bottom")
        let wider = StudioCameraFraming.nudged(r, dx: 0.10, dy: 0, reshape: true)
        check(near(wider.width, 0.35) && near(wider.maxX, 1.0), "Option-right widens and is pulled back inside")
        var tiny = r
        for _ in 0..<60 { tiny = StudioCameraFraming.nudged(tiny, dx: -0.01, dy: -0.01, reshape: true) }
        check(near(tiny.width, StudioCameraFraming.minimumTileFraction), "shrinking stops at the minimum")
        // Control: an unclamped move really would leave the frame.
        check(r.offsetBy(dx: 0.10, dy: 0).maxX > 1, "control: the raw move leaves the frame")
        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
