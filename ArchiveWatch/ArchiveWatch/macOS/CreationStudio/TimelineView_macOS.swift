#if os(macOS)
import SwiftUI
import AppKit
import QuartzCore

// The AppKit timeline (docs/macOS-DESIGN.md §7, de-risk spike #2). An NSView+CALayer
// document view in an NSScrollView — per Rule 7b, SwiftUI view-per-clip stutters and Canvas
// loses native scroll/hit-testing, so the timeline drops to AppKit. Zoom drives
// points-per-second (NOT NSScrollView magnification, which would blur thumbnails) so clips
// re-tile crisply. CapCut-approachable (Rule 7c): a magnetic main track, click-to-scrub,
// click-to-select, drag-trim handles, ⌘-scroll zoom, Space/⌫/B keys, plus the direct-
// manipulation layer: corner FADE handles, junction DISSOLVE handles, MARKERS, and snapping.

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
        // Reading these makes SwiftUI re-call updateNSView when they change (observation). `clips`
        // live on the non-@Observable document, so an off-band repack (supercut tighten) wouldn't
        // redraw on its own — `timelineRevision` is the observed trigger that forces the re-read.
        _ = model.timelineRevision
        let state = TimelineContentView.State(
            clips: model.clips, pps: model.pointsPerSecond, selectedIDs: model.selectedIDs,
            primaryID: model.selection.id,
            playhead: model.playheadSeconds, thumbnails: model.thumbnails,
            totalDuration: model.totalDuration, prep: model.clipPrep, markers: model.markers,
            overlays: model.textOverlays, audioClips: model.audioClips)
        context.coordinator.content?.render(state)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var content: TimelineContentView? }
}

final class TimelineContentView: NSView, NSMenuItemValidation {
    struct State {
        let clips: [TimelineClip]
        let pps: Double
        var selectedIDs: Set<UUID> = []      // the full multi-selection (clips + overlays + audio)
        var primaryID: UUID? = nil           // the focused element (brighter ring + trim handles)
        let playhead: Double
        let thumbnails: [UUID: [CGImage]]
        let totalDuration: Double
        let prep: [UUID: EditorModel.ClipPrep]
        let markers: [Double]
        var overlays: [TextOverlay] = []
        var audioClips: [AudioClip] = []
    }

    private let model: EditorModel
    private var state = State(clips: [], pps: 60, playhead: 0, thumbnails: [:], totalDuration: 0, prep: [:], markers: [])
    private var playheadLayer: CALayer?
    private var lastStructuralSig = 0

    private let rulerH: CGFloat = 26
    private let trackTop: CGFloat = 30
    private let trackH: CGFloat = 76           // video lane (shrunk to make room for the lanes below)
    private let handleW: CGFloat = 8
    private let fadeBandH: CGFloat = 16        // top band where fade handles live
    private let minWidth: CGFloat = 400
    // Lanes below the video track: a TITLES lane + a DYNAMIC stack of audio lanes (multi-track —
    // as many music/voiceover clips as you want, greedy-packed into non-overlapping rows).
    private let laneGap: CGFloat = 3
    private let laneH: CGFloat = 22
    private var titleTop: CGFloat { trackTop + trackH + laneGap }
    private var audioTop: CGFloat { titleTop + laneH + laneGap }
    private func audioLaneY(_ index: Int) -> CGFloat { audioTop + CGFloat(index) * (laneH + laneGap) }
    private var audioLaneCount: Int { max(1, packedAudioLanes().count) }
    private var contentHeight: CGFloat { audioTop + CGFloat(audioLaneCount) * (laneH + laneGap) + 6 }

    /// A clip's on-timeline length (its source length; a small default until the duration loads).
    private func audioBlockDuration(_ c: AudioClip) -> Double { c.sourceDuration > 0 ? c.sourceDuration : 4 }

    /// Greedy-pack audio clips (sorted by start) into non-overlapping lanes so multiple music +
    /// voiceover clips stack into as many rows as needed.
    private func packedAudioLanes() -> [[AudioClip]] {
        let sorted = state.audioClips.sorted { $0.startSeconds < $1.startSeconds }
        var lanes: [[AudioClip]] = []
        var laneEnds: [Double] = []
        for c in sorted {
            let start = c.startSeconds, end = start + audioBlockDuration(c)
            if let li = laneEnds.firstIndex(where: { $0 <= start + 0.001 }) {
                lanes[li].append(c); laneEnds[li] = end
            } else {
                lanes.append([c]); laneEnds.append(end)
            }
        }
        return lanes
    }

