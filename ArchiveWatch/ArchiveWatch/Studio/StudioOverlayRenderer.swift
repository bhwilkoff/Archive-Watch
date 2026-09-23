// Watch Together Studio — the overlay the audience reads
// (docs/WATCH-TOGETHER.md §2.1, §4).
//
// This is the part of the Studio that no other streaming tool can have. The
// film is ours, from a catalog whose every field was audited this month
// (Decisions 124/125), so the show can carry a lower third that is actually
// TRUE: the title, the year, the director, and when the film entered the
// public domain. An OBS user captioning a window types that by hand and gets
// it wrong; we read it from the same record the app draws.
//
// WHAT IT DRAWS
//   · a lower third — title, "1926 · Buster Keaton", "Public domain since 1954"
//   · full-frame cards — starting soon (with a countdown), intermission, ending
//
// WHY IT IS CACHED. Text layout is expensive and the program renders 30 frames
// a second, so rasterising the lower third per frame would spend the whole
// budget on type that did not change. The overlay is drawn into a bitmap only
// when its CONTENT changes (a new film, a new countdown second, a card), and
// every other frame composites the cached image — which is a GPU blend.
//
// AND THE BLEND IS CROPPED TO ITS CONTENT. Caching alone was not enough:
// compositing a full-frame 1920x1080 RGBA layer every frame took the Mac's
// render mean from 3.40 ms to 9.02 ms (measured 2026-09-17) even though the
// layer never changed and is ~90% transparent. A lower third occupies a strip;
// it is cropped to that strip so Core Image blends a strip.
//
// SAFE AREA. 5% a side, the broadcast title-safe convention and the same
// proportion as tvOS-DESIGN §6.1's 90×60 and ROKU-DESIGN's 96×54 action-safe.
// A viewer watching the stream on a television must not lose the title.

import CoreGraphics
import CoreImage
import CoreText
import Foundation

final class StudioOverlayRenderer: @unchecked Sendable {

    private let size: CGSize
    private let scale: CGFloat          // 1920-wide reference → actual
    private var cached: CIImage?
    private var cachedKey: String = ""
    /// The region the last rasterisation actually drew into, so the composite
    /// blends only that.
    private var contentRect: CGRect = .zero
    /// Chat is cached separately: it changes every few seconds while the lower
    /// third does not, and one key for both would re-lay the film's title on
    /// every message.
    private var cachedChat: CIImage?
    private var cachedChatKey: String = ""

    private let lock = NSLock()

