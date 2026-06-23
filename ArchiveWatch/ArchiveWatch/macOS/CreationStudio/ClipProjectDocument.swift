#if os(macOS)
import SwiftUI
import Combine
import UniformTypeIdentifiers

// The `.archiveproj` document (docs/macOS-DESIGN.md §2; de-risk spike #1 — "the weakest
// seam"). Rule 2b: a reference PACKAGE (a directory bundle), NOT archive.org bytes —
// it holds the timeline JSON + (later) project-local imports + a caches/ subfolder.
//
// Phase-1 spike note: we prototype on ReferenceFileDocument (a reference type fits an
// incrementally-mutated object graph + gives autosave/Versions/undo for free). The
// documented limitation — ReferenceFileDocument exposes NO document file URL and saves on
// the main thread — is fine for the timeline JSON but NOT for resolving relative cache
// paths or holding security-scoped bookmarks to the archive cache. When Unit 2's engine
// needs the document's URL + bookmarks, migrate the backbone to NSDocument +
// NSHostingController (the macos-native-app-shell skill's budgeted step). Until then this
// proves the package read/write round-trip.

extension UTType {
    /// Exported package type for Archive Watch projects. Must match the
    /// UTExportedTypeDeclarations entry in Info-macOS.plist exactly.
    static let archiveProject = UTType(exportedAs: "org.archivewatch.project")
}

// Not @MainActor: ReferenceFileDocument's snapshot/fileWrapper run off the main thread
// (the snapshot VALUE crosses threads, not the object). SwiftUI mutates `project` on the
// main thread from the editor view; the serializer only touches the passed Sendable
// snapshot + nonisolated statics — no shared mutable state crosses threads.
final class ClipProjectDocument: ReferenceFileDocument {
    typealias Snapshot = ClipProject

    static var readableContentTypes: [UTType] { [.archiveProject] }
    static var writableContentTypes: [UTType] { [.archiveProject] }

    /// The live, observable project. Editor views mutate this; SwiftUI autosaves.
    @Published var project: ClipProject

    nonisolated private static let timelineFileName = "timeline.json"

    init() { project = .empty }

    init(configuration: ReadConfiguration) throws {
        // The document is a directory wrapper (package); read timeline.json from it.
        // Tolerate a flat-file fallback so a future format change can't orphan old files.
        let root = configuration.file
        let data: Data
        if root.isDirectory, let child = root.fileWrappers?[Self.timelineFileName],
           let d = child.regularFileContents {
            data = d
        } else if let d = root.regularFileContents {
            data = d
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try Self.decoder.decode(ClipProject.self, from: data)
    }

    /// Capture a value snapshot on the main actor; SwiftUI serialises it off-thread.
    func snapshot(contentType: UTType) throws -> ClipProject {
        var snap = project
        snap.modifiedAt = Date()
        return snap
    }

    /// Write the package: a directory wrapper containing timeline.json. Reuse the
    /// existing caches/imports children on overwrite so a save never drops them.
    nonisolated func fileWrapper(snapshot: ClipProject,
                                 configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Self.encoder.encode(snapshot)
        let timeline = FileWrapper(regularFileWithContents: data)
        timeline.preferredFilename = Self.timelineFileName

        let root = configuration.existingFile ?? FileWrapper(directoryWithFileWrappers: [:])
        // Replace only timeline.json; keep any sibling wrappers (caches/, imports/).
        if root.isDirectory {
            if let old = root.fileWrappers?[Self.timelineFileName] { root.removeFileWrapper(old) }
            root.addFileWrapper(timeline)
            return root
        }
        return FileWrapper(directoryWithFileWrappers: [Self.timelineFileName: timeline])
    }

    nonisolated static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]   // diffable project files
        e.dateEncodingStrategy = .iso8601
        return e
    }
    nonisolated static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
#endif
