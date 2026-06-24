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
        // Reading these makes SwiftUI re-call updateNSView when they change (observation).
        let state = TimelineContentView.State(
            clips: model.clips, pps: model.pointsPerSecond, selectedID: model.selectedClipID,
            playhead: model.playheadSeconds, thumbnails: model.thumbnails,
            totalDuration: model.totalDuration, prep: model.clipPrep, markers: model.markers,
            overlays: model.textOverlays, music: model.musicBed, voiceover: model.voiceover,
            selectedOverlayID: model.selectedOverlayID)
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
        let prep: [UUID: EditorModel.ClipPrep]
        let markers: [Double]
        var overlays: [TextOverlay] = []
        var music: MusicBed? = nil
        var voiceover: MusicBed? = nil
        var selectedOverlayID: UUID? = nil
    }

    private let model: EditorModel
    private var state = State(clips: [], pps: 60, selectedID: nil, playhead: 0, thumbnails: [:], totalDuration: 0, prep: [:], markers: [])
    private var playheadLayer: CALayer?
    private var lastStructuralSig = 0

    private let rulerH: CGFloat = 26
    private let trackTop: CGFloat = 30
    private let trackH: CGFloat = 76           // video lane (shrunk to make room for the lanes below)
    private let handleW: CGFloat = 8
    private let fadeBandH: CGFloat = 16        // top band where fade handles live
    private let minWidth: CGFloat = 400
    // Lanes below the video track: a TITLES lane + MUSIC + VOICEOVER audio lanes (multi-track).
    private let laneGap: CGFloat = 3
    private let laneH: CGFloat = 22
    private var titleTop: CGFloat { trackTop + trackH + laneGap }
    private var musicTop: CGFloat { titleTop + laneH + laneGap }
    private var voiceTop: CGFloat { musicTop + laneH + laneGap }
    private var contentHeight: CGFloat { voiceTop + laneH + 6 }

    // Drag state
    private enum Drag {
        case none, scrub
        case trimLeft(UUID), trimRight(UUID), move(UUID)
        case fadeIn(UUID), fadeOut(UUID), transition(UUID)
        case moveOverlay(UUID), moveMusic, moveVoiceover   // lane blocks (titles / audio)
    }
    private var drag: Drag = .none
    private var dragStartX: CGFloat = 0
    private var dragStartValue: Double = 0      // fade/transition seconds at mouseDown (delta drags)
    private var dragMoved = false
    private var contextClipID: UUID?
    private var contextSeconds: Double = 0

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
        h.combine(s.pps); h.combine(s.selectedID); h.combine(s.totalDuration)
        for c in s.clips {
            h.combine(c.id); h.combine(c.timelineStart.value); h.combine(c.sourceRange.duration.value)
            h.combine(c.fadeInSeconds); h.combine(c.fadeOutSeconds); h.combine(c.transitionInSeconds)
        }
        for m in s.markers { h.combine(m) }
        h.combine(s.selectedOverlayID)
        for o in s.overlays { h.combine(o.id); h.combine(o.timelineRange.start.value)
            h.combine(o.timelineRange.duration.value); h.combine(o.text) }
        if let m = s.music { h.combine(m.fileName); h.combine(m.startSeconds) }
        if let v = s.voiceover { h.combine(v.fileName); h.combine(v.startSeconds) }
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
            container.borderWidth = clip.id == state.selectedID ? 2 : 1
            container.borderColor = (clip.id == state.selectedID
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
                let on = clip.id == state.selectedID
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

        // Lanes below the video track: Titles + Music + Voiceover (the multi-track timeline).
        // Each block sits at its start time and is draggable to retime independently of the video.
        addLane(y: titleTop, label: "TITLES", on: layer)
        for ov in state.overlays {
            layer.addSublayer(laneBlock(x: x(ov.timelineRange.start.seconds), y: titleTop,
                w: max(6, x(ov.timelineRange.duration.seconds)),
                fill: NSColor.systemIndigo, selected: ov.id == state.selectedOverlayID,
                text: ov.text.isEmpty ? "Text" : ov.text))
        }
        addLane(y: musicTop, label: "MUSIC", on: layer)
        if let m = state.music {
            layer.addSublayer(laneBlock(x: x(m.startSeconds), y: musicTop,
                w: max(6, x(max(1, state.totalDuration - m.startSeconds))),
                fill: NSColor.systemGreen, selected: false, text: m.displayName))
        }
        addLane(y: voiceTop, label: "VOICEOVER", on: layer)
        if let v = state.voiceover {
            layer.addSublayer(laneBlock(x: x(v.startSeconds), y: voiceTop,
                w: max(6, x(max(1, state.totalDuration - v.startSeconds))),
                fill: NSColor.systemOrange, selected: false, text: v.displayName))
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
        if p.y >= musicTop, p.y <= musicTop + laneH {
            if let m = state.music, p.x >= x(m.startSeconds) { return .moveMusic }
            return .none
        }
        if p.y >= voiceTop, p.y <= voiceTop + laneH {
            if let v = state.voiceover, p.x >= x(v.startSeconds) { return .moveVoiceover }
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        dragStartX = p.x; dragMoved = false
        let h = hit(at: p)
        // Select the involved clip.
        switch h {
        case .trimLeft(let id), .trimRight(let id), .move(let id),
             .fadeIn(let id), .fadeOut(let id), .transition(let id):
            model.selectedClipID = id
            model.selectedOverlayID = nil
            if case .failed = state.prep[id] { model.retryClip(id); drag = .none; return }
        default: break
        }
        switch h {
        case .fadeIn(let id):     dragStartValue = clip(id)?.fadeInSeconds ?? 0
        case .fadeOut(let id):    dragStartValue = clip(id)?.fadeOutSeconds ?? 0
        case .transition(let id): dragStartValue = clip(id)?.transitionInSeconds ?? 0
        case .moveOverlay(let id):
            model.selectedOverlayID = id
            model.selectedClipID = nil
            if let ov = state.overlays.first(where: { $0.id == id }) {
                let t = model.playheadSeconds
                // Seek into the overlay's range so the program monitor actually SHOWS it (you can
                // only drag the text on screen while it's rendered) — fixes "only works while playing".
                if t < ov.timelineRange.start.seconds || t > ov.timelineRange.endSeconds {
                    model.seek(toSeconds: ov.timelineRange.start.seconds + 0.1)
                }
                dragStartValue = seconds(p.x) - ov.timelineRange.start.seconds
            }
        case .moveMusic:          dragStartValue = seconds(p.x) - (state.music?.startSeconds ?? 0)
        case .moveVoiceover:      dragStartValue = seconds(p.x) - (state.voiceover?.startSeconds ?? 0)
        case .none:               drag = .scrub; model.seek(toSeconds: snapSeconds(p.x)); return
        default: break
        }
        drag = h
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .scrub:
            model.seek(toSeconds: snapSeconds(p.x))
        case .trimLeft(let id):
            guard let c = clip(id) else { return }
            let deltaSec = snapSeconds(p.x) - c.timelineStart.seconds
            model.trim(id, newInSeconds: c.sourceRange.start.seconds + deltaSec)
        case .trimRight(let id):
            guard let c = clip(id) else { return }
            let newDur = snapSeconds(p.x) - c.timelineStart.seconds
            model.trim(id, newOutSeconds: c.sourceRange.start.seconds + newDur)
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
        case .moveMusic:
            model.setMusicStart(max(0, model.snap(seconds(p.x) - dragStartValue)))
        case .moveVoiceover:
            model.setVoiceoverStart(max(0, model.snap(seconds(p.x) - dragStartValue)))
        case .none: break
        }
    }

    /// Scrub seconds with snapping to edit points (clip edges / markers / 0).
    private func snapSeconds(_ px: CGFloat) -> Double { model.snap(seconds(px)) }

    override func mouseUp(with event: NSEvent) {
        if case .move = drag, !dragMoved { model.seek(toSeconds: snapSeconds(dragStartX)) }
        drag = .none
    }

    // MARK: right-click context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let h = hit(at: p)
        var id: UUID?
        switch h {
        case .trimLeft(let i), .trimRight(let i), .move(let i), .fadeIn(let i), .fadeOut(let i), .transition(let i): id = i
        default: id = nil
        }
        guard let id, let c = clip(id) else { return nil }
        model.selectedClipID = id
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
    @objc private func ctxClearFades() { if let id = contextClipID { model.setClipFade(id, fadeIn: 0, fadeOut: 0) } }
    @objc private func ctxClearTransition() { if let id = contextClipID { model.setClipTransition(id, 0) } }
    @objc private func ctxMute() {
        if let id = contextClipID, let c = clip(id) { model.setClipVolume(id, c.audioVolume == 0 ? 1 : 0) }
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
        case .move, .moveOverlay, .moveMusic, .moveVoiceover: NSCursor.openHand.set()
        default:                                          NSCursor.arrow.set()
        }
    }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ": model.togglePlay()
        case "b", "B": model.splitAtPlayhead()
        case "m", "M": model.toggleMarkerAtPlayhead()
        case ",": model.goToMarker(forward: false)
        case ".": model.goToMarker(forward: true)
        case String(UnicodeScalar(NSDeleteCharacter)!), String(UnicodeScalar(NSBackspaceCharacter)!):
            if let id = model.selectedClipID { model.deleteClip(id) }
        default:
            if let id = model.selectedClipID, event.keyCode == 51 { model.deleteClip(id) }
            else { super.keyDown(with: event) }
        }
    }
}
#endif
