// §8.48 — a shout-out sits ABOVE the film's identity, keeps the viewer's own
// spelling, and cannot grow past four lines.
//
// §D26 lets somebody in the audience reach the screen. Three things about that
// are load-bearing, and each is asserted here against the RENDER rather than
// the source:
//
//  1. It never displaces the lower third. The film's own identity is the one
//     graphic a stranger's words may not push off the frame, so the banner's
//     bottom must sit at or above the lower third's top.
//  2. The name is drawn in the case its owner typed. Every other uppercase run
//     in this renderer is a label we wrote; a handle is not ours to restyle.
//     THE CONTROL IS THE POINT — "crazyspecz" and "CRAZYSPECZ" must render to
//     DIFFERENT widths. An `.uppercased()` in the renderer makes them
//     identical, so this is the one assertion that cannot pass with the defect
//     reinstated.
//  3. `ShoutOut.maxCharacters` is the picker's refusal rule and is a
//     hand-derived guess at the renderer's geometry. A guess that nothing
//     checks drifts, so a string of exactly that length is wrapped here with
//     the renderer's own metrics and counted.
import CoreImage
import CoreGraphics
import Foundation

@main struct T {
    static let size = CGSize(width: 1280, height: 720)
    static var failures: [String] = []

    static func check(_ ok: Bool, _ what: String, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(what) — \(detail)")
        if !ok { failures.append(what) }
    }

    /// ONE renderer for every call, deliberately. The first version of this
    /// test built a fresh `StudioOverlayRenderer` each time, which defeats the
    /// image cache entirely — and the cache was where the real defect lived:
    /// its key carried the lower third alone, so a banner could never appear
    /// and, having appeared, could never expire. A harness that constructs its
    /// subject fresh cannot see a staleness bug.
    static let renderer = StudioOverlayRenderer(size: size)
    static func extent(_ o: StudioOverlay) -> CGRect {
        renderer.image(for: o)?.extent ?? .zero
    }

    static func base() -> StudioOverlay {
        var o = StudioOverlay()
        o.title = "Safety Last!"
        o.subtitle = "1923 · Fred C. Newmeyer"
        o.provenance = "Public domain — published 1923, before 1930"
        return o
    }

