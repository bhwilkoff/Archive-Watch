#if os(macOS)
import Foundation
import AVFoundation
import Observation

// The export orchestrator (docs/macOS-DESIGN.md §3–§4): cache every clip's window to a
// local faststart MP4 (Rule 4b), compile the composition (Rule 3a/3e), then run ONE
// AVAssetExportSession over the LOCAL composition — reliable, because nothing remote
// reaches the exporter. Provenance credit is burned in (CompositionBuilder) and the
// source archive.org pages embedded in metadata (Rule 5b / learning gate). Progress is
// observable so the editor can show it; caching is the first 40%, the encode the rest.
@MainActor
@Observable
final class ExportService {
    enum Phase: Equatable { case idle, caching, composing, exporting, done, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var outputURL: URL?

    var isBusy: Bool { phase == .caching || phase == .composing || phase == .exporting }

    /// The standard public-domain credit. Per-item CC dedications (Catalog.Item.clipCreditLine)
    /// can override this once the real browser supplies the item — Phase 1 ships PD-only.
    nonisolated static let defaultCredit = "archivewatch.org · Public Domain"

    func export(_ project: ClipProject, to url: URL) async {
        guard !project.timeline.clips.isEmpty else { phase = .failed("The timeline is empty."); return }
        phase = .caching; progress = 0; outputURL = nil
        // Attribution is optional (owner decision): burn the credit only when the project
        // opts in. The archive.org source still rides in metadata regardless.
        let creditLine: String? = project.burnAttribution ? Self.defaultCredit : nil

        do {
            // 1) Cache each clip window to a local faststart MP4 (Rule 4b).
            let clips = project.timeline.clips
            var cached: [UUID: URL] = [:]
            for (i, clip) in clips.enumerated() {
                cached[clip.id] = try await ClipCacheService.cachedURL(for: clip)
                progress = Double(i + 1) / Double(clips.count) * 0.4
            }

            // 2) Compile the (composition, videoComposition) — reads LOCAL files only.
            phase = .composing
            let built = try await CompositionBuilder.build(
                timeline: project.timeline, cachedURLs: cached, creditLine: creditLine)

            // 3) Export the local composition (reliable — nothing remote reaches the exporter).
            phase = .exporting
            guard let session = AVAssetExportSession(asset: built.composition,
                                                     presetName: AVAssetExportPresetHighestQuality) else {
                throw CreationStudioError.cannotCreateExportSession
            }
            session.videoComposition = built.videoComposition
            // Embed the archive.org source(s) only when attribution is on — a clean
            // export leaves no trace (owner decision: attribution is optional).
            if creditLine != nil {
                session.metadata = CompositionBuilder.provenanceMetadata(
                    title: project.title, catalogItemIDs: clips.map(\.catalogItemID))
            }

            try? FileManager.default.removeItem(at: url)
            let progressTask = Task { [weak self] in
                for await state in session.states(updateInterval: 0.2) {
                    if case .exporting(let p) = state {
                        await MainActor.run { self?.progress = 0.4 + p.fractionCompleted * 0.6 }
                    }
                }
            }
            defer { progressTask.cancel() }
            try await session.export(to: url, as: .mp4)

            progress = 1
            outputURL = url
            phase = .done
        } catch {
            // Surface the full error (domain/code/underlying) — AVFoundation's
            // localizedDescription is often just "The operation could not be completed."
            let ns = error as NSError
            let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { " · \($0.domain) \($0.code)" } ?? ""
            phase = .failed("\(ns.localizedDescription) [\(ns.domain) \(ns.code)\(underlying)]")
        }
    }
}
#endif
