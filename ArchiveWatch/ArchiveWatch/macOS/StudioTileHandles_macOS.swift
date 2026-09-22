#if os(macOS)
import SwiftUI

// FRAMING THE CAMERA BY DRAGGING IT — macOS-DESIGN §D14, rewritten 2026-09-22.
//
// Owner, on the first attempt: *"I think the crop is pretty clumsy. Most people
// expect to crop the video frame (size and shape of the actual video tile)
// rather than zoom and move. I like the ability to zoom the video within the
// frame and move it around the frame, but it is clunky implementation with
// four different sliders. Can you research/consult a macos design pattern for
// cropping, zooming, and moving video around a preview screen (surely, OBS has
// a way to do this as well ...)."*
//
// OBS's canvas is the pattern, and it is the one hosts already know:
//   · drag INSIDE the box            → move it
//   · drag a CORNER handle           → resize, keeping proportions
//   · drag a SIDE handle             → stretch one dimension (change the SHAPE)
//   · hold Option and drag a handle  → crop, and the edges turn green
//   · Edit Transform (⌘E)            → the same thing as numbers, for precision
// (obsproject.com/kb/sources-guide, and OBS's own Alt/Option-drag crop.)
//
// WHAT WE TAKE AND WHAT WE CHANGE. We take the handles, the drag-to-move, and
// the corner-versus-side distinction. We do NOT need OBS's separate crop mode,
// because our tile is aspect-FILLED: reshaping the box IS the crop. A 16:9
// webcam in a square tile shows a square of the host, and that is exactly what
// "crop to my face" asks for. One gesture where OBS has two, and no modifier
// key to discover.
//
// The SOURCE's own zoom and pan stay, because the owner asked for them — but as
// scroll and Option-drag INSIDE the box, which is the macOS idiom for moving a
// picture inside a frame (Preview, Photos, Maps) and costs no sliders.
//
// WHY IT LIVES OVER THE STREAM PREVIEW. §D5: the preview is what the audience
// sees. Manipulating the tile there is direct manipulation of the real thing;
// four sliders in another column were a second description of a picture that
// was already on screen.

struct StudioTileHandles: View {
    /// The tile's rect in the PROGRAM frame, normalized, origin bottom-left —
    /// published by the engine from the frame it actually composited.
    let tile: CGRect
    /// The program's aspect, so the preview's letterboxing can be undone.
    let programAspect: CGFloat
    @Bindable var controls: StudioControls

    /// Where the gesture started, in normalized program space. Held so a drag
    /// is absolute rather than re-reading a value it is itself changing —
    /// which accumulates rounding and makes the tile creep.
    @State private var origin: CGRect?

    /// Which part of the box the pointer is on. `.body` moves, the rest resize.
    enum Grab: Hashable {
        case body
        case corner(x: Int, y: Int)   // -1 / +1
        case edge(x: Int, y: Int)     // exactly one of x,y is non-zero
    }

