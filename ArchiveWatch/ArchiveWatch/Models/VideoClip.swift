import Foundation
import SwiftData

// A clip the user authored in Clip Studio (the Create feature, iOS/iPadOS).
// Stores the EDIT DEFINITION (source + in/out + framing + caption + format)
// plus the path to the last rendered file in Caches. The definition is the
// source of truth: if the cached render is evicted under disk pressure, the
// clip can be re-exported from the definition. Keyed on a UUID so multiple
// clips of the same film coexist; `sourceArchiveID` links back to the catalog.
//
// CloudKit mirror (Decision 022) is deferred — clips are large/local and the
// v1 value is on-device. When synced, only the definition syncs, never bytes.
@Model
final class VideoClip {
    @Attribute(.unique) var id: String
    var sourceArchiveID: String
    var sourceTitle: String
    var inSeconds: Double
    var durationSeconds: Double
    var aspect: String          // ClipAspect.rawValue
    var format: String          // ClipFormat.rawValue
    var caption: String
    var createdAt: Date
    /// Filename (not absolute path) of the last render under the clips Caches
    /// dir — absolute paths don't survive container moves between launches.
    var renderFilename: String?

    init(id: String = UUID().uuidString,
         sourceArchiveID: String, sourceTitle: String,
         inSeconds: Double, durationSeconds: Double,
         aspect: String, format: String, caption: String,
         renderFilename: String? = nil) {
        self.id = id
        self.sourceArchiveID = sourceArchiveID
        self.sourceTitle = sourceTitle
        self.inSeconds = inSeconds
        self.durationSeconds = durationSeconds
        self.aspect = aspect
        self.format = format
        self.caption = caption
        self.createdAt = Date()
        self.renderFilename = renderFilename
    }
}
