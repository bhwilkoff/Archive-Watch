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
/// Anything that can hand the engine the call's latest picture (§D23).
///
/// A PROTOCOL so `StudioEngine` does not import ScreenCaptureKit: the engine
/// is compiled standalone by a dozen §8 harness cases, and a reference to a
/// macOS-only framework would drag it into every one of them — the same
/// dependency-inversion reason `StudioChatYouTube` takes a fetch closure.
public protocol GuestFrameSource: AnyObject, Sendable {
    func latest() -> CVPixelBuffer?
}

public enum StudioLayout: String, CaseIterable, Sendable {
    case film       // film full-frame, no camera
    case corner     // film full-frame, camera PiP bottom-right (default)
    case theatre    // the MST3K row: camera strip along the bottom
    case side       // film 2/3 left, camera 1/3 right
    case host       // camera full-frame, film in a PiP
    /// §D23 — the sixth, and the first with a THIRD picture in it: the film
    /// full-frame, and a right-hand column carrying the call above the host.
    /// It extends `corner`'s vocabulary rather than inventing one: the host
    /// stays where five placements have trained the eye to find them, and the
    /// guests arrive directly above, at the same width, reading as one column
    /// of people rather than two loose tiles.
    case guests     // film full-frame, call + camera stacked right

    public var showsFilm: Bool { true }
    public var showsCamera: Bool { self != .film }
    /// Only one placement carries the call's picture. Asked as a question
    /// rather than compared against a case, so a seventh placement that also
    /// showed guests would not need every call site edited.
    public var showsGuests: Bool { self == .guests }

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
        case .guests: return "Film, you, and your guests"
        }
    }

    /// Where the CALL's picture sits, or nil where this placement has none.
    ///
    /// DERIVED FROM THE CAMERA'S RECT, never computed beside it: the two tiles
    /// are one column and a second derivation is how they drift apart by a few
    /// pixels and stop reading as one thing. `guestAspect` is the captured
    /// WINDOW's, which is whatever shape the host's call app happens to be —
    /// so the width is fixed and the height follows, never the reverse.
    public func guestRect(in size: CGSize, cameraAspect: CGFloat,
                          guestAspect: CGFloat) -> CGRect? {
        guard showsGuests,
              let cam = rects(in: size, cameraAspect: cameraAspect).camera else { return nil }
        let gap = size.height * 0.02
        let h = cam.width / max(guestAspect, 0.1)
        let y = cam.maxY + gap
        // A tall call window would run the column off the top of the frame.
        // The tile is CLAMPED rather than allowed to overflow, because a
        // guest cropped by the frame edge looks like a fault.
        let ceiling = size.height - size.width * 0.05
        guard y < ceiling else { return nil }
        return CGRect(x: cam.minX, y: y, width: cam.width, height: min(h, ceiling - y))
    }

    /// Where the chat column sits, or nil when this layout has no room.
    ///
    /// LEFT by default, stopping above the lower third. In `side` the film
    /// occupies the left two thirds, so chat moves to the right column UNDER
    /// the camera — the same lesson the camera tiles taught: a layout decides
    /// where things can go, and assuming one position for all five is how
    /// `theatre` ended up drawing over the lower third.
    /// §D22 — `side` MIRRORS the computed rect rather than choosing a new
    /// one. Every case below dodges the lower third and the camera tile for
    /// this preset; re-deriving those dodges for a second side is how the two
    /// copies drift, and one of them already had a sign error that ran the
    /// column through the host's face.
    public func chatRect(in size: CGSize, cameraAspect: CGFloat,
                         side: StudioChatSide = .left,
                         guestAspect: CGFloat? = nil) -> CGRect? {
        guard let r = chatRectLeft(in: size, cameraAspect: cameraAspect) else { return nil }
        guard side == .right else { return r }
        var m = CGRect(x: size.width - r.maxX, y: r.minY, width: r.width, height: r.height)
        // A MIRROR IS ONLY SAFE WHERE THE FRAME IS SYMMETRIC, AND IT IS NOT.
        //
        // `chatRectLeft` dodges the camera for THIS preset, and every preset
        // that shows one puts it on the RIGHT — so the mirrored column lands
        // straight on the host's face. That is the 2026-09-17 defect (§D22)
        // arriving by a new route, and it was caught by the test rather than
        // by reading this function, which is the only reason it is not shipped.
        //
        // The column yields, never the camera: a host who moved chat to the
        // right did not ask for their own face to move.
        // The camera AND the call, because §D23's placement stacks both on the
        // right and a column that dodged only one would land on the other.
        var obstacles: [CGRect] = []
        if let cam = rects(in: size, cameraAspect: cameraAspect).camera, showsCamera {
            obstacles.append(cam)
        }
        // THE REAL SHAPE, not a guess. The first version assumed 16:9 with a
        // comment calling that "the safe direction" — which is backwards: a
        // WIDER window makes a SHORTER tile, so the guess under-estimated a
        // 4:3 call by 63 px and the column landed on it. Caught by §8.42 at
        // the first non-16:9 shape it tried. `nil` means no call is attached,
        // so there is no tile to dodge.
        if let ga = guestAspect,
           let g = guestRect(in: size, cameraAspect: cameraAspect, guestAspect: ga) {
            obstacles.append(g)
        }
        for cam in obstacles {
            let gap = size.height * 0.02
            if m.intersects(cam) {
                let floor = cam.maxY + gap                 // CI: y grows upward
                m = CGRect(x: m.minX, y: floor, width: m.width,
                           height: max(0, m.maxY - floor))
            }
        }
        // A column too short to hold one line is not a column; say nothing
        // rather than draw a sliver.
        return m.height >= size.height * 0.08 ? m : nil
    }

    /// §D26 — CHAT YIELDS TO A SHOUT-OUT, it is not covered by one.
    ///
    /// The lower third sitting OVER chat is deliberate: a long message must
    /// never hide the film's own title. Applying that same rule to the banner
    /// put it straight through the last two lines a host had been reading —
    /// seen on the glass, with `kt_projects` behind it — because a banner is
    /// tall and arrives mid-conversation. So the column shortens for the
    /// twelve seconds one is up.
    ///
    /// Only on the LEFT: a banner is anchored to the lower third's 5% inset,
    /// so a right-hand column never meets it and shortening that one would
    /// take lines away for nothing.
    ///
    /// Returns `.null` when what is left is too short to be chat. A column
    /// with room for one line is worse than no column: it reads as chat having
    /// broken, rather than as one message being featured.
    public static func chatYielding(_ rect: CGRect, toOverlayTop top: CGFloat?,
                                    side: StudioChatSide, in size: CGSize) -> CGRect {
        guard let top, side == .left else { return rect }
        let clear = top + size.height * 0.015
        guard clear > rect.minY else { return rect }
        let shortened = CGRect(x: rect.minX, y: clear,
                               width: rect.width, height: rect.maxY - clear)
        return shortened.height > size.height * 0.12 ? shortened : .null
    }

    private func chatRectLeft(in size: CGSize, cameraAspect: CGFloat) -> CGRect? {
        let inset = size.width * 0.05
        switch self {
        case .film, .corner, .theatre, .host, .guests:
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

    /// Whether the camera is drawn as a TILE that can be moved and resized
    /// (§D14). In `host` it is the ground and there is nowhere to move it to;
    /// in `film` there is no camera at all.
    public var cameraIsTile: Bool { self != .film && self != .host }

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
        case .guests:
            // The host keeps EXACTLY `corner`'s tile — same size, same
            // position — so switching to this placement moves nobody who was
            // already framed. Only the guests are new.
            let w = size.width * 0.26
            let h = w / max(cameraAspect, 0.1)
            let inset = size.width * 0.05
            return (full, CGRect(x: size.width - w - inset, y: inset, width: w, height: h))
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

/// ONE MORE PLACE THE SAME SHOW GOES — simulcast (roadmap #2).
///
/// A name the host will recognise on a readout, and the address to send to.
/// The address already carries its stream key (`StudioGoLive.combine` joins
/// them), so this is never shown, logged or stored past the session — §4's
/// rule applies to an extra destination exactly as it does to the first.
public struct StudioExtraDestination: Sendable, Equatable {
    public let name: String
    public let url: URL
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

/// HOW THE HOST SITS IN THE SHOW — macOS-DESIGN §D14.
///
/// Owner, 2026-09-22: *"I'd like to be able to move my camera around the
/// preview window AND crop the video (to only capture my face, etc.)."*
///
/// §4 said layouts were presets and never free-form, and that rule bought
/// something real — five named arrangements rather than OBS's six decisions
/// per scene, and names that a television, a phone and a Mac can agree on.
/// What it got wrong was treating the tile's SIZE and POSITION, and the crop
/// of the camera's own picture, as part of the arrangement. They are not.
/// They are how a host fits themselves INTO an arrangement, and a webcam that
/// sees a whole room when the host wanted a face is a framing problem no
/// preset can solve.
///
/// So the preset still decides the arrangement and this rides on top of it.
/// It is deliberately NOT per-layout: a host who framed their face does not
/// want it undone by trying "Side by side". The crop follows the person; the
/// preset follows the show.
public struct StudioCameraFraming: Sendable, Equatable {

    /// THE TILE ITSELF, as a normalized rect in the program frame — origin
    /// BOTTOM-LEFT, matching Core Image and the layout rects this overrides.
    /// `nil` means "wherever the placement puts it".
    ///
    /// THIS REPLACED A SCALE AND TWO OFFSETS, and the reason is the owner's:
    /// *"Most people expect to crop the video frame (size and shape of the
    /// actual video tile) rather than zoom and move ... it is clunky
    /// implementation with four different sliders."* A scale can only make the
    /// preset's rectangle bigger or smaller; it can never change its SHAPE,
    /// and shape is what cropping a camera means. A 16:9 webcam in a 1:1 tile
    /// IS a crop, because the tile is aspect-FILLED.
    public var tile: CGRect?

    /// The crop taken from the CAMERA's own picture, 1 = the whole frame.
    /// Clamped at 4 because past that a 720p tile is upscaling more than it is
    /// cropping and the host looks worse than they did unzoomed.
    public var zoom: CGFloat = 1
    /// Where that crop sits inside the camera's picture, -1…1 of the travel
    /// the zoom makes available. At zoom 1 there is no travel and these do
    /// nothing, which is correct rather than a special case.
    public var panX: CGFloat = 0
    public var panY: CGFloat = 0

    public init() {}

    public var isDefault: Bool { tile == nil && zoom == 1 && panX == 0 && panY == 0 }

    public static let zoomRange: ClosedRange<CGFloat> = 1...4
    /// A tile may not be shrunk to nothing or grown past the frame.
    public static let minimumTileFraction: CGFloat = 0.06

    /// The tile the renderer should draw into: the host's, or the preset's.
    ///
    /// CLAMPED, not free. A tile dragged off the edge is one the host cannot
    /// get back, and an audience watching a sliver of a face is worse off than
    /// one watching none.
    public func apply(to preset: CGRect, in size: CGSize) -> CGRect {
        guard let tile else { return preset }
        let minW = size.width * Self.minimumTileFraction
        let minH = size.height * Self.minimumTileFraction
        var w = max(minW, min(size.width, tile.width * size.width))
        var h = max(minH, min(size.height, tile.height * size.height))
        w = min(w, size.width)
        h = min(h, size.height)
        let x = min(max(0, tile.minX * size.width), size.width - w)
        let y = min(max(0, tile.minY * size.height), size.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The crop to take from a camera frame of `extent`.
    public func crop(of extent: CGRect) -> CGRect {
        let z = min(max(Self.zoomRange.lowerBound, zoom), Self.zoomRange.upperBound)
        guard z > 1 else { return extent }
        let w = extent.width / z, h = extent.height / z
        // The travel is what the crop can move WITHOUT leaving the picture, so
        // pan is expressed against that rather than against the frame — which
        // is what makes -1 and 1 mean "as far as it goes" at every zoom rather
        // than "off the edge" at low ones.
        let travelX = (extent.width - w) / 2, travelY = (extent.height - h) / 2
        let cx = extent.midX + min(max(-1, panX), 1) * travelX
        let cy = extent.midY + min(max(-1, panY), 1) * travelY
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Normalize a rect the host dragged in the preview back into storage.
    public static func normalized(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        return CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                      width: rect.width / size.width, height: rect.height / size.height)
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

    /// §D26 — a message the host has put ON the broadcast, attributed.
    ///
    /// The one thing in this overlay that did not originate with the host.
    /// Everything else here — the cards, the lower third, the placement — is
    /// the host talking; this is the host listening, in public.
    public var shoutOut: ShoutOut?

    public struct ShoutOut: Sendable, Equatable {
        public var author: String
        public var text: String
        /// When it went up, so it can be cleared without anybody remembering
        /// to. A host reading a comment aloud is not also watching a timer.
        public var shownAt: Date
        /// §D26: long enough to read a sentence aloud and answer it.
        public static let seconds: TimeInterval = 12
        /// The banner never grows past this, because past it the graphic is
        /// covering the film rather than sitting under it.
        public static let maxLines = 4
        /// What the PICKER uses to refuse a message before the host puts it up.
        /// Derived from the renderer's own geometry — 38pt paper over 62% of a
        /// 1920 frame is ~62 characters a line — and §8.48 asserts the two
        /// agree by wrapping a string of exactly this length and counting.
        public static let maxCharacters = 62 * maxLines

        public static func tooLong(_ text: String) -> Bool {
            text.count > maxCharacters
        }

        public init(author: String, text: String, shownAt: Date = Date()) {
            self.author = author
            self.text = text
            self.shownAt = shownAt
        }
    }

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
        /// THE HOST'S OWN WORDS (macOS-DESIGN §D10).
        ///
        /// Owner, 2026-09-22: *"I'd like to be able to have a 'free text'
        /// option for the Cards. Ideally with multiple lines of different
        /// weights as the cards exist now."*
        ///
        /// The three fixed cards cover the three moments a watch-along always
        /// has. They do not cover the moment a host wants to say something
        /// else, and the answer to that was to say it aloud or not at all.
        ///
        /// What this deliberately is NOT: a text layer, a font picker, a
        /// colour picker or a position control. A card is a full-frame
        /// interruption drawn in the app's own typography. The host chooses
        /// the WORDS and their RANK; the design system keeps everything else,
        /// exactly as it does for the three fixed cards.
        case custom(lines: [CardLine])
    }

    /// One line of a custom card: the text, and which of the project's own
    /// hierarchy levels it occupies.
    ///
    /// The ranks are the SIX LEVELS CLAUDE.md already allows ("three weights ×
    /// two sizes"), named for what they do in a card rather than by point
    /// size, so the card cannot grow a seventh — which is the refusal that
    /// rule exists to make easy.
    public struct CardLine: Sendable, Equatable, Identifiable, Hashable {
        public enum Rank: String, Sendable, Equatable, CaseIterable, Hashable {
            case display, heading, body, caption

            public var label: String {
                switch self {
                case .display: return "Display"
                case .heading: return "Heading"
                case .body: return "Body"
                case .caption: return "Caption"
                }
            }
        }
        public var id: Int
        public var text: String
        public var rank: Rank

        public init(id: Int, text: String, rank: Rank) {
            self.id = id; self.text = text; self.rank = rank
        }
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
    /// §D14 — where the camera tile landed in the last composed frame,
    /// normalized to the program (origin bottom-left). Nil when no tile was
    /// drawn. A surface uses this to place drag handles on the REAL tile
    /// rather than on its own re-derivation of the layout.
    public var cameraTile: CGRect?
    /// Where the call's tile landed (§D24), so the handles sit on the rect
    /// the compositor USED rather than a re-derivation in the view.
    public var guestTile: CGRect?
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
    /// How many the host's own filter dropped (§D22). Reported rather than
    /// silent, because a filter that is quietly eating a conversation looks
    /// exactly like an audience that stopped talking — the same confusion
    /// §D21 names for the film, one layer up.
    public var chatLinesFiltered = 0
    /// §D26 — the host's reader, newest last. Not what the audience sees.
    public var chatRecent: [StudioOverlay.ChatLine] = []
    /// Whether the call's picture is reaching the program (§D23).
    public var guestsAttached = false
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

    /// EVERY OTHER DESTINATION, named. §4 says health is never hidden, and a
    /// simulcast averages into a lie: "82% of frames delivered" describes no
    /// destination and hides that one of them is dead. The PRIMARY stays in
    /// `publisher` so that every readout written before simulcast existed
    /// keeps working unchanged; these are the rest.
    public var extraDestinations: [ExtraDestination] = []

    public struct ExtraDestination: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var health: RTMPHealth
    }
    public var audio = StudioAudioHealth()
    /// True when a destination was supplied. Without one the engine still
    /// composites and encodes — it just sends nowhere.
    public var hasDestination = false
    /// Why the show ended, when it ended on its own account rather than
    /// because the host stopped it (§6.6's expired deadline; §6.5's
    /// `.critical` thermal state, which is still UNIMPLEMENTED — the rule is
    /// written and nothing acts on it).
    public var endedReason: String?

    /// The FILM has ended; the SHOW has not (owner item 13, §9.bbbbbb). Not a
    /// fault — a state a host must be told about, because their audience is
    /// looking at a frozen frame with a live camera tile over it.
    public var filmEnded = false

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
    /// The ONE place the host's output choices reach the engine — Decision
    /// 133: a control is proved where its value lands.
    mutating func applyOutputSettings() {
        width = StudioOutputSettings.width
        height = StudioOutputSettings.height
        frameRate = StudioOutputSettings.frameRate
        videoBitrate = StudioOutputSettings.bitrateKbps * 1_000
    }

    static func benchDoored() -> StudioEngine.Configuration {
        var c = StudioEngine.Configuration()
        // THE HOST'S OWN SETTINGS FIRST (§D4), the bench door second — the
        // door is a DEBUG override and must be able to override, but with
        // nothing set it must not quietly reinstate the hardcoded defaults
        // the host just changed.
        c.applyOutputSettings()
        #if DEBUG
        if let kbps = ProcessInfo.processInfo.environment["AW_STUDIO_BITRATE"]
            .flatMap(Int.init), kbps > 0 {
            c.videoBitrate = kbps * 1_000
        }
        #endif
        return c
    }
}

/// The composed programme frame, shared with whoever wants to LOOK at it.
///
/// §C5: the Mac's preview must draw the frame the ENCODER receives, not an
/// approximation assembled again in SwiftUI — "what I see" and "what they see"
/// diverging is the exact failure Decision 133 is about. The engine is an
/// actor and `CVPixelBuffer` is not Sendable, so the frame crosses isolation
/// the way the camera's already does: a lock-guarded box that the producer
/// writes and any thread may read.
public final class StudioProgramMirror: @unchecked Sendable {
    public static let shared = StudioProgramMirror()
    private let lock = NSLock()
    private var frame: CVPixelBuffer?
    private var generation: UInt64 = 0

    public func publish(_ buffer: CVPixelBuffer) {
        lock.lock(); frame = buffer; generation &+= 1; lock.unlock()
    }
    /// The newest frame and its generation, so a view can skip a redraw when
    /// nothing has changed rather than re-rendering the same picture at 30 Hz.
    public func latest() -> (CVPixelBuffer, UInt64)? {
        lock.lock(); defer { lock.unlock() }
        guard let frame else { return nil }
        return (frame, generation)
    }
    public func clear() { lock.lock(); frame = nil; lock.unlock() }
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

    /// §D22 — the host's own three chat controls, held on the ENGINE because
    /// that is where the pump and the compositor both read them. `showChat`
    /// above is the OVERLAY's flag (is there a column in this frame); these
    /// are the host's intent, which the pump turns into that flag.
    public var chatEnabled = true
    public var chatFilter = StudioChatFilter()
    /// Stored on the RENDERER, which is the object that draws with it. A
    /// second copy here would be a value that can disagree with the frame —
    /// the exact shape Decision 133 is about.
    public var chatSide: StudioChatSide {
        get { renderer.chatSide }
        set { renderer.chatSide = newValue }
    }

    public private(set) var health = StudioHealth()
    /// One §6.6 recovery episode at a time (see `recoverIfSevered`).
    private var recovering = false
    private var filmEndObserver: (any NSObjectProtocol)?
    private var filmRateObserver: NSKeyValueObservation?
    private var supervisor: Task<Void, Never>?
    private var thermalWatcher: Task<Void, Never>?
    public private(set) var layout: StudioLayout = .corner
    public private(set) var overlay = StudioOverlay()

    // `var`, because §D4 lets the host change the bitrate mid-show and §6.5's
    // thermal RECOVERY restores to `config.videoBitrate` — so a stale value
    // here would quietly undo the host's choice minutes after they made it.
    private var config: Configuration
    private let publisher: RTMPPublisher
    private let renderer: ProgramRenderer
    private var encoder: H264Encoder?

    /// Whether the video encoder in use is the hardware one — nil until a show
    /// has started. Reported rather than assumed (§9.vv).
    public var encoderIsHardware: Bool? { encoder?.usingHardware }
    private var filmOutput: AVPlayerItemVideoOutput?
    private weak var filmPlayer: AVPlayer?
    private var cameraTap: CameraFrameTap?
    private var guestSource: GuestFrameSource?
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
                         duckEnabled: Bool? = nil,
                         callGain: Float? = nil, callMuted: Bool? = nil,
                         micGateEnabled: Bool? = nil, micGateThreshold: Float? = nil) {
        if let filmGain { mixer.filmGain = filmGain }
        if let micGain { mixer.micGain = micGain }
        if let filmMuted { mixer.filmMuted = filmMuted }
        if let micMuted { mixer.micMuted = micMuted }
        if let duckEnabled { mixer.duckEnabled = duckEnabled }
        if let callGain { mixer.callGain = callGain }
        if let callMuted { mixer.callMuted = callMuted }
        if let micGateEnabled { mixer.micGateEnabled = micGateEnabled }
        if let micGateThreshold { mixer.micGateThreshold = micGateThreshold }
    }

    /// Attach (or detach) the CALL's audio — §D2's fourth input.
    ///
    /// The ring, not the tap: `AudioHardwareCreateProcessTap` is macOS-only
    /// and this file compiles on four platforms, so the engine takes the one
    /// thing every platform's audio path already understands.
    nonisolated func attachCallAudio(ring: AudioRing?) {
        mixer.callRing = ring
    }

    /// What the mixer is set to, so a surface can SHOW the gains rather than
    /// keep its own copy and drift from them (Rule 8.8c).
    public var audioSettings: (filmGain: Float, micGain: Float, duckEnabled: Bool) {
        (mixer.filmGain, mixer.micGain, mixer.duckEnabled)
    }

    public func setLayout(_ l: StudioLayout) { layout = l; renderer.layout = l }

    /// §D22 — all three at once. Separate setters would let a surface push
    /// two and forget the third, which is how the layout picker stayed inert
    /// on one platform for a session (Decision 133).
    /// §D23's call picture, as a PULLER rather than a buffer — the same
    /// shape as `cameraTap`. Detaching sets it to nil, so a tile of a call
    /// that has ended disappears rather than freezing: a still of people who
    /// have gone looks live, which is the worst of the three states.
    public func attachGuests(_ source: GuestFrameSource?) {
        guestSource = source
        health.guestsAttached = source != nil
    }

    /// §D26. Replaces whatever is up: one at a time, because a queue turns
    /// an acknowledgment into a ticker.
    public func showShoutOut(author: String, text: String) {
        overlay.shoutOut = StudioOverlay.ShoutOut(author: author, text: text)
        renderer.overlay = overlay
    }

    /// What is on screen, for the surface's mirror.
    public var currentShoutOut: StudioOverlay.ShoutOut? { overlay.shoutOut }

    public func clearShoutOut() {
        guard overlay.shoutOut != nil else { return }
        overlay.shoutOut = nil
        renderer.overlay = overlay
    }

    /// Clears a shout-out that has had its twelve seconds. Called on the same
    /// once-a-second beat the provenance line uses, rather than a timer of its
    /// own — one clock for the overlay's self-clearing things.
    @discardableResult
    public func expireShoutOutIfDue() -> Bool {
        guard let s = overlay.shoutOut else { return false }
        guard Date().timeIntervalSince(s.shownAt) > StudioOverlay.ShoutOut.seconds else {
            return false
        }
        overlay.shoutOut = nil
        renderer.overlay = overlay
        return true
    }

    public func setChatControls(enabled: Bool, side: StudioChatSide,
                                filter: StudioChatFilter) {
        chatEnabled = enabled
        chatSide = side
        chatFilter = filter
        // TAKE EFFECT NOW, not on the next message. A host turning chat off
        // mid-show expects the column gone, and the pump only runs when new
        // lines arrive — on a quiet channel that could be minutes.
        // §D22a: the host's toggle can only ever turn it OFF while nothing is
        // going out. Turning it on does not conjure an audience.
        overlay.showChat = enabled && health.showState.isOnAir
        if overlay.showChat { overlay.chat = filter.apply(overlay.chat) } else { overlay.chat = [] }
        renderer.overlay = overlay
    }
    /// §D14 — how the host sits in whichever arrangement is chosen.
    public func setCameraFraming(_ f: StudioCameraFraming) { renderer.framing = f }
    public func setGuestFraming(_ f: StudioCameraFraming) { renderer.guestFraming = f }
    public var guestFraming: StudioCameraFraming { renderer.guestFraming }
    public var cameraFraming: StudioCameraFraming { renderer.framing }
    public func setOverlay(_ o: StudioOverlay) { overlay = o; renderer.overlay = o }

    /// THE ONE OUTPUT SETTING THAT MAY CHANGE MID-SHOW (§D4).
    ///
    /// Resolution and frame rate cannot: an RTMP ingest will not accept a
    /// change to either mid-publish, which is the correction §6.5 already
    /// carries. The bitrate can, and the encoder already does it for thermal
    /// steps, so a host asking for it is the same path §6.5 uses.
    ///
    /// `config.videoBitrate` is updated too, or the next thermal RECOVERY
    /// would restore the OLD rate — §6.5 restores to `config.videoBitrate`,
    /// so leaving it stale would quietly undo the host's choice minutes later.
    @discardableResult
    public func setVideoBitrate(_ bps: Int) -> Bool {
        guard bps > 0 else { return false }
        config.videoBitrate = bps
        await_publisherBudget(bps)
        guard let encoder else { return false }
        let ok = encoder.setBitrate(bps)
        if ok { health.videoBitrateNow = bps }
        return ok
    }

    private func await_publisherBudget(_ bps: Int) {
        Task { await publisher.setQueueBudget(videoBitrate: bps,
                                              audioBitrate: config.audioBitrate) }
    }

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

    /// Simulcast (roadmap #2). One encode, several destinations — the
    /// expensive half (composite, then H.264) is already done once, so a
    /// second destination costs a second socket and no more CPU.
    ///
    /// WHY NOT A LIST THAT INCLUDES THE PRIMARY. The primary drives
    /// `showState`, §6.6's reconnect and §6.4's back-pressure, and those rules
    /// are written against one connection. Promoting them to "the worst of N"
    /// is a real design question — should a dead Twitch end a healthy YouTube
    /// show? — and the answer is no, so the primary keeps its meaning and
    /// extras are best-effort. A failing extra is VISIBLE (it has its own
    /// health) and does not end anything.
    private var extraPublishers: [(name: String, publisher: RTMPPublisher)] = []


    private var twitchChat: StudioChatTwitch?
    /// YouTube's half. Polled rather than streamed, because the Data API
    /// offers a client of our type no streaming chat interface at all and
    /// tells us in each response how soon to ask again (§D-roadmap #3).
    private var youtubeChat: StudioChatYouTube?

    /// Reads a Twitch channel into the overlay, for as long as the show runs.
    ///
    /// IN THE ENGINE, not in a surface. The first version of this lived in
    /// `StudioSession`, which is macOS-first by its own header — so chat
    /// reached the Mac and neither the television nor the phone, and PARITY
    /// said it reached all three. That is exactly how §6.2's audio session and
    /// §6.3's idle timer came to be implemented in one place only. Runtime
    /// behaviour belongs where the engine is; a surface's job is to name the
    /// channel.
    /// Reads a YouTube broadcast's chat for as long as the show runs.
    ///
    /// The `liveChatID` comes from the `liveBroadcasts.insert` that created
    /// this very broadcast — it is carried here by `StudioGoLive.Destination`,
    /// which is the change that made this possible at all: the id was being
    /// read and dropped in the same function.
    public func attachYouTubeChat(liveChatID: String,
                                  fetch: @escaping StudioChatYouTube.Fetch) async {
        guard !liveChatID.isEmpty else { return }
        let chat = StudioChatYouTube()
        youtubeChat = chat
        await chat.start(liveChatID: liveChatID, fetch: fetch)
    }

    /// A CONVERSATION WE INVENTED, for `AW_STUDIO_CHAT_DEMO`.
    ///
    /// The older `AW_STUDIO_CHAT` door names a REAL Twitch channel, which is
    /// how strangers' messages ended up over the owner's film on 2026-09-22.
    /// Verifying §D26's audience pane needs lines, not a stranger, so these
    /// are written here — including the over-long one, because the row that
    /// REFUSES to be shown is the half a happy-path demo never reaches.
    private(set) var demoChat: [StudioOverlay.ChatLine] = []

    public func setDemoChat(_ lines: [StudioOverlay.ChatLine]) {
        demoChat = lines
    }

    public func attachTwitchChat(channel: String) async {
        guard !channel.isEmpty else { return }
        let chat = StudioChatTwitch()
        twitchChat = chat
        await chat.start(channel: channel)
        // NOT switched on here — `pumpChat` decides, and only on air (§D22a).
        renderer.overlay = overlay
    }

    /// Pulls the tail of the chat into the overlay. Called once a second from
    /// `refreshHealth`, which every surface already calls at that cadence —
    /// so no surface has to remember to do this.
    private func pumpChat() async {
        // EITHER SOURCE, one column. A broadcast reaches one platform at a
        // time, so at most one of these is running — but the pump asks both
        // rather than assuming which, because "whichever is attached" is a
        // fact the caller already established and this function should not
        // re-derive (Decision 133's rule, in its smallest form).
        let lines: [StudioOverlay.ChatLine]
        let received: Int
        if let chat = twitchChat {
            lines = await chat.lines
            received = await chat.health.linesReceived
        } else if let chat = youtubeChat {
            lines = await chat.lines
            received = await chat.health.linesReceived
        } else if !demoChat.isEmpty {
            lines = demoChat
            received = demoChat.count
        } else {
            return
        }
        guard !lines.isEmpty else { return }
        // FILTER BEFORE TAKING THE TAIL (§D22). The other order looks
        // identical and is not: filtering the last eight would leave a column
        // of two when six of them were bot commands, instead of showing the
        // eight most recent things a PERSON said. The host turned the bots
        // off to see more conversation, not less.
        // NO BROADCAST, NO CHAT (§D22a). A rehearsal is not going anywhere, so
        // there is no audience, so there is nobody chatting — and a column
        // drawn over one is showing the host something no viewer could ever
        // see. The owner, on being shown exactly that: *"Shouldn't there be no
        // chat on a stream that isn't going anywhere and certainly isn't going
        // to twitch to get a chat from twitch?"*
        //
        // It is checked HERE rather than at the attach, because a show can go
        // on air after a source is attached and can come off air while one
        // still is; the question is about THIS FRAME.
        guard health.showState.isOnAir else {
            if overlay.showChat || !overlay.chat.isEmpty {
                overlay.showChat = false
                overlay.chat = []
                renderer.overlay = overlay
            }
            return
        }
        let kept = chatFilter.apply(lines)
        let tail = Array(kept.suffix(8))
        health.chatLinesFiltered = lines.count - kept.count
        // §D26 — THE HOST'S OWN COPY, and it is not the audience's.
        // The composited tail is eight lines because that is what fits beside
        // a film; a host reading along wants more, and wants them whether or
        // not chat is being shown to anybody. These are the lines they can put
        // on screen, so they are POST-filter: a host cannot elevate something
        // they have already told the program to hide.
        health.chatRecent = Array(kept.suffix(40))
        guard tail.map(\.id) != overlay.chat.map(\.id)
                || overlay.showChat != chatEnabled else { return }
        overlay.showChat = chatEnabled
        overlay.chat = tail
        renderer.overlay = overlay
        health.chatLinesCarried = tail.count
        health.chatLinesReceived = received
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
        observeFilmEnd(player: player)
        // The film's audio, tapped off the mix it is already decoding. A film
        // with no audio track is a REAL case in this catalog (silent cinema),
        // so a false return is recorded, never treated as a failure.
        if let item = player.currentItem {
            sourceHasAudio = await Self.assetHasAudio(item)
            audioAttached = await mixer.film.attach(to: item)
        }
    }

    /// THE FILM ENDING, OBSERVED WHERE ALL THREE PLATFORMS MEET.
    ///
    /// Owner item 13 / §9.bbbbbb: a 60-second film and a 97-second broadcast
    /// leave the audience on a frozen final frame with the camera tile live
    /// over it, and nothing says so. Continuing to broadcast is RIGHT — the
    /// owner's rule is that "the stream should only end when the person
    /// streaming it decides that it should end" — but §4 says health is never
    /// hidden, and "your audience is watching a still" is health.
    ///
    /// §9.bbbbbb named the hard part as telling "ended" from "buffering",
    /// since `filmFramesPulled` stopping is true of both, and a false positive
    /// would be a new way to ruin a broadcast. It dissolves by not inferring
    /// it: `didPlayToEndTimeNotification` is the PLAYER saying so.
    ///
    /// IT LIVES HERE, not in `StudioSession`, because only macOS goes through
    /// that object — tvOS attaches from `DetailView` and iOS from
    /// `StudioPlayerContainer_iOS`. `attachFilm` is the one function all three
    /// call, which is what Decision 133 means by a shared code PATH rather
    /// than a shared type.
    private func observeFilmEnd(player: AVPlayer) {
        if let filmEndObserver { NotificationCenter.default.removeObserver(filmEndObserver) }
        health.filmEnded = false
        filmEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { await self.setFilmEnded(true) }
            }
        // A HOST WHO SEEKS BACK IS WATCHING AGAIN. A warning that stays true
        // after it stops being true is one nobody reads the next time.
        filmRateObserver = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] p, _ in
            guard let self, p.timeControlStatus == .playing else { return }
            Task { await self.setFilmEnded(false) }
        }
    }

    private func setFilmEnded(_ ended: Bool) {
        guard health.filmEnded != ended else { return }
        health.filmEnded = ended
        if ended { awdiag("AWFILMEND the film reached its end; the show continues") }
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
    /// `additional` are simulcast destinations (roadmap #2): the same encoded
    /// frames, sent to more sockets. They are BEST-EFFORT — one that refuses
    /// to connect is reported and does not stop the show, because a dead
    /// Twitch must not end a healthy YouTube broadcast.
    public func start(destination: URL?,
                      additional: [StudioExtraDestination] = []) async throws {
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
            // THE EXTRAS, each in its own `do` so one refusal cannot throw the
            // show away. The PRIMARY above is allowed to throw — a host who
            // asked to go live and reached nothing should hear about it — and
            // that asymmetry is the whole design: `try` above, `try?` with a
            // recorded reason here.
            for spec in additional {
                let extra = RTMPPublisher()
                await extra.setQueueBudget(videoBitrate: config.videoBitrate,
                                           audioBitrate: config.audioBitrate)
                do {
                    try await extra.publish(to: spec.url, config: streamConfig)
                    extraPublishers.append((spec.name, extra))
                    awdiag("AWPUB simulcast: %@ connected", spec.name)
                } catch {
                    // NAMED, not silent. An extra that never connected and an
                    // extra that connected and stalled look identical on a
                    // readout that only counts bytes, and they need opposite
                    // fixes.
                    var dead = RTMPHealth()
                    dead.lastError = "\(error)"
                    health.extraDestinations.append(
                        StudioHealth.ExtraDestination(name: spec.name, health: dead))
                    awdiag("AWPUB simulcast: %@ FAILED — %@", spec.name, "\(error)")
                }
            }
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
        // AND THE YOUTUBE POLLER, or a finished show keeps asking YouTube for
        // the chat of a broadcast that has ended — every 5 seconds, for as
        // long as the app is open. A reader that outlives its show is the
        // same defect as a player that outlives its window (§D12).
        if let chat = youtubeChat { await chat.stop() }
        youtubeChat = nil
        ticker?.cancel(); ticker = nil
        mixer.stop()
        encoder?.stop(); encoder = nil
        if publishing { await publisher.close() }
        for extra in extraPublishers { await extra.publisher.close() }
        extraPublishers = []
        health.isRunning = false
        if publishing { health.publisher = await publisher.health }
    }

    public func refreshHealth() async {
        health.encoderIsHardware = encoder?.usingHardware
        if publishing { health.publisher = await publisher.health }
        // EACH extra by name. Rebuilt rather than mutated so a destination
        // that failed to connect (already in the list, carrying its reason)
        // is not overwritten by a publisher that never existed.
        if publishing, !extraPublishers.isEmpty {
            var rows: [StudioHealth.ExtraDestination] = health.extraDestinations.filter { row in
                !extraPublishers.contains { $0.name == row.name }
            }
            for extra in extraPublishers {
                rows.append(StudioHealth.ExtraDestination(
                    name: extra.name, health: await extra.publisher.health))
            }
            health.extraDestinations = rows
        }
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
        health.cameraTile = renderer.lastCameraRect
        health.guestTile = renderer.lastGuestRect
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
        renderer.guestFrame = guestSource?.latest()
        let program = renderer.render(film: lastFilmFrame, camera: cameraTap?.latest())
        StudioProgramMirror.shared.publish(program)
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
        for extra in extraPublishers {
            await extra.publisher.send(audioFrame: frame, presentationTime: pts)
        }
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
        // THE SAME ENCODED FRAME, not a second encode. `EncodedVideoFrame`
        // carries the AVCC bytes that already exist; handing it to a second
        // publisher costs a copy into a queue.
        for extra in extraPublishers {
            await extra.publisher.send(video: frame)
        }
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
// `CACurrentMediaTimeCompat` MOVED to StudioAudio.swift, the lower layer that
// also uses it. It lived here, which meant `StudioAudio` could not compile
// without the whole engine — and §8.38, a test of a pure value type with no
// ring and no clock, dragged in six files to reach one inline function.

// MARK: - Program renderer

/// Draws one program frame: the film, the camera, the lower third, the cards.
/// Core Image onto a Metal-backed pool, so the composite stays on the GPU and
/// the encoder gets a pixel buffer it can take without a copy.
final class ProgramRenderer: @unchecked Sendable {
    let size: CGSize
    var layout: StudioLayout = .corner
    /// §D14 — the host's own framing, on top of whatever the layout decides.
    var framing = StudioCameraFraming()
    /// Where the call tile landed, normalized — published for the same reason
    /// the camera's is (Decision 133): a surface must read the rect the
    /// compositor USED, never re-derive it.
    private(set) var lastGuestRect: CGRect?
    /// §D24 — the guests' own framing. A SECOND instance of the same value
    /// type, never a parallel one: a call window needs cropping more than a
    /// webcam does, because Zoom and Meet wrap the grid in chrome a host does
    /// not want to broadcast.
    var guestFraming = StudioCameraFraming()

    /// §D22. On the RENDERER, beside `framing`, because that is the object
    /// that draws the frame — the engine's `chatSide` is the host's intent and
    /// this is where it lands. Two names for one fact is Decision 133's whole
    /// subject, so the setter below is the only writer.
    var chatSide: StudioChatSide = .left
    /// The call's latest picture (§D23), written once per composite from the
    /// engine's puller — never held across frames, so a call that stops
    /// drawing disappears rather than freezing.
    var guestFrame: CVPixelBuffer?
    /// The camera tile's rect in the LAST composed frame, normalized. Read by
    /// the Studio window to place its drag handles (§D14).
    private(set) var lastCameraRect: CGRect?
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
        if camera == nil || cameraRect == nil || !layout.showsCamera { lastCameraRect = nil }
        let drawFilm = { [self] (base: CIImage) -> CIImage in
            guard let film else { return base }
            return fit(CIImage(cvPixelBuffer: film), into: filmRect).composited(over: base)
        }
        let drawCamera = { [self] (base: CIImage) -> CIImage in
            guard let camera, let cameraRect, layout.showsCamera else { return base }
            // §D14: the HOST'S FRAMING, applied where the pixels are — the
            // crop to the camera's own picture, then the tile's size and
            // position. `apply` is a no-op on a default framing and on a
            // layout where the camera is the ground, so there is one path
            // rather than a branch per layout.
            let placed = layout.cameraIsTile
                ? framing.apply(to: cameraRect, in: size) : cameraRect
            // WHERE THE TILE ACTUALLY LANDED, normalized, so a surface can put
            // its handles on the real thing instead of recomputing the layout
            // and drifting from it. That recomputation is exactly the "two
            // descriptions of one picture" Decision 133 keeps finding.
            lastCameraRect = StudioCameraFraming.normalized(placed, in: size)
            var src = CIImage(cvPixelBuffer: camera)
            let crop = framing.crop(of: src.extent)
            if crop != src.extent { src = src.cropped(to: crop) }
            return fill(src, into: placed).composited(over: base)
        }
        // THE CALL, between the film and the host. Drawn before the camera so
        // the host is never occluded by their own guests — the tiles do not
        // overlap today, and this keeps that true if a placement ever lets
        // them.
        func drawGuests(_ base: CIImage) -> CIImage {
            guard layout.showsGuests, let g = guestFrame else { return base }
            var src = CIImage(cvPixelBuffer: g)
            let aspect = src.extent.height > 0 ? src.extent.width / src.extent.height : 16.0/9.0
            guard let preset = layout.guestRect(in: size, cameraAspect: cameraAspect,
                                                guestAspect: aspect) else { return base }
            // §D24 — the placement decides where the tile STARTS, the host
            // decides where it ends up. Same two steps as the camera: the box
            // is displaced and reshaped, then the SOURCE is cropped into it.
            let placed = guestFraming.apply(to: preset, in: size)
            lastGuestRect = StudioCameraFraming.normalized(placed, in: size)
            let crop = guestFraming.crop(of: src.extent)
            if crop != src.extent { src = src.cropped(to: crop) }
            return fill(src, into: placed).composited(over: base)
        }
        image = layout.cameraIsBackground
            ? drawFilm(drawCamera(drawGuests(image)))
            : drawCamera(drawGuests(drawFilm(image)))
        // Chat under the lower third, so a long message can never obscure the
        // film's own title. A SEPARATE cached layer: chat changes every few
        // seconds and the lower third does not, and one cache key for both
        // would re-rasterise the type on every message.
        // Rasterised BEFORE chat now, because its height decides chat's.
        let l3 = overlayRenderer.image(for: overlay)
        if overlay.showChat, !overlay.chat.isEmpty,
           var rect = layout.chatRect(in: size, cameraAspect: cameraAspect, side: chatSide,
                                      guestAspect: guestFrame.map {
                                          let e = CIImage(cvPixelBuffer: $0).extent
                                          return e.height > 0 ? e.width / e.height : 16.0/9.0
                                      }) {
            rect = StudioLayout.chatYielding(rect,
                                             toOverlayTop: overlay.shoutOut == nil
                                                ? nil : l3?.extent.maxY,
                                             side: chatSide, in: size)
            if !rect.isEmpty,
               let chat = overlayRenderer.chatImage(for: overlay, in: rect) {
                image = chat.composited(over: image)
            }
        }
        // The lower third sits ON TOP of both, and is a cached bitmap — the
        // text is laid out only when its content changes, never per frame.
        if let l3 { image = l3.composited(over: image) }
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