    /// Brand colours (CLAUDE.md shared design system). The program is
    /// dark-first: the film is behind it.
    private static let marqueeOrange = CGColor(red: 1.0, green: 0.361, blue: 0.208, alpha: 1)
    private static let paper = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let ink = CGColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)

    init(size: CGSize) {
        self.size = size
        self.scale = size.width / 1920.0
    }

    /// The composited overlay for this state, or nil when there is nothing to
    /// draw. Cached on content.
    func image(for overlay: StudioOverlay) -> CIImage? {
        let key = Self.key(for: overlay)
        lock.lock()
        if key == cachedKey, let cached { lock.unlock(); return cached }
        lock.unlock()

        guard !key.isEmpty else {
            lock.lock(); cachedKey = key; cached = nil; lock.unlock()
            return nil
        }
        let image = rasterise(overlay)
        lock.lock(); cachedKey = key; cached = image; lock.unlock()
        return image
    }

    /// Everything that changes the pixels, and nothing that does not — so a
    /// steady lower third is rasterised once for the whole show.
    private static func key(for o: StudioOverlay) -> String {
        if let card = o.card {
            switch card {
            case .startingSoon(let s): return "card:soon:\(s)|\(o.title)"
            case .intermission: return "card:intermission|\(o.title)"
            case .ending: return "card:ending"
            // Every line and every rank, because both change the pixels. A key
            // that named only the text would keep a cached raster when the
            // host re-ranked a line, which is precisely the kind of "the
            // control moved and the program did not" that Decision 133 is
            // about — one cache miss away from the same class of bug.
            case .custom(let lines):
                return "card:custom|" + lines.map { "\($0.rank.rawValue):\($0.text)" }
                    .joined(separator: "\u{1F}")
            }
        }
        // ANY line, not the title alone (§D15). The host chooses which of the
        // three the lower third carries, so gating on the title meant turning
        // it off silently took the year, the director and the provenance with
        // it — two controls doing one control's job, which is how a host
        // concludes a toggle is broken.
        // §D26 — the shout-out is PART OF THE KEY, and it is the half that
        // moves. Without it the cache served the lower third alone, so a
        // banner never appeared; and once one had appeared under some other
        // key change, it could never expire, because nothing about the frame
        // had changed by the time it was due to come down.
        let shout = o.shoutOut.map { "|s:\($0.author)\u{1F}\($0.text)" } ?? ""
        let l3 = o.showLowerThird
            && !(o.title.isEmpty && o.subtitle.isEmpty && o.provenance.isEmpty)
        // A shout-out stands on its own: a host may run with every lower-third
        // line off and still put somebody on screen.
        guard l3 || !shout.isEmpty else { return "" }
        return l3 ? "l3:\(o.title)|\(o.subtitle)|\(o.provenance)" + shout
                  : "l3:" + shout
    }

    // MARK: Chat

    /// The chat column, newest at the BOTTOM — the direction every chat client
    /// scrolls, so a viewer's eye already knows where the new line appears.
    /// Each line carries its OWN pill rather than sitting on a column-wide
    /// panel: a panel is furniture the audience has to look past, and a pill
    /// only darkens the film where there are words.
    func chatImage(for overlay: StudioOverlay, in rect: CGRect) -> CIImage? {
        // THE WHOLE RECT, not just its x and width. The column's BOTTOM moves
        // now — a shout-out shortens it (§D26) — and a key that named only the
        // horizontal geometry handed back the image drawn at the old height,
        // so the banner went on covering the last two lines however the rect
        // was recomputed. Same defect as the lower third's own key, found the
        // same morning: a cache key that names some of its inputs is a cache
        // that is wrong about the rest.
        let key = "chat:\(Int(rect.minX)),\(Int(rect.minY)),"
            + "\(Int(rect.width)),\(Int(rect.height))|"
            + overlay.chat.map { "\($0.id):\($0.isEvent ? 1 : 0)" }.joined(separator: ",")
        lock.lock()
        if key == cachedChatKey, let cachedChat { lock.unlock(); return cachedChat }
        lock.unlock()
        let img = rasteriseChat(overlay.chat, in: rect)
        lock.lock(); cachedChatKey = key; cachedChat = img; lock.unlock()
        return img
    }

    private func rasteriseChat(_ lines: [StudioOverlay.ChatLine], in rect: CGRect) -> CIImage? {
        guard let ctx = context() else { return nil }
        ctx.clear(CGRect(origin: .zero, size: size))

        let authorFont = font(21, weight: 0.4)
        let textFont = font(21, weight: 0.0)
        let pad = 12 * scale
        let gap = 7 * scale
        let maxTextWidth = rect.width - pad * 2

        // Lay out from the BOTTOM up and stop when the column is full: the
        // newest message is the one that must always be visible, so the oldest
        // is what falls off — not the newest, which is what a top-down layout
        // with a height clamp would silently do.
        var y = rect.minY
        var drawn = 0
        for line in lines.reversed() {
            let author = self.line(line.author + "  ", font: authorFont,
                                   color: line.isEvent ? Self.marqueeOrange
                                                       : CGColor(red: 0.45, green: 0.62, blue: 1, alpha: 1))
            let wrapped = wrap(line.text, font: textFont, maxWidth: maxTextWidth - width(author),
                               firstIndent: width(author))
            let lineH = 26 * scale
            let blockH = CGFloat(wrapped.count) * lineH + pad * 1.4
            if y + blockH > rect.maxY { break }

            let widest = max(width(author) + (wrapped.first.map { width($0) } ?? 0),
                             wrapped.dropFirst().map { width($0) }.max() ?? 0)
            let pill = CGRect(x: rect.minX, y: y,
                              width: min(rect.width, widest + pad * 2), height: blockH)
            // NEAR-FULL opacity where type sits, which is the lesson the lower
            // third's scrim already learned a day earlier: "white type over an
            // arbitrary film frame is only legible if something guarantees the
            // ground". At 0.68 over a silent film's INTERTITLE — large bright
            // white text, which is exactly where a chat column lands on this
            // catalogue — the effective ground is about 0.32 white and 21 pt
            // white type on it is mud. Seen in a frame pulled from the
            // server's own recording (§6.4a).
            //
            // The pill still HUGS its text rather than blacking out a column:
            // the film showing through around the messages is the design, and
            // only the ground under type needed fixing.
            ctx.setFillColor(CGColor(gray: 0, alpha: line.isEvent ? 0.92 : 0.88))
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 8 * scale,
                               cornerHeight: 8 * scale, transform: nil))
            ctx.fillPath()

            // Bottom-up inside the pill too, so the wrapped lines read in order.
            var ty = y + pad * 0.7
            for (i, seg) in wrapped.enumerated().reversed() {
                let x = rect.minX + pad + (i == 0 ? width(author) : 0)
                draw(seg, at: CGPoint(x: x, y: ty), in: ctx)
                if i == 0 { draw(author, at: CGPoint(x: rect.minX + pad, y: ty), in: ctx) }
                ty += lineH
            }
            y += blockH + gap
            drawn += 1
        }
        guard drawn > 0, let cg = ctx.makeImage() else { return nil }
        let used = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y - rect.minY)
        return CIImage(cgImage: cg).cropped(to: used.integral)
    }

    /// Word wrap by measurement, because a character count is not a width —
    /// and this catalog's audience writes in more than one script.
    private func wrap(_ text: String, font: CTFont, maxWidth: CGFloat,
                      firstIndent: CGFloat) -> [CTLine] {
        var out: [CTLine] = []
        var current = ""
        var budget = max(20 * scale, maxWidth)
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if width(self.line(candidate, font: font, color: Self.paper)) <= budget {
                current = candidate
            } else {
                if !current.isEmpty { out.append(self.line(current, font: font, color: Self.paper)) }
                // Only the FIRST line is indented by the author's name.
                budget = max(20 * scale, maxWidth + firstIndent)
                // A WORD WITH NO SPACES IN IT STILL HAS TO FIT.
                //
                // Splitting on spaces alone means a single long token is
                // emitted whole, at whatever width it happens to be — and the
                // pill behind it is clamped to the column, so the text runs
                // out past its own background and off the frame. Seen on air
                // 2026-09-22 with a real Twitch message
                // ("...butthenameislessgenericsoyoudontac") over a film, which
                // is the audience's view, not ours. Chat is the one text in
                // this app written by strangers, so it is the one place an
                // unbreakable token is not a rare case.
                var rest = Substring(word)
                while !rest.isEmpty,
                      width(self.line(String(rest), font: font, color: Self.paper)) > budget {
                    // Longest prefix that fits. Linear from the end rather
                    // than a binary search: these are chat lines, the strings
                    // are short, and the widths are not monotone enough in
                    // practice to trust a bisection on a proportional font.
                    var cut = rest.index(before: rest.endIndex)
                    while cut > rest.startIndex,
                          width(self.line(String(rest[..<cut]), font: font,
                                          color: Self.paper)) > budget {
                        cut = rest.index(before: cut)
                    }
                    guard cut > rest.startIndex else { break }   // one glyph wider than the column
                    out.append(self.line(String(rest[..<cut]), font: font, color: Self.paper))
                    rest = rest[cut...]
                    if out.count >= 5 { break }
                }
                current = String(rest)
            }
            if out.count >= 5 { break }      // one message never owns the column
        }
        if !current.isEmpty, out.count < 5 {
            out.append(self.line(current, font: font, color: Self.paper))
        }
        return out.isEmpty ? [self.line(text, font: font, color: Self.paper)] : out
    }

    // MARK: Rasterising

    private func context() -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func rasterise(_ o: StudioOverlay) -> CIImage? {
        guard let ctx = context() else { return nil }
        ctx.clear(CGRect(origin: .zero, size: size))
        if let card = o.card {
            draw(card: card, film: o.title, in: ctx)
            contentRect = CGRect(origin: .zero, size: size)   // a card owns the frame
        } else {
            contentRect = o.showLowerThird ? drawLowerThird(o, in: ctx) : .null
            // §D26 — ABOVE the lower third, never instead of it. The film's
            // own identity is the one thing that must never be displaced by
            // something a stranger typed.
            if let s = o.shoutOut {
                let r = drawShoutOut(s, above: contentRect, in: ctx)
                contentRect = contentRect.union(r)
            }
        }
        guard let cg = ctx.makeImage() else { return nil }
        // Crop to what was drawn: the rest is transparent and blending it is
        // pure cost. `.cropped(to:)` bounds the CIImage's extent, so Core
        // Image does the work over a strip rather than the whole frame.
        return CIImage(cgImage: cg).cropped(to: contentRect.integral)
    }

    /// Six typographic levels, no seventh (CLAUDE.md). Sizes are given at the
    /// 1920 reference width and scaled.
    private func font(_ points: CGFloat, weight: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, points * scale, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, points * scale, nil)
        let traits: [CFString: Any] = [kCTFontWeightTrait: weight]
        let attrs: [CFString: Any] = [kCTFontTraitsAttribute: traits]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, points * scale, nil, desc)
    }

    private func line(_ text: String, font: CTFont, color: CGColor, tracking: CGFloat = 0) -> CTLine {
        var attrs: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
        ]
        if tracking != 0 { attrs[.init(kCTKernAttributeName as String)] = tracking * scale }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attrs))
    }

    private func draw(_ line: CTLine, at point: CGPoint, in ctx: CGContext) {
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private func width(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    // MARK: Lower third

    /// Returns the rect it drew into.
    @discardableResult
    /// §D26 — somebody in the audience, on the broadcast, with their name on it.
    ///
    /// Styled as the lower third's louder sibling rather than as a card: same
    /// marquee rule, same paper type, same 5% title-safe inset, so it reads as
    /// this program acknowledging someone and not as a plugin's notification.
    /// The NAME carries the marquee orange because the name is the point —
    /// the words could have come from anywhere; the attribution is what makes
    /// it an acknowledgment.
    private func drawShoutOut(_ s: StudioOverlay.ShoutOut,
                              above lowerThird: CGRect,
                              in ctx: CGContext) -> CGRect {
        let inset = size.width * 0.05
        let nameFont = font(24, weight: 0.4)
        let textFont = font(38, weight: 0.0)
        let maxWidth = size.width * 0.62          // never the full width: this
                                                  // sits over a film, not on a slide
        // NOT `.uppercased()`. Every other uppercase run in this renderer is a
        // label WE wrote — "PUBLIC DOMAIN — …" is ours to style. A viewer's
        // handle is their own spelling, and restyling it is the small version
        // of getting somebody's name wrong on the one graphic that exists to
        // name them.
        let name = line(s.author, font: nameFont,
                        color: Self.marqueeOrange, tracking: 0.4)
        var body = wrap(s.text, font: textFont, maxWidth: maxWidth, firstIndent: 0)
        guard !body.isEmpty else { return .zero }
        // A 500-character Twitch message wraps to seven lines and covers the
        // film. The picker refuses one this long with a reason
        // (`ShoutOut.tooLong`); this is the backstop for a message that
        // arrives some other way.
        if body.count > StudioOverlay.ShoutOut.maxLines {
            body = Array(body.prefix(StudioOverlay.ShoutOut.maxLines))
        }

        let lineH = 46 * scale
        let pad = 22 * scale
        let gap = 10 * scale
        let nameH = 30 * scale
        let blockH = CGFloat(body.count) * lineH + nameH + pad * 2
        // Sit ABOVE whatever the lower third occupies, with a gap. When the
        // host has turned every lower-third line off, `lowerThird` is empty
        // and this simply takes its place near the bottom.
        let baseY = (lowerThird.isEmpty ? size.height * 0.10 : lowerThird.maxY) + gap
        let widest = max(width(name),
                         body.map { width($0) }.max() ?? 0)
        let rect = CGRect(x: inset, y: baseY,
                          width: min(maxWidth + pad * 2, widest + pad * 2),
                          height: blockH)

        // The same near-opaque ground the chat pills use, for the same reason:
        // white type over an arbitrary film frame is only legible if something
        // guarantees the ground (§9.chat).
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 0.92))
        ctx.fill(rect)
        // A marquee rule down the left edge, exactly as the lower third has,
        // so the two read as one family rather than two overlays.
        ctx.setFillColor(Self.marqueeOrange)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 4 * scale, height: rect.height))

        var y = rect.maxY - pad - 26 * scale
        ctx.textPosition = CGPoint(x: rect.minX + pad, y: y)
        CTLineDraw(name, ctx)
        y -= 14 * scale
        for l in body {
            y -= lineH
            ctx.textPosition = CGPoint(x: rect.minX + pad, y: y)
            CTLineDraw(l, ctx)
        }
        return rect
    }

    private func drawLowerThird(_ o: StudioOverlay, in ctx: CGContext) -> CGRect {
        let inset = size.width * 0.05                   // 5% title-safe
        let titleFont = font(52, weight: 0.4)           // display, semibold
        let subFont = font(30, weight: 0.0)
        let provFont = font(22, weight: 0.3)

        // EVERY line is optional now (§D15) — the title included. It used to be
        // drawn unconditionally and its height counted into the stack, so a
        // host who turned it off got an empty slot and a taller scrim over
        // nothing.
        let title = o.title.isEmpty ? nil
            : line(o.title, font: titleFont, color: Self.paper)
        let sub = o.subtitle.isEmpty ? nil
            : line(o.subtitle, font: subFont, color: CGColor(gray: 0.85, alpha: 1))
        let prov = o.provenance.isEmpty ? nil
            : line(o.provenance.uppercased(), font: provFont, color: Self.marqueeOrange, tracking: 1.2)

        // Geometry: a left-aligned stack sitting on the 5% line, with a rule
        // in marquee orange as the only decoration. Density comes from
        // removing chrome, not adding it (CLAUDE.md) — so there is no box,
        // just a soft scrim that keeps white type legible over any film.
        let titleH = 52 * scale
        let subH = 30 * scale
        let provH = 22 * scale
        let gap = 12 * scale
        var stackH: CGFloat = 0
        var lines = 0
        if title != nil { stackH += titleH; lines += 1 }
        if sub != nil { stackH += subH; lines += 1 }
        if prov != nil { stackH += provH; lines += 1 }
        stackH += gap * CGFloat(max(0, lines - 1))
        // `.null`, never `.zero`: this rect gets `union`ed with the
        // shout-out's, and `CGRect.zero` is a real rect AT THE ORIGIN, so an
        // absent lower third would have stretched the composited strip from
        // the banner all the way down to y=0.
        guard lines > 0 else { return .null }

        let baseY = inset                                   // bottom of the stack
        // The scrim must cover the stack AND the run-up above it, or the top
        // of the title sits on bare film. Measured against a 240-grey band: a
        // 0.72→0 ramp over stackH + 1.2×inset left the provenance line at an
        // effective 0.39 alpha and unreadable. It now holds near-full opacity
        // across the text and fades only above it.
        //
        // It also fades to the RIGHT, and that is not cosmetic: a full-width
        // band darkened the bottom of the camera tile in the `corner` layout
        // (seen on the glass, 2026-09-17). The scrim exists to make TYPE
        // legible, so it ends where the type does.
        let scrimH = stackH + inset * 1.9
        let textRight = [title, sub, prov].compactMap { $0 }.map { width($0) }.max() ?? 0
        let scrimW = min(size.width, inset + 24 * scale + textRight + inset * 2.4)
        drawScrim(height: scrimH, solidTo: baseY + stackH, width: scrimW, in: ctx)

        let ruleW = 4 * scale
        let ruleX = inset
        ctx.setFillColor(Self.marqueeOrange)
        ctx.fill(CGRect(x: ruleX, y: baseY, width: ruleW, height: stackH))

        let textX = ruleX + ruleW + 20 * scale
        var y = baseY
        if let prov {
            draw(prov, at: CGPoint(x: textX, y: y), in: ctx)
            y += provH + gap
        }
        if let sub {
            draw(sub, at: CGPoint(x: textX, y: y), in: ctx)
            y += subH + gap
        }
        if let title { draw(title, at: CGPoint(x: textX, y: y), in: ctx) }
        return CGRect(x: 0, y: 0, width: scrimW, height: scrimH)
    }

    /// A bottom-up gradient scrim. White type over an arbitrary film frame is
    /// only legible if something guarantees the ground — and a scrim does it
    /// without drawing a panel the viewer has to look at.
    private func drawScrim(height: CGFloat, solidTo: CGFloat, width scrimW: CGFloat, in ctx: CGContext) {
        // Three stops, not two: hold the ground under the text, then fade.
        // A single 0→1 ramp spends most of its opacity where there is no type.
        let hold = min(0.98, max(0.1, solidTo / height))
        let colors = [
            CGColor(gray: 0, alpha: 0.94),
            CGColor(gray: 0, alpha: 0.90),
            CGColor(gray: 0, alpha: 0),
        ] as CFArray
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors,
                                        locations: [0, hold, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: scrimW, height: height))
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        // Erase the right-hand tail with `.destinationOut`, which gives the
        // scrim a true two-dimensional falloff in one pass rather than a
        // second, differently-blended layer.
        let fadeFrom = scrimW * 0.55
        let erase = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)] as CFArray
        if let tail = CGGradient(colorsSpace: space, colors: erase, locations: [0, 1]) {
            ctx.setBlendMode(.destinationOut)
            ctx.drawLinearGradient(tail, start: CGPoint(x: fadeFrom, y: 0),
                                   end: CGPoint(x: scrimW, y: 0), options: [])
            ctx.setBlendMode(.normal)
        }
        ctx.restoreGState()
    }

    // MARK: Cards

    private func draw(card: StudioOverlay.Card, film: String, in ctx: CGContext) {
        // A card REPLACES the program, so it owns the frame and paints its
        // own ground — the film behind it must not read through.
        ctx.setFillColor(Self.ink)
        ctx.fill(CGRect(origin: .zero, size: size))

        // THE HOST'S OWN WORDS (§D10) take a different block, because a fixed
        // card has a known shape — wordmark, rule, headline, detail — and a
        // custom one has however many lines the host wrote. It shares the
        // ground, the wordmark and the rule, so the two read as the same
        // object; only the middle is theirs.
        if case .custom(let lines) = card {
            drawCustom(lines: lines, in: ctx)
            return
        }

        let headline: String
        let detail: String
        switch card {
        case .custom:
            // Handled above; the compiler cannot know that, and a `default`
            // here would silently absorb the NEXT card anyone adds.
            return
        case .startingSoon(let seconds):
            headline = "Starting soon"
            detail = seconds > 0 ? Self.clock(seconds) : "any moment now"
        case .intermission:
            headline = "Intermission"
            detail = "back shortly"
        case .ending:
            headline = "Thanks for watching"
            detail = "archivewatch.org"
        }

        let mark = line("ARCHIVE WATCH", font: font(26, weight: 0.4),
                        color: Self.marqueeOrange, tracking: 4)
        let head = line(headline, font: font(96, weight: 0.4), color: Self.paper)
        let det = line(detail, font: font(40, weight: 0.0), color: CGColor(gray: 0.72, alpha: 1))
        // NAME THE FILM. A viewer who arrives at a countdown should learn what
        // they are about to watch — that is §2.1's whole argument, and it is
        // the one thing a generic "starting soon" card cannot say.
        let showsFilm = !film.isEmpty && {
            if case .ending = card { return false } else { return true }
        }()
        let filmLine = showsFilm
            ? line(film, font: font(44, weight: 0.3), color: CGColor(gray: 0.95, alpha: 1))
            : nil

        // Lay the block out from its real height so it is OPTICALLY centred,
        // rather than hanging off hardcoded offsets from the midpoint.
        let markH = 26 * scale, headH = 96 * scale, detH = 40 * scale, filmH = 44 * scale
        let ruleGap = 22 * scale, gap = 34 * scale
        var blockH = markH + ruleGap + 3 * scale + gap + headH + gap + detH
        if filmLine != nil { blockH += gap * 0.7 + filmH }

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        var y = centre.y - blockH / 2               // baseline of the lowest line

        draw(det, at: CGPoint(x: centre.x - width(det) / 2, y: y), in: ctx)
        y += detH + gap
        if let filmLine {
            draw(filmLine, at: CGPoint(x: centre.x - width(filmLine) / 2, y: y), in: ctx)
            y += filmH + gap * 0.7
        }
        draw(head, at: CGPoint(x: centre.x - width(head) / 2, y: y), in: ctx)
        y += headH + gap

        // A single rule under the wordmark, marquee orange — the only
        // decoration a card gets.
        ctx.setFillColor(Self.marqueeOrange)
        let ruleW = 120 * scale
        ctx.fill(CGRect(x: centre.x - ruleW / 2, y: y, width: ruleW, height: 3 * scale))
        y += 3 * scale + ruleGap
        draw(mark, at: CGPoint(x: centre.x - width(mark) / 2, y: y), in: ctx)
    }

    /// A card of the host's own lines (§D10).
    ///
    /// The four ranks map to the project's own hierarchy — CLAUDE.md's "three
    /// weights × two sizes = six levels", of which a card uses four. They are
    /// the SAME sizes and weights the fixed cards use, which is why a custom
    /// card cannot look like a different product: Display is the 96-point
    /// semibold of "Thanks for watching", Body is the 40-point regular of
    /// "back shortly", Caption is the 26-point of the wordmark.
    ///
    /// Lines are laid out from the block's real height so the stack is
    /// optically centred, exactly as the fixed cards are — a custom card with
    /// one line and one with four must both sit in the middle of the frame.
    private func drawCustom(lines: [StudioOverlay.CardLine], in ctx: CGContext) {
        let mark = line("ARCHIVE WATCH", font: font(26, weight: 0.4),
                        color: Self.marqueeOrange, tracking: 4)

        // AN EMPTY LINE IS DROPPED, not drawn as a gap. The host's editor
        // starts with four slots so there is somewhere to type; three of them
        // are usually blank, and a blank slot must not push the block
        // off-centre or reserve a band of black.
        let written = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        // §D10: an empty custom card is not shown. Reaching here with nothing
        // to say would paint the frame black over the film, which is a fault
        // rather than a choice — so the ground stays, the wordmark stays, and
        // the card at least identifies itself.
        let drawn: [(CTLine, CGFloat)] = written.prefix(4).map { l in
            let points = Self.points(for: l.rank)
            return (line(l.text, font: font(points, weight: Self.weight(for: l.rank)),
                         color: Self.colour(for: l.rank)), points * scale)
        }

        let markH = 26 * scale, ruleGap = 22 * scale, gap = 30 * scale
        var blockH = markH + ruleGap + 3 * scale
        if !drawn.isEmpty {
            blockH += gap + drawn.map(\.1).reduce(0, +)
                + gap * CGFloat(max(0, drawn.count - 1))
        }

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        var y = centre.y - blockH / 2      // baseline of the LOWEST line

        // Bottom-up, because y is a baseline and the stack is built from the
        // bottom — so the host's lines are drawn in reverse and read in order.
        for (text, height) in drawn.reversed() {
            draw(text, at: CGPoint(x: centre.x - width(text) / 2, y: y), in: ctx)
            y += height + gap
        }
        if !drawn.isEmpty { y -= gap }
        y += gap

        ctx.setFillColor(Self.marqueeOrange)
        let ruleW = 120 * scale
        ctx.fill(CGRect(x: centre.x - ruleW / 2, y: y, width: ruleW, height: 3 * scale))
        y += 3 * scale + ruleGap
        draw(mark, at: CGPoint(x: centre.x - width(mark) / 2, y: y), in: ctx)
    }

    private static func points(for rank: StudioOverlay.CardLine.Rank) -> CGFloat {
        switch rank {
        case .display: return 96
        case .heading: return 56
        case .body:    return 40
        case .caption: return 26
        }
    }

    private static func weight(for rank: StudioOverlay.CardLine.Rank) -> CGFloat {
        switch rank {
        case .display, .heading: return 0.4      // semibold
        case .body:              return 0.0      // regular
        case .caption:           return 0.3      // medium
        }
    }

    private static func colour(for rank: StudioOverlay.CardLine.Rank) -> CGColor {
        switch rank {
        case .display, .heading: return Self.paper
        case .body:              return CGColor(gray: 0.85, alpha: 1)
        case .caption:           return CGColor(gray: 0.72, alpha: 1)
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }
}