    private static let handle: CGFloat = 9
    private let marquee = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        GeometryReader { geo in
            let drawn = Self.aspectFit(programAspect, in: geo.size)
            let inset = CGPoint(x: (geo.size.width - drawn.width) / 2,
                                y: (geo.size.height - drawn.height) / 2)
            let box = Self.viewRect(tile, drawn: drawn, inset: inset)
            ZStack(alignment: .topLeading) {
                // A HIT AREA OVER THE WHOLE PREVIEW is deliberately NOT here.
                // The gesture is on the box and its handles only, so a drag
                // that starts on empty film does nothing rather than silently
                // teleporting the tile — and so a host can still see the
                // programme without the preview being one big control.
                Rectangle()
                    .strokeBorder(marquee.opacity(0.95), lineWidth: 1.5)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .allowsHitTesting(false)

                ForEach(Self.grabs, id: \.self) { grab in
                    let p = Self.point(for: grab, in: box)
                    Rectangle()
                        .fill(marquee)
                        .frame(width: Self.handle, height: Self.handle)
                        .offset(x: p.x - Self.handle / 2, y: p.y - Self.handle / 2)
                        .opacity(grab == .body ? 0 : 1)
                        .allowsHitTesting(false)
                }

                // The BODY, then the handles on top, each with its own gesture
                // so the hit target is the handle rather than a hit-test guess.
                dragTarget(.body, rect: box, drawn: drawn)
                ForEach(Self.grabs.filter { $0 != .body }, id: \.self) { grab in
                    let p = Self.point(for: grab, in: box)
                    dragTarget(grab,
                               rect: CGRect(x: p.x - Self.handle,
                                            y: p.y - Self.handle,
                                            width: Self.handle * 2,
                                            height: Self.handle * 2),
                               drawn: drawn)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func dragTarget(_ grab: Grab, rect: CGRect, drawn: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            // `.position`, NOT `.offset`. Offset is a RENDER transform: it
            // moves what you see and leaves the view laid out where it was, so
            // the `NSView` that `ScrollZoom` puts behind this one sat at the
            // pane's top-left corner and its "is the pointer over me?" test
            // was asking about the wrong rectangle. Measured: ten scroll ticks
            // dead centre of the box left `zoom` at 1.0. `.position` places the
            // view's CENTRE in the parent's coordinate space and is a layout
            // change, so the backing view goes where the box is.
            // ScrollZoom BEFORE `.position`, so its backing view is the size
            // of the BOX. `.position` makes its child fill the parent and
            // places the content inside, so a background applied after it
            // backs the whole pane — measured as `rect=690,488 650x394`, the
            // entire stream preview, which would have made a scroll anywhere
            // in the pane zoom the camera.
            .modifier(ScrollZoom(enabled: grab == .body, controls: controls))
            .position(x: rect.midX, y: rect.midY)
            // THE POINTER SAYS WHAT THE HANDLE DOES, which is the other half
            // of a handle being discoverable at all: a box with eight squares
            // and an arrow cursor asks you to guess. macOS publishes no
            // diagonal resize cursor, so a corner gets the crosshair rather
            // than a wrong arrow.
            .onHover { inside in
                if inside { Self.cursor(for: grab).set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in apply(grab, value, drawn: drawn) }
                    .onEnded { _ in origin = nil }
            )
    }

    /// Turn a drag into a new tile, or into a pan of the source.
    private func apply(_ grab: Grab, _ value: DragGesture.Value, drawn: CGSize) {
        guard drawn.width > 1, drawn.height > 1 else { return }
        let start = origin ?? (controls.framing.tile ?? tile)
        if origin == nil { origin = start }

        // The preview is letterboxed, so a drag of N points is N/drawn of the
        // PROGRAM — not N/pane. Getting that wrong makes the tile lag the
        // pointer by however much letterboxing there is.
        let dx = value.translation.width / drawn.width
        // Y IS INVERTED: SwiftUI's drag grows downward; the program frame's
        // origin is bottom-left.
        let dy = -value.translation.height / drawn.height

        // OPTION-DRAG PANS THE SOURCE, which is the one thing reshaping the
        // box cannot do: it chooses WHICH part of the camera fills the shape.
        if NSEvent.modifierFlags.contains(.option), grab == .body {
            var f = controls.framing
            guard f.zoom > 1 else { return }          // nothing to pan at 1x
            f.panX = min(max(-1, f.panX - dx * 2 * f.zoom), 1)
            f.panY = min(max(-1, f.panY - dy * 2 * f.zoom), 1)
            controls.framing = f
            return
        }

        var r = start
        switch grab {
        case .body:
            r.origin.x += dx
            r.origin.y += dy
        case .corner(let sx, let sy):
            // PROPORTIONS KEPT on a corner, stretched on a side — OBS's own
            // split, and the reason both exist: a corner is "make me bigger",
            // a side is "make me a different shape".
            let ratio = start.height > 0 ? start.width / start.height : 1
            // BOTH AXES drive a corner, averaged. Reading `dx` alone made a
            // corner ignore vertical movement, which is not what a corner
            // handle looks like it should do.
            let widen = (dx * CGFloat(sx) + dy * CGFloat(sy) * ratio) / 2
            var w = start.width + widen
            w = max(StudioCameraFraming.minimumTileFraction, min(1, w))
            let h = min(1, w / max(0.01, ratio))
            if sx < 0 { r.origin.x = start.maxX - w }
            if sy < 0 { r.origin.y = start.maxY - h }
            r.size = CGSize(width: w, height: h)
        case .edge(let sx, let sy):
            if sx != 0 {
                var w = start.width + dx * CGFloat(sx)
                w = max(StudioCameraFraming.minimumTileFraction, min(1, w))
                if sx < 0 { r.origin.x = start.maxX - w }
                r.size.width = w
            }
            if sy != 0 {
                var h = start.height + dy * CGFloat(sy)
                h = max(StudioCameraFraming.minimumTileFraction, min(1, h))
                if sy < 0 { r.origin.y = start.maxY - h }
                r.size.height = h
            }
        }
        r.origin.x = min(max(0, r.origin.x), max(0, 1 - r.width))
        r.origin.y = min(max(0, r.origin.y), max(0, 1 - r.height))
        var f = controls.framing
        f.tile = r
        controls.framing = f
    }

    // MARK: Geometry

    static let grabs: [Grab] = [
        .body,
        .corner(x: -1, y: -1), .corner(x: 1, y: -1),
        .corner(x: -1, y: 1), .corner(x: 1, y: 1),
        .edge(x: -1, y: 0), .edge(x: 1, y: 0),
        .edge(x: 0, y: -1), .edge(x: 0, y: 1),
    ]

    /// Normalized program rect (origin bottom-left) → view rect (origin
    /// top-left), inside the letterboxed preview.
    static func viewRect(_ t: CGRect, drawn: CGSize, inset: CGPoint) -> CGRect {
        CGRect(x: inset.x + t.minX * drawn.width,
               y: inset.y + (1 - t.maxY) * drawn.height,
               width: t.width * drawn.width,
               height: t.height * drawn.height)
    }

    static func point(for grab: Grab, in box: CGRect) -> CGPoint {
        switch grab {
        case .body: return CGPoint(x: box.midX, y: box.midY)
        case .corner(let x, let y), .edge(let x, let y):
            // y is in PROGRAM space (up is +1) and the box is in VIEW space
            // (down is +1), so the sign flips here and nowhere else.
            return CGPoint(x: box.midX + CGFloat(x) * box.width / 2,
                           y: box.midY - CGFloat(y) * box.height / 2)
        }
    }

    static func cursor(for grab: Grab) -> NSCursor {
        switch grab {
        case .body: return .openHand
        case .corner: return .crosshair
        case .edge(let x, _): return x != 0 ? .resizeLeftRight : .resizeUpDown
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
    @Bindable var controls: StudioControls

    func body(content: Content) -> some View {
        content.background(enabled ? AnyView(Catcher(controls: controls)) : AnyView(Color.clear))
    }

    private struct Catcher: NSViewRepresentable {
        @Bindable var controls: StudioControls
        func makeNSView(context: Context) -> NSView { MonitorView(controls: controls) }
        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? MonitorView)?.controls = controls
        }
        static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
            (nsView as? MonitorView)?.stop()
        }

        final class MonitorView: NSView {
            var controls: StudioControls
            private var monitor: Any?

            init(controls: StudioControls) {
                self.controls = controls
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stop()
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                    [weak self] event in
                    // ONLY SCALARS CROSS THE ISOLATION BOUNDARY. `NSEvent` is
                    // not `Sendable`, so it may not be captured into
                    // `assumeIsolated` — the same rule WatchTogether's stall
                    // observer follows by sending an `ObjectIdentifier` rather
                    // than the `Notification`.
                    let delta = event.scrollingDeltaY
                    let precise = event.hasPreciseScrollingDeltas
                    let from = event.window.map(ObjectIdentifier.init)
                    let handled = MainActor.assumeIsolated { () -> Bool in
                        guard let self, let window = self.window else { return false }
                        // A SYNTHESISED scroll (a harness, an accessibility
                        // tool) can arrive with no `window` set, so a strict
                        // identity check would make this gesture untestable
                        // and would fail for anyone driving the Mac with
                        // assistive software. Where the event names a window
                        // it must be ours; where it does not, the pointer
                        // being inside our own bounds is the test — and that
                        // is the condition that actually matters.
                        if let from, from != ObjectIdentifier(window) { return false }
                        let onScreen = window.convertToScreen(
                            self.convert(self.bounds, to: nil))
                        let mouse = NSEvent.mouseLocation
                        guard window.isKeyWindow else { return false }
                        guard onScreen.contains(mouse) else { return false }
                        self.zoom(delta: delta, precise: precise)
                        return true
                    }
                    return handled ? nil : event   // swallow only what we used
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            private func zoom(delta: CGFloat, precise: Bool) {
                var f = controls.framing
                // A trackpad reports fractional, precise deltas and a wheel
                // reports whole lines; these two factors land both somewhere
                // that feels like one gesture rather than a jump.
                let step = precise ? delta * 0.01 : delta * 0.06
                f.zoom = min(max(StudioCameraFraming.zoomRange.lowerBound, f.zoom + step),
                             StudioCameraFraming.zoomRange.upperBound)
                if f.zoom == 1 { f.panX = 0; f.panY = 0 }
                controls.framing = f
            }
        }
    }
}
#endif