    // Drag state
    private enum Drag {
        case none, scrub, marquee
        case trimLeft(UUID), trimRight(UUID), move(UUID)
        case fadeIn(UUID), fadeOut(UUID), transition(UUID)
        case moveOverlay(UUID), moveAudio(UUID)            // single lane block (titles / audio)
        case moveSelection(UUID)                           // multi-move all selected FREE elements
    }
    private var drag: Drag = .none
    private var dragStartX: CGFloat = 0
    private var dragStartValue: Double = 0      // fade/transition seconds (or grab offset) at mouseDown
    private var trimRestSeconds: Double = 0     // the timeline edge a trim handle started ON (snap-exclude it)
    private var dragMoved = false
    private var pendingCheckpoint = false       // record ONE undo step on the first drag move
    private var lastDragP: NSPoint = .zero       // latest drag position (committed on mouseUp)
    private var lastEditDragTime: CFTimeInterval = 0   // throttle clock for edit drags
    private var contextClipID: UUID?
    private var contextAudioID: UUID?
    private var contextOverlayID: UUID?
    private var contextSeconds: Double = 0
    // Multi-selection drag + marquee
    private var marqueeStart: NSPoint = .zero
    private var marqueeAdditive = false
    private var marqueeLayer: CALayer?
    private var dragOrigins: [UUID: Double] = [:]   // selected free elements' original starts
    private var dragAnchorOrigin: Double = 0        // the grabbed element's original start
    private var clickToCollapse: UUID?              // click (no drag) on a multi-selected member → select only it

    init(model: EditorModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    func render(_ s: State) {
        state = s
        let w = max(minWidth, CGFloat(s.totalDuration * s.pps) + 40)
        if abs(frame.width - w) > 0.5 || abs(frame.height - contentHeight) > 0.5 {
            setFrameSize(NSSize(width: w, height: contentHeight))
        }
        let sig = structuralSignature(s)
        if sig != lastStructuralSig {
            lastStructuralSig = sig
            rebuildLayers()
        }
        positionPlayhead()
    }

    private func structuralSignature(_ s: State) -> Int {
        var h = Hasher()
        for id in s.selectedIDs { h.combine(id) }; h.combine(s.primaryID); h.combine(s.pps); h.combine(s.totalDuration)
        for c in s.clips {
            h.combine(c.id); h.combine(c.timelineStart.value); h.combine(c.sourceRange.duration.value)
            h.combine(c.fadeInSeconds); h.combine(c.fadeOutSeconds); h.combine(c.transitionInSeconds)
        }
        for m in s.markers { h.combine(m) }
                for o in s.overlays { h.combine(o.id); h.combine(o.timelineRange.start.value)
            h.combine(o.timelineRange.duration.value); h.combine(o.text) }
        for a in s.audioClips { h.combine(a.id); h.combine(a.startSeconds)
            h.combine(a.sourceDuration); h.combine(a.displayName); h.combine(a.kind) }
        var thumbX = 0, prepX = 0
        for (k, v) in s.thumbnails { thumbX ^= k.hashValue &* 31 &+ v.count }
        for (k, v) in s.prep { prepX ^= k.hashValue &* 17 &+ (v == .ready ? 2 : v == .caching ? 1 : 3) }
        h.combine(thumbX); h.combine(prepX)
        return h.finalize()
    }

    private func positionPlayhead() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playheadLayer?.frame = CGRect(x: x(state.playhead), y: 0, width: 2, height: bounds.height)
        CATransaction.commit()
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
            label.string = timecode(t); label.fontSize = 10
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
            container.borderWidth = state.selectedIDs.contains(clip.id) ? 2 : 1
            container.borderColor = (state.selectedIDs.contains(clip.id)
                ? NSColor.controlAccentColor : NSColor(white: 0.3, alpha: 1)).cgColor

            if let thumbs = state.thumbnails[clip.id], !thumbs.isEmpty {
                let tw = cw / CGFloat(thumbs.count)
                for (i, img) in thumbs.enumerated() {
                    let frame = CALayer()
                    frame.contents = img; frame.contentsGravity = .resizeAspectFill
                    frame.masksToBounds = true
                    frame.frame = CGRect(x: CGFloat(i) * tw, y: 0, width: tw + 1, height: trackH)
                    container.addSublayer(frame)
                }
            }

            let label = CATextLayer()
            label.string = "  " + clip.label; label.fontSize = 11
            label.foregroundColor = NSColor.white.cgColor; label.contentsScale = 2
            label.truncationMode = .end
            label.frame = CGRect(x: 0, y: 2, width: cw, height: 16)
            let labelBG = CALayer()
            labelBG.frame = CGRect(x: 0, y: 0, width: cw, height: 20)
            labelBG.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
            container.addSublayer(labelBG); container.addSublayer(label)

            switch state.prep[clip.id] {
            case .caching where (state.thumbnails[clip.id]?.isEmpty ?? true):
                container.addSublayer(centeredText("Caching…", width: cw, color: NSColor(white: 0.85, alpha: 1)))
            case .failed(let reason):
                let tint = CALayer()
                tint.frame = CGRect(x: 0, y: 0, width: cw, height: trackH)
                tint.backgroundColor = NSColor.systemRed.withAlphaComponent(0.22).cgColor
                container.addSublayer(tint)
                container.addSublayer(centeredText("⚠ \(reason) — click to retry", width: cw, color: .white))
            default: break
            }

            // Fade ramps drawn as translucent wedges from the top corners, + a draggable dot
            // at the end of each ramp (classic NLE fade handle).
            addFade(to: container, clipW: cw, seconds: clip.fadeInSeconds, isIn: true)
            addFade(to: container, clipW: cw, seconds: clip.fadeOutSeconds, isIn: false)

            // Trim handles (full height, below the fade band).
            for hx in [CGFloat(0), cw - handleW] {
                let h = CALayer()
                h.frame = CGRect(x: hx, y: fadeBandH, width: handleW, height: trackH - fadeBandH)
                let on = state.selectedIDs.contains(clip.id)
                h.backgroundColor = (on ? NSColor.controlAccentColor : NSColor(white: 0.5, alpha: 0.6)).cgColor
                container.addSublayer(h)
            }
            layer.addSublayer(container)
        }

