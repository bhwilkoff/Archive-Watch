// Watch Together Studio — the engine (Decision 127, docs/WATCH-TOGETHER.md §3.5).
//
// Platform-free by design: it is handed a film `AVPlayer`, optionally a camera
// `AVCaptureSession`, and a layout; it produces an encoded H.264 program and
// hands it to an `RTMPPublisher`. iPhone, Apple TV (Continuity Camera) and Mac
// differ only in where the camera comes from and what the UI looks like.
//
// The film is COMPOSITED from our own player output, never screen-captured
// (§3.3): `AVPlayerItemVideoOutput` gives us the decoded frame, Core Image
// draws the program (film + camera + overlays) into a Metal-backed pixel
// buffer, and VideoToolbox encodes it. That is the whole reason the Studio can
// carry an accurate lower third and let the host pause the film — a screen
// capture would only ever be a picture of the app.
//
// Timing: the program clock is the ENCODER's, driven by a display link / timer
// at the target frame rate, not the film's. A paused film keeps streaming (the
// host is still talking); a stalled film keeps streaming (the last frame
// holds). A program that stops when the film stops is a dead broadcast.

import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import VideoToolbox

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Layout

/// The program layouts, by name (§4 — presets, never free-form in v1).
public enum StudioLayout: String, CaseIterable, Sendable {
    case film       // film full-frame, no camera
    case corner     // film full-frame, camera PiP bottom-right (default)
    case theatre    // the MST3K row: camera strip along the bottom
    case side       // film 2/3 left, camera 1/3 right
    case host       // camera full-frame, film in a PiP

    public var showsFilm: Bool { true }
    public var showsCamera: Bool { self != .film }

    /// Where the chat column sits, or nil when this layout has no room.
    ///
    /// LEFT by default, stopping above the lower third. In `side` the film
    /// occupies the left two thirds, so chat moves to the right column UNDER
    /// the camera — the same lesson the camera tiles taught: a layout decides
    /// where things can go, and assuming one position for all five is how
    /// `theatre` ended up drawing over the lower third.
    public func chatRect(in size: CGSize, cameraAspect: CGFloat) -> CGRect? {
        let inset = size.width * 0.05
        switch self {
        case .film, .corner, .theatre, .host:
            let w = size.width * 0.26
            // Above the lower third's stack and its scrim.
            let bottom = size.height * 0.30
            return CGRect(x: inset, y: bottom,
                          width: w, height: size.height * 0.52)
        case .side:
            let fw = (size.width * 2 / 3).rounded()
            let cw = size.width - fw
            let ch = cw / max(cameraAspect, 0.1)
            // The camera is vertically CENTRED in the right column, so its
            // BOTTOM is (height − ch) / 2. Using (height + ch) / 2 — its top —
            // ran the chat column straight through the host's face (seen on
            // the glass, 2026-09-17). In CI coordinates y grows upward, which
            // is exactly where that sign error hides.
            let cameraBottom = (size.height - ch) / 2
            let top = cameraBottom - inset * 0.4
            let bottom = size.height * 0.10
            guard top - bottom > size.height * 0.18 else { return nil }
            return CGRect(x: fw + inset * 0.4, y: bottom,
                          width: cw - inset * 0.8, height: top - bottom)
        }
    }

    /// In `host` the CAMERA is the ground and the film is the inset tile, so
    /// the two must be drawn in the opposite order. Drawing film-then-camera
    /// unconditionally painted the full-frame camera straight over the film
    /// PiP and the film simply vanished (seen on the glass, 2026-09-17).
    public var cameraIsBackground: Bool { self == .host }

