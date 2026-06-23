#if os(macOS)
import SwiftUI
import AVKit
import SwiftData

// Native macOS player: AVPlayerView (AppKit) wrapped in NSViewRepresentable, fed by the
// SHARED ResilientStreamLoader (resume-on-reset + node failover) for MP4 or the native
// HLS master when the title has subtitles. Resume + progress via the SwiftData
// WatchProgress model (same store the other platforms write).
//
// PlayerSurface is the reusable engine; PlayerWindow plays a Catalog.Item and
// EpisodePlayer plays a series Episode with prev/next transport (TV drill-in).

struct PlayerWindow: View {
    let item: Catalog.Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlayerSurface(archiveID: item.archiveID,
                      videoURL: item.videoURLParsed,
                      subtitleHLS: item.subtitleHLSURL)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigation) {
                    Text(item.title).font(.headline).lineLimit(1)
                }
            }
    }
}

// Episode player with manual prev/next (parity §3 "prev/next episode in player").
// Switching recreates the surface via .id, so each episode keeps its own resume
// position; the chevrons live in a small overlay capsule.
struct EpisodePlayer: View {
    let context: EpisodeContext
    @Environment(\.dismiss) private var dismiss
    @State private var episode: Episode

    init(context: EpisodeContext) {
        self.context = context
        _episode = State(initialValue: context.episode)
    }

    private var series: Series { context.series }
    private var prev: Episode? { series.episode(before: episode) }
    private var next: Episode? { series.episode(after: episode) }

    var body: some View {
        PlayerSurface(archiveID: episode.archiveID,
                      videoURL: episode.videoURLParsed,
                      subtitleHLS: nil)
            .id(episode.archiveID)
            .overlay(alignment: .topTrailing) {
                if prev != nil || next != nil {
                    HStack(spacing: 16) {
                        Button { if let p = prev { episode = p } } label: {
                            Image(systemName: "backward.end.fill")
                        }.disabled(prev == nil)
                        if let n = episode.numberLabel {
                            Text(n).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                        Button { if let n = next { episode = n } } label: {
                            Image(systemName: "forward.end.fill")
                        }.disabled(next == nil)
                    }
                    .buttonStyle(.plain).tint(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: .capsule)
                    .padding(12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigation) {
                    Text(episode.title).font(.headline).lineLimit(1)
                }
            }
    }
}

// The shared playback surface: builds the AVPlayer (HLS or resilient MP4), resumes
// from + persists WatchProgress keyed by archiveID. archiveID is the resume key for
// both films and episodes (an episode's archiveID is a real archive.org item).
private struct PlayerSurface: View {
    let archiveID: String
    let videoURL: URL?
    let subtitleHLS: URL?

    @Environment(\.modelContext) private var ctx
    @State private var player: AVPlayer?
    @State private var loader: ResilientStreamLoader?     // retained for the asset's lifetime

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayerNS(player: player).ignoresSafeArea()
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: persist)
    }

    private func setup() {
        let playerItem: AVPlayerItem
        if let hls = subtitleHLS {
            playerItem = AVPlayerItem(url: hls)                 // native CC + seek
        } else if let url = videoURL {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
        } else {
            return
        }
        playerItem.preferredForwardBufferDuration = 300
        // NOTE: AVPlayerItem.externalMetadata is iOS/tvOS-only; on macOS the title
        // rides in the player window toolbar instead.

        let p = AVPlayer(playerItem: playerItem)
        if let resume = savedProgress(), resume > 5 {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        p.play()
        player = p
    }

    private func savedProgress() -> Double? {
        let id = archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        guard let wp = try? ctx.fetch(d).first, !wp.isComplete else { return nil }
        return wp.positionSeconds
    }

    private func persist() {
        guard let p = player, let cur = p.currentItem else { return }
        let pos = p.currentTime().seconds
        let dur = cur.duration.seconds
        guard pos.isFinite, pos > 3, dur.isFinite, dur > 0 else { return }
        let id = archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        if let wp = try? ctx.fetch(d).first {
            wp.positionSeconds = pos; wp.durationSeconds = dur; wp.lastWatchedAt = .now
        } else {
            ctx.insert(WatchProgress(archiveID: id, positionSeconds: pos, durationSeconds: dur))
        }
        try? ctx.save()
    }
}

struct VideoPlayerNS: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .inline
        v.allowsPictureInPicturePlayback = true
        v.showsFullScreenToggleButton = true
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}
#endif
