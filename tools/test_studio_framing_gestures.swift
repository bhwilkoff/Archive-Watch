// §8.78 — the canvas gestures do what their handles say (macOS-DESIGN §D14b).
//
// Owner, 2026-10-02: "The resizing and cropping of my video and the call
// video doesn't work as it should. It was very hard to manipulate and crop a
// video." The rule, as geometry: a CORNER scales the tile and its picture
// together; an EDGE moves only that edge and cuts the picture there while the
// picture itself stays still; ⌥-drag slides the picture inside the cut; scroll
// zooms it. Each is checked by mapping a point of the SOURCE to where it lands
// on the program before and after: a cut must not move what it does not cut.
//
// Control: the §D14a behavior (reshape an aspect-filled box) moves the
// picture under an edge drag, and the same measurement must catch it.
import Foundation
import CoreGraphics

@main struct FramingGestures {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "  ok  " : "  FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    static let P: CGFloat = 16.0 / 9.0      // program aspect
    static let S: CGFloat = 16.0 / 9.0      // a 16:9 webcam

    /// Where source point `p` (normalized) is drawn on the program, or nil
    /// when the framing does not show it.
    static func place(_ p: CGPoint, _ f: StudioCameraFraming, tile t: CGRect) -> CGPoint? {
        let c = f.visibleCrop(sourceAspect: S, tileAspect: t.width * P / t.height)
        guard c.contains(p) else { return nil }
        return CGPoint(x: t.minX + (p.x - c.minX) / c.width * t.width,
                       y: t.minY + (p.y - c.minY) / c.height * t.height)
    }
    static func near(_ a: CGPoint?, _ b: CGPoint?, _ tol: CGFloat = 1e-6) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) < tol && abs(a.y - b.y) < tol
    }

    static func main() {
        print("=== 8.78 canvas framing gestures ===")
        let t = CGRect(x: 0.70, y: 0.05, width: 0.25, height: 0.25)   // 16:9 tile
        let f0 = StudioCameraFraming()
        let probe = CGPoint(x: 0.3, y: 0.5)          // a point left of where we cut

        // EDGE: drag the RIGHT edge in by 0.08 — the picture stays put.
        let cut = StudioCameraFraming.dragged(f0, tile: t, grab: .edge(x: 1, y: 0), dx: -0.08, dy: 0,
                                              programAspect: P, sourceAspect: S)
        check("right edge in: the tile narrows from the right", abs(cut.tile!.minX - t.minX) < 1e-9
              && abs(cut.tile!.width - 0.17) < 1e-9, "\(cut.tile!)")
        check("right edge in: what is left of the cut does not move",
              near(place(probe, f0, tile: t), place(probe, cut, tile: cut.tile!)))
        check("right edge in: the right of the picture is gone",
              place(CGPoint(x: 0.95, y: 0.5), cut, tile: cut.tile!) == nil)
        // LEFT edge in, TOP edge down: same rule on the other sides.
        let left = StudioCameraFraming.dragged(f0, tile: t, grab: .edge(x: -1, y: 0), dx: 0.05, dy: 0,
                                               programAspect: P, sourceAspect: S)
        check("left edge in: a point right of the cut does not move",
              near(place(CGPoint(x: 0.8, y: 0.5), f0, tile: t), place(CGPoint(x: 0.8, y: 0.5), left, tile: left.tile!)))
        let top = StudioCameraFraming.dragged(f0, tile: t, grab: .edge(x: 0, y: 1), dx: 0, dy: -0.06,
                                              programAspect: P, sourceAspect: S)
        check("top edge down: a point below the cut does not move",
              near(place(CGPoint(x: 0.5, y: 0.2), f0, tile: t), place(CGPoint(x: 0.5, y: 0.2), top, tile: top.tile!)))
        // An edge cannot reveal what the source does not have.
        let out = StudioCameraFraming.dragged(f0, tile: t, grab: .edge(x: 1, y: 0), dx: 0.3, dy: 0,
                                              programAspect: P, sourceAspect: S)
        check("right edge OUT on an uncut picture: nothing to reveal, the tile stays",
              abs(out.tile!.width - t.width) < 1e-9, "\(out.tile!.width)")
        let back = StudioCameraFraming.dragged(cut, tile: cut.tile!, grab: .edge(x: 1, y: 0), dx: 0.08, dy: 0,
                                               programAspect: P, sourceAspect: S)
        check("right edge back out: the cut is undone exactly",
              abs(back.tile!.width - t.width) < 1e-9 && abs((back.crop?.maxX ?? 0) - 1) < 1e-9)

        // CORNER: scale about the opposite corner, proportions and cut kept.
        let big = StudioCameraFraming.dragged(cut, tile: cut.tile!, grab: .corner(x: -1, y: 1), dx: -0.1, dy: 0.1,
                                              programAspect: P, sourceAspect: S)
        let r0 = cut.tile!.width / cut.tile!.height, r1 = big.tile!.width / big.tile!.height
        check("corner: proportions kept", abs(r0 - r1) < 1e-6, "\(r0) vs \(r1)")
        check("corner: anchored at the opposite corner",
              abs(big.tile!.maxX - cut.tile!.maxX) < 1e-9 && abs(big.tile!.minY - cut.tile!.minY) < 1e-9)
        check("corner: the cut is unchanged", big.crop == cut.crop)
        let huge = StudioCameraFraming.dragged(f0, tile: t, grab: .corner(x: 1, y: 1), dx: 5, dy: 5,
                                               programAspect: P, sourceAspect: S)
        check("corner: never past the frame", huge.tile!.maxX <= 1 + 1e-9 && huge.tile!.maxY <= 1 + 1e-9)

        // BODY: moves the tile, clamps inside the frame, cut untouched.
        let moved = StudioCameraFraming.dragged(cut, tile: cut.tile!, grab: .body, dx: 0.5, dy: 0,
                                                programAspect: P, sourceAspect: S)
        check("body: moved and kept inside", abs(moved.tile!.maxX - 1) < 1e-9 && moved.crop == cut.crop)

        // PAN: the picture follows the pointer inside a cut.
        let zoomed = StudioCameraFraming.zoomed(f0, tile: t, factor: 2, programAspect: P, sourceAspect: S)
        check("scroll: zooms the picture, not the tile",
              zoomed.tile == t && abs((zoomed.crop?.width ?? 1) - 0.5) < 1e-6)
        let panned = StudioCameraFraming.dragged(zoomed, tile: t, grab: .pan, dx: 0.05, dy: 0,
                                                 programAspect: P, sourceAspect: S)
        check("⌥-drag right: the picture moves right (the cut moves left)",
              (panned.crop?.minX ?? 0) < (zoomed.crop?.minX ?? 0))
        let far = StudioCameraFraming.dragged(zoomed, tile: t, grab: .pan, dx: -5, dy: 0,
                                              programAspect: P, sourceAspect: S)
        check("⌥-drag: never past the picture's edge", abs((far.crop?.maxX ?? 0) - 1) < 1e-9)
        let out2 = StudioCameraFraming.zoomed(f0, tile: t, factor: 0.2, programAspect: P, sourceAspect: S)
        check("scroll out: never past the whole picture", (out2.crop?.width ?? 2) <= 1 + 1e-9)

        // A §D14a framing (zoom/pan) converts without a jump.
        var old = StudioCameraFraming(); old.zoom = 2; old.panX = 0.5
        let conv = StudioCameraFraming.dragged(old, tile: t, grab: .corner(x: 1, y: 1), dx: 0, dy: 0,
                                               programAspect: P, sourceAspect: S)
        check("an older zoom/pan framing converts without moving the picture",
              near(place(CGPoint(x: 0.6, y: 0.5), old, tile: t), place(CGPoint(x: 0.6, y: 0.5), conv, tile: conv.tile!)))

        // CONTROL: §D14a's edge — reshape an aspect-filled box — moves the
        // picture under the drag, and the measurement above must see it.
        var reshaped = f0; reshaped.tile = CGRect(x: t.minX, y: t.minY, width: 0.17, height: t.height)
        check("CONTROL: a reshape of an aspect-filled box moves the picture",
              !near(place(probe, f0, tile: t), place(probe, reshaped, tile: reshaped.tile!)))

        print(failures == 0 ? "PASS" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
