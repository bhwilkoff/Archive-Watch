#if os(macOS)
import SwiftUI

// THE STREAM CANVAS — every tile is moved, resized, cropped and layered where
// it is drawn (macOS-DESIGN §D14b, which corrects §D14a).
//
// Owner, 2026-10-02, after the first full show: *"The resizing and cropping of
// my video and the call video doesn't work as it should. It was very hard to
// manipulate and crop a video. You should do additional research on how to
// allow for resizing and cropping with the corner/middle tiles."* And: *"You
// should be able to decide the order of the video feeds (send to back or
// something)."*
//
// What was wrong, measured rather than guessed:
//   · The drag was read in the gesture's LOCAL space, and the handle being
//     dragged moved with the tile — so every frame's translation was measured
//     from a view that had just moved, and the tile lagged, stalled and
//     jumped under the pointer. Now every gesture reads one fixed space, the
//     canvas (`studioCanvas`).
//   · The box was drawn from the rect the ENGINE composited, a frame or more
//     behind the pointer. Now it is drawn from the host's own framing, which
//     the engine then draws — the same value, without the round trip.
//   · An edge RESHAPED an aspect-filled box, so dragging it in cut both sides
//     and dragging it out zoomed the picture. Now the handles do what their
//     shapes say (the research: Keynote's mask, Photos' crop, Ecamm's and
//     OBS's crop): a CORNER square scales tile and picture together; an EDGE
//     bar cuts the picture at that edge and the picture stays still — the cut
//     edges turn green, as OBS's do, over a faint outline of the whole
//     picture; ⌥-drag slides the picture inside its cut; scroll zooms it.
//   · Only the selected tile could be dragged; any other had to be clicked
//     first, in a 1-pixel dashed outline. Now any tile is grabbed where it is
//     drawn, front-most first, and right-click offers Arrange and Reset.
//
// One set of handles at a time (§D24): two would make a drag ambiguous
// wherever tiles overlap.

struct StudioCanvas: View {
    /// What the engine composited, normalized program rects (origin bottom-left).
    let drawn: [String: CGRect]
    /// Each tile's SOURCE shape, w/h.
    let sourceAspects: [String: CGFloat]
    /// The scene's tiles, back to front.
    let order: [String]
    /// The full-frame camera of "You, with the film inset": not movable.
    let ground: String?
    let programAspect: CGFloat
    let name: (String) -> String
    @Bindable var controls: StudioControls

    private struct Drag {
        let id: String
        let grab: StudioCameraFraming.Grab
        let start: StudioCameraFraming
        let startTile: CGRect
    }
    @State private var drag: Drag?
    @State private var hovering: String?

    private let marquee = Brand.primary
    private let cropGreen = Color(red: 0.25, green: 0.85, blue: 0.35)
    static let space = "studioCanvas"

