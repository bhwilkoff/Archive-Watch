#if os(macOS)
import Foundation
import CoreMedia

// Creation Studio data model (docs/macOS-DESIGN.md §3–§4, Decision 042).
//
// Rule 4a — references, never copies: a clip is a REFERENCE into archive.org
// (catalogItemID + sourceURL + ranges), never copied bytes. OTIO-SHAPED Codable
// (we emit `.otio` for interchange but do NOT vendor the OTIO library — no third-
// party Swift packages). Times are CMTime-exact (value/timescale), not Doubles, so
// frame-accurate boundaries survive round-trips and don't cap Phase 3 (shot-level
// granularity) or Phase 4 (word-level supercut segments) — the "don't paint later
// phases into a corner" checklist.

/// A CMTime-exact instant, Codable as a rational (value/timescale). Mirrors OTIO
/// RationalTime; converts losslessly to/from CMTime.
struct TimeStamp: Codable, Hashable, Sendable {
    var value: Int64
    var timescale: Int32

    init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
    init(_ t: CMTime) {
        // A non-numeric CMTime (indefinite/invalid) collapses to zero so the model
        // is always serialisable; callers guard real durations upstream.
        if t.isNumeric { value = t.value; timescale = t.timescale }
        else { value = 0; timescale = 600 }
    }
    init(seconds: Double, preferredTimescale: Int32 = 600) {
        self.init(CMTime(seconds: seconds, preferredTimescale: preferredTimescale))
    }

    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
    var seconds: Double { cmTime.seconds }

    static let zero = TimeStamp(value: 0, timescale: 600)
}

/// A CMTime-exact range as start + duration (OTIO TimeRange shape).
struct TimeRange: Codable, Hashable, Sendable {
    var start: TimeStamp
    var duration: TimeStamp

    init(start: TimeStamp, duration: TimeStamp) { self.start = start; self.duration = duration }
    init(_ r: CMTimeRange) { start = TimeStamp(r.start); duration = TimeStamp(r.duration) }
    init(startSeconds: Double, durationSeconds: Double, preferredTimescale: Int32 = 600) {
        start = TimeStamp(seconds: startSeconds, preferredTimescale: preferredTimescale)
        duration = TimeStamp(seconds: durationSeconds, preferredTimescale: preferredTimescale)
    }

    var cmRange: CMTimeRange { CMTimeRange(start: start.cmTime, duration: duration.cmTime) }
    var endSeconds: Double { start.seconds + duration.seconds }
}

/// A reusable reference to a trimmed window of an archive.org title — the unit of
/// the proxy-clip LIBRARY and the thing dropped onto a timeline. Pure references
/// (Rule 4a). `availableRange` is the source's full extent (OTIO available_range);
/// `sourceRange` is the user's in/out within it (OTIO source_range).
struct ProxyClip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var catalogItemID: String          // archive.org identifier (provenance + rights anchor)
    var sourceURL: URL                 // the playable video URL (Decision 021 stream source)
    var availableRange: TimeRange?     // full source extent if known (nil until probed)
    var sourceRange: TimeRange         // in/out the user marked
    var label: String                  // user-facing name (defaults to the title)
    var tags: [String]
    var posterFrameSeconds: Double     // where to grab the library thumbnail
    var title: String                  // denormalised so a project is self-describing offline

    init(id: UUID = UUID(), catalogItemID: String, sourceURL: URL,
         availableRange: TimeRange? = nil, sourceRange: TimeRange,
         label: String, tags: [String] = [], posterFrameSeconds: Double = 0, title: String) {
        self.id = id; self.catalogItemID = catalogItemID; self.sourceURL = sourceURL
        self.availableRange = availableRange; self.sourceRange = sourceRange
        self.label = label; self.tags = tags
        self.posterFrameSeconds = posterFrameSeconds; self.title = title
    }
}

/// One placed clip on the project timeline. Carries its own source reference
/// (denormalised from the library so the `.archiveproj` is portable even if the
/// library entry is later deleted) plus where it sits and which track it's on.
struct TimelineClip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var proxyClipID: UUID?             // origin library entry, if any (else ad-hoc)
    var catalogItemID: String
    var sourceURL: URL
    var sourceRange: TimeRange         // in/out within the source
    var timelineStart: TimeStamp       // position on the timeline
    var track: Int                     // video: 0 = main A, 1 = overlay B (A/B scheme, Rule 3c)
    var label: String

    /// Duration on the timeline equals the source window's duration (no speed change in
    /// Phase 1 — speed ramps are a later layer on the same spine).
    var timelineRange: TimeRange { TimeRange(start: timelineStart, duration: sourceRange.duration) }

    init(id: UUID = UUID(), proxyClipID: UUID? = nil, catalogItemID: String, sourceURL: URL,
         sourceRange: TimeRange, timelineStart: TimeStamp, track: Int = 0, label: String) {
        self.id = id; self.proxyClipID = proxyClipID; self.catalogItemID = catalogItemID
        self.sourceURL = sourceURL; self.sourceRange = sourceRange
        self.timelineStart = timelineStart; self.track = track; self.label = label
    }

    static func from(_ proxy: ProxyClip, at start: TimeStamp, track: Int = 0) -> TimelineClip {
        TimelineClip(proxyClipID: proxy.id, catalogItemID: proxy.catalogItemID,
                     sourceURL: proxy.sourceURL, sourceRange: proxy.sourceRange,
                     timelineStart: start, track: track, label: proxy.label)
    }
}