    /// Where the film and the camera sit inside a `size` program frame.
    /// Returns rects in Core Image's coordinate space (origin bottom-left).
    public func rects(in size: CGSize, cameraAspect: CGFloat) -> (film: CGRect, camera: CGRect?) {
        let full = CGRect(origin: .zero, size: size)
        switch self {
        case .film:
            return (full, nil)
        case .corner:
            // Bottom right, on the 5% title-safe line — clear of the lower
            // third at bottom left.
            let w = size.width * 0.26
            let h = w / max(cameraAspect, 0.1)
            let inset = size.width * 0.05
            return (full, CGRect(x: size.width - w - inset, y: inset, width: w, height: h))
        case .theatre:
            // The MST3K row: the host sits along the bottom, ON the film.
            // Anchored bottom-RIGHT, not centred — the lower third lives at
            // bottom-LEFT and a centred strip lands on top of it (seen on the
            // glass, 2026-09-17). Inset by the 5% title-safe margin so it is
            // not lost to a television's overscan.
            let h = size.height * 0.26
            let w = h * cameraAspect
            let inset = size.width * 0.05
            return (full, CGRect(x: size.width - w - inset, y: 0, width: w, height: h))
        case .side:
            let fw = (size.width * 2 / 3).rounded()
            let filmH = fw * 9 / 16
            let film = CGRect(x: 0, y: (size.height - filmH) / 2, width: fw, height: filmH)
            let cw = size.width - fw
            let ch = cw / max(cameraAspect, 0.1)
            return (film, CGRect(x: fw, y: (size.height - ch) / 2, width: cw, height: ch))
        case .host:
            // The camera owns the frame; the film is a reference tile. TOP
            // right, because bottom-left is the lower third's and bottom-right
            // is where `corner` trains the eye to expect the camera.
            let w = size.width * 0.26
            let h = w * 9 / 16
            let inset = size.width * 0.05
            return (CGRect(x: size.width - w - inset, y: size.height - h - inset,
                           width: w, height: h),
                    full)
        }
    }
}

/// What the program draws over the film: the catalog's own verified data
/// (§2.1 — the audience learns what the film IS).
public struct StudioOverlay: Sendable, Equatable {
    public var title: String = ""
    public var subtitle: String = ""      // "1926 · Buster Keaton"
    public var provenance: String = ""    // "Public domain since 1954"
    public var showLowerThird: Bool = true
    /// A full-frame card replaces the program (pre-roll / intermission / end).
    public var card: Card? = nil
    /// The audience, on screen. This is §2.2's participation test made
    /// literal: the host authors the show and the people watching answer, and
    /// the answer is IN the program so every viewer sees the conversation —
    /// which is what a watch-along actually is.
    public var chat: [ChatLine] = []
    public var showChat: Bool = true

    public struct ChatLine: Sendable, Equatable, Identifiable {
        public var id: String
        public var author: String
        public var text: String
        /// A follow, subscription or raid — the platform's own event, given
        /// the marquee colour rather than a badge we would have to fetch.
        public var isEvent: Bool

        public init(id: String, author: String, text: String, isEvent: Bool = false) {
            self.id = id; self.author = author; self.text = text; self.isEvent = isEvent
        }
    }

    public enum Card: Sendable, Equatable {
        case startingSoon(secondsRemaining: Int)
        case intermission
        case ending
    }

    public init() {}
}

// MARK: - Health

public struct StudioHealth: Sendable, Equatable {
    public var isRunning = false
    public var programFramesRendered = 0
    public var programFramesEncoded = 0
    public var renderDroppedFrames = 0
    public var averageRenderMilliseconds: Double = 0
    /// Bytes the encoder produced, whether or not they were published — the
    /// real bitrate of the program even on a null sink.
    public var encodedBytes = 0
    /// New film frames actually pulled from the player. If this stops
    /// climbing while the film is meant to be playing, the program is showing
    /// a frozen picture — which a host must be told about, and which an
    /// encoded-bitrate reading alone will NOT reveal (a static frame encodes
    /// to almost nothing and every other counter looks healthy).
    public var filmFramesPulled = 0
    /// Frames the ENCODER produced in the last second. Zero while the film is
    /// still arriving is the fault the 2026-09-17 tvOS soak found: encoding
    /// stopped at 293 s and every other counter stayed healthy for the
    /// remaining five minutes (§9).
    public var encodedFramesPerSecond = 0
    /// The last thing VideoToolbox refused to do, if anything. Swallowed
    /// before that soak: neither `VTCompressionSessionEncodeFrame`'s return
    /// nor its callback status was read.
    public var encoderFault: String?
    /// Times the renderer could not get a pixel buffer from its pool. Counted
    /// separately from an encoder fault because pool exhaustion and an encoder
    /// malfunction present identically — encoding simply stops — and need
    /// opposite fixes.
    public var pixelBufferPoolFailures = 0
    public var thermalState: String = "nominal"
    public var publisher = RTMPHealth()
    public var audio = StudioAudioHealth()
    /// True when a destination was supplied. Without one the engine still
    /// composites and encodes — it just sends nowhere.
    public var hasDestination = false

