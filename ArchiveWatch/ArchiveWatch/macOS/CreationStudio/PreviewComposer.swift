#if os(macOS)
import Foundation
import AVFoundation

// The live editing preview (docs/macOS-DESIGN.md §3, Rule 3a "preview == export"; Rule 3b
// "rebuild-and-swap"). Builds the SAME composition recipe as export, but sourced from the
// REMOTE resilient assets (the full films) splicing the clip's live in/out range — so a
// trim is just a different insert range and needs NO re-cache (the cache is keyed to a
// fixed window; re-caching on every trim drag would be unusable). archive.org streaming is
// handled by `ResilientStreamLoader`, exactly as playback does. The rendered result matches
// export because the videoComposition recipe is identical; only the byte source differs.
@MainActor
enum PreviewComposer {
    struct Preview {
        let playerItem: AVPlayerItem
        /// Resource-loader delegates are held weakly by their assets — retain for the
        /// player item's lifetime (the EditorModel keeps the Preview alive).
        let loaders: [ResilientStreamLoader]
        let duration: CMTime
    }

    static func build(timeline: Timeline, creditLine: String?) async throws -> Preview {
        let ordered = timeline.clips.sorted { $0.timelineStart.seconds < $1.timelineStart.seconds }
        var resolved: [CompositionBuilder.ResolvedClip] = []
        var loaders: [ResilientStreamLoader] = []
        for clip in ordered {
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: clip.sourceURL)
            if let loader { loaders.append(loader) }
            resolved.append(.init(asset: asset, insertRange: clip.sourceRange.cmRange,
                                  audioVolume: clip.audioVolume))
        }
        // bakeOverlays: false — the Core Animation overlay tool is offline-render-only and
        // crashes AVPlayerItem.setVideoComposition. The clip/reframe/audio recipe is identical
        // to export; text + credit are drawn live over the program monitor instead.
        let built = try await CompositionBuilder.build(
            resolved: resolved, timeline: timeline, creditLine: creditLine, bakeOverlays: false)
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        item.audioMix = built.audioMix
        item.preferredForwardBufferDuration = 5   // editing scrub, not long playback
        return Preview(playerItem: item, loaders: loaders, duration: built.duration)
    }
}
#endif
