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
    var audioVolume: Double            // this clip's audio level in the mix, 0…1.5 (#4)
    var fadeInSeconds: Double          // fade up from black + audio in, over the clip's head
    var fadeOutSeconds: Double         // fade to black + audio out, over the clip's tail
    var transitionInSeconds: Double    // transition FROM the previous clip INTO this one (0 = cut)
    var transitionKindRaw: String      // dissolve | wipe | push (TransitionKind.rawValue)
    var lookRaw: String                // color grade id (ClipLook.rawValue; "none" = ungraded)

    /// Duration on the timeline equals the source window's duration (no speed change in
    /// Phase 1 — speed ramps are a later layer on the same spine).
    var timelineRange: TimeRange { TimeRange(start: timelineStart, duration: sourceRange.duration) }

    init(id: UUID = UUID(), proxyClipID: UUID? = nil, catalogItemID: String, sourceURL: URL,
         sourceRange: TimeRange, timelineStart: TimeStamp, track: Int = 0, label: String,
         audioVolume: Double = 1.0, fadeInSeconds: Double = 0, fadeOutSeconds: Double = 0,
         transitionInSeconds: Double = 0, transitionKindRaw: String = "dissolve", lookRaw: String = "none") {
        self.id = id; self.proxyClipID = proxyClipID; self.catalogItemID = catalogItemID
        self.sourceURL = sourceURL; self.sourceRange = sourceRange
        self.timelineStart = timelineStart; self.track = track; self.label = label
        self.audioVolume = audioVolume
        self.fadeInSeconds = fadeInSeconds; self.fadeOutSeconds = fadeOutSeconds
        self.transitionInSeconds = transitionInSeconds; self.transitionKindRaw = transitionKindRaw
        self.lookRaw = lookRaw
    }

    // Tolerant decode: pre-#4 clips default to full volume, pre-fades clips to 0 fade
    // (additive-schema discipline).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        proxyClipID = try c.decodeIfPresent(UUID.self, forKey: .proxyClipID)
        catalogItemID = try c.decode(String.self, forKey: .catalogItemID)
        sourceURL = try c.decode(URL.self, forKey: .sourceURL)
        sourceRange = try c.decode(TimeRange.self, forKey: .sourceRange)
        timelineStart = try c.decode(TimeStamp.self, forKey: .timelineStart)
        track = try c.decode(Int.self, forKey: .track)
        label = try c.decode(String.self, forKey: .label)
        audioVolume = try c.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1.0
        fadeInSeconds = try c.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 0
        fadeOutSeconds = try c.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 0
        transitionInSeconds = try c.decodeIfPresent(Double.self, forKey: .transitionInSeconds) ?? 0
        transitionKindRaw = try c.decodeIfPresent(String.self, forKey: .transitionKindRaw) ?? "dissolve"
        lookRaw = try c.decodeIfPresent(String.self, forKey: .lookRaw) ?? "none"
    }

    var look: ClipLook { ClipLook(rawValue: lookRaw) ?? .none }
    var transitionKind: TransitionKind { TransitionKind(rawValue: transitionKindRaw) ?? .dissolve }

    static func from(_ proxy: ProxyClip, at start: TimeStamp, track: Int = 0) -> TimelineClip {
        TimelineClip(proxyClipID: proxy.id, catalogItemID: proxy.catalogItemID,
                     sourceURL: proxy.sourceURL, sourceRange: proxy.sourceRange,
                     timelineStart: start, track: track, label: proxy.label)
    }
}

/// How a clip transitions in from the previous clip over the overlap. All are ramp-based on the
/// standard compositor (no Metal): dissolve = opacity, wipe = crop reveal, push = transform slide.
enum TransitionKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case dissolve, wipe, push
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
/// A single audio source on its own track (Rule 3c — audio on N tracks). The timeline holds an
/// ARRAY of these (multiple music + multiple voiceover), replacing the old single musicBed/voiceover.
enum AudioKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case music, voiceover
    var id: String { rawValue }
    var label: String { self == .music ? "Music" : "Voiceover" }
    var symbol: String { self == .music ? "music.note" : "mic" }
}

/// An imported/recorded audio clip mixed under the timeline (#4 audio layers). The file is copied
/// into the project's media cache (Rule 2b), so only its cache filename + mix settings are stored.
struct AudioClip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: AudioKind
    var fileName: String                // file inside ProjectMediaCache (copied on import/record)
    var displayName: String
    var volume: Double                  // 0…1.5
    var startSeconds: Double            // where it begins on the timeline
    var fadeInSeconds: Double           // ramp up over the head
    var fadeOutSeconds: Double          // ramp down over the tail
    var sourceDuration: Double          // cached file length (block width + trim cap; 0 = unknown)

    init(id: UUID = UUID(), kind: AudioKind, fileName: String, displayName: String,
         volume: Double = 1.0, startSeconds: Double = 0,
         fadeInSeconds: Double = 0, fadeOutSeconds: Double = 0, sourceDuration: Double = 0) {
        self.id = id; self.kind = kind; self.fileName = fileName; self.displayName = displayName
        self.volume = volume; self.startSeconds = startSeconds
        self.fadeInSeconds = fadeInSeconds; self.fadeOutSeconds = fadeOutSeconds
        self.sourceDuration = sourceDuration
    }
}

