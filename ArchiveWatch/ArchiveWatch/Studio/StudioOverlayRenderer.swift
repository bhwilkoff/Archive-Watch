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
            }
        }
        guard o.showLowerThird, !o.title.isEmpty else { return "" }
        return "l3:\(o.title)|\(o.subtitle)|\(o.provenance)"
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
            contentRect = drawLowerThird(o, in: ctx)
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
    private func drawLowerThird(_ o: StudioOverlay, in ctx: CGContext) -> CGRect {
        let inset = size.width * 0.05                   // 5% title-safe
        let titleFont = font(52, weight: 0.4)           // display, semibold
        let subFont = font(30, weight: 0.0)
        let provFont = font(22, weight: 0.3)

        let title = line(o.title, font: titleFont, color: Self.paper)
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
        var stackH = titleH
        if sub != nil { stackH += gap + subH }
        if prov != nil { stackH += gap + provH }

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
        draw(title, at: CGPoint(x: textX, y: y), in: ctx)
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

        let headline: String
        let detail: String
        switch card {
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

    private static func clock(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }
}
