#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation

// CapCut / iMovie-style clip timeline (Decision 033). The native idioms the
// previous custom UI got wrong (owner feedback 2026-06-16):
//   • The filmstrip SCROLLS under a FIXED center playhead — scrolling IS
//     scrubbing, and the preview shows the frame under the playhead live.
//   • Pinch to ZOOM the timeline (essential for long archive.org films).
//   • The selection is a highlighted band with drag handles, but the primary
//     way to set in/out is "Set Start / Set End at the playhead" — no
//     alternating two-handle dance.
//   • During playback the strip auto-scrolls so the playing frame stays under
//     the playhead.
// Built on a real UIScrollView for native momentum/deceleration + precise,
// programmable contentOffset (SwiftUI's ScrollView can't drive offset both
// ways cleanly). The preview uses a controls-free AVPlayerLayer so this is the
// ONLY scrubber in the editor.

// MARK: Controls-free preview (AVPlayerLayer — no AVKit transport UI)

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> Container {
        let v = Container(); v.playerLayer.player = player; return v
    }
    func updateUIView(_ uiView: Container, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
    final class Container: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

// MARK: Timeline

struct ClipTimelineView: UIViewRepresentable {
    let duration: Double
    let thumbnails: [UIImage]
    let inSeconds: Double
    let outSeconds: Double
    let playheadSeconds: Double
    let isPlaying: Bool
    let maxClip: Double
    /// User scrubbed the playhead to this time (seek preview; pause playback).
    let onScrub: (Double) -> Void
    /// A trim handle moved: (newIn, newOut, timeToPreview).
    let onTrim: (Double, Double, Double) -> Void

    func makeUIView(context: Context) -> ClipTimelineUIView {
        let v = ClipTimelineUIView()
        v.onScrub = onScrub
        v.onTrim = onTrim
        v.configure(duration: duration, maxClip: maxClip, thumbnails: thumbnails,
                    inSeconds: inSeconds, outSeconds: outSeconds)
        return v
    }

    func updateUIView(_ v: ClipTimelineUIView, context: Context) {
        v.onScrub = onScrub
        v.onTrim = onTrim
        v.maxClip = maxClip
        v.setThumbnails(thumbnails)
        v.setSelection(inSeconds: inSeconds, outSeconds: outSeconds)
        if isPlaying { v.follow(playheadSeconds) }
    }
}

final class ClipTimelineUIView: UIView, UIScrollViewDelegate {
    var onScrub: ((Double) -> Void)?
    var onTrim: ((Double, Double, Double) -> Void)?
    var maxClip: Double = 60

    private let scrollView = UIScrollView()
    private let content = UIView()
    private let band = UIView()
    private let leftHandle = UIView()
    private let rightHandle = UIView()
    private let playhead = UIView()
    private var tiles: [UIImageView] = []

    private var duration: Double = 0
    private var inSeconds: Double = 0
    private var outSeconds: Double = 0
    private var pps: CGFloat = 0                 // points per second (zoom)
    private let stripHeight: CGFloat = 64
    private let handleW: CGFloat = 22

    private var isProgrammatic = false           // suppress onScrub during code-driven scroll
    private var isHandleDragging = false
    private var didInitialScroll = false
    private var pinchStartPps: CGFloat = 0
    private var pinchCenterTime: Double = 0

    private let accent = UIColor(red: 1.0, green: 0.36, blue: 0.21, alpha: 1) // Brand marquee orange

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .normal
        scrollView.delegate = self
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        content.backgroundColor = UIColor(white: 0.08, alpha: 1)
        scrollView.addSubview(content)

        band.backgroundColor = accent.withAlphaComponent(0.18)
        band.layer.borderColor = accent.cgColor
        band.layer.borderWidth = 3
        band.layer.cornerRadius = 6
        band.isUserInteractionEnabled = false
        content.addSubview(band)

        for h in [leftHandle, rightHandle] {
            h.backgroundColor = accent
            h.layer.cornerRadius = 5
            let grip = UIView()
            grip.backgroundColor = .white
            grip.layer.cornerRadius = 1
            grip.translatesAutoresizingMaskIntoConstraints = false
            h.addSubview(grip)
            NSLayoutConstraint.activate([
                grip.centerXAnchor.constraint(equalTo: h.centerXAnchor),
                grip.centerYAnchor.constraint(equalTo: h.centerYAnchor),
                grip.widthAnchor.constraint(equalToConstant: 2),
                grip.heightAnchor.constraint(equalToConstant: 22)
            ])
            content.addSubview(h)
        }
        leftHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panLeft)))
        rightHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panRight)))

        playhead.backgroundColor = .white
        playhead.layer.cornerRadius = 1.5
        playhead.layer.shadowColor = UIColor.black.cgColor
        playhead.layer.shadowOpacity = 0.6
        playhead.layer.shadowRadius = 2
        playhead.isUserInteractionEnabled = false
        addSubview(playhead)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        scrollView.addGestureRecognizer(pinch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(duration: Double, maxClip: Double, thumbnails: [UIImage],
                   inSeconds: Double, outSeconds: Double) {
        self.duration = max(duration, 0.001)
        self.maxClip = maxClip
        self.inSeconds = inSeconds
        self.outSeconds = outSeconds
        setThumbnails(thumbnails)
        setNeedsLayout()
    }

    func setThumbnails(_ thumbs: [UIImage]) {
        guard thumbs.count != tiles.count || tiles.isEmpty else {
            for (i, t) in thumbs.enumerated() where i < tiles.count { tiles[i].image = t }
            return
        }
        tiles.forEach { $0.removeFromSuperview() }
        tiles = thumbs.map { img in
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            content.insertSubview(iv, belowSubview: band)
            return iv
        }
        setNeedsLayout()
    }

    func setSelection(inSeconds: Double, outSeconds: Double) {
        guard !isHandleDragging else { return }
        self.inSeconds = inSeconds
        self.outSeconds = outSeconds
        layoutSelection()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        scrollView.frame = bounds
        if pps == 0 {
            // Default zoom: show ~24s (or the whole film if shorter) across the width.
            pps = bounds.width / CGFloat(min(max(duration, 1), 24))
        }
        let inset = bounds.width / 2
        scrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        let contentWidth = CGFloat(duration) * pps
        content.frame = CGRect(x: 0, y: (bounds.height - stripHeight) / 2, width: contentWidth, height: stripHeight)
        scrollView.contentSize = CGSize(width: contentWidth, height: stripHeight)
        layoutTiles()
        layoutSelection()
        playhead.frame = CGRect(x: bounds.midX - 1.5, y: 4, width: 3, height: bounds.height - 8)
        if !didInitialScroll {
            didInitialScroll = true
            setCenterTime(inSeconds)
        }
    }

    private func layoutTiles() {
        guard !tiles.isEmpty else { return }
        let w = content.bounds.width / CGFloat(tiles.count)
        for (i, iv) in tiles.enumerated() {
            iv.frame = CGRect(x: CGFloat(i) * w, y: 0, width: ceil(w) + 1, height: stripHeight)
        }
    }

    private func layoutSelection() {
        let x0 = CGFloat(inSeconds) * pps
        let x1 = CGFloat(outSeconds) * pps
        band.frame = CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: stripHeight)
        leftHandle.frame = CGRect(x: x0 - handleW / 2, y: -4, width: handleW, height: stripHeight + 8)
        rightHandle.frame = CGRect(x: x1 - handleW / 2, y: -4, width: handleW, height: stripHeight + 8)
    }

    private func centerTime() -> Double {
        Double((scrollView.contentOffset.x + bounds.width / 2) / pps)
    }

    private func setCenterTime(_ t: Double) {
        isProgrammatic = true
        let x = CGFloat(max(0, min(t, duration))) * pps - bounds.width / 2
        scrollView.contentOffset = CGPoint(x: x, y: 0)
        isProgrammatic = false
    }

    /// Programmatic scroll so the playing frame stays under the playhead.
    func follow(_ t: Double) {
        guard !isHandleDragging else { return }
        setCenterTime(t)
    }

    // MARK: Scrubbing

    func scrollViewDidScroll(_ sv: UIScrollView) {
        guard !isProgrammatic, !isHandleDragging else { return }
        let t = max(0, min(centerTime(), duration))
        onScrub?(t)
    }

    // MARK: Zoom

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchStartPps = pps
            pinchCenterTime = centerTime()
        case .changed:
            let minPps = bounds.width / CGFloat(min(max(duration, 1), 600))   // zoom out: up to 10 min across
            let maxPps = bounds.width / 1.5                                    // zoom in: ~1.5s across
            pps = max(minPps, min(pinchStartPps * g.scale, maxPps))
            setNeedsLayout(); layoutIfNeeded()
            setCenterTime(pinchCenterTime)
        default:
            break
        }
    }

    // MARK: Trim handles

    @objc private func panLeft(_ g: UIPanGestureRecognizer) {
        handlePan(g, isLeft: true)
    }
    @objc private func panRight(_ g: UIPanGestureRecognizer) {
        handlePan(g, isLeft: false)
    }

    private var dragStartIn = 0.0
    private var dragStartOut = 0.0

    private func handlePan(_ g: UIPanGestureRecognizer, isLeft: Bool) {
        let dx = Double(g.translation(in: content).x / pps)
        switch g.state {
        case .began:
            isHandleDragging = true
            scrollView.panGestureRecognizer.isEnabled = false
            dragStartIn = inSeconds; dragStartOut = outSeconds
        case .changed:
            if isLeft {
                var v = dragStartIn + dx
                v = min(max(0, v), outSeconds - 0.5)
                v = max(v, outSeconds - maxClip)
                inSeconds = v
                layoutSelection()
                onTrim?(inSeconds, outSeconds, inSeconds)
            } else {
                var v = dragStartOut + dx
                v = max(min(duration, v), inSeconds + 0.5)
                v = min(v, inSeconds + maxClip)
                outSeconds = v
                layoutSelection()
                onTrim?(inSeconds, outSeconds, outSeconds)
            }
        case .ended, .cancelled, .failed:
            isHandleDragging = false
            scrollView.panGestureRecognizer.isEnabled = true
        default:
            break
        }
    }
}
#endif