    /// What the SHOW is doing, in the host's terms.
    ///
    /// This exists because the first ten-foot readout said **IDLE** while the
    /// engine was encoding 5.5 Mbps (seen on an Apple TV, 2026-09-17). It was
    /// reporting the PUBLISHER's state as though it were the show's: with no
    /// destination the publisher never leaves `.idle`, which is true of the
    /// publisher and a lie about the program. A host who is making a show that
    /// goes nowhere must be told that, not told nothing is happening.
    public var showState: ShowState {
        guard isRunning else { return .off }
        // Checked BEFORE the publisher, because this is the failure that
        // looks healthiest: the socket stays open, the render loop keeps
        // hitting 30 fps, the film keeps arriving, and the audience sees
        // nothing. Deliberately cause-agnostic — it fires for an encoder
        // malfunction, an exhausted buffer pool, or anything else that stops
        // frames coming out.
        if filmFramesPulled > 0 && encodedFramesPerSecond == 0 { return .notEncoding }
        if let e = publisher.lastError, !e.isEmpty { _ = e; return .offline }
        if !hasDestination { return .encodingOnly }
        switch publisher.state {
        case .publishing: return .live
        case .connecting, .handshaking, .connected: return .connecting
        case .failed: return .offline
        case .closed: return .ended
        case .idle: return .connecting
        }
    }

    public enum ShowState: Sendable, Equatable {
        case off, encodingOnly, notEncoding, connecting, live, offline, ended

        /// Short, for a capsule or a readout.
        public var label: String {
            switch self {
            case .off: return "OFF"
            case .encodingOnly: return "NOT SENDING"
            case .notEncoding: return "STOPPED"
            case .connecting: return "CONNECTING"
            case .live: return "LIVE"
            case .offline: return "OFFLINE"
            case .ended: return "ENDED"
            }
        }

        /// A sentence, where there is room for one.
        public var detail: String? {
            switch self {
            case .encodingOnly:
                return "The show is being made but not sent anywhere — no destination is set."
            case .notEncoding:
                return "The picture has stopped being encoded — your audience is not receiving the show."
            case .connecting: return "Connecting to the platform…"
            case .offline: return "The connection to the platform is down."
            case .ended: return "The broadcast has ended."
            case .off, .live: return nil
            }
        }

        public var isOnAir: Bool { self == .live }
    }
}

// MARK: - Engine