/// A render canvas size, Codable.
struct RenderSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double
    var cgSize: CGSize { CGSize(width: width, height: height) }
    static let hd1080 = RenderSize(width: 1920, height: 1080)
}

/// A timed text overlay (title / lower-third / caption) burned in over the timeline via
/// the Core Animation tool (Phase 2 #3). Timeline-global with its own on-screen window, so
/// a title can sit over any clip or a gap. Position is normalized (0…1); y is from the TOP.
struct TextOverlay: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var text: String
    var timelineRange: TimeRange        // when it's visible on the timeline
    var positionX: Double               // 0…1, 0.5 = center
    var positionY: Double               // 0…1 from top, 0.85 = lower third
    var fontScale: Double               // fraction of render width
    var colorHex: String
    var hasBackground: Bool             // legibility shadow

    init(id: UUID = UUID(), text: String, timelineRange: TimeRange,
         positionX: Double = 0.5, positionY: Double = 0.85, fontScale: Double = 0.05,
         colorHex: String = "#FFFFFF", hasBackground: Bool = true) {
        self.id = id; self.text = text; self.timelineRange = timelineRange
        self.positionX = positionX; self.positionY = positionY; self.fontScale = fontScale
        self.colorHex = colorHex; self.hasBackground = hasBackground
    }
}

/// The ordered set of clips + render settings. Compiles (Unit 2) to the single
/// (AVMutableComposition, AVVideoComposition.Configuration, AVMutableAudioMix) triple
/// that feeds BOTH preview and export (Rule 3a).
struct Timeline: Codable, Hashable, Sendable {
    var clips: [TimelineClip]
    var textOverlays: [TextOverlay]
    var frameRate: Double
    var renderSize: RenderSize

    init(clips: [TimelineClip] = [], textOverlays: [TextOverlay] = [],
         frameRate: Double = 30, renderSize: RenderSize = .hd1080) {
        self.clips = clips; self.textOverlays = textOverlays
        self.frameRate = frameRate; self.renderSize = renderSize
    }

    // Tolerant decode: projects written before `textOverlays` existed default to [] (the
    // additive-schema discipline — old .archiveproj files keep opening). Encode synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clips = try c.decode([TimelineClip].self, forKey: .clips)
        textOverlays = try c.decodeIfPresent([TextOverlay].self, forKey: .textOverlays) ?? []
        frameRate = try c.decode(Double.self, forKey: .frameRate)
        renderSize = try c.decode(RenderSize.self, forKey: .renderSize)
    }

    /// Timeline end = the furthest clip end across all tracks.
    var durationSeconds: Double { clips.map { $0.timelineRange.endSeconds }.max() ?? 0 }
}

/// The contents of an `.archiveproj` document (Rule 2b — references + project-local
/// imports, NEVER archive.org bytes). `formatVersion` lets the reader evolve the
/// schema additively (the catalog-contract discipline applied to projects).
struct ClipProject: Codable, Hashable, Sendable {
    var formatVersion: Int
    var title: String
    var timeline: Timeline
    /// Burn the "archivewatch.org · Public Domain" credit into the export. Default ON
    /// (attribution is encouraged + is the social wedge), but the user can turn it OFF
    /// for a clean export — it is NOT mandatory (owner decision 2026-06-23, amending the
    /// learning gate / Rule 5b). The archive.org source still rides in file metadata.
    var burnAttribution: Bool
    var createdAt: Date
    var modifiedAt: Date

    static let currentFormatVersion = 1

    init(title: String = "Untitled", timeline: Timeline = Timeline(),
         burnAttribution: Bool = true, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.title = title; self.timeline = timeline
        self.burnAttribution = burnAttribution
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }

    // Tolerant decode: a project written before `burnAttribution` existed defaults to ON
    // (additive-schema discipline — old files keep working). Encode stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        title = try c.decode(String.self, forKey: .title)
        timeline = try c.decode(Timeline.self, forKey: .timeline)
        burnAttribution = try c.decodeIfPresent(Bool.self, forKey: .burnAttribution) ?? true
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    static var empty: ClipProject { ClipProject() }
}
#endif
