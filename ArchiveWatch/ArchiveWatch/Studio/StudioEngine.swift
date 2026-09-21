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

    /// User-facing names; the raw values are wire/diagnostic words.
    ///
    /// Lives HERE, not in a per-platform view. It began inside
    /// `GoLiveSheet_iOS.swift` behind `#if os(iOS)`, so the macOS panel could
    /// not see it — and the tempting fix is a second copy, which is how two
    /// platforms end up calling the same layout different things
    /// (`cross-platform-parity-discipline`).
    public var label: String {
        switch self {
        case .film: return "Film only"
        case .corner: return "Film with you in the corner"
        case .theatre: return "Theatre row (you along the bottom)"
        case .side: return "Side by side"
        case .host: return "You, with the film inset"
        }
    }

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
            // SIZE is what separates this from `corner`, and it has to be
            // size, because position is not available: a centred strip lands on
            // the lower third (seen on the glass, 2026-09-17), so this is
            // anchored bottom-right exactly as `corner` is. At 0.26 it was
            // `corner` moved down 64 px — same 332x187 tile, same corner — so
            // the setting did nothing a host could see, which is what the owner
            // reported on 2026-09-20. At 0.38 the host is a presence along the
            // bottom rather than a thumbnail: 486x273 against corner's 332x187.
            let h = size.height * 0.38
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
    /// Frames the CAMERA tap has received. `filmFramesPulled` exists because
    /// a frozen film is invisible to every other counter; this exists for the
    /// same reason and was missing, which cost a run: on 2026-09-19 the log
    /// said `AWCONT attached camera=Continuity Camera` while the program on
    /// the wire had no tile in it, and nothing could distinguish "no frames
    /// are arriving" from "frames arrive and are not drawn". The renderer is
    /// handed `cameraTap?.latest()`, so a nil frame draws no tile and says
    /// nothing.
    public var cameraFramesReceived = 0
    /// Whether a camera tap is attached at all. Without this, "no camera
    /// frames" cannot be told apart from "this show has no camera", and a
    /// warning that fires on every film-only broadcast is one nobody reads.
    public var cameraAttached = false
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
    /// The bitrate the encoder is ACTUALLY using, which §6.5 can move. Shown
    /// rather than the configured one, or a thermal step is invisible.
    public var videoBitrateNow = 0
    /// §5: an adaptive step is shown as it happens. Nil when nothing has
    /// been stepped; a sentence the host can read when it has.
    public var qualityNote: String?
    /// Chat the program is carrying, and how much has arrived. §4: a health
    /// value is never hidden, and "is the chat actually live?" is the question
    /// a host asks of an overlay they cannot see from the sofa.
    public var chatLinesCarried = 0
    public var chatLinesReceived = 0
    /// The audio session category actually in force, and whether activating it
    /// worked — e.g. "playback/moviePlayback active".
    ///
    /// Recorded because §6.2 could only be verified by ABSENCE otherwise: no
    /// error message meant nothing was known. A failed activation silently
    /// stops `AVPlayer` (§9), so the one thing worth putting on a screen is
    /// what the session actually is.
    public var audioSessionState: String = "not set"

    /// Whether the video encoder in use is the HARDWARE one — nil before a
    /// show starts. Carried in health so every surface can show it, because
    /// Android spent days at a third of its frame rate on a software encoder
    /// nobody had thought to ask about (§9.uu).
    public var encoderIsHardware: Bool?

    public var publisher = RTMPHealth()
    public var audio = StudioAudioHealth()
    /// True when a destination was supplied. Without one the engine still
    /// composites and encodes — it just sends nowhere.
    public var hasDestination = false
    /// Why the show ended, when it ended on its own account rather than
    /// because the host stopped it (§6.6's expired deadline; §6.5's
    /// `.critical` thermal state, which is still UNIMPLEMENTED — the rule is
    /// written and nothing acts on it).
    public var endedReason: String?

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
        // §6.6 outranks `.offline`: while a rebuild is in flight the link is
        // down but the show is not over, and those are different sentences.
        if publisher.isReconnecting { return .reconnecting }
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
        case off, encodingOnly, notEncoding, connecting, live, reconnecting, offline, ended

        /// Short, for a capsule or a readout.
        public var label: String {
            switch self {
            case .off: return "OFF"
            case .encodingOnly: return "NOT SENDING"
            case .notEncoding: return "STOPPED"
            case .connecting: return "CONNECTING"
            case .live: return "LIVE"
            case .reconnecting: return "RECONNECTING"
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
            case .reconnecting:
                return "The connection dropped — getting it back. Your audience sees a pause, not an ending."
            case .offline: return "The connection to the platform is down."
            case .ended: return "The broadcast has ended."
            case .off, .live: return nil
            }
        }

        public var isOnAir: Bool { self == .live }

        /// The two states §6.6 can be in, for a readout that wants to tint.
        public var isTroubled: Bool { self == .reconnecting || self == .offline || self == .notEncoding }
    }
}

// MARK: - Engine