public actor StudioEngine {

    public struct Configuration: Sendable {
        public var width = 1920
        public var height = 1080
        public var frameRate = 30
        public var videoBitrate = 6_000_000
        public var audioBitrate = 128_000
        public var audioSampleRate: Double = 44100
        public init() {}
    }

    public private(set) var health = StudioHealth()
    public private(set) var layout: StudioLayout = .corner
    public private(set) var overlay = StudioOverlay()

    private let config: Configuration
    private let publisher: RTMPPublisher
    private let renderer: ProgramRenderer
    private var encoder: H264Encoder?
    private var filmOutput: AVPlayerItemVideoOutput?
    private weak var filmPlayer: AVPlayer?
    private var cameraTap: CameraFrameTap?
    private var ticker: Task<Void, Never>?
    private var started: CFTimeInterval = 0
    private var renderTimeTotal: Double = 0
    private var lastFilmFrame: CVPixelBuffer?
    private var publishing = false
    private let mixer: StudioAudioMixer
    private var audioAttached = false

    public init(configuration: Configuration = Configuration(), publisher: RTMPPublisher = RTMPPublisher()) {
        self.config = configuration
        self.publisher = publisher
        self.renderer = ProgramRenderer(size: CGSize(width: configuration.width, height: configuration.height))
        self.mixer = StudioAudioMixer(sampleRate: configuration.audioSampleRate)
    }

    /// The §4 faders. Set at any time, including while live.
    public func setAudio(filmGain: Float? = nil, micGain: Float? = nil,
                         filmMuted: Bool? = nil, micMuted: Bool? = nil) {
        if let filmGain { mixer.filmGain = filmGain }
        if let micGain { mixer.micGain = micGain }
        if let filmMuted { mixer.filmMuted = filmMuted }
        if let micMuted { mixer.micMuted = micMuted }
    }

    public func setLayout(_ l: StudioLayout) { layout = l; renderer.layout = l }
    public func setOverlay(_ o: StudioOverlay) { overlay = o; renderer.overlay = o }

    /// Attaches the film. The player keeps playing to the viewer's own screen;
    /// we only add a video output to read its frames.
    ///
    /// NO pixel-format request. Asking for 32BGRA works on iOS and yields
    /// NOTHING on tvOS — measured on an Apple TV 4K 2nd gen: 1 frame in 607,
    /// while every other counter (fps, encode, thermals) looked healthy. The
    /// decoder there hands back its native biplanar YUV, and Core Image
    /// consumes either, so the format is left to AVFoundation.
    public func attachFilm(player: AVPlayer) async {
        filmPlayer = player
        let out = AVPlayerItemVideoOutput(outputSettings: nil)
        player.currentItem?.add(out)
        filmOutput = out
        // The film's audio, tapped off the mix it is already decoding. A film
        // with no audio track is a REAL case in this catalog (silent cinema),
        // so a false return is recorded, never treated as a failure.
        if let item = player.currentItem {
            audioAttached = await mixer.film.attach(to: item)
        }
    }

    /// True when the film actually had an audio track to tap.
    public var filmHasAudio: Bool { audioAttached }

    /// Why the film is not arriving, for the diagnostic line. Cheap enough to
    /// read once a second and the only way to tell "the player is not playing"
    /// from "the output has no buffer for this time".
    public func filmDiagnostics() -> String {
        guard let out = filmOutput else { return "no video output" }
        let t = out.itemTime(forHostTime: CACurrentMediaTimeCompat())
        let has = out.hasNewPixelBuffer(forItemTime: t)
        let rate = filmPlayer?.rate ?? -1
        let status = filmPlayer?.currentItem?.status.rawValue ?? -1
        let likely = filmPlayer?.currentItem?.isPlaybackLikelyToKeepUp ?? false
        return String(format: "rate=%.2f status=%d keepUp=%@ itemTime=%.2f hasNew=%@",
                      rate, status, likely ? "y" : "n",
                      t.isValid ? CMTimeGetSeconds(t) : -1, has ? "y" : "n")
    }

    /// Attaches a camera tap. The `AVCaptureSession` is owned by the platform
    /// layer (iOS picks a built-in device; tvOS gets one from the Continuity
    /// Camera picker) and is NOT `Sendable`, so the caller builds the tap
    /// against its own session and hands only the tap across.
    public func attachCamera(tap: CameraFrameTap) {
        cameraTap = tap
    }

    /// Adopts the host's microphone tap. Built against the platform's own
    /// `AVCaptureSession` by the caller, for the same reason the camera tap
    /// is: an `AVCaptureSession` is not `Sendable` and cannot cross in here.
    public func attachMicrophone(tap: MicAudioTap) {
        mixer.adopt(mic: tap)
    }

    /// Starts encoding and publishing. `destination` is an rtmp(s):// URL
    /// carrying the app path and stream key (§4 — fetched by API, or typed
    /// only for a custom destination).
    ///
    /// A NIL destination encodes and discards. That is not a convenience: the
    /// on-device headroom measurement is about decode + composite + encode,
    /// and on iOS a LAN destination sits behind the local-network permission
    /// prompt — which would need a human to tap it, and the standing rule is
    /// that the owner is never the tester. The publisher is proven separately
    /// (WATCH-TOGETHER §8.1), so the measurement does not need it in the path.
    public func start(destination: URL?) async throws {
        guard !health.isRunning else { return }

        let enc = H264Encoder(width: config.width, height: config.height,
                              frameRate: config.frameRate, bitrate: config.videoBitrate)
        try enc.start()
        encoder = enc

        // The first encoded frame carries the avcC we must publish before any
        // media, so encode one black frame and wait for its FORMAT (read on
        // the encoder's thread — a CMSampleBuffer does not cross to here).
        guard let avcC = try await enc.encodeAndAwaitFormat(renderer.blankFrame()) else {
            throw StudioError.noVideoFormat
        }
        var streamConfig = RTMPStreamConfig(
            width: config.width, height: config.height, frameRate: Double(config.frameRate),
            videoBitrate: config.videoBitrate, avcC: avcC,
            audioSampleRate: config.audioSampleRate, audioChannels: 2,
            audioBitrate: config.audioBitrate,
            audioSpecificConfig: mixer.audioSpecificConfig)
        streamConfig.frameRate = Double(config.frameRate)

        if let destination {
            try await publisher.publish(to: destination, config: streamConfig)
            publishing = true
        } else {
            publishing = false
        }
        health.hasDestination = publishing

        // Convert on the encoder's callback thread: EncodedVideoFrame is
        // Sendable, a CMSampleBuffer is not.
        enc.onSample = { [weak self] sample in
            guard let self, let frame = EncodedVideoFrame(sample) else { return }
            Task { await self.publish(video: frame) }
        }

        // Audio starts with video so the two clocks share an origin; the
        // publisher's first timestamp is whichever arrives first and both are
        // measured from here.
        mixer.onFrame = { [weak self] data, pts in
            guard let self else { return }
            Task { await self.publish(audio: data, at: pts) }
        }
        mixer.start()

        // §6.3, and it belongs HERE rather than in a harness.
        //
        // THIS IS THE 291-SECOND STALL. tvOS starts its screen saver after
        // five minutes of no input, and taking the display INVALIDATES the
        // VideoToolbox session — `VTCompressionSessionEncodeFrame` then
        // returns `kVTInvalidSessionErr` (-12903) forever. Measured twice on
        // an Apple TV: encoding stopped at 293 s, then at 291 s on the
        // re-run, both just under the five-minute default, with memory flat
        // at 278 MB and 1.8 GB free — so it was never pressure.
        //
        // §6.3 already required the idle timer off while live. It was set only
        // in `StudioLab`, behind `#if os(iOS)`, so tvOS never got it and the
        // real Studio never got it on EITHER platform. A rule written in the
        // design doc and implemented in the test harness is not implemented.
        await Self.holdTheScreenAwake(true)

        started = CACurrentMediaTimeCompat()
        health.isRunning = true
        startTicking()
    }

    /// `UIApplication` is main-actor-only and exists on iOS and tvOS alike —
    /// which is the whole point: the property is not iOS-specific and the
    /// platform that most needed it was the one excluded.
    private static func holdTheScreenAwake(_ on: Bool) async {
        #if canImport(UIKit) && !os(macOS)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = on }
        #endif
    }

    public func stop() async {
        await Self.holdTheScreenAwake(false)
        ticker?.cancel(); ticker = nil
        mixer.stop()
        encoder?.stop(); encoder = nil
        if publishing { await publisher.close() }
        health.isRunning = false
        if publishing { health.publisher = await publisher.health }
    }

    public func refreshHealth() async {
        if publishing { health.publisher = await publisher.health }
        health.audio = mixer.currentHealth()
        health.thermalState = Self.thermalName()
        if health.programFramesRendered > 0 {
            health.averageRenderMilliseconds = renderTimeTotal / Double(health.programFramesRendered)
        }
        // Encoded frames per SECOND, not the total: a total that stops
        // climbing is only visible to someone differencing it, which is
        // exactly what the readout was not doing when the tvOS soak stalled.
        // This is called once a second by every caller.
        health.encodedFramesPerSecond = max(0, health.programFramesEncoded - lastEncodedFrameCount)
        lastEncodedFrameCount = health.programFramesEncoded
        health.encoderFault = encoder?.fault
        health.pixelBufferPoolFailures = renderer.poolFailures
    }

    /// The previous sample, so `encodedFramesPerSecond` is a rate.
    private var lastEncodedFrameCount = 0

    // MARK: The program clock

    /// One tick per program frame. The engine's own clock, so a paused or
    /// stalled film never stops the broadcast.
    private func startTicking() {
        let interval = 1.0 / Double(config.frameRate)
        ticker = Task { [weak self] in
            guard let self else { return }
            var frame = 0
            let start = CACurrentMediaTimeCompat()
            while !Task.isCancelled {
                await self.renderOne(frameIndex: frame)
                frame += 1
                // Sleep to the NEXT frame boundary rather than a fixed delay,
                // so a slow render costs that frame and not the schedule.
                let due = start + Double(frame) * interval
                let now = CACurrentMediaTimeCompat()
                if due > now {
                    try? await Task.sleep(nanoseconds: UInt64((due - now) * 1_000_000_000))
                } else {
                    await self.noteRenderOverrun()
                }
            }
        }
    }

    private func noteRenderOverrun() { health.renderDroppedFrames += 1 }

    private func renderOne(frameIndex: Int) async {
        guard let encoder else { return }
        let t0 = CACurrentMediaTimeCompat()

        // The film's current frame, if it has advanced. A paused film returns
        // nothing new, so the last frame holds — which is what a viewer of a
        // paused riff-stream should see.
        if let out = filmOutput {
            let itemTime = out.itemTime(forHostTime: CACurrentMediaTimeCompat())
            if out.hasNewPixelBuffer(forItemTime: itemTime),
               let px = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                lastFilmFrame = px
                health.filmFramesPulled += 1
            }
        }

        let program = renderer.render(film: lastFilmFrame, camera: cameraTap?.latest())
        health.programFramesRendered += 1
        renderTimeTotal += (CACurrentMediaTimeCompat() - t0) * 1000

        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(config.frameRate))
        encoder.encode(program, at: pts)
    }

    private func publish(audio frame: Data, at pts: CMTime) async {
        health.encodedBytes += frame.count
        guard publishing else { return }
        await publisher.send(audioFrame: frame, presentationTime: pts)
    }

    private func publish(video frame: EncodedVideoFrame) async {
        health.programFramesEncoded += 1
        health.encodedBytes += frame.avccData.count
        guard publishing else { return }
        await publisher.send(video: frame)
    }

    // MARK: Helpers

    /// AudioSpecificConfig for AAC-LC at the given rate and channel count.
    static func audioSpecificConfig(sampleRate: Double, channels: Int) -> Data {
        let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let index = UInt16(rates.firstIndex(of: sampleRate) ?? 4)
        let bits = (UInt16(2) << 11) | (index << 7) | (UInt16(channels) << 3)
        return Data([UInt8(bits >> 8), UInt8(bits & 0xFF)])
    }

    static func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

