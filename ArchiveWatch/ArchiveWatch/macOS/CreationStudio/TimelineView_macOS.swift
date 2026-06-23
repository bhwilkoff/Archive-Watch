#if os(macOS)
import SwiftUI
import AppKit
import QuartzCore

// The AppKit timeline (docs/macOS-DESIGN.md §7, de-risk spike #2). An NSView+CALayer
// document view in an NSScrollView — per Rule 7b, SwiftUI view-per-clip stutters and Canvas
// loses native scroll/hit-testing, so the timeline drops to AppKit. Zoom drives
// points-per-second (NOT NSScrollView magnification, which would blur thumbnails) so clips
// re-tile crisply. CapCut-approachable (Rule 7c): a magnetic main track, click-to-scrub,
// click-to-select, drag-trim handles, ⌘-scroll zoom, Space/⌫/B keys. Ripple/markers/
// snapping are fast-follows on this same view.

struct ClipTimelineView: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.08, alpha: 1)
        let content = TimelineContentView(model: model)
        scroll.documentView = content
        context.coordinator.content = content
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Reading these makes SwiftUI re-call updateNSView when they change (observation).
        let state = TimelineContentView.State(
            clips: model.clips, pps: model.pointsPerSecond, selectedID: model.selectedClipID,
            playhead: model.playheadSeconds, thumbnails: model.thumbnails,
            totalDuration: model.totalDuration)
        context.coordinator.content?.render(state)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var content: TimelineContentView? }
}

final class TimelineContentView: NSView {
    struct State {
        let clips: [TimelineClip]
        let pps: Double
        let selectedID: UUID?
        let playhead: Double
        let thumbnails: [UUID: [CGImage]]
        let totalDuration: Double
    }

    private let model: EditorModel
    private var state = State(clips: [], pps: 60, selectedID: nil, playhead: 0, thumbnails: [:], totalDuration: 0)

    private let rulerH: CGFloat = 26
    private let trackTop: CGFloat = 30
    private let trackH: CGFloat = 110
    private let handleW: CGFloat = 8
    private let minWidth: CGFloat = 400

    // Drag state
    private enum Drag { case none, scrub, trimLeft(UUID), trimRight(UUID) }
    private var drag: Drag = .none

    init(model: EditorModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }                 // top-left origin (matches time→x)
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    func render(_ s: State) {
        state = s
        let w = max(minWidth, CGFloat(s.totalDuration * s.pps) + 40)
        setFrameSize(NSSize(width: w, height: 150))
        needsLayout = true
        rebuildLayers()
    }

    private func x(_ seconds: Double) -> CGFloat { CGFloat(seconds * state.pps) }
    private func seconds(_ x: CGFloat) -> Double { Double(x) / state.pps }

    // MARK: layers

    private func rebuildLayers() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let layer else { return }

        // Ruler ticks + labels.
        let stepSec = rulerStep(for: state.pps)
        var t = 0.0
        while t <= state.totalDuration + stepSec {
            let tx = x(t)
            let tick = CALayer()
            tick.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
            tick.frame = CGRect(x: tx, y: 0, width: 1, height: rulerH)
            layer.addSublayer(tick)
            let label = CATextLayer()
            label.string = timecode(t)
            label.fontSize = 10
            label.foregroundColor = NSColor(white: 0.55, alpha: 1).cgColor
            label.contentsScale = 2
            label.frame = CGRect(x: tx + 3, y: 3, width: 60, height: 14)
            layer.addSublayer(label)
            t += stepSec
        }

