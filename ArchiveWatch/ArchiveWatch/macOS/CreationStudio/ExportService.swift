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
// Export formats (#5). H.264/MP4 shares everywhere; ProRes/MOV is the editing/archival
// master. All honor the project's render size via the videoComposition (these presets are
// not fixed-dimension, unlike AVAssetExportPreset1920x1080).
enum ExportFormat: String, CaseIterable, Identifiable {
    case h264 = "H.264 · MP4"
    case proRes422 = "ProRes 422 · MOV"
    case proRes4444 = "ProRes 4444 · MOV"
    var id: String { rawValue }

    var preset: String {
        switch self {
        case .h264:      AVAssetExportPresetHighestQuality
        case .proRes422: AVAssetExportPresetAppleProRes422LPCM
        case .proRes4444: AVAssetExportPresetAppleProRes4444LPCM
        }
    }
    var fileType: AVFileType { self == .h264 ? .mp4 : .mov }
    var fileExtension: String { self == .h264 ? "mp4" : "mov" }
    var blurb: String {
        switch self {
        case .h264:       "Shareable everywhere — best for posting online."
        case .proRes422:  "High-quality master for re-editing. Large file."
        case .proRes4444: "Maximum quality (and alpha). Largest file."
        }
    }
}

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

    func export(_ project: ClipProject, to url: URL, format: ExportFormat = .h264) async {
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

            // 2) Compile the (composition, videoComposition) from the LOCAL cached files.
            phase = .composing
            let ordered = clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds }
            var resolved: [CompositionBuilder.ResolvedClip] = []
            for clip in ordered {
                guard let url = cached[clip.id] else { continue }
                // Bake the clip's color grade into a source file first (Looks compose with
                // transitions because they're a separate graded source — Rule 3d note).
                let gradedURL = (try? await LookGrader.gradedURL(for: url, look: clip.look)) ?? url
                let asset = AVURLAsset(url: gradedURL)
                let dur = try await asset.load(.duration)               // the cached file IS the window
                resolved.append(.init(asset: asset, insertRange: CMTimeRange(start: .zero, duration: dur),
                                      audioVolume: clip.audioVolume,
                                      fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds,
                                      transitionIn: clip.transitionInSeconds))
            }
            // Resolve the music bed from the project cache (if any) so the export includes it.
            var music: CompositionBuilder.ResolvedMusic?
            if let m = project.timeline.musicBed {
                let url = ProjectMediaCache.directory.appendingPathComponent(m.fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    music = .init(asset: AVURLAsset(url: url), volume: m.volume, startSeconds: m.startSeconds)
                }
            }
            let built = try await CompositionBuilder.build(
                resolved: resolved, timeline: project.timeline, creditLine: creditLine, music: music)

            // 3) Export the local composition (reliable — nothing remote reaches the exporter).
            phase = .exporting
            guard let session = AVAssetExportSession(asset: built.composition,
                                                     presetName: format.preset) else {
                throw CreationStudioError.cannotCreateExportSession
            }
            session.videoComposition = built.videoComposition
            session.audioMix = built.audioMix
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
            try await session.export(to: url, as: format.fileType)

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