public enum StudioError: Error, CustomStringConvertible {
    case noVideoFormat
    case encoderUnavailable(OSStatus)

    public var description: String {
        switch self {
        case .noVideoFormat: return "the encoder produced no avcC to publish"
        case .encoderUnavailable(let s): return "VideoToolbox refused the session (\(s))"
        }
    }
}

/// `CACurrentMediaTime()` needs QuartzCore, which is not available in a
/// command-line harness build on every platform; the mach clock is.
@inline(__always) func CACurrentMediaTimeCompat() -> CFTimeInterval {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    let ns = Double(mach_absolute_time()) * Double(t.numer) / Double(t.denom)
    return ns / 1_000_000_000
}

// MARK: - Program renderer

/// Draws one program frame: the film, the camera, the lower third, the cards.
/// Core Image onto a Metal-backed pool, so the composite stays on the GPU and
/// the encoder gets a pixel buffer it can take without a copy.
final class ProgramRenderer: @unchecked Sendable {
    let size: CGSize
    var layout: StudioLayout = .corner
    var overlay = StudioOverlay()

    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    private let overlayRenderer: StudioOverlayRenderer

    init(size: CGSize) {
        self.size = size
        self.overlayRenderer = StudioOverlayRenderer(size: size)
        if let device = MTLCreateSystemDefaultDeviceCompat() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        var p: CVPixelBufferPool?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 6] as CFDictionary,
                                attrs as CFDictionary, &p)
        pool = p
    }

    /// Counted because an exhausted pool and a malfunctioning encoder look
    /// identical from outside — frames simply stop — and the fixes are
    /// opposite.
    private(set) var poolFailures = 0

    func newBuffer() -> CVPixelBuffer? {
        guard let pool else { poolFailures += 1; return nil }
        var px: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &px)
        if px == nil { poolFailures += 1 }
        return px
    }

    /// A black program frame — what `start` encodes to learn the avcC, and
    /// what the cards are drawn over.
    func blankFrame() -> CVPixelBuffer {
        let px = newBuffer()!
        ciContext.render(CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)), to: px)
        return px
    }

    func render(film: CVPixelBuffer?, camera: CVPixelBuffer?) -> CVPixelBuffer {
        guard let out = newBuffer() else { return blankFrame() }
        var image = CIImage(color: CIColor(red: 0.039, green: 0.039, blue: 0.039))  // --color-text ground
            .cropped(to: CGRect(origin: .zero, size: size))

        // A CARD owns the frame: the film behind it must not read through.
        if overlay.card != nil {
            if let card = overlayRenderer.image(for: overlay) {
                image = card.composited(over: image)
            }
            ciContext.render(image, to: out)
            return out
        }

        let cameraAspect: CGFloat = {
            guard let camera else { return 16.0 / 9.0 }
            return CGFloat(CVPixelBufferGetWidth(camera)) / CGFloat(max(1, CVPixelBufferGetHeight(camera)))
        }()
        let (filmRect, cameraRect) = layout.rects(in: size, cameraAspect: cameraAspect)

        // Z-ORDER FOLLOWS THE LAYOUT: whichever source is the ground goes down
        // first, or the inset tile is painted over.
        let drawFilm = { [self] (base: CIImage) -> CIImage in
            guard let film else { return base }
            return fit(CIImage(cvPixelBuffer: film), into: filmRect).composited(over: base)
        }
        let drawCamera = { [self] (base: CIImage) -> CIImage in
            guard let camera, let cameraRect, layout.showsCamera else { return base }
            return fill(CIImage(cvPixelBuffer: camera), into: cameraRect).composited(over: base)
        }
        image = layout.cameraIsBackground ? drawFilm(drawCamera(image)) : drawCamera(drawFilm(image))
        // Chat under the lower third, so a long message can never obscure the
        // film's own title. A SEPARATE cached layer: chat changes every few
        // seconds and the lower third does not, and one cache key for both
        // would re-rasterise the type on every message.
        if overlay.showChat, !overlay.chat.isEmpty,
           let rect = layout.chatRect(in: size, cameraAspect: cameraAspect),
           let chat = overlayRenderer.chatImage(for: overlay, in: rect) {
            image = chat.composited(over: image)
        }
        // The lower third sits ON TOP of both, and is a cached bitmap — the
        // text is laid out only when its content changes, never per frame.
        if let l3 = overlayRenderer.image(for: overlay) {
            image = l3.composited(over: image)
        }
        ciContext.render(image, to: out)
        return out
    }

    /// Aspect-FIT: never reshape the film (Decision 097's rule, carried into
    /// the program — a hero never reshapes its art, and neither does a show).
    private func fit(_ img: CIImage, into rect: CGRect) -> CIImage {
        let e = img.extent
        guard e.width > 0, e.height > 0 else { return img }
        let scale = min(rect.width / e.width, rect.height / e.height)
        let w = e.width * scale, h = e.height * scale
        return img
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: rect.minX + (rect.width - w) / 2 - e.minX * scale,
                                               y: rect.minY + (rect.height - h) / 2 - e.minY * scale))
            .cropped(to: rect)
    }

    /// Aspect-FILL for the camera tile: a face should fill its box.
    private func fill(_ img: CIImage, into rect: CGRect) -> CIImage {
        let e = img.extent
        guard e.width > 0, e.height > 0 else { return img }
        let scale = max(rect.width / e.width, rect.height / e.height)
        let w = e.width * scale, h = e.height * scale
        return img
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: rect.minX + (rect.width - w) / 2 - e.minX * scale,
                                               y: rect.minY + (rect.height - h) / 2 - e.minY * scale))
            .cropped(to: rect)
    }

}

