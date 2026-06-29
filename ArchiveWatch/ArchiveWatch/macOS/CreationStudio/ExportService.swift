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
            // 1) Cache each clip window to a local faststart MP4 (Rule 4b) — CONCURRENTLY, bounded.
            // Was a SERIAL loop (one clip at a time): a 30-clip multi-film project meant ~30 sequential
            // full-quality window downloads, which timed out the export entirely on a slow/throttled
            // connection. A bounded task group (same shape as the preview rebuild) caches several at
            // once — the global ReencodeLimiter still caps total in-flight encodes — and a clip that
            // can't be cached becomes a black GAP (below) instead of failing the WHOLE export.
            let clips = project.timeline.clips
            var cached: [UUID: URL] = [:]
            let exportConc = Int(ProcessInfo.processInfo.environment["AW_CS_EXPORT_CONC"] ?? "") ?? 4
            var done = 0
            await withTaskGroup(of: (UUID, URL?).self) { group in
                var it = clips.makeIterator()
                func addNext() {
                    guard let clip = it.next() else { return }
                    group.addTask {
                        // A single un-cacheable clip must not abort the export — return nil → gap.
                        (clip.id, try? await ClipCacheService.cachedURL(for: clip))
                    }
                }
                for _ in 0..<max(1, exportConc) { addNext() }
                while let (id, url) = await group.next() {
                    if let url { cached[id] = url }
                    done += 1
                    progress = Double(done) / Double(clips.count) * 0.4
                    Self.diag("cached \(done)/\(clips.count)\(url == nil ? " (FAILED → gap)" : "")")
                    addNext()
                }
            }
            Self.diag("composing \(clips.count) clip(s), \(cached.count) cached")

            // 2) Compile the (composition, videoComposition) from the LOCAL cached files.
            phase = .composing
            let ordered = clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds }
            var resolved: [CompositionBuilder.ResolvedClip] = []
            for clip in ordered {
                // A clip that couldn't be cached reserves a black GAP of its timeline length, so the
                // export stays positionally 1:1 with the timeline (neighbours keep their positions)
                // instead of being dropped — the same gap discipline the preview uses.
                guard let url = cached[clip.id] else {
                    resolved.append(.gap(seconds: clip.sourceRange.duration.seconds)); continue
                }
                // Bake the clip's color grade into a source file first (Looks compose with
                // transitions because they're a separate graded source — Rule 3d note).
                let gradedURL = (try? await LookGrader.gradedURL(for: url, look: clip.look)) ?? url
                let asset = AVURLAsset(url: gradedURL)
                let dur = try await asset.load(.duration)               // the cached file IS the window
                resolved.append(.init(asset: asset, insertRange: CMTimeRange(start: .zero, duration: dur),
                                      audioVolume: clip.audioVolume,
                                      fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds,
                                      transitionIn: clip.transitionInSeconds, transitionKind: clip.transitionKind))
            }
            // Resolve every audio clip (N music + voiceover tracks) from the project cache so the
            // export includes them, each with its own duration cap + fades.
            let beds: [CompositionBuilder.ResolvedMusic] = project.timeline.audioClips.compactMap { clip in
                let url = ProjectMediaCache.directory.appendingPathComponent(clip.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return .init(asset: AVURLAsset(url: url), volume: clip.volume, startSeconds: clip.startSeconds,
                             maxDuration: clip.sourceDuration > 0 ? clip.sourceDuration : nil,
                             fadeIn: clip.fadeInSeconds, fadeOut: clip.fadeOutSeconds)
            }
            let built = try await CompositionBuilder.build(
                resolved: resolved, timeline: project.timeline, creditLine: creditLine, beds: beds)

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
                    title: url.deletingPathExtension().lastPathComponent,
                    catalogItemIDs: clips.map(\.catalogItemID))
            }

            Self.diag("exporting → \(url.lastPathComponent) (\(format.rawValue))")
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
            // Surface the full error (domain/code + the WHOLE underlying chain) — AVFoundation's
            // localizedDescription is often just "The operation could not be completed.", and the
            // useful code is usually nested (e.g. -11841 AVErrorInvalidVideoComposition).
            let ns = error as NSError
            let stageLabel: String = {
                switch phase { case .caching: "caching"; case .composing: "composing"
                               case .exporting: "exporting"; default: "" }
            }()
            let msg = "\(ns.localizedDescription) [\(Self.errorChain(ns))]"
            Self.diag("FAILED during \(stageLabel): \(msg)")
            phase = .failed(msg)
        }
    }

    /// Full "domain code · domain code · …" chain by walking NSUnderlyingErrorKey — so a nested
    /// AVError (the actionable code) is never hidden behind a generic top-level one.
    nonisolated static func errorChain(_ error: NSError) -> String {
        var parts: [String] = []
        var cur: NSError? = error
        var guardN = 0
        while let e = cur, guardN < 6 {
            parts.append("\(e.domain) \(e.code)")
            cur = e.userInfo[NSUnderlyingErrorKey] as? NSError
            guardN += 1
        }
        return parts.joined(separator: " · ")
    }

    nonisolated static func diag(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["AW_CS_DIAG"] != nil else { return }
        FileHandle.standardError.write(Data("AWCS EXPORT \(message())\n".utf8))
    }
}
#endif
