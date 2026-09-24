// §8.61 — an exhausted pixel-buffer pool is survived, not crashed on (launch
// audit B). Every buffer the pool hands out is HELD, as a backed-up encoder
// would hold them:
//   cap     — allocation stops at the ceiling instead of growing forever
//   render  — with nothing left, render() returns the LAST program frame
//   blank   — blankFrame() returns nil (it force-unwrapped and crashed)
import Foundation
import CoreVideo

@main struct PoolTest {
    static func main() {
        let r = ProgramRenderer(size: CGSize(width: 640, height: 360))
        let first = r.render(film: nil, camera: nil)
        var held: [CVPixelBuffer] = first.map { [$0] } ?? []
        while held.count < 100, let px = r.newBuffer() { held.append(px) }
        print("  cap: pool stopped after \(held.count) outstanding buffers (failures counted: \(r.poolFailures))")
        let again = r.render(film: nil, camera: nil)
        let heldLast = again != nil && again! === first!
        print("  render with the pool exhausted returned the last frame: \(heldLast)")
        let blank = r.blankFrame()
        print("  blankFrame with the pool exhausted returned nil: \(blank == nil)")
        let pass = held.count < 100 && r.poolFailures > 0 && heldLast && blank == nil
        print(pass ? "PASS" : "FAIL"); exit(pass ? 0 : 1)
    }
}