@inline(__always) func MTLCreateSystemDefaultDeviceCompat() -> MTLDevice? {
    MTLCreateSystemDefaultDevice()
}

// MARK: - H.264 encoder

/// VideoToolbox, configured for live: real-time, no frame reordering, a
/// keyframe every 2 s (what YouTube and Twitch ask for), CBR-ish.
final class H264Encoder: @unchecked Sendable {
    private var session: VTCompressionSession?
    private let width: Int, height: Int, frameRate: Int, bitrate: Int
    var onSample: ((CMSampleBuffer) -> Void)?
    private let lock = NSLock()
    private var firstFormatContinuation: CheckedContinuation<Data?, Error>?

    /// The last thing VideoToolbox refused, and how many times it has refused.
    ///
    /// Both statuses used to be DISCARDED — `VTCompressionSessionEncodeFrame`'s
    /// return value entirely, and the callback's behind
    /// `guard status == noErr ... else { return }`. On 2026-09-17 a ten-minute
    /// tvOS soak stopped encoding at 293 seconds and ran another five minutes
    /// reporting `drops=0 thermal=nominal`, because the one thing that knew
    /// what had happened threw it away.
    private var _fault: String?
    private var _faultCount = 0

    var fault: String? { lock.lock(); defer { lock.unlock() }; return _fault }
    var faultCount: Int { lock.lock(); defer { lock.unlock() }; return _faultCount }