    static func main() {
        // ---- 1. above the lower third, never instead of it ----------------
        let plain = extent(base())
        var withShout = base()
        withShout.shoutOut = .init(author: "crazyspecz",
                                   text: "my grandmother saw this in a theater in 1924")
        let both = extent(withShout)
        print("  lower third alone: \(Int(plain.minY))..\(Int(plain.maxY))")
        print("  with shout-out:    \(Int(both.minY))..\(Int(both.maxY))")
        check(both.maxY > plain.maxY,
              "the banner is above the lower third",
              "grew upward by \(Int(both.maxY - plain.maxY))pt")
        check(abs(both.minY - plain.minY) < 1,
              "the lower third did not move",
              "minY \(Int(plain.minY)) -> \(Int(both.minY))")

        // A host who has turned every lower-third line off still gets a banner.
        var bare = StudioOverlay()
        bare.shoutOut = withShout.shoutOut
        let bareRect = extent(bare)
        check(bareRect.height > 1 && bareRect.minY < size.height * 0.5,
              "it stands alone with no lower third",
              "rect \(Int(bareRect.width))x\(Int(bareRect.height)) at y=\(Int(bareRect.minY))")

        // ---- 2. the viewer's own spelling (the negative control) ----------
        var lower = base(); lower.shoutOut = .init(author: "crazyspecz", text: "hi")
        var upper = base(); upper.shoutOut = .init(author: "CRAZYSPECZ", text: "hi")
        // Measured with NO lower third, or the scrim's width swamps the
        // banner's and both spellings read identically — which is how the
        // first run of this test "failed" over a product that was already
        // correct.
        lower.showLowerThird = false; upper.showLowerThird = false
        let lw = extent(lower).width, uw = extent(upper).width
        check(abs(lw - uw) > 1,
              "the name keeps the case its owner typed",
              "crazyspecz \(Int(lw))pt vs CRAZYSPECZ \(Int(uw))pt")

        // ---- 3. the refusal rule agrees with the renderer -----------------
        let word = "archive "                      // 8 chars, wraps cleanly
        let atLimit = String(repeating: word,
                             count: StudioOverlay.ShoutOut.maxCharacters / word.count)
        var at = base(); at.shoutOut = .init(author: "ora331", text: atLimit)
        let atH = extent(at).height - plain.height
        var over = base()
        over.shoutOut = .init(author: "ora331", text: atLimit + atLimit + atLimit)
        let overH = extent(over).height - plain.height
        print("  \(atLimit.count) chars -> \(Int(atH))pt · \(atLimit.count * 3) chars -> \(Int(overH))pt")
        check(atH > 0 && abs(atH - overH) < 2,
              "maxCharacters is at or under the four-line ceiling",
              "a message 3x as long draws the same height")
        check(StudioOverlay.ShoutOut.tooLong(atLimit + "x")
              && !StudioOverlay.ShoutOut.tooLong(atLimit),
              "the picker refuses past the ceiling and not before",
              "\(StudioOverlay.ShoutOut.maxCharacters) characters")

        // ---- 4. it goes away on its own ------------------------------------
        let fresh = StudioOverlay.ShoutOut(author: "a", text: "b")
        let stale = StudioOverlay.ShoutOut(
            author: "a", text: "b",
            shownAt: Date().addingTimeInterval(-StudioOverlay.ShoutOut.seconds - 1))
        check(Date().timeIntervalSince(fresh.shownAt) < StudioOverlay.ShoutOut.seconds
              && Date().timeIntervalSince(stale.shownAt) > StudioOverlay.ShoutOut.seconds,
              "the clock is readable from the value",
              "\(Int(StudioOverlay.ShoutOut.seconds))s")

        // ---- 5. the cache cannot hold a banner on screen ------------------
        // THE ORIGINAL DEFECT. `key(for:)` named the lower third and nothing
        // else, so the same renderer handed back the same strip whether a
        // shout-out was up or not.
        var run = base()
        let alone = extent(run).height
        run.shoutOut = .init(author: "ora331", text: "chaplin walked so keaton could run")
        let up = extent(run).height
        run.shoutOut = nil
        let down = extent(run).height
        print("  same renderer: none \(Int(alone))pt -> up \(Int(up))pt -> expired \(Int(down))pt")
        check(up > alone && abs(down - alone) < 1,
              "the same renderer shows it and takes it away",
              "the cache key carries the shout-out")

        // ---- 6. chat gets out of the way ---------------------------------
        // THE COLLISION IS REAL AND MUST BE ASSERTED FIRST, or the yield rule
        // is being tested against a case that never happens. Seen on the
        // glass: the banner drew straight through `kt_projects`.
        guard let chat = StudioLayout.corner.chatRect(in: size, cameraAspect: 16.0/9.0,
                                                      side: .left, guestAspect: nil) else {
            print("FAIL: this layout has no chat rect"); exit(1)
        }
        let top = both.maxY
        check(top > chat.minY,
              "a left-hand column and the banner really do collide",
              "chat from y=\(Int(chat.minY)), banner to y=\(Int(top))")

        let yielded = StudioLayout.chatYielding(chat, toOverlayTop: top,
                                                side: .left, in: size)
        check(!yielded.isEmpty && yielded.minY > top && abs(yielded.maxY - chat.maxY) < 1,
              "the column shortens from the BOTTOM",
              "y \(Int(chat.minY))..\(Int(chat.maxY)) -> \(Int(yielded.minY))..\(Int(yielded.maxY))")

        // NEGATIVE CONTROLS, both directions.
        let right = StudioLayout.chatYielding(chat, toOverlayTop: top,
                                              side: .right, in: size)
        check(right == chat, "a right-hand column is untouched", "same rect")
        let none = StudioLayout.chatYielding(chat, toOverlayTop: nil,
                                             side: .left, in: size)
        check(none == chat, "no banner, no yield", "same rect")
        // A banner so tall nothing readable is left takes the column away
        // rather than leaving a one-line stub.
        let swamped = StudioLayout.chatYielding(chat, toOverlayTop: chat.maxY - 4,
                                                side: .left, in: size)
        check(swamped.isEmpty,
              "a column with no room left is dropped, not stubbed",
              "height would have been 4pt")

        // ---- 7. the shortened column is actually DRAWN shorter -------------
        // The yield rule was right and the glass still showed the banner over
        // `kt_projects`, because `chatImage`'s cache key named the column's x
        // and WIDTH and not its height. One renderer, two rects, same lines:
        // if the key is incomplete the second call hands back the first image.
        var talk = base()
        talk.showChat = true
        talk.chat = (1...7).map {
            .init(id: "c\($0)", author: "person\($0)",
                  text: "line \($0) of a conversation worth reading", isEvent: false)
        }
        let full = renderer.chatImage(for: talk, in: chat)?.extent ?? .zero
        let short = renderer.chatImage(for: talk, in: yielded)?.extent ?? .zero
        print("  chat drawn: full y=\(Int(full.minY)) · shortened y=\(Int(short.minY))"
              + " · banner top y=\(Int(top))")
        // THE REQUIREMENT IS CLEARANCE, not a smaller block. Chat is
        // bottom-anchored in its rect, so shortening the rect moves the
        // conversation UP rather than cropping it — which is the better
        // outcome and is what the first version of this assertion got wrong,
        // demanding `maxY` not grow and failing over a correct product.
        check(full.height > 0 && short.height > 0 && short.minY >= top,
              "the drawn column clears the banner",
              "bottom moved up by \(Int(short.minY - full.minY))pt")

        if failures.isEmpty { print("PASS §8.48"); exit(0) }
        print("FAIL §8.48: \(failures.joined(separator: "; "))"); exit(1)
    }
}