        // Cross-dissolve handles at each junction (the incoming clip overlaps the previous).
        for (i, clip) in state.clips.enumerated() where i > 0 {
            let jx = x(clip.timelineStart.seconds)               // overlap region starts here
            let diamond = CALayer()
            let sz: CGFloat = 14
            diamond.frame = CGRect(x: jx - sz / 2, y: trackTop + trackH / 2 - sz / 2, width: sz, height: sz)
            diamond.backgroundColor = (clip.transitionInSeconds > 0
                ? NSColor.systemPurple : NSColor(white: 0.6, alpha: 0.8)).cgColor
            diamond.cornerRadius = 3
            diamond.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
            diamond.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
            diamond.borderWidth = 1
            layer.addSublayer(diamond)
        }

        // Lanes below the video track: a TITLES lane + a packed stack of audio lanes (multi-track).
        // Each block sits at its start time and is draggable to retime independently of the video.
        addLane(y: titleTop, label: "TITLES", on: layer)
        for ov in state.overlays {
            layer.addSublayer(laneBlock(x: x(ov.timelineRange.start.seconds), y: titleTop,
                w: max(6, x(ov.timelineRange.duration.seconds)),
                fill: NSColor.systemIndigo, selected: state.selectedIDs.contains(ov.id),
                text: ov.text.isEmpty ? "Text" : ov.text))
        }
        let lanes = packedAudioLanes()
        if lanes.isEmpty {
            addLane(y: audioTop, label: "AUDIO", on: layer)
        } else {
            for (li, laneClips) in lanes.enumerated() {
                let y = audioLaneY(li)
                addLane(y: y, label: li == 0 ? "AUDIO" : "", on: layer)
                for c in laneClips {
                    layer.addSublayer(laneBlock(x: x(c.startSeconds), y: y,
                        w: max(6, x(audioBlockDuration(c))),
                        fill: c.kind == .music ? NSColor.systemGreen : NSColor.systemOrange,
                        selected: state.selectedIDs.contains(c.id), text: c.displayName))
                }
            }
        }