    private func record(_ status: OSStatus, _ where_: String) {
        lock.lock()
        _faultCount += 1
        // The number is the useful part — kVTInvalidSessionErr (-12903) and
        // kVTVideoEncoderMalfunctionErr (-12361) mean different things and
        // only one is recoverable by restarting the session.
        _fault = "the encoder refused a frame (\(where_) \(status))"
        lock.unlock()
    }

    init(width: Int, height: Int, frameRate: Int, bitrate: Int) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.bitrate = bitrate
    }

    func start() throws {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let s else { throw StudioError.encoderUnavailable(status) }
        session = s
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (frameRate * 2) as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        // A hard ceiling as well as an average: a platform's ingest rejects a
        // burst, and a burst is what a scene cut produces.
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bitrate / 8 * 2, 1] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    func stop() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    func encode(_ pixelBuffer: CVPixelBuffer, at pts: CMTime) {
        guard let session else { return }
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            frameProperties: nil, infoFlagsOut: &flags) { [weak self] status, _, sample in
            guard let self else { return }
            guard status == noErr, let sample else {
                // A frame the encoder dropped on its own account. Recorded,
                // not ignored — this is half of what the soak could not see.
                self.record(status, "callback")
                return
            }
            self.deliver(sample)
        }
        if status != noErr { record(status, "submit") }
    }

    private func deliver(_ sample: CMSampleBuffer) {
        lock.lock()
        let pending = firstFormatContinuation
        firstFormatContinuation = nil
        lock.unlock()
        if let pending {
            // Read the avcC HERE, on the callback thread, and hand back Data —
            // a CMFormatDescription is no more Sendable than the sample is.
            pending.resume(returning: CMSampleBufferGetFormatDescription(sample)?.avcCRecord)
            return
        }
        onSample?(sample)
    }

    /// Encodes one frame and waits for its AVCDecoderConfigurationRecord, which
    /// the publisher must send before any media.
    func encodeAndAwaitFormat(_ pixelBuffer: CVPixelBuffer) async throws -> Data? {
        try await withCheckedThrowingContinuation { c in
            lock.lock(); firstFormatContinuation = c; lock.unlock()
            encode(pixelBuffer, at: .zero)
        }
    }
}

// MARK: - Camera frames

/// Holds the most recent camera frame. The engine pulls on its own clock
/// rather than being pushed, so a 60 fps camera and a 30 fps program do not
/// need a queue between them.
public final class CameraFrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CVPixelBuffer?
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "org.archivewatch.studio.camera")

    public override init() { super.init() }

    public func attach(to session: AVCaptureSession) {
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    public func latest() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return frame
    }

    public func captureOutput(_ o: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); frame = px; lock.unlock()
    }
}
