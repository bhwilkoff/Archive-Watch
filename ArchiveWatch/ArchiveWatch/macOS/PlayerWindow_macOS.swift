#if os(macOS)
import SwiftUI
import AVKit
import SwiftData

// Native macOS player: AVPlayerView (AppKit) wrapped in NSViewRepresentable, fed by the
// SHARED ResilientStreamLoader (resume-on-reset + node failover) for MP4 or the native
// HLS master when the title has subtitles. Resume + progress via the SwiftData
// WatchProgress model (same store the other platforms write).

struct PlayerWindow: View {
    let item: Catalog.Item
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { persist(); dismiss() }
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: persist)
    }

    private func setup() {
        let playerItem: AVPlayerItem
        if let hls = item.subtitleHLSURL {
            playerItem = AVPlayerItem(url: hls)                 // native CC + seek
        } else if let url = item.videoURLParsed {
            let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
            loader = l
            playerItem = AVPlayerItem(asset: asset)
        } else {
            return
        }
        playerItem.preferredForwardBufferDuration = 300
        // NOTE: AVPlayerItem.externalMetadata is iOS/tvOS-only; on macOS AVPlayerView
        // surfaces title via the window. A title/info overlay is a later refinement.

        let p = AVPlayer(playerItem: playerItem)
        if let resume = savedProgress(), resume > 5 {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        p.play()
        player = p
    }

    private func savedProgress() -> Double? {
        let id = item.archiveID
        let d = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.archiveID == id })
        guard let wp = try? ctx.fetch(d).first, !wp.isComplete else { return nil }
        return wp.positionSeconds
    }

    private func persist() {
        guard let p = player, let cur = p.currentItem else { return }
        let pos = p.currentTime().seconds
        let dur = cur.duration.seconds
        guard pos.isFinite, pos > 3, dur.isFinite, dur > 0 else { return }
        let id = item.archiveID
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