/// LEGACY single-bed shape — kept only so projects written before multi-track audio still decode
/// (migrated into `audioClips` in Timeline.init(from:)). Do NOT use for new code.
struct MusicBed: Codable, Hashable, Sendable {
    var fileName: String
    var displayName: String
    var volume: Double
    var startSeconds: Double
}

struct Timeline: Codable, Hashable, Sendable {
    var clips: [TimelineClip]
    var textOverlays: [TextOverlay]
    var frameRate: Double
    var renderSize: RenderSize
    var markers: [Double]               // timeline seconds — navigation + snap targets
    var audioClips: [AudioClip]         // N music + voiceover tracks (replaces musicBed/voiceover)

    init(clips: [TimelineClip] = [], textOverlays: [TextOverlay] = [],
         frameRate: Double = 30, renderSize: RenderSize = .hd1080, markers: [Double] = [],
         audioClips: [AudioClip] = []) {
        self.clips = clips; self.textOverlays = textOverlays
        self.frameRate = frameRate; self.renderSize = renderSize; self.markers = markers
        self.audioClips = audioClips
    }

    enum CodingKeys: String, CodingKey {
        case clips, textOverlays, frameRate, renderSize, markers, audioClips
        case musicBed, voiceover        // legacy keys — decode-only (migration)
    }

    // Tolerant decode: a project written before multi-track audio carried a single `musicBed`
    // and/or `voiceover`; migrate them into `audioClips` so old .archiveproj files keep opening
    // (additive-schema discipline).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clips = try c.decode([TimelineClip].self, forKey: .clips)
        textOverlays = try c.decodeIfPresent([TextOverlay].self, forKey: .textOverlays) ?? []
        frameRate = try c.decode(Double.self, forKey: .frameRate)
        renderSize = try c.decode(RenderSize.self, forKey: .renderSize)
        markers = try c.decodeIfPresent([Double].self, forKey: .markers) ?? []
        if let arr = try c.decodeIfPresent([AudioClip].self, forKey: .audioClips) {
            audioClips = arr
        } else {
            var migrated: [AudioClip] = []
            func migrate(_ bed: MusicBed?, _ kind: AudioKind) {
                guard let b = bed else { return }
                migrated.append(AudioClip(kind: kind, fileName: b.fileName, displayName: b.displayName,
                                          volume: b.volume, startSeconds: b.startSeconds))
            }
            migrate(try c.decodeIfPresent(MusicBed.self, forKey: .musicBed), .music)
            migrate(try c.decodeIfPresent(MusicBed.self, forKey: .voiceover), .voiceover)
            audioClips = migrated
        }
    }

    // Custom encode (the explicit CodingKeys include legacy keys we must NOT write).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clips, forKey: .clips)
        try c.encode(textOverlays, forKey: .textOverlays)
        try c.encode(frameRate, forKey: .frameRate)
        try c.encode(renderSize, forKey: .renderSize)
        try c.encode(markers, forKey: .markers)
        try c.encode(audioClips, forKey: .audioClips)
    }

    /// Timeline end = the furthest clip end across all tracks.
    var durationSeconds: Double { clips.map { $0.timelineRange.endSeconds }.max() ?? 0 }
}

/// The contents of an `.archiveproj` document (Rule 2b — references + project-local
/// imports, NEVER archive.org bytes). `formatVersion` lets the reader evolve the
/// schema additively (the catalog-contract discipline applied to projects).
struct ClipProject: Codable, Hashable, Sendable {
    var formatVersion: Int
    // No in-project "title" field: on macOS the document's name IS its filename (shown in the
    // window title bar, renamed natively). A separate editable title would compete with it.
    var timeline: Timeline
    /// Burn the "archivewatch.org · Public Domain" credit into the export. Default ON
    /// (attribution is encouraged + is the social wedge), but the user can turn it OFF
    /// for a clean export — it is NOT mandatory (owner decision 2026-06-23, amending the
    /// learning gate / Rule 5b). The archive.org source still rides in file metadata.
    var burnAttribution: Bool
    var createdAt: Date
    var modifiedAt: Date

    static let currentFormatVersion = 1

    init(timeline: Timeline = Timeline(),
         burnAttribution: Bool = true, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.timeline = timeline
        self.burnAttribution = burnAttribution
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }

    // Tolerant decode: a project written before `burnAttribution` existed defaults to ON
    // (additive-schema discipline — old files keep working). A legacy `title` key is simply
    // ignored (synthesized CodingKeys no longer include it). Encode stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        timeline = try c.decode(Timeline.self, forKey: .timeline)
        burnAttribution = try c.decodeIfPresent(Bool.self, forKey: .burnAttribution) ?? true
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    static var empty: ClipProject { ClipProject() }
}
#endif