        // Markers — vertical line + ruler flag.
        for m in state.markers {
            let mx = x(m)
            let line = CALayer()
            line.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.8).cgColor
            line.frame = CGRect(x: mx, y: rulerH, width: 1, height: bounds.height - rulerH)
            layer.addSublayer(line)
            let flag = CALayer()
            flag.backgroundColor = NSColor.systemTeal.cgColor
            flag.frame = CGRect(x: mx, y: rulerH - 8, width: 8, height: 8)
            layer.addSublayer(flag)
        }

        let ph = CALayer()
        ph.backgroundColor = NSColor.systemRed.cgColor
        layer.addSublayer(ph)
        playheadLayer = ph
    }

    /// A fade wedge + handle dot inside a clip container (local coords).
    private func addFade(to container: CALayer, clipW: CGFloat, seconds: Double, isIn: Bool) {
        let fw = min(clipW, x(seconds))
        let dotX = isIn ? fw : clipW - fw
        if fw > 1 {
            let wedge = CAShapeLayer()
            let fill = CGMutablePath(), line = CGMutablePath()
            if isIn {
                fill.move(to: .init(x: 0, y: trackH)); fill.addLine(to: .init(x: fw, y: 0)); fill.addLine(to: .init(x: 0, y: 0)); fill.closeSubpath()
                line.move(to: .init(x: 0, y: trackH)); line.addLine(to: .init(x: fw, y: 0))   // ramp up
            } else {
                fill.move(to: .init(x: clipW, y: trackH)); fill.addLine(to: .init(x: clipW - fw, y: 0)); fill.addLine(to: .init(x: clipW, y: 0)); fill.closeSubpath()
                line.move(to: .init(x: clipW - fw, y: 0)); line.addLine(to: .init(x: clipW, y: trackH))  // ramp down
            }
            wedge.path = fill
            wedge.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
            container.addSublayer(wedge)
            // A visible yellow ramp line (the wedge fill alone disappears on a dark clip).
            let stroke = CAShapeLayer()
            stroke.path = line
            stroke.strokeColor = NSColor.systemYellow.withAlphaComponent(0.9).cgColor
            stroke.lineWidth = 1.5; stroke.fillColor = nil
            container.addSublayer(stroke)
        }
        let dot = CALayer()
        dot.frame = CGRect(x: dotX - 4, y: 0, width: 8, height: 8)
        dot.cornerRadius = 4
        dot.backgroundColor = NSColor.systemYellow.cgColor
        container.addSublayer(dot)
    }

    private func centeredText(_ s: String, width: CGFloat, color: NSColor) -> CATextLayer {
        let t = CATextLayer()
        t.string = s; t.fontSize = 11; t.foregroundColor = color.cgColor
        t.alignmentMode = .center; t.truncationMode = .end; t.contentsScale = 2
        t.frame = CGRect(x: 4, y: trackH / 2 - 8, width: max(0, width - 8), height: 16)
        return t
    }

    /// A faint lane background strip + a left-edge label.
    private func addLane(y: CGFloat, label: String, on layer: CALayer) {
        let bg = CALayer()
        bg.frame = CGRect(x: 0, y: y, width: max(bounds.width, frame.width), height: laneH)
        bg.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        layer.addSublayer(bg)
        let lbl = CATextLayer()
        lbl.string = label; lbl.fontSize = 8; lbl.foregroundColor = NSColor(white: 0.45, alpha: 1).cgColor
        lbl.contentsScale = 2
        lbl.frame = CGRect(x: 4, y: y + 6, width: 80, height: 11)
        layer.addSublayer(lbl)
    }

    /// A draggable block on a lane (a title / music / voiceover block).
    private func laneBlock(x: CGFloat, y: CGFloat, w: CGFloat, fill: NSColor, selected: Bool, text: String) -> CALayer {
        let block = CALayer()
        block.frame = CGRect(x: x, y: y + 2, width: w, height: laneH - 4)
        block.backgroundColor = fill.withAlphaComponent(0.85).cgColor
        block.cornerRadius = 4
        block.borderWidth = selected ? 2 : 0
        block.borderColor = NSColor.controlAccentColor.cgColor
        block.masksToBounds = true
        let lbl = CATextLayer()
        lbl.string = "  " + text; lbl.fontSize = 10; lbl.foregroundColor = NSColor.white.cgColor
        lbl.contentsScale = 2; lbl.truncationMode = .end
        lbl.frame = CGRect(x: 0, y: 1, width: max(0, w), height: 13)
        block.addSublayer(lbl)
        return block
    }

    private func rulerStep(for pps: Double) -> Double {
        let target = 80.0 / pps
        for s in [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300] where Double(s) >= target { return Double(s) }
        return 600
    }
    private func timecode(_ s: Double) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }

    // MARK: interaction

    /// Hit-test a point to a drag region. Fade dots (top band) and junction diamonds take
    /// priority over trim/body.
    private func hit(at p: NSPoint) -> Drag {
        // Lane blocks (titles / audio) — below the video track, each in its own y band.
        if p.y >= titleTop, p.y <= titleTop + laneH {
            for ov in state.overlays {
                let bx = x(ov.timelineRange.start.seconds), bw = max(6, x(ov.timelineRange.duration.seconds))
                if p.x >= bx, p.x <= bx + bw { return .moveOverlay(ov.id) }
            }
            return .none
        }
        if p.y >= audioTop {
            let lanes = packedAudioLanes()
            let li = Int((p.y - audioTop) / (laneH + laneGap))
            if li >= 0, li < lanes.count {
                for c in lanes[li] {
                    let bx = x(c.startSeconds), bw = max(6, x(audioBlockDuration(c)))
                    if p.x >= bx, p.x <= bx + bw { return .moveAudio(c.id) }
                }
            }
            return .none
        }
        // Junction dissolve diamonds (in the mid-track band).
        if p.y >= trackTop + trackH / 2 - 10, p.y <= trackTop + trackH / 2 + 10 {
            for (i, clip) in state.clips.enumerated() where i > 0 {
                if abs(p.x - x(clip.timelineStart.seconds)) <= 9 { return .transition(clip.id) }
            }
        }
        guard p.y >= trackTop, p.y <= trackTop + trackH else { return .none }
        for clip in state.clips {
            let cx = x(clip.timelineStart.seconds)
            let cw = x(clip.sourceRange.duration.seconds)
            guard p.x >= cx, p.x <= cx + cw else { continue }
            // Fade handle dots live in the top band at the ramp end.
            if p.y <= trackTop + fadeBandH {
                let inX = cx + min(cw, x(clip.fadeInSeconds))
                let outX = cx + cw - min(cw, x(clip.fadeOutSeconds))
                if abs(p.x - inX) <= 7 { return .fadeIn(clip.id) }
                if abs(p.x - outX) <= 7 { return .fadeOut(clip.id) }
            }
            if p.x <= cx + handleW { return .trimLeft(clip.id) }
            if p.x >= cx + cw - handleW { return .trimRight(clip.id) }
            return .move(clip.id)
        }
        return .none
    }

    private func clip(_ id: UUID) -> TimelineClip? { state.clips.first { $0.id == id } }

    /// The element id a drag region refers to (nil for scrub/marquee/empty).
    private func elementID(of d: Drag) -> UUID? {
        switch d {
        case .trimLeft(let i), .trimRight(let i), .move(let i), .fadeIn(let i), .fadeOut(let i),
             .transition(let i), .moveOverlay(let i), .moveAudio(let i), .moveSelection(let i): return i
        case .none, .scrub, .marquee: return nil
        }
    }
    /// A FREE element's start time on the timeline (overlay / audio); nil for a magnetic clip.
    private func freeStart(of id: UUID) -> Double? {
        if let o = state.overlays.first(where: { $0.id == id }) { return o.timelineRange.start.seconds }
        if let a = state.audioClips.first(where: { $0.id == id }) { return a.startSeconds }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        dragStartX = p.x; dragMoved = false; clickToCollapse = nil
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        // The ruler band drives the playhead (drag to scrub), independent of selection.
        if p.y < rulerH { drag = .scrub; model.seek(toSeconds: snapSeconds(p.x)); return }

        let h = hit(at: p)
        let hitID = elementID(of: h)

        // ⌘-click toggles, ⇧-click extends — no drag, no scrub.
        if let id = hitID {
            if cmd { model.toggleSelected(id); drag = .none; return }
            if shift { model.addSelected(id); drag = .none; return }
        }

        switch h {
        case .none:
            // Empty area → rubber-band marquee on drag, clear-selection + seek on a plain click.
            marqueeStart = p; marqueeAdditive = cmd || shift; drag = .marquee
        case .trimLeft(let id), .trimRight(let id), .fadeIn(let id), .fadeOut(let id), .transition(let id):
            model.selectOnly(id)
            if case .failed = state.prep[id] { model.retryClip(id); drag = .none; return }
            switch h {
            case .fadeIn(let i):     dragStartValue = clip(i)?.fadeInSeconds ?? 0
            case .fadeOut(let i):    dragStartValue = clip(i)?.fadeOutSeconds ?? 0
            case .transition(let i): dragStartValue = clip(i)?.transitionInSeconds ?? 0
            // Anchor the clip's IN-point at grab so a trim is computed from a FIXED reference, not
            // the already-trimmed live value — without this, trimLeft re-added (cursor − clipStart)
            // to an in-point that had ALREADY moved each frame, so it accelerated/stuck even when
            // the cursor was still (the asymmetry vs trimRight, whose `in` never moves). (#10)
            // Also capture the timeline edge the handle STARTS ON so snapping won't yank it back to
            // that edge — the left handle rests on the previous clip's end, which was the real
            // "sticky" cause that made the beginning of a clip impossible to fine-tune.
            case .trimLeft(let i):
                dragStartValue = clip(i)?.sourceRange.start.seconds ?? 0
                trimRestSeconds = clip(i)?.timelineStart.seconds ?? 0
            case .trimRight(let i):
                dragStartValue = clip(i)?.sourceRange.start.seconds ?? 0
                trimRestSeconds = clip(i)?.timelineRange.endSeconds ?? 0
            default: break
            }
            drag = h; pendingCheckpoint = true
        case .move(let id):
            // Magnetic clip — single reorder. If it's part of a multi-selection, keep the set
            // (drag reorders this clip); a plain click with no drag collapses to just it.
            if model.selectedIDs.contains(id) { clickToCollapse = id } else { model.selectOnly(id) }
            drag = h; pendingCheckpoint = true
        case .moveOverlay(let id), .moveAudio(let id):
            if model.selectedIDs.contains(id) && model.selectedIDs.count > 1 {
                // Drag the WHOLE selection (all free elements) together.
                dragOrigins = Dictionary(uniqueKeysWithValues: model.selectedIDs.compactMap { i in
                    freeStart(of: i).map { (i, $0) } })
                dragAnchorOrigin = freeStart(of: id) ?? seconds(p.x)
                dragStartValue = seconds(p.x) - dragAnchorOrigin   // grab offset
                clickToCollapse = id
                drag = .moveSelection(id); pendingCheckpoint = true
            } else {
                model.selectOnly(id)
                if case .moveOverlay = h, let ov = state.overlays.first(where: { $0.id == id }) {
                    let t = model.playheadSeconds
                    // Seek into the overlay's range so the program monitor SHOWS it (you can only
                    // drag the text on screen while it's rendered).
                    if t < ov.timelineRange.start.seconds || t > ov.timelineRange.endSeconds {
                        model.seek(toSeconds: ov.timelineRange.start.seconds + 0.1)
                    }
                    dragStartValue = seconds(p.x) - ov.timelineRange.start.seconds
                } else {
                    dragStartValue = seconds(p.x) - (state.audioClips.first { $0.id == id }?.startSeconds ?? 0)
                }
                drag = h; pendingCheckpoint = true
            }
        default: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastDragP = p
        // Scrubbing stays fully smooth (a seek is cheap + doesn't rebuild the timeline). EDIT drags
        // (trim / fade / move / lanes) each mutate the model → a full timeline rebuild, so coalesce
        // them to ~30fps — a trackpad fires 120+ events/sec and the pile-up is the "laggy" feel.
        if case .scrub = drag { applyDrag(p); return }
        // Marquee: draw the rubber band live (no model change → no rebuild → the band persists);
        // the selection itself is committed on mouseUp.
        if case .marquee = drag {
            if abs(p.x - marqueeStart.x) > 3 || abs(p.y - marqueeStart.y) > 3 { dragMoved = true }
            drawMarquee(to: p); return
        }
        let now = CACurrentMediaTime()
        guard now - lastEditDragTime >= 0.033 else { return }
        lastEditDragTime = now
        if pendingCheckpoint { model.checkpoint(); pendingCheckpoint = false }   // one undo step per drag
        applyDrag(p)
    }

    // MARK: marquee (rubber-band selection)

    private func marqueeRect(to p: NSPoint) -> CGRect {
        CGRect(x: min(marqueeStart.x, p.x), y: min(marqueeStart.y, p.y),
               width: abs(p.x - marqueeStart.x), height: abs(p.y - marqueeStart.y))
    }
    private func drawMarquee(to p: NSPoint) {
        if marqueeLayer == nil {
            let l = CALayer()
            l.borderColor = NSColor.controlAccentColor.cgColor
            l.borderWidth = 1
            l.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer?.addSublayer(l); marqueeLayer = l
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        marqueeLayer?.frame = marqueeRect(to: p)
        CATransaction.commit()
    }
    /// Every element (clip / overlay / audio) whose on-screen rect intersects the marquee.
    private func marqueeHits(_ r: CGRect) -> Set<UUID> {
        var ids = Set<UUID>()
        for c in state.clips {
            let cr = CGRect(x: x(c.timelineStart.seconds), y: trackTop,
                            width: max(2, x(c.sourceRange.duration.seconds)), height: trackH)
            if cr.intersects(r) { ids.insert(c.id) }
        }
        for o in state.overlays {
            let orr = CGRect(x: x(o.timelineRange.start.seconds), y: titleTop,
                             width: max(2, x(o.timelineRange.duration.seconds)), height: laneH)
            if orr.intersects(r) { ids.insert(o.id) }
        }
        for (li, laneClips) in packedAudioLanes().enumerated() {
            let y = audioLaneY(li)
            for c in laneClips {
                let ar = CGRect(x: x(c.startSeconds), y: y, width: max(2, x(audioBlockDuration(c))), height: laneH)
                if ar.intersects(r) { ids.insert(c.id) }
            }
        }
        return ids
    }
    private func endMarquee() {
        marqueeLayer?.removeFromSuperlayer(); marqueeLayer = nil
    }

    private func applyDrag(_ p: NSPoint) {
        switch drag {
        case .scrub:
            model.seek(toSeconds: snapSeconds(p.x))
        case .trimLeft(let id):
            guard let c = clip(id) else { return }
            // Source time at the cursor = anchored-in + (cursor − clip start). dragStartValue is the
            // in-point captured at grab (FIXED), so holding the cursor still holds the trim still (#10).
            // Snapping excludes THIS clip's own edges so the handle doesn't stick to where it sits.
            let cursorSrc = dragStartValue + (snapTrim(p.x, id) - c.timelineStart.seconds)
            model.trim(id, newInSeconds: cursorSrc)
        case .trimRight(let id):
            guard let c = clip(id) else { return }
            let cursorSrc = dragStartValue + (snapTrim(p.x, id) - c.timelineStart.seconds)
            model.trim(id, newOutSeconds: cursorSrc)
        case .fadeIn(let id):
            guard let c = clip(id) else { return }
            model.setClipFade(id, fadeIn: max(0, seconds(p.x) - c.timelineStart.seconds))
        case .fadeOut(let id):
            guard let c = clip(id) else { return }
            model.setClipFade(id, fadeOut: max(0, c.timelineRange.endSeconds - seconds(p.x)))
        case .transition(let id):
            // Drag LEFT = more overlap. Delta from the mousedown position.
            let deltaSec = seconds(dragStartX) - seconds(p.x)
            model.setClipTransition(id, dragStartValue + deltaSec)
        case .move(let id):
            if !dragMoved && abs(p.x - dragStartX) < 4 { return }
            dragMoved = true
            var target = 0
            for c in state.clips where c.id != id {
                let center = x(c.timelineStart.seconds) + x(c.sourceRange.duration.seconds) / 2
                if p.x > center { target += 1 } else { break }
            }
            model.moveClip(id, toIndex: target)
        case .moveOverlay(let id):
            model.setOverlayStart(id, seconds: max(0, model.snap(seconds(p.x) - dragStartValue)))
        case .moveAudio(let id):
            model.setAudioStart(id, max(0, model.snap(seconds(p.x) - dragStartValue)))
        case .moveSelection:
            if !dragMoved && abs(p.x - dragStartX) < 4 { return }
            dragMoved = true
            // Move every selected FREE element by the same Δt (anchored on the grabbed one).
            let desiredAnchor = max(0, model.snap(seconds(p.x) - dragStartValue))
            model.moveSelectedFreeElements(byDelta: desiredAnchor - dragAnchorOrigin, origins: dragOrigins)
        case .marquee, .none: break
        }
    }

    /// Scrub seconds with snapping to edit points (clip edges / markers / 0).
    private func snapSeconds(_ px: CGFloat) -> Double { model.snap(seconds(px)) }
    /// Trim snapping — snaps to OTHER clips' edges / markers / playhead you drag TOWARD, but never
    /// this clip's own edges (excluding: id) nor the edge the handle STARTED on (excludingNear:),
    /// which sits right under the handle and otherwise snaps back on every small move (sticky).
    private func snapTrim(_ px: CGFloat, _ id: UUID) -> Double {
        model.snap(seconds(px), excluding: id, excludingNear: trimRestSeconds)
    }

    override func mouseUp(with event: NSEvent) {
        // Marquee: commit the selection (rubber band → intersecting elements), or — if it never
        // moved — treat as a plain click in empty space: clear the selection + seek there.
        if case .marquee = drag {
            if dragMoved { model.setSelectedIDs(marqueeHits(marqueeRect(to: lastDragP)), additive: marqueeAdditive) }
            else { model.clearSelection(); model.seek(toSeconds: snapSeconds(dragStartX)) }
            endMarquee(); drag = .none; return
        }
        // Land exactly where released — coalescing may have skipped the final move.
        switch drag {
        case .none, .scrub: break
        case .move where !dragMoved: break              // a click-select, not a move
        case .moveSelection where !dragMoved: break     // a click on a selected member, not a move
        default: applyDrag(lastDragP)
        }
        // A plain click (no drag) on a member of a multi-selection collapses to just that element.
        if !dragMoved, let id = clickToCollapse { model.selectOnly(id) }
        if case .move = drag, !dragMoved { model.seek(toSeconds: snapSeconds(dragStartX)) }
        drag = .none; clickToCollapse = nil
    }

    // MARK: right-click context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let h = hit(at: p)
        // If the right-click lands on a member of a MULTI-selection, offer a bulk "Delete N items".
        if let hid = elementID(of: h), model.selectedIDs.contains(hid), model.selectedIDs.count > 1 {
            let m = NSMenu()
            let del = NSMenuItem(title: "Delete \(model.selectedIDs.count) Items",
                                 action: #selector(ctxDeleteSelection), keyEquivalent: "")
            del.target = self; m.addItem(del)
            return m
        }
        // Audio clip right-click: select it + a Delete item (its full edit set lives in the inspector).
        if case .moveAudio(let aid) = h, let a = state.audioClips.first(where: { $0.id == aid }) {
            model.selectOnly(aid)
            contextAudioID = aid
            let m = NSMenu()
            let del = NSMenuItem(title: "Delete \(a.kind.label)", action: #selector(ctxDeleteAudio), keyEquivalent: "")
            del.target = self; m.addItem(del)
            return m
        }
        // Text overlay right-click: select it + Delete (its full edit set lives in the inspector).
        if case .moveOverlay(let oid) = h {
            model.selectOnly(oid)
            contextOverlayID = oid
            let m = NSMenu()
            let del = NSMenuItem(title: "Delete Title", action: #selector(ctxDeleteOverlay), keyEquivalent: "")
            del.target = self; m.addItem(del)
            return m
        }
        var id: UUID?
        switch h {
        case .trimLeft(let i), .trimRight(let i), .move(let i), .fadeIn(let i), .fadeOut(let i), .transition(let i): id = i
        default: id = nil
        }
        guard let id, let c = clip(id) else { return nil }
        model.selectOnly(id)
        contextClipID = id; contextSeconds = seconds(p.x)
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        add("Split Here", #selector(ctxSplit))
        add(c.audioVolume == 0 ? "Unmute Audio" : "Mute Audio", #selector(ctxMute))
        add("Duplicate", #selector(ctxDuplicate))
        if c.fadeInSeconds > 0 || c.fadeOutSeconds > 0 { add("Clear Fades", #selector(ctxClearFades)) }
        if c.transitionInSeconds > 0 { add("Clear Dissolve", #selector(ctxClearTransition)) }
        menu.addItem(.separator())
        add("Delete Clip", #selector(ctxDelete))
        return menu
    }

    @objc private func ctxSplit() { if let id = contextClipID { model.splitClip(id, atTimelineSeconds: contextSeconds) } }
    @objc private func ctxDuplicate() { if let id = contextClipID { model.duplicateClip(id) } }
    @objc private func ctxDelete() { if let id = contextClipID { model.deleteClip(id) } }
    @objc private func ctxDeleteAudio() { if let id = contextAudioID { model.removeAudio(id) } }
    @objc private func ctxDeleteOverlay() { if let id = contextOverlayID { model.deleteOverlay(id) } }
    @objc private func ctxDeleteSelection() { model.deleteSelection() }
    @objc private func ctxClearFades() { if let id = contextClipID { model.checkpoint(); model.setClipFade(id, fadeIn: 0, fadeOut: 0) } }
    @objc private func ctxClearTransition() { if let id = contextClipID { model.checkpoint(); model.setClipTransition(id, 0) } }
    @objc private func ctxMute() {
        if let id = contextClipID, let c = clip(id) { model.checkpoint(); model.setClipVolume(id, c.audioVolume == 0 ? 1 : 0) }
    }

    // The standard Edit-menu Copy/Paste (⌘C/⌘V) route here while the timeline is first responder.
    @objc func copy(_ sender: Any?) { model.copySelected() }
    @objc func paste(_ sender: Any?) { model.paste() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): return model.selectedClipID != nil
        case #selector(paste(_:)): return model.hasClipboard
        default: return true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            model.zoom(by: 1 + Double(event.scrollingDeltaY) * 0.01, focusSeconds: seconds(convert(event.locationInWindow, from: nil).x))
        } else {
            super.scrollWheel(with: event)
        }
    }

    // Trackpad PINCH zoom (the magnify gesture) — drives points-per-second around the pinch point.
    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        model.zoom(by: 1 + Double(event.magnification), focusSeconds: seconds(p.x))
    }

    // Cursor feedback so it's clear WHAT you're about to grab (trim edge / fade / transition / move).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        guard case .none = drag else { return }   // keep the grab cursor during a drag
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .trimLeft, .trimRight:                       NSCursor.resizeLeftRight.set()
        case .fadeIn, .fadeOut, .transition:              NSCursor.pointingHand.set()
        case .move, .moveOverlay, .moveAudio, .moveSelection: NSCursor.openHand.set()
        default:                                          NSCursor.arrow.set()
        }
    }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    // Keyboard transport + editing, mapped to Final Cut Pro muscle memory where we have the command
    // (#11). Space play/pause; ←/→ step one frame (⇧ = 1 s, ⌘ = start/end); ↑/↓ jump edit points;
    // B blade at playhead; M marker; J/K/L play controls; +/− zoom; ⌫ delete; ⌘A select-all.
    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        if cmd, event.charactersIgnoringModifiers == "a" { model.selectAll(); return }
        switch event.charactersIgnoringModifiers {
        case " ": model.togglePlay()
        case "\u{F702}":   // ← left arrow
            if cmd { model.goToStart() } else { model.nudgePlayhead(seconds: shift ? -1 : -model.frameStep) }
        case "\u{F703}":   // → right arrow
            if cmd { model.goToEnd() } else { model.nudgePlayhead(seconds: shift ? 1 : model.frameStep) }
        case "\u{F700}": model.goToEdit(forward: false)    // ↑ previous edit point (FCP)
        case "\u{F701}": model.goToEdit(forward: true)     // ↓ next edit point (FCP)
        case "b", "B": model.splitAtPlayhead()             // blade at playhead (FCP B)
        case "m", "M": model.toggleMarkerAtPlayhead()      // marker (FCP M)
        case "l", "L": model.play()                        // FCP L = play forward
        case "k", "K": model.pause()                       // FCP K = pause
        case "j", "J": model.pause()                       // FCP J = reverse (no reverse playback → pause)
        case "+", "=": model.zoom(by: 1.25)                // zoom in
        case "-", "_": model.zoom(by: 0.8)                 // zoom out
        case ",": model.goToMarker(forward: false)
        case ".": model.goToMarker(forward: true)
        case "\u{1B}": model.clearSelection()              // Esc deselects
        case String(UnicodeScalar(NSDeleteCharacter)!), String(UnicodeScalar(NSBackspaceCharacter)!):
            model.deleteSelection()                        // deletes the WHOLE multi-selection
        default:
            switch event.keyCode {
            case 51:  model.deleteSelection()              // forward-delete
            case 115: model.goToStart()                    // Home
            case 119: model.goToEnd()                      // End
            default:  super.keyDown(with: event)
            }
        }
    }
}
#endif