    var body: some View {
        GeometryReader { geo in
            let fit = Self.aspectFit(programAspect, in: geo.size)
            let inset = CGPoint(x: (geo.size.width - fit.width) / 2, y: (geo.size.height - fit.height) / 2)
            let ids = order.filter { $0 != ground && rect($0) != nil }
            let selected = controls.framedTile.flatMap { ids.contains($0) ? $0 : nil }
            ZStack(alignment: .topLeading) {
                // Back to front, so the FRONT tile takes the click where two
                // overlap — the one the audience sees is the one you grab.
                ForEach(ids, id: \.self) { id in
                    if let r = rect(id) {
                        let box = Self.viewRect(r, drawn: fit, inset: inset)
                        tileBody(id, box: box, fit: fit, selected: id == selected)
                    }
                }
                if let id = selected, let r = rect(id) {
                    let box = Self.viewRect(r, drawn: fit, inset: inset)
                    if let ghost = sourceOutline(id, tile: r) {
                        // THE WHOLE PICTURE, while it is being cut or slid:
                        // what the crop is taking away, not just what is left.
                        let g = Self.viewRect(ghost, drawn: fit, inset: inset)
                        Rectangle()
                            .strokeBorder(cropGreen.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: g.width, height: g.height)
                            .offset(x: g.minX, y: g.minY)
                            .allowsHitTesting(false)
                    }
                    selectionBox(box)
                    ForEach(Self.handles, id: \.self) { grab in
                        handle(id, grab: grab, box: box, fit: fit)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(name: Self.space)
        }
        // THE KEYBOARD (§D14a's amendment, kept): arrows move the selected
        // tile 1% (Shift: 10%); Option-arrows CROP it — left/right move its
        // right edge, up/down its top edge — by the same geometry as a drag.
        .focusable()
        // The selection box IS the focus indicator; the system ring drew a
        // second, unrelated outline round the whole preview.
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard let id = controls.framedTile, id != ground, let r = rect(id) else { return .ignored }
            let step: CGFloat = press.modifiers.contains(.shift) ? 0.10 : 0.01
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch press.key {
            case .leftArrow: dx = -step
            case .rightArrow: dx = step
            case .upArrow: dy = step
            case .downArrow: dy = -step
            default: return .ignored
            }
            let crop = press.modifiers.contains(.option)
            let grab: StudioCameraFraming.Grab = crop ? (dx != 0 ? .edge(x: 1, y: 0) : .edge(x: 0, y: 1)) : .body
            set(id, StudioCameraFraming.dragged(framing(id), tile: r, grab: grab, dx: dx, dy: dy,
                                               programAspect: programAspect, sourceAspect: aspect(id)))
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stream canvas")
        .accessibilityHint("Arrow keys move the selected tile; Option with the arrow keys crops it.")
    }

    // MARK: Pieces

    @ViewBuilder
    private func tileBody(_ id: String, box: CGRect, fit: CGSize, selected: Bool) -> some View {
        let hot = hovering == id
        Rectangle()
            .strokeBorder(selected ? Color.clear : Color.white.opacity(hot ? 0.9 : 0.45),
                          style: StrokeStyle(lineWidth: hot ? 1.5 : 1, dash: [5, 4]))
            .contentShape(Rectangle())
            .frame(width: max(1, box.width), height: max(1, box.height))
            .modifier(ScrollZoom(enabled: selected) { factor in zoom(id, by: factor) })
            .position(x: box.midX, y: box.midY)
            .onHover { inside in
                hovering = inside ? id : (hovering == id ? nil : hovering)
                (inside ? NSCursor.openHand : NSCursor.arrow).set()
            }
            .gesture(dragGesture(id, grab: .body, fit: fit))
            .contextMenu { tileMenu(id) }
            .help(selected ? "" : "Drag to move \(name(id)); right-click to arrange")
            .accessibilityElement()
            .accessibilityLabel("\(name(id)) tile")
            .accessibilityAddTraits(selected ? [.isSelected] : [.isButton])
            .accessibilityAction { controls.selectedTile = id }
    }

    private func selectionBox(_ box: CGRect) -> some View {
        let cutting: Set<Int> = {
            guard let d = drag, case .edge(let x, let y) = d.grab else { return [] }
            return [x == -1 ? 0 : x == 1 ? 1 : y == 1 ? 2 : 3]
        }()
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(marquee.opacity(0.95), lineWidth: 1.5)
            // The edge being cut, in OBS's green.
            ForEach(Array(cutting), id: \.self) { side in
                Rectangle().fill(cropGreen)
                    .frame(width: side < 2 ? 2.5 : box.width, height: side < 2 ? box.height : 2.5)
                    .offset(x: side == 1 ? box.width - 2.5 : 0, y: side == 3 ? box.height - 2.5 : 0)
            }
        }
        .frame(width: box.width, height: box.height)
        .offset(x: box.minX, y: box.minY)
        .allowsHitTesting(false)
    }

    /// A CORNER is a square (resize); an EDGE is a bar along the side (crop).
    /// Different shapes for different acts, so the handle says which it is
    /// before it is touched — and a hit area well past the drawn mark, because
    /// a 9-point square on a preview is a hard target to find mid-show.
    @ViewBuilder
    private func handle(_ id: String, grab: StudioCameraFraming.Grab, box: CGRect, fit: CGSize) -> some View {
        let p = Self.point(for: grab, in: box)
        let isCorner: Bool = { if case .corner = grab { return true } else { return false } }()
        let horizontalBar: Bool = { if case .edge(_, let y) = grab { return y != 0 } else { return false } }()
        let mark = isCorner ? CGSize(width: 10, height: 10)
            : horizontalBar ? CGSize(width: min(28, box.width * 0.4), height: 5)
            : CGSize(width: 5, height: min(28, box.height * 0.4))
        let hit = isCorner ? CGSize(width: 22, height: 22)
            : horizontalBar ? CGSize(width: max(24, box.width * 0.5), height: 16)
            : CGSize(width: 16, height: max(24, box.height * 0.5))
        ZStack {
            Color.clear.contentShape(Rectangle()).frame(width: hit.width, height: hit.height)
            RoundedRectangle(cornerRadius: isCorner ? 1.5 : 2.5)
                .fill(isCorner ? marquee : Color.white)
                .overlay(RoundedRectangle(cornerRadius: isCorner ? 1.5 : 2.5)
                    .strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                .frame(width: mark.width, height: mark.height)
                .allowsHitTesting(false)
        }
        .position(x: p.x, y: p.y)
        .onHover { inside in
            if inside { Self.cursor(for: grab).set() } else { NSCursor.arrow.set() }
        }
        .gesture(dragGesture(id, grab: grab, fit: fit))
        .help(isCorner ? "Drag to resize" : "Drag to crop this side")
    }

    @ViewBuilder
    private func tileMenu(_ id: String) -> some View {
        let i = controls.shown.firstIndex(of: id) ?? 0
        let last = controls.shown.count - 1
        Button("Bring to Front") { controls.move(id, .front) }.disabled(i == last)
        Button("Bring Forward") { controls.move(id, .forward) }.disabled(i == last)
        Button("Send Backward") { controls.move(id, .backward) }.disabled(i == 0)
        Button("Send to Back") { controls.move(id, .back) }.disabled(i == 0)
        Divider()
        Button("Reset Crop") {
            var f = framing(id)
            f.crop = nil; f.zoom = 1; f.panX = 0; f.panY = 0
            set(id, f)
        }
        .disabled(!framing(id).isCropped)
        Button("Reset Size and Position") {
            var f = framing(id); f.tile = nil; set(id, f)
        }
        .disabled(framing(id).tile == nil)
        Divider()
        Button("Hide in This Scene") { controls.setShown(id, false) }
    }

    // MARK: Gestures

    private func dragGesture(_ id: String, grab: StudioCameraFraming.Grab, fit: CGSize) -> some Gesture {
        // ZERO distance, so the press itself selects (Keynote, OBS); a press
        // that never moves changes nothing else.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard fit.width > 1, fit.height > 1 else { return }
                if drag?.id != id {
                    guard let r = rect(id) else { return }
                    controls.selectedTile = id
                    let g: StudioCameraFraming.Grab =
                        (grab == .body && NSEvent.modifierFlags.contains(.option)) ? .pan : grab
                    drag = Drag(id: id, grab: g, start: framing(id), startTile: r)
                    if g == .pan { NSCursor.closedHand.set() }
                }
                guard let d = drag else { return }
                // The preview is letterboxed, so N points of drag are N/fit of
                // the PROGRAM, and y is inverted (program origin bottom-left).
                let dx = v.translation.width / fit.width
                let dy = -v.translation.height / fit.height
                guard abs(dx) > 0 || abs(dy) > 0 else { return }
                set(id, StudioCameraFraming.dragged(d.start, tile: d.startTile, grab: d.grab,
                                                    dx: dx, dy: dy, programAspect: programAspect,
                                                    sourceAspect: aspect(id)))
            }
            .onEnded { _ in drag = nil }
    }

    private func zoom(_ id: String, by factor: CGFloat) {
        guard let r = rect(id) else { return }
        set(id, StudioCameraFraming.zoomed(framing(id), tile: r, factor: factor,
                                           programAspect: programAspect, sourceAspect: aspect(id)))
    }

    // MARK: Values

    /// The tile's rect: the host's own framing where it has one (so the box
    /// follows the pointer this frame, not the engine's next), otherwise
    /// where the engine drew it.
    private func rect(_ id: String) -> CGRect? {
        guard let engine = drawn[id] else { return nil }
        return controls.framings[id]?.tile ?? engine
    }
    private func framing(_ id: String) -> StudioCameraFraming { controls.framings[id] ?? StudioCameraFraming() }
    private func aspect(_ id: String) -> CGFloat { sourceAspects[id] ?? 16.0 / 9.0 }
    private func set(_ id: String, _ f: StudioCameraFraming) { controls.framings[id] = f }

    /// The whole source, placed where the visible cut puts it, while a crop
    /// or a slide is in progress (nil otherwise).
    private func sourceOutline(_ id: String, tile t: CGRect) -> CGRect? {
        guard let d = drag, d.id == id else { return nil }
        switch d.grab { case .edge, .pan: break; default: return nil }
        let c = framing(id).visibleCrop(sourceAspect: aspect(id),
                                        tileAspect: t.height > 0 ? t.width * programAspect / t.height : 1)
        guard c.width > 0, c.height > 0 else { return nil }
        let w = t.width / c.width, h = t.height / c.height
        return CGRect(x: t.minX - c.minX * w, y: t.minY - c.minY * h, width: w, height: h)
    }

    // MARK: Geometry

    static let handles: [StudioCameraFraming.Grab] = [
        .corner(x: -1, y: -1), .corner(x: 1, y: -1), .corner(x: -1, y: 1), .corner(x: 1, y: 1),
        .edge(x: -1, y: 0), .edge(x: 1, y: 0), .edge(x: 0, y: -1), .edge(x: 0, y: 1),
    ]

    /// Normalized program rect (origin bottom-left) → view rect (origin
    /// top-left), inside the letterboxed preview.
    static func viewRect(_ t: CGRect, drawn: CGSize, inset: CGPoint) -> CGRect {
        CGRect(x: inset.x + t.minX * drawn.width,
               y: inset.y + (1 - t.maxY) * drawn.height,
               width: t.width * drawn.width,
               height: t.height * drawn.height)
    }

    static func point(for grab: StudioCameraFraming.Grab, in box: CGRect) -> CGPoint {
        switch grab {
        case .body, .pan: return CGPoint(x: box.midX, y: box.midY)
        case .corner(let x, let y), .edge(let x, let y):
            // y is in PROGRAM space (up is +1) and the box in VIEW space.
            return CGPoint(x: box.midX + CGFloat(x) * box.width / 2,
                           y: box.midY - CGFloat(y) * box.height / 2)
        }
    }

    static func cursor(for grab: StudioCameraFraming.Grab) -> NSCursor {
        switch grab {
        case .body: return .openHand
        case .pan: return .closedHand
        case .corner(let x, let y):
            let pos: NSCursor.FrameResizePosition = x < 0 ? (y > 0 ? .topLeft : .bottomLeft)
                                                          : (y > 0 ? .topRight : .bottomRight)
            return .frameResize(position: pos, directions: .all)
        case .edge(let x, let y):
            let pos: NSCursor.FrameResizePosition = x < 0 ? .left : x > 0 ? .right : y > 0 ? .top : .bottom
            return .frameResize(position: pos, directions: .all)
        }
    }

    static func aspectFit(_ aspect: CGFloat, in box: CGSize) -> CGSize {
        guard aspect > 0, box.width > 0, box.height > 0 else { return .zero }
        let w = min(box.width, box.height * aspect)
        return CGSize(width: w, height: w / aspect)
    }
}

/// SCROLL-TO-ZOOM, via a local event monitor rather than an `NSView`.
///
/// The obvious implementation — an `NSView` behind the box overriding
/// `scrollWheel` — does not work, and the reason is worth writing down because
/// it will look wrong to the next person who tries it. AppKit dispatches
/// `scrollWheel` to the view `hitTest` returns and then up ITS responder
/// chain. A representable placed with `.background` is a SIBLING of SwiftUI's
/// hosting view, not an ancestor, so the hosting view takes the hit and the
/// event walks a chain the catcher is not on. Measured: eight scroll ticks
/// over the box left `zoom` at exactly 1.0. Putting it in `.overlay` instead
/// only moves the problem — it would then take the hit and kill the drag.
///
/// A local monitor sees the event before any of that, and the view can still
/// answer "is the pointer over me" by converting its own bounds to the screen.
/// The event is SWALLOWED when it is handled, so the Inputs column does not
/// also scroll underneath.
private struct ScrollZoom: ViewModifier {
    let enabled: Bool
    let zoom: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(enabled ? AnyView(Catcher(zoom: zoom)) : AnyView(Color.clear))
    }

    private struct Catcher: NSViewRepresentable {
        let zoom: (CGFloat) -> Void
        func makeNSView(context: Context) -> NSView { MonitorView(zoom: zoom) }
        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? MonitorView)?.zoom = zoom
        }
        static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
            (nsView as? MonitorView)?.stop()
        }

        final class MonitorView: NSView {
            var zoom: (CGFloat) -> Void
            private var monitor: Any?

            init(zoom: @escaping (CGFloat) -> Void) {
                self.zoom = zoom
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stop()
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                    [weak self] event in
                    // ONLY SCALARS CROSS THE ISOLATION BOUNDARY: `NSEvent` is
                    // not `Sendable`.
                    let delta = event.scrollingDeltaY
                    let precise = event.hasPreciseScrollingDeltas
                    let from = event.window.map(ObjectIdentifier.init)
                    let handled = MainActor.assumeIsolated { () -> Bool in
                        guard let self, let window = self.window else { return false }
                        // A synthesised scroll can arrive with no `window`;
                        // where the event names one it must be ours.
                        if let from, from != ObjectIdentifier(window) { return false }
                        let onScreen = window.convertToScreen(self.convert(self.bounds, to: nil))
                        guard window.isKeyWindow, onScreen.contains(NSEvent.mouseLocation) else { return false }
                        // A trackpad reports fractional, precise deltas and a
                        // wheel whole lines; these land both on one feel.
                        let step = precise ? delta * 0.006 : delta * 0.03
                        self.zoom(1 + step)
                        return true
                    }
                    return handled ? nil : event
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
        }
    }
}
#endif
