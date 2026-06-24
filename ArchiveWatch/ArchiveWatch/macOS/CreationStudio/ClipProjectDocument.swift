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
//
// Durable media: project-local media (imported music + recorded voiceover) is EMBEDDED into
// a `media/` subdirectory of the package on save and extracted back to the working cache on
// open — so the edit travels to another Mac and survives a Caches purge, WITHOUT needing the
// document URL or security-scoped bookmarks (the bytes live inside the package). The engine
// keeps resolving media by filename from ProjectMediaCache (the disposable working copy);
// the package is the durable source of truth. archive.org video stays a remote reference.

extension UTType {
    /// Exported package type for Archive Watch projects. Must match the
    /// UTExportedTypeDeclarations entry in Info-macOS.plist exactly.
    static let archiveProject = UTType(exportedAs: "org.archivewatch.project")
}

// @MainActor: the live, observable `project` is mutable state edited from the main-thread
// editor views, so the document is main-actor-isolated — which is what makes that mutable
// `@Published` stored state Sendable-safe under the Swift 6 language mode. ReferenceFileDocument
// is a `@preconcurrency` Sendable protocol with nonisolated requirements, so the conformance is
// annotated `@preconcurrency` (Apple's native mechanism for adopting strict concurrency against
// a pre-concurrency protocol). `fileWrapper(snapshot:)` stays `nonisolated`: SwiftUI serialises
// the passed Sendable snapshot off the main thread, and it only touches that snapshot +
// nonisolated statics — never `project`.
@MainActor
final class ClipProjectDocument: @preconcurrency ReferenceFileDocument {
    typealias Snapshot = ClipProject

    static var readableContentTypes: [UTType] { [.archiveProject] }
    static var writableContentTypes: [UTType] { [.archiveProject] }

    /// The live, observable project. Editor views mutate this; SwiftUI autosaves.
    @Published var project: ClipProject

    nonisolated private static let timelineFileName = "timeline.json"
    nonisolated private static let mediaDirName = "media"

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
        // Extract embedded media (music / voiceover) back to the working cache, so the engine
        // finds them by filename even on a different Mac / after the cache was purged. The package
        // is the durable, portable store; ProjectMediaCache is the disposable working copy.
        if root.isDirectory, let media = root.fileWrappers?[Self.mediaDirName]?.fileWrappers {
            for (name, fw) in media {
                guard let bytes = fw.regularFileContents else { continue }
                let dst = ProjectMediaCache.directory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dst.path) { try? bytes.write(to: dst) }
            }
        }
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
            Self.embedMedia(snapshot, into: root)
            return root
        }
        let dir = FileWrapper(directoryWithFileWrappers: [Self.timelineFileName: timeline])
        Self.embedMedia(snapshot, into: dir)
        return dir
    }

    /// Embed the project's referenced media (music / voiceover) into a `media/` subdirectory of the
    /// package — copied FROM the working cache — so the edit travels with the project and survives a
    /// cache purge. No security-scoped bookmarks needed: the bytes live inside the package.
    nonisolated private static func embedMedia(_ project: ClipProject, into root: FileWrapper) {
        if let old = root.fileWrappers?[mediaDirName] { root.removeFileWrapper(old) }
        let names = [project.timeline.musicBed?.fileName, project.timeline.voiceover?.fileName].compactMap { $0 }
        guard !names.isEmpty else { return }
        var children: [String: FileWrapper] = [:]
        for name in names {
            let url = ProjectMediaCache.directory.appendingPathComponent(name)
            if let bytes = try? Data(contentsOf: url) {
                let fw = FileWrapper(regularFileWithContents: bytes)
                fw.preferredFilename = name
                children[name] = fw
            }
        }
        guard !children.isEmpty else { return }
        let media = FileWrapper(directoryWithFileWrappers: children)
        media.preferredFilename = mediaDirName
        root.addFileWrapper(media)
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
