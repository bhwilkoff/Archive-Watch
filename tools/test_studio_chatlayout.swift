// §8.42 — a chat message with no spaces in it WRAPS rather than being clipped.
//
// Found on air 2026-09-22, reading a real Twitch channel into the programme:
// a message reading "...butthenameislessgenericsoyoudontac" ran off the end of
// its own pill and stopped mid-glyph at the column edge. `wrap` split on
// SPACES only, so a single long token was emitted whole; the pill hugs the
// text it was told about and the renderer clips to the column, so the tail of
// the word sat on the FILM with no ground behind it — which is the one thing
// the pill exists to prevent.
//
// Chat is the only text in this app written by strangers, so an unbreakable
// token is not a rare case there; it is most of Twitch.
//
// THE ASSERTION IS HEIGHT, not width, and that is the point: the first
// version of this test measured the rightmost pixel and PASSED with the defect
// reinstated, because the renderer was already clipping to the column. What
// distinguishes the two is whether the word WRAPPED — one clipped line, or
// several that fit.
import CoreImage
import CoreGraphics
import Foundation

@main struct T {
    static let size = CGSize(width: 1280, height: 720)

    static func blockHeight(_ text: String, _ author: String) -> CGFloat {
        let r = StudioOverlayRenderer(size: size)
        var o = StudioOverlay()
        o.showChat = true
        o.chat = [.init(id: "x", author: author, text: text, isEvent: false)]
        guard let rect = StudioLayout.corner.chatRect(in: size, cameraAspect: 16.0/9.0),
              let img = r.chatImage(for: o, in: rect) else { return 0 }
        return img.extent.height
    }

    static func main() {
        guard let rect = StudioLayout.corner.chatRect(in: size, cameraAspect: 16.0/9.0) else {
            print("FAIL: this layout has no chat rect"); exit(1)
        }
        print("  chat column: x=\(Int(rect.minX)) w=\(Int(rect.width))")

        let short = blockHeight("LOL", "ora331")
        // The real message, verbatim from the channel.
        let long  = blockHeight("yeahbutthenameislessgenericsoyoudontactuallyhavetoworryaboutit",
                                "crazyspecz")
        // A long run of ordinary words, which ALWAYS wrapped — the control
        // that says the height measurement means what it claims.
        let words = blockHeight("well that is a lot of separate little words to fit in here",
                                "kongbtw")
        print("  one short line:      \(Int(short)) px")
        print("  one unbreakable word: \(Int(long)) px")
        print("  many short words:    \(Int(words)) px  (control — always wrapped)")

        guard short > 0, words > short else {
            print("FAIL: control — spaced text did not wrap, so this test measures nothing")
            exit(1)
        }
        print("  ok   control — spaced text wraps to more than one line")

        guard long > short else {
            print("FAIL: a message with no spaces in it did NOT wrap — it is one clipped")
            print("      line, so its tail is drawn past its own pill onto the film.")
            exit(1)
        }
        print("  ok   an unbreakable word wraps instead of being clipped")

        // §D22 — THE SIDE, read off the geometry the compositor asks for
        // rather than off the picker. Decision 133: a control is proved where
        // its value lands.
        let left  = StudioLayout.corner.chatRect(in: size, cameraAspect: 16.0/9.0, side: .left)
        let right = StudioLayout.corner.chatRect(in: size, cameraAspect: 16.0/9.0, side: .right)
        guard let l = left, let r = right else { print("FAIL: no chat rect"); exit(1) }
        print("  left  column x=\(Int(l.minX))..\(Int(l.maxX))")
        print("  right column x=\(Int(r.minX))..\(Int(r.maxX))")
        // THE RULE, corrected 2026-09-22 after this assertion failed for the
        // right reason. The sides are NOT simply mirrored: every preset that
        // shows a camera puts it on the right, so the right column has to
        // yield vertically or it lands on the host's face. What must hold is
        // that the WIDTH and the EDGE INSET are shared — those are the parts
        // a second derivation would drift on — and that the right column is
        // never TALLER than the left, since it can only ever give way.
        guard l.width == r.width else {
            print("FAIL: the two sides have different widths (\(Int(l.width)) vs \(Int(r.width)))")
            exit(1)
        }
        guard r.height <= l.height + 0.5 else {
            print("FAIL: the right column is TALLER than the left (\(Int(r.height)) vs")
            print("      \(Int(l.height))) — it should only ever yield, never grow.")
            exit(1)
        }
        guard r.maxY <= l.maxY + 0.5 else {
            print("FAIL: the right column's top is above the left's — it is not the same")
            print("      column shifted, so the two geometries have diverged.")
            exit(1)
        }
        guard r.minX > l.minX else {
            print("FAIL: \"right\" is not to the right of \"left\" — the side does not land.")
            exit(1)
        }
        // MIRRORED, exactly: the inset from each edge must match, or the
        // column sits closer to one edge than the other and it shows.
        guard abs((size.width - r.maxX) - l.minX) < 0.5 else {
            print("FAIL: the right column's inset (\(Int(size.width - r.maxX))) does not match")
            print("      the left column's (\(Int(l.minX))).")
            exit(1)
        }
        print("  ok   the side lands on the compositor's own rect, mirrored exactly")

        // AND THE ONE THE MIRROR CAN GET WRONG. In `.side` the camera owns the
        // RIGHT third of the frame, and `chatRectLeft` is built to dodge it.
        // Mirroring that rect puts the column straight onto the host's face —
        // which is the exact defect §D22 cites from 2026-09-17, arriving by a
        // new route. A mirror is only safe where the frame is symmetric.
        let camAspect: CGFloat = 16.0/9.0
        for layout in StudioLayout.allCases {
            guard let cl = layout.chatRect(in: size, cameraAspect: camAspect, side: .left),
                  let cr = layout.chatRect(in: size, cameraAspect: camAspect, side: .right)
            else { continue }
            guard let cam = layout.rects(in: size, cameraAspect: camAspect).camera,
                  layout.showsCamera else { continue }
            for (name, rect) in [("left", cl), ("right", cr)] {
                if rect.intersects(cam.insetBy(dx: 4, dy: 4)) {
                    print("FAIL: in \(layout.rawValue), chat on the \(name) overlaps the camera")
                    print("      chat \(rect)  camera \(cam)")
                    exit(1)
                }
            }
        }
        print("  ok   no layout puts either side of the column on the camera")
        print("PASS")
    }
}