/// The bench's bitrate door, in ONE place.
///
/// `AW_STUDIO_BITRATE` is kbps, DEBUG only. It exists to separate two things a
/// dropped frame cannot tell apart on its own: an encoder that cannot hold a
/// rate, and a network that cannot carry it. Pointed at a local server there is
/// no uplink in the path at all, so what survives is the device's own ceiling.
///
/// Defined once and used by every Apple entry point, because "one surface
/// fixed, siblings not" has been the recurring defect in this feature.
extension StudioEngine.Configuration {
    static func benchDoored() -> StudioEngine.Configuration {
        var c = StudioEngine.Configuration()
        #if DEBUG
        if let kbps = ProcessInfo.processInfo.environment["AW_STUDIO_BITRATE"]
            .flatMap(Int.init), kbps > 0 {
            c.videoBitrate = kbps * 1_000
        }
        #endif
        return c
    }
}

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
    /// One §6.6 recovery episode at a time (see `recoverIfSevered`).
    private var recovering = false
    private var supervisor: Task<Void, Never>?
    private var thermalWatcher: Task<Void, Never>?
    public private(set) var layout: StudioLayout = .corner
    public private(set) var overlay = StudioOverlay()

    private let config: Configuration
    private let publisher: RTMPPublisher
    private let renderer: ProgramRenderer
    private var encoder: H264Encoder?

    /// Whether the video encoder in use is the hardware one — nil until a show
    /// has started. Reported rather than assumed (§9.vv).
    public var encoderIsHardware: Bool? { encoder?.usingHardware }
    private var filmOutput: AVPlayerItemVideoOutput?
    private weak var filmPlayer: AVPlayer?
    private var cameraTap: CameraFrameTap?
    private var ticker: Task<Void, Never>?
    private var started: CFTimeInterval = 0
    private var renderTimeTotal: Double = 0
    private var lastFilmFrame: CVPixelBuffer?
    private var publishing = false
    private let mixer: StudioAudioMixer

    /// The film's audio bed, reachable WITHOUT the actor.
    ///
    /// The HLS tee's decoder runs its own real-time pump (§9.oooo) and must be
    /// able to hand over PCM without hopping onto this actor for every 23 ms
    /// packet. Safe because the mixer and the tap are both `@unchecked
    /// Sendable` and the ring underneath is lock-guarded — the same ring the
    /// `MTAudioProcessingTap` writes to on platforms where it can attach, so
    /// nothing downstream can tell the two sources apart.
    nonisolated var filmAudioBed: FilmAudioTap { mixer.film }
    private var audioAttached = false
    private var firstAudioAt: CFTimeInterval?
    private var firstVideoAt: CFTimeInterval?
    private var originsReported = false

    /// Prints the gap between the two clocks' first output, once both exist.
    /// Positive means AUDIO went first — which on the wire reads as audio
    /// running ahead of the picture by that much.
    private func reportClockOriginsIfReady() {
        guard !originsReported, let a = firstAudioAt, let v = firstVideoAt else { return }
        originsReported = true
        awdiag("AWCLOCKS firstAudio-firstVideo=%+.0f ms (positive = audio started first)",
               (v - a) * 1000)
    }

    public init(configuration: Configuration = Configuration(), publisher: RTMPPublisher = RTMPPublisher()) {
        self.config = configuration
        self.publisher = publisher
        self.renderer = ProgramRenderer(size: CGSize(width: configuration.width, height: configuration.height))
        self.mixer = StudioAudioMixer(sampleRate: configuration.audioSampleRate)
    }

    /// The §4 faders. Set at any time, including while live.
    public func setAudio(filmGain: Float? = nil, micGain: Float? = nil,
                         filmMuted: Bool? = nil, micMuted: Bool? = nil,
                         duckEnabled: Bool? = nil) {
        if let filmGain { mixer.filmGain = filmGain }
        if let micGain { mixer.micGain = micGain }
        if let filmMuted { mixer.filmMuted = filmMuted }
        if let micMuted { mixer.micMuted = micMuted }
        if let duckEnabled { mixer.duckEnabled = duckEnabled }
    }

    /// What the mixer is set to, so a surface can SHOW the gains rather than
    /// keep its own copy and drift from them (Rule 8.8c).
    public var audioSettings: (filmGain: Float, micGain: Float, duckEnabled: Bool) {
        (mixer.filmGain, mixer.micGain, mixer.duckEnabled)
    }

    public func setLayout(_ l: StudioLayout) { layout = l; renderer.layout = l }
    public func setOverlay(_ o: StudioOverlay) { overlay = o; renderer.overlay = o }

    /// THE PROVENANCE LINE LASTS 20 SECONDS, and the ENGINE enforces it.
    ///
    /// It was implemented in tvOS's `DetailView` health loop alone, so iOS
    /// showed it for the whole broadcast. Owner, 2026-09-20: *"the provenance
    /// line doesn't disappear after 20 seconds on the iOS live stream."*
    /// macOS never had it either. A rule living in one platform's view loop is
    /// a rule the other platforms do not have — the same shape as §6.3's idle
    /// timer and §6.2's audio session, which Decision 130 was written about.
    /// Here it is in the one place every platform already runs.
    ///
    /// THE CLOCK STARTS AT `.live`, NOT AT `start()`, and that distinction is
    /// the owner's: *"you have to know when the stream goes live to know when
    /// the first 20 seconds will be."* §9.tt measured ~12 s between starting
    /// and the first published packet — film load, handshake, opening
    /// keyframe — so a timer from `start` spends most of its window before
    /// anybody can see it, and a viewer joining at the top of the stream gets
    /// four seconds of provenance or none.
    ///
    /// A badge that never leaves is branding, not provenance.
    private var provenanceLiveSince: Date?
    private var provenanceCleared = false

    /// Call once a second from whatever polls health. Idempotent.
    @discardableResult
    public func expireProvenanceIfDue(after seconds: TimeInterval = 20) -> Bool {
        guard !provenanceCleared, !overlay.provenance.isEmpty else { return false }
        guard health.showState == .live else { return false }
        guard let since = provenanceLiveSince else {
            provenanceLiveSince = Date()
            return false
        }
        guard Date().timeIntervalSince(since) >= seconds else { return false }
        provenanceCleared = true
        var later = overlay
        later.provenance = ""
        setOverlay(later)
        awdiag("AWPROV provenance cleared %.0fs after going live", seconds)
        return true
    }

    // MARK: - Chat the program CARRIES

    private var twitchChat: StudioChatTwitch?

    /// Reads a Twitch channel into the overlay, for as long as the show runs.
    ///
    /// IN THE ENGINE, not in a surface. The first version of this lived in
    /// `StudioSession`, which is macOS-first by its own header — so chat
    /// reached the Mac and neither the television nor the phone, and PARITY
    /// said it reached all three. That is exactly how §6.2's audio session and
    /// §6.3's idle timer came to be implemented in one place only. Runtime
    /// behaviour belongs where the engine is; a surface's job is to name the
    /// channel.
    public func attachTwitchChat(channel: String) async {
        guard !channel.isEmpty else { return }
        let chat = StudioChatTwitch()
        twitchChat = chat
        await chat.start(channel: channel)
        overlay.showChat = true
        renderer.overlay = overlay
    }

    /// Pulls the tail of the chat into the overlay. Called once a second from
    /// `refreshHealth`, which every surface already calls at that cadence —
    /// so no surface has to remember to do this.
    private func pumpChat() async {
        guard let chat = twitchChat else { return }
        let lines = await chat.lines
        guard !lines.isEmpty else { return }
        let tail = Array(lines.suffix(8))
        guard tail.map(\.id) != overlay.chat.map(\.id) else { return }
        overlay.showChat = true
        overlay.chat = tail
        renderer.overlay = overlay
        health.chatLinesCarried = tail.count
        health.chatLinesReceived = await chat.health.linesReceived
    }

    /// Attaches the film. The player keeps playing to the viewer's own screen;
    /// we only add a video output to read its frames.
    ///
    /// NO pixel-format request. Asking for 32BGRA works on iOS and yields
    /// NOTHING on tvOS — measured on an Apple TV 4K 2nd gen: 1 frame in 607,
    /// while every other counter (fps, encode, thermals) looked healthy. The
    /// decoder there hands back its native biplanar YUV, and Core Image
    /// consumes either, so the format is left to AVFoundation.
    /// Reads the item's audio tracks ON THE MAIN ACTOR and returns only a
    /// Bool, because that is the one shape that can cross back into an actor:
    /// `AVAsset` cannot.
    @MainActor
    private static func assetHasAudio(_ item: AVPlayerItem) async -> Bool? {
        guard let tracks = try? await item.asset.loadTracks(withMediaType: .audio) else {
            return nil
        }
        return !tracks.isEmpty
    }

    public func attachFilm(player: AVPlayer) async {
        filmPlayer = player
        let out = AVPlayerItemVideoOutput(outputSettings: nil)
        player.currentItem?.add(out)
        filmOutput = out
        // The film's audio, tapped off the mix it is already decoding. A film
        // with no audio track is a REAL case in this catalog (silent cinema),
        // so a false return is recorded, never treated as a failure.
        if let item = player.currentItem {
            sourceHasAudio = await Self.assetHasAudio(item)
            audioAttached = await mixer.film.attach(to: item)
        }
    }

    /// True when the film actually had an audio track to tap.
    /// True when the film's audio is reaching the program by EITHER route —
    /// the tap on iOS/macOS, or the pull path on tvOS.
    public var filmHasAudio: Bool { audioAttached || mixer.film.isReceivingExternal }

    /// Decoded film audio waiting in the mixer's ring, in seconds.
    public var filmAudioBuffered: Double { mixer.film.bufferedSeconds }

    /// Film time of the audio the tap last delivered (iOS/macOS).
    public var filmAudioSourcePosition: Double? { mixer.film.sourceFilmPosition }

    /// Why the film's audio is NOT on air, or nil when it is (or when the film
    /// is genuinely silent).
    ///
    /// `attach` returns false for two completely different reasons and the
    /// engine could not tell them apart: a silent film — a real and common case
    /// in a public-domain catalog — and an asset that vends no tracks to tap.
    /// tvOS is always the second (§9.jjjj): Decision 106 plays the film as HLS,
    /// an HLS asset has no `AVAssetTrack`s, `AVMutableAudioMix` therefore has
    /// nothing to attach to, and every television broadcast went out in
    /// silence while the readout said "audio: active" — because that line
    /// describes the audio SESSION, not the content.
    ///
    /// The caller passes what it knows about the SOURCE, which is the only way
    /// to separate the two.
    /// Does the film being tapped actually HAVE an audio track?
    ///
    /// Recorded at attach time rather than asked for later, because
    /// `AVPlayerItem.asset` is main-actor isolated and `AVAsset` is not
    /// Sendable, so an actor cannot reach across for it — `attachFilm` is
    /// already the moment the item is in hand. Nil when it could not be
    /// determined, which `filmAudioProblem` treats as "say nothing" rather
    /// than "no audio". It exists to tell a genuinely SILENT film — a real and
    /// common case in a public-domain catalogue, as the owner pointed out on
    /// 2026-09-20 — from a tap that failed to attach.
    public private(set) var sourceHasAudio: Bool?

    public func filmAudioProblem(sourceHasAudio: Bool?) -> String? {
        guard !audioAttached else { return nil }
        // THE PULL PATH COUNTS. This guard used to be absent, so on tvOS — where
        // the tap can never attach — the screen said "the film's audio is not
        // being sent" through a broadcast whose audio the owner was listening
        // to. The warning described the tap, and the tap stopped being how
        // television audio gets sent (§9.tttt).
        guard !mixer.film.isReceivingExternal else { return nil }
        guard sourceHasAudio == true else { return nil }   // genuinely silent, or unknown
        return "The film's audio is not being sent. The picture is unaffected."
    }

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

        // §6.2 FIRST: the mixer and the film both depend on the session being
        // in the right category, and on iOS it arrives here still in
        // `.playback`.
        raiseAudioSessionForShow()

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
            // §6.4's cap is a LATENCY budget, so it can only be computed from
            // this show's bitrates — the publisher has no idea what they are
            // until now.
            await publisher.setQueueBudget(videoBitrate: config.videoBitrate, audioBitrate: config.audioBitrate)
            try await publisher.publish(to: destination, config: streamConfig)
            publishing = true
            // The broadcast must OPEN on a keyframe, for the same reason a
            // reconnected one must (§6.6).
            //
            // Measured 2026-09-17 by §8.6: **59 video frames — two full
            // seconds — were dropped at the start of every broadcast.** A
            // fresh publish begins with `droppingUntilKeyframe`, the IDR from
            // the avcC probe is consumed rather than sent, and everything the
            // ticker produces after it is a P-frame until the 2 s GOP
            // boundary. So the first two seconds any viewer received were
            // undecodable. The reconnect path had asked for this keyframe
            // since §6.6 was written; the path every broadcast takes had not.
            enc.requestKeyframe()
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
        health.endedReason = nil
        health.videoBitrateNow = config.videoBitrate
        health.qualityNote = nil
        startTicking()
        if publishing { superviseTheConnection() }
        watchTheTemperature()
        // Apply whatever the state ALREADY is: a host who starts a broadcast
        // on an already-hot device gets no notification, because nothing
        // changed.
        await applyThermalState()
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
        restoreAudioSession()
        supervisor?.cancel(); supervisor = nil
        thermalWatcher?.cancel(); thermalWatcher = nil
        if let chat = twitchChat { await chat.stop() }
        twitchChat = nil
        ticker?.cancel(); ticker = nil
        mixer.stop()
        encoder?.stop(); encoder = nil
        if publishing { await publisher.close() }
        health.isRunning = false
        if publishing { health.publisher = await publisher.health }
    }

    public func refreshHealth() async {
        health.encoderIsHardware = encoder?.usingHardware
        if publishing { health.publisher = await publisher.health }
        health.audio = mixer.currentHealth()
        // The EFFECTIVE state, or a harness override would be overwritten once
        // a second by the real one and §6.5 could never be exercised.
        health.thermalState = Self.thermalName(effectiveThermalState)
        health.videoBitrateNow = encoder?.currentBitrate ?? config.videoBitrate
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
        await pumpChat()
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

    // MARK: - §6.2 The audio session

    #if os(iOS) || os(tvOS)
    private var previousAudioCategory: AVAudioSession.Category?
    #endif

    /// §6.2, and it belongs HERE for the same reason §6.3's idle timer does.
    ///
    /// Every product path that starts the Studio — the iOS go-live container,
    /// the tvOS transport menu, the Mac — started it WITHOUT touching the
    /// audio session. The only code that honoured §6.2 was `StudioLab`, the
    /// debug harness. So on iOS the show began with the session still in
    /// `.playback` from ordinary playback (`PlayerView_iOS`), which cannot
    /// record: the documented `.playAndRecord` never happened, and a mic tap
    /// would have captured nothing. The fourth rule in this section found
    /// implemented only in the harness.
    ///
    /// The platform conditionals are real rather than lazy: `.defaultToSpeaker`
    /// does not exist on tvOS, and `.moviePlayback` with `.playAndRecord` is
    /// invalid everywhere (OSStatus -50). On tvOS the session stays in
    /// `.playback` until `StudioContinuity` finds an actual microphone port and
    /// raises it — raising it earlier fails, and a failed activation stops
    /// `AVPlayer` dead (§9).
    /// Raise the audio session BEFORE asking Continuity for a microphone.
    ///
    /// The continuity mic is an `AVAudioSession` INPUT PORT, and a session that
    /// is not in a record-capable category lists no inputs — so querying it
    /// first always answers "none". `start()` raises the session at line ~554,
    /// long after the attach path runs, which is why a paired phone reported
    /// `camera=Continuity Camera micPort=none`: the camera is a capture device
    /// and was found, the microphone is a session port and could not be.
    /// Idempotent — `previousAudioCategory` is only captured once.
    public func prepareAudioSession() { raiseAudioSessionForShow() }

    private func raiseAudioSessionForShow() {
        #if os(iOS) || os(tvOS)
        let s = AVAudioSession.sharedInstance()
        if previousAudioCategory == nil { previousAudioCategory = s.category }
        do {
            // The CONTROL for §6.2, and it exists because "the film still
            // played" only means something if a wrong category visibly stops
            // it. `AW_STUDIO_BAD_AUDIO=1` asks for the combination §6.2 names
            // as invalid everywhere — `.moviePlayback` with `.playAndRecord`,
            // OSStatus -50 — so a run can show the opposite outcome on the
            // same glass. Never set in production.
            if ProcessInfo.processInfo.environment["AW_STUDIO_BAD_AUDIO"] == "1" {
                try s.setCategory(.playAndRecord, mode: .moviePlayback, options: [.mixWithOthers])
                try s.setActive(true)
                health.audioSessionState = "BAD-AUDIO CONTROL: playAndRecord/moviePlayback active"
                return
            }
            #if os(tvOS)
            // DO NOT STOMP A CONTINUITY MICROPHONE. §6.2 says tvOS stays
            // `.playback` "until a Continuity microphone is attached, and only
            // then `.playAndRecord`" — the second half of that sentence was
            // never implemented, so this forced `.playback` back over the
            // category `StudioContinuity` had just raised for the microphone.
            //
            // With a capture session holding an audio input, that downgrade is
            // REFUSED: OSStatus 561017449, `'!pri'`,
            // `AVAudioSessionErrorInsufficientPriority`, which the host then
            // reads on the glass as "audio: FAILED" during a broadcast whose
            // film audio is in fact fine (measured 2026-09-19 — `filmLevel`
            // 0.16-0.23 throughout).
            //
            // If the session is already recording, the microphone owns it and
            // this has nothing to add.
            if s.category == .playAndRecord {
                health.audioSessionState = "PlayAndRecord (continuity microphone owns it)"
                return
            }
            try s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            #else
            // iOS: ASK TO RECORD, BUT FALL BACK TO PLAYING.
            //
            // A call — FaceTime included, and therefore a SharePlay watch
            // party — REFUSES a recording session, and Apple says so in
            // `AVAudioSession.h` naming this exact case:
            //
            //   "Apps may activate a AVAudioSessionCategoryPlayback session
            //    when another app is hosting a call (to start a SharePlay
            //    activity for example). However, they are not permitted to
            //    capture the microphone of the active call, so attempts to
            //    activate a session with category ...Record or
            //    ...PlayAndRecord will fail with error
            //    AVAudioSessionErrorCodeInsufficientPriority."
            //
            // Asking unconditionally therefore threw `'!pri'` (561017449) for
            // every host in a call, and the throw left the session
            // unconfigured — so a broadcast that could have carried the FILM
            // perfectly well carried nothing, for want of a microphone it was
            // never going to get. tvOS already had this right for the
            // Continuity case above; iOS did not.
            //
            // The host's voice is genuinely unavailable during a call. The
            // film is not, so the film goes out.
            do {
                try s.setCategory(.playAndRecord, mode: .default,
                                  options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            } catch {
                try s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try s.setActive(true)
                health.audioSessionState =
                    "Playback (a call owns the microphone — your voice is not in the show)"
                awdiag("AWAUD playAndRecord refused (%@) — fell back to playback", "\(error)")
                return
            }
            #endif
            try s.setActive(true)
            health.audioSessionState = "\(s.category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"
                + "/\(s.mode.rawValue.replacingOccurrences(of: "AVAudioSessionMode", with: "")) active"
        } catch {
            // Never swallowed: a failed activation is the thing that silently
            // stops the film, so it goes on the readout the host can see.
            health.audioSessionState = "FAILED: \(error.localizedDescription)"
            health.qualityNote = "The audio session could not be set up (\(error.localizedDescription)). "
                + "Your voice may not be in the stream."
        }
        #endif
    }

    /// §6.2's last sentence: restore the previous category on close. The
    /// harness never did, so a Studio session left the whole app in
    /// `.playAndRecord` — which on a phone means the next film plays through
    /// the receiver rather than the speaker.
    private func restoreAudioSession() {
        #if os(iOS) || os(tvOS)
        guard let prev = previousAudioCategory else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(prev, mode: .moviePlayback, options: [.mixWithOthers])
        try? s.setActive(true)
        previousAudioCategory = nil
        #endif
    }

    // MARK: - §6.5 Thermal pressure

    /// The fraction of the configured bitrate used at `.serious`.
    public static let seriousBitrateFraction = 0.6

    /// Harness seam: when set, this stands in for
    /// `ProcessInfo.thermalState`. A device cannot be made `.critical` on
    /// demand, and a rule nothing can exercise is a rule nobody has checked
    /// — which is exactly how §6.5 came to be written and implemented
    /// nowhere. Never set in shipping code.
    private var thermalOverride: ProcessInfo.ThermalState?
    public func overrideThermalState(_ state: ProcessInfo.ThermalState?) async {
        thermalOverride = state
        await applyThermalState()
    }
    private var effectiveThermalState: ProcessInfo.ThermalState {
        thermalOverride ?? ProcessInfo.processInfo.thermalState
    }

    /// Observed rather than polled, so a step happens when the state changes
    /// instead of up to a second later.
    private func watchTheTemperature() {
        thermalWatcher?.cancel()
        thermalWatcher = Task { [weak self] in
            let notes = NotificationCenter.default.notifications(named: ProcessInfo.thermalStateDidChangeNotification)
            for await _ in notes {
                guard let self else { return }
                await self.applyThermalState()
            }
        }
    }

    /// §6.5. The bitrate is the ONLY dial: resolution and frame rate are
    /// fixed for the life of an RTMP publish (Bitmovin's input requirements
    /// are explicit that format parameters must not change during a stream),
    /// so the rule's earlier "halve the resolution" would have broken the
    /// broadcast it was meant to save.
    private func applyThermalState() async {
        guard health.isRunning else { return }
        let state = effectiveThermalState
        health.thermalState = Self.thermalName(state)
        switch state {
        case .critical:
            // Not a quality step. At `.critical` the system may terminate the
            // app, and an end card the audience sees beats a frozen frame
            // left behind by a killed process.
            await endShow(reason: "the device became too hot to keep broadcasting")
        case .serious:
            let stepped = Int(Double(config.videoBitrate) * Self.seriousBitrateFraction)
            if let encoder, encoder.currentBitrate != stepped {
                if encoder.setBitrate(stepped) {
                    health.videoBitrateNow = stepped
                    health.qualityNote = "The device is running hot, so the picture is being sent at "
                        + "\(stepped / 1000) kbps instead of \(config.videoBitrate / 1000) kbps."
                } else {
                    // The step FAILED, and saying nothing here would leave the
                    // readout claiming a reduction that never happened.
                    health.qualityNote = "The device is running hot and the encoder refused to lower the bitrate."
                }
            }
        case .nominal, .fair:
            if let encoder, encoder.currentBitrate != config.videoBitrate {
                if encoder.setBitrate(config.videoBitrate) {
                    health.videoBitrateNow = config.videoBitrate
                    let note = "Back to full quality \(config.videoBitrate / 1000) kbps."
                    health.qualityNote = note
                    // The GOOD news is transient; a degraded state is not. A
                    // step down belongs on the readout for as long as it is in
                    // effect, but "back to full quality" is an announcement —
                    // left up, it sits there for the rest of the show reading
                    // like a warning.
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(8))
                        await self?.clearQualityNote(ifStill: note)
                    }
                }
            }
        @unknown default:
            break
        }
    }

    /// Clears the restore announcement, but only if nothing has replaced it.
    ///
    /// Its own isolated method because `health` belongs to this actor: a
    /// detached `Task` closure touching it directly is a Swift 6 error, and
    /// the guard has to read and write under the same isolation or it can
    /// clear a note set in between.
    private func clearQualityNote(ifStill note: String) {
        guard health.qualityNote == note else { return }
        health.qualityNote = nil
    }

    // MARK: - §6.6 Recovering a severed link

    /// §6.6's schedule lives in `RTMPReconnectPolicy` — one copy, read by
    /// this engine and by the harness that proves it.
    public static var reconnectDeadline: Double { RTMPReconnectPolicy.deadlineSeconds }

    /// Polls once a second for a link that has gone, and rebuilds it.
    /// Separate from the render ticker on purpose: reconnecting must not be
    /// able to stall the frame clock, and a render that stalls must not stop
    /// the recovery.
    private func superviseTheConnection() {
        supervisor?.cancel()
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.recoverIfSevered()
            }
        }
    }

    /// One recovery episode: attempt, back off, attempt, until the link is
    /// back or the deadline passes.
    ///
    /// The backoff is 1, 2, 4, 8, then 15 s — fast at the start because the
    /// window is a minute, and capped because a link that has refused four
    /// times in fifteen seconds is not going to be persuaded by a fifth in
    /// the same second. One episode at a time: Twitch permits a single active
    /// session per key and a new connection displaces the old, so overlapping
    /// attempts would kick each other off.
    private func recoverIfSevered() async {
        guard health.isRunning, publishing, !recovering else { return }
        guard await publisher.needsReconnect else { return }
        recovering = true
        defer { recovering = false }

        let backoff = RTMPReconnectPolicy.backoffSeconds
        let giveUpAt = CACurrentMediaTimeCompat() + Self.reconnectDeadline
        var attempt = 0
        while health.isRunning, CACurrentMediaTimeCompat() < giveUpAt {
            attempt += 1
            do {
                try await publisher.reconnect()
                health.publisher = await publisher.health
                // The new session must OPEN on a keyframe, or the server's
                // recording and every rejoining viewer hold nothing
                // decodable while the stream reads as live (Decision 129,
                // and it is the same fact on both platforms).
                encoder?.requestKeyframe()
                return
            } catch {
                health.publisher = await publisher.health
                let wait = backoff[min(attempt - 1, backoff.count - 1)]
                // Never sleep past the deadline — otherwise a 15 s backoff
                // decides when we give up instead of the rule.
                let remaining = giveUpAt - CACurrentMediaTimeCompat()
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: UInt64(min(wait, remaining) * 1_000_000_000))
            }
        }
        // The window has closed. End the show rather than hold a readout that
        // says RECONNECTING over a stream the platform finished minutes ago.
        await endShow(reason: "the connection could not be restored within \(Int(Self.reconnectDeadline)) seconds")
    }

    /// Stops the show and says why, so the surface can draw an end card
    /// instead of a frozen frame (§6.3). `stop()` is the host's own choice
    /// and carries no reason.
    public func endShow(reason: String) async {
        guard health.isRunning else { return }
        health.endedReason = reason
        await stop()
    }

    private func renderOne(frameIndex: Int) async {
        guard let encoder else { return }
        let t0 = CACurrentMediaTimeCompat()

        // The film's current frame, if it has advanced. A paused film returns
        // nothing new, so the last frame holds — which is what a viewer of a
        // paused Watch Together broadcast should see.
        if let out = filmOutput {
            let itemTime = out.itemTime(forHostTime: CACurrentMediaTimeCompat())
            if out.hasNewPixelBuffer(forItemTime: itemTime),
               let px = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                lastFilmFrame = px
                health.filmFramesPulled += 1
            }
        }

        health.cameraFramesReceived = cameraTap?.received ?? 0
        health.cameraAttached = cameraTap != nil
        let program = renderer.render(film: lastFilmFrame, camera: cameraTap?.latest())
        health.programFramesRendered += 1
        renderTimeTotal += (CACurrentMediaTimeCompat() - t0) * 1000

        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(config.frameRate))
        encoder.encode(program, at: pts)
    }

    private func publish(audio frame: Data, at pts: CMTime) async {
        // THE TWO ORIGINS, measured rather than asserted. `mixer.onFrame` is
        // wired with the comment "audio starts with video so the two clocks
        // share an origin" — and the wire says audio LEADS the picture by
        // ~140 ms (§9.ggggg), which is exactly what a pair of counters started
        // at different instants would produce. Each track stamps from its own
        // count, so if audio begins counting before the first frame is encoded,
        // its samples claim a time the picture had not reached.
        if firstAudioAt == nil {
            firstAudioAt = CACurrentMediaTimeCompat()
            reportClockOriginsIfReady()
        }
        health.encodedBytes += frame.count
        guard publishing else { return }
        await publisher.send(audioFrame: frame, presentationTime: pts)
    }

    private func publish(video frame: EncodedVideoFrame) async {
        if firstVideoAt == nil {
            firstVideoAt = CACurrentMediaTimeCompat()
            reportClockOriginsIfReady()
        }
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

    static func thermalName(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> String {
        switch state {
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

    /// Whether VideoToolbox actually gave us a HARDWARE encoder.
    ///
    /// `encoderSpecification: nil` is NOT the same mistake Android made with
    /// `createEncoderByType`: the SDK documents
    /// `kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder` as
    /// "Optional, true by default", so nil already means "hardware if there is
    /// one". But that is a fact about the DEFAULT, not about this session, and
    /// the Android ceiling was believed for days on exactly that kind of
    /// reasoning (§9.uu). `UsingHardwareAcceleratedVideoEncoder` is documented
    /// "Read; assumed false by default", so it is read here and reported.
    /// `Require…` is deliberately NOT set: it fails session creation outright
    /// on a machine with no hardware encoder, and a slow broadcast beats none.
    private(set) var usingHardware: Bool?

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
        // burst, and a burst is what a scene cut produces. Same factor as
        // `setBitrate` uses, or a thermal step would tighten a cap the start
        // path had left loose.
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [Int(Double(bitrate) / 8.0 * Self.dataRateCapFactor), 1] as CFArray)
        var hwValue: CFTypeRef?
        if VTSessionCopyProperty(s,
                key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                allocator: nil, valueOut: &hwValue) == noErr {
            usingHardware = (hwValue as? Bool) ?? ((hwValue as? NSNumber)?.boolValue)
        }
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    func stop() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    /// §6.5: the ONE quality dial that may move mid-broadcast. Resolution and
    /// frame rate are fixed for the life of an RTMP publish, so this changes
    /// neither — it re-sets `AverageBitRate` and `DataRateLimits` on the live
    /// session, which VideoToolbox accepts.
    ///
    /// Returns false when VideoToolbox refused, because a step that silently
    /// failed would have the readout reporting a reduction that never
    /// happened — the 291-second soak was a swallowed OSStatus and this is
    /// the same shape.
    @discardableResult
    func setBitrate(_ bps: Int) -> Bool {
        guard let session else { return false }
        let avg = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        // The cap is a byte budget over one second, and it is what actually
        // BINDS. `AverageBitRate` alone is a soft VBR target over a long
        // window: measured 2026-09-17, stepping it from 4000 to 2400 kbps
        // moved the wire from 3.6 to 3.3 Mbps — a 7% drop where 40% was asked
        // for — because the cap sat at twice the average and never bit.
        let cap = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                                       value: [Int(Double(bps) / 8.0 * Self.dataRateCapFactor), 1] as CFArray)
        if avg != noErr { record(avg, "setBitrate/average"); return false }
        if cap != noErr { record(cap, "setBitrate/cap"); return false }
        lock.lock(); _currentBitrate = bps; lock.unlock()
        return true
    }
    /// How much over the target the one-second cap allows. Tight enough to
    /// bind, loose enough to let a keyframe through: an I-frame is several
    /// times a P-frame, so a cap at 1.0 would starve the GOP it starts.
    static let dataRateCapFactor = 1.15

    private var _currentBitrate = 0
    var currentBitrate: Int { lock.lock(); defer { lock.unlock() }; return _currentBitrate == 0 ? bitrate : _currentBitrate }

    /// Set by §6.6 when a reconnected session needs to OPEN on a keyframe.
    /// Read-and-cleared under the lock so one request produces exactly one
    /// forced frame — a flag that stays set turns the stream into all-I-frames
    /// at several times the bitrate, on a link that just proved it was weak.
    private var _forceNextKeyframe = false
    func requestKeyframe() { lock.lock(); _forceNextKeyframe = true; lock.unlock() }
    private func takeKeyframeRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _forceNextKeyframe { _forceNextKeyframe = false; return true }
        return false
    }

    func encode(_ pixelBuffer: CVPixelBuffer, at pts: CMTime) {
        guard let session else { return }
        var flags = VTEncodeInfoFlags()
        let properties: CFDictionary? = takeKeyframeRequest()
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
            : nil
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            frameProperties: properties, infoFlagsOut: &flags) { [weak self] status, _, sample in
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
    /// The sample buffer that owns `frame`. See `captureOutput`.
    private var held: CMSampleBuffer?
    private var count = 0
    private var lastWidth = 0, lastHeight = 0
    private let output = AVCaptureVideoDataOutput()
    /// THE SESSION, RETAINED. Nothing else held it: `StudioContinuity` stores
    /// no session, and the caller's is a local `let session` inside an `if`
    /// block. The block exited, ARC freed the session, capture stopped — and
    /// every log line still said success, because `startRunning()` HAD
    /// succeeded a moment earlier. Measured 2026-09-19: the attach chain ran
    /// clean, `AWCONT attached camera=Continuity Camera`, and then
    /// `AWCAM frames=0 (+0/s)` every second for the whole run with no tile on
    /// the wire. The tap is owned by the engine for the life of the show and
    /// cannot work without its session, so the tap is what should hold it.
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "org.archivewatch.studio.camera")

    public override init() { super.init() }

    public func attach(to session: AVCaptureSession, rotationAngle: CGFloat = 0) {
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        // INSIDE A TRANSACTION. An `addOutput` on a session that is not
        // configuring commits on the spot, and committing makes the device
        // renegotiate its format against the session preset. On a Continuity
        // Camera that renegotiation threw
        // `-[AVCaptureDevice _setActiveFormat:…sessionPreset:] Unsupported
        // format ((null))` and killed the app with signal 6 (2026-09-19) —
        // an ObjC exception, so nothing on the Swift side could catch it.
        // Batching it means the negotiation happens once, at commit, against
        // the preset `StudioContinuity.makeSession` already proved reachable.
        session.beginConfiguration()
        if session.canAddOutput(output) { session.addOutput(output) }
        // ROTATE BEFORE RUNNING. `AVCaptureVideoDataOutput` physically rotates
        // its buffers, and the header is explicit that this "requires a lengthy
        // configuration of the capture render pipeline and should be done
        // before calling startRunning" — which is why it belongs here, inside
        // the same configuration transaction, and not applied later.
        //
        // Rotating the BUFFER (rather than cropping in the compositor) is what
        // makes a portrait-held phone broadcast as a portrait tile: the
        // renderer derives the tile's aspect from the buffer's own dimensions,
        // so a rotated buffer gives a correctly-shaped tile for free.
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(rotationAngle) {
                conn.videoRotationAngle = rotationAngle
                awdiag("AWCAM rotation %.0f applied", rotationAngle)
            } else {
                awdiag("AWCAM rotation %.0f NOT supported — leaving %.0f",
                       rotationAngle, conn.videoRotationAngle)
            }
        }
        session.commitConfiguration()
        self.session = session
    }

    public func latest() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return frame
    }

    /// How many frames have ever arrived. Read by the engine into
    /// `StudioHealth.cameraFramesReceived`; see that field for why.
    public var received: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    public func captureOutput(_ o: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        // HOLD THE SAMPLE BUFFER, NOT JUST THE PIXEL BUFFER.
        //
        // `CMSampleBufferGetImageBuffer` vends a pixel buffer OWNED BY the
        // sample buffer. Keeping only the pixel buffer lets the sample buffer
        // go when this method returns, and the capture pool is then free to
        // recycle those pages and write the next frame over them. The
        // renderer still gets a valid, non-nil buffer — so a tile IS drawn —
        // and what is in it is whatever the pool last did. Owner, 2026-09-20,
        // watching the broadcast: "I see the tile. I don't see the actual
        // camera taking video."
        //
        // That is why every counter looked healthy: `AWCAM frames=19621
        // (+30/s) receiving` was true, `latest()` was non-nil, the layout was
        // `.corner`, and the tile was composited. Only its CONTENTS were gone.
        //
        // One buffer is held at a time, which the pool can afford;
        // `alwaysDiscardsLateVideoFrames` keeps it from backing up.
        held = sampleBuffer
        frame = px
        count += 1
        // EVERY TIME THE SHAPE CHANGES, not only on the first frame. The tile's
        // aspect is derived from these numbers (`StudioEngine.cameraAspect`),
        // so they are the only proof that a requested rotation actually took:
        // a portrait-held phone broadcast correctly reads 1080x1920 here, and
        // 1920x1080 means the rotation did not reach the buffers whatever the
        // attach logged.
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        if w != lastWidth || h != lastHeight {
            lastWidth = w; lastHeight = h
            let fmt = CVPixelBufferGetPixelFormatType(px)
            awdiag("AWCAM frame shape %dx%d (%@) fourcc=%c%c%c%c at frame %d", w, h,
                   w >= h ? "landscape" : "portrait",
                   Int32((fmt >> 24) & 0xff), Int32((fmt >> 16) & 0xff),
                   Int32((fmt >> 8) & 0xff), Int32(fmt & 0xff), count)
        }
        lock.unlock()
    }
}