        // Clip blocks.
        for clip in state.clips {
            let cx = x(clip.timelineStart.seconds)
            let cw = max(2, x(clip.sourceRange.duration.seconds))
            let container = CALayer()
            container.frame = CGRect(x: cx, y: trackTop, width: cw, height: trackH)
            container.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
            container.cornerRadius = 6
            container.masksToBounds = true
            container.borderWidth = clip.id == state.selectedID ? 2 : 1
            container.borderColor = (clip.id == state.selectedID
                ? NSColor.controlAccentColor : NSColor(white: 0.3, alpha: 1)).cgColor

            // Filmstrip thumbnails tiled across the clip width.
            if let thumbs = state.thumbnails[clip.id], !thumbs.isEmpty {
                let tw = cw / CGFloat(thumbs.count)
                for (i, img) in thumbs.enumerated() {
                    let frame = CALayer()
                    frame.contents = img
                    frame.contentsGravity = .resizeAspectFill
                    frame.masksToBounds = true
                    frame.frame = CGRect(x: CGFloat(i) * tw, y: 0, width: tw + 1, height: trackH)
                    container.addSublayer(frame)
                }
            }

            // Label.
            let label = CATextLayer()
            label.string = "  " + clip.label
            label.fontSize = 11
            label.foregroundColor = NSColor.white.cgColor
            label.contentsScale = 2
            label.truncationMode = .end
            label.frame = CGRect(x: 0, y: 2, width: cw, height: 16)
            let labelBG = CALayer()
            labelBG.frame = CGRect(x: 0, y: 0, width: cw, height: 20)
            labelBG.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
            container.addSublayer(labelBG)
            container.addSublayer(label)

            // Trim handles (brighter on the selected clip).
            for (isLeft, hx) in [(true, CGFloat(0)), (false, cw - handleW)] {
                let h = CALayer()
                h.frame = CGRect(x: hx, y: 0, width: handleW, height: trackH)
                let on = clip.id == state.selectedID
                h.backgroundColor = (on ? NSColor.controlAccentColor : NSColor(white: 0.5, alpha: 0.6)).cgColor
                _ = isLeft
                container.addSublayer(h)
            }
            layer.addSublayer(container)
        }

        // Playhead.
        let ph = CALayer()
        ph.backgroundColor = NSColor.systemRed.cgColor
        ph.frame = CGRect(x: x(state.playhead), y: 0, width: 2, height: bounds.height)
        layer.addSublayer(ph)
    }

    private func rulerStep(for pps: Double) -> Double {
        // Aim for a tick label every ~80pt.
        let target = 80.0 / pps
        for s in [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300] where Double(s) >= target { return Double(s) }
        return 600
    }
    private func timecode(_ s: Double) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }

    // MARK: interaction

    private func clipHit(at p: NSPoint) -> (clip: TimelineClip, region: Drag)? {
        guard p.y >= trackTop, p.y <= trackTop + trackH else { return nil }
        for clip in state.clips {
            let cx = x(clip.timelineStart.seconds)
            let cw = x(clip.sourceRange.duration.seconds)
            if p.x >= cx && p.x <= cx + cw {
                if p.x <= cx + handleW { return (clip, .trimLeft(clip.id)) }
                if p.x >= cx + cw - handleW { return (clip, .trimRight(clip.id)) }
                return (clip, .none)
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let hit = clipHit(at: p) {
            model.selectedClipID = hit.clip.id
            switch hit.region {
            case .trimLeft, .trimRight: drag = hit.region
            default:
                drag = .scrub
                model.seek(toSeconds: seconds(p.x))
            }
        } else {
            drag = .scrub
            model.seek(toSeconds: seconds(p.x))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .scrub:
            model.seek(toSeconds: seconds(p.x))
        case .trimLeft(let id):
            guard let clip = state.clips.first(where: { $0.id == id }) else { return }
            // New IN = the source second corresponding to the dragged left edge.
            let deltaSec = seconds(p.x) - clip.timelineStart.seconds
            model.trim(id, newInSeconds: clip.sourceRange.start.seconds + deltaSec)
        case .trimRight(let id):
            guard let clip = state.clips.first(where: { $0.id == id }) else { return }
            let newDurOnTimeline = seconds(p.x) - clip.timelineStart.seconds
            model.trim(id, newOutSeconds: clip.sourceRange.start.seconds + newDurOnTimeline)
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) { drag = .none }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let factor = 1 + Double(event.scrollingDeltaY) * 0.01
            model.zoom(by: factor)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ": model.togglePlay()
        case "b", "B": model.splitAtPlayhead()
        case String(UnicodeScalar(NSDeleteCharacter)!), String(UnicodeScalar(NSBackspaceCharacter)!):
            if let id = model.selectedClipID { model.deleteClip(id) }
        default:
            if let id = model.selectedClipID,
               event.keyCode == 51 /* delete */ { model.deleteClip(id) }
            else { super.keyDown(with: event) }
        }
    }
}
#endif
