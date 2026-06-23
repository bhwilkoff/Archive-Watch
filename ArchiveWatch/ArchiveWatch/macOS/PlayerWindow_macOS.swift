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
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var speed = 1.0

    var body: some View {
        PlayerSurface(archiveID: item.archiveID,
                      videoURL: item.videoURLParsed,
                      subtitleHLS: item.subtitleHLSURL,
                      speed: speed,
                      onEnded: autoplayNext)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigation) {
                    Text(item.title).font(.headline).lineLimit(1)
                }
                ToolbarItem { SpeedMenu(speed: $speed) }
            }
    }

    /// When a film ends and Autoplay is on, swap the player to the next title
    /// (router.nowPlaying drives the sheet, so changing it re-presents the player).
    private func autoplayNext() {
        guard store.autoplayMode != .off,
              let next = ContinuousPlayback.next(after: item, mode: store.autoplayMode, store: store)
        else { return }
        router.play(next)
    }
}

// Shared speed control for the macOS players (AVPlayerView has no built-in speed
// menu; the tvOS/iOS AVPlayerViewController does). Drives the player's rate.
struct SpeedMenu: View {
    @Binding var speed: Double
    private let speeds: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]
    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { s in
                Button {
                    speed = s
                } label: {
                    if speed == s { Label(label(s), systemImage: "checkmark") }
                    else { Text(label(s)) }
                }
            }
        } label: { Label("Speed", systemImage: "speedometer") }
        .help("Playback speed")
    }
    private func label(_ s: Double) -> String {
        s == 1.0 ? "Normal" : (s == floor(s) ? "\(Int(s))×" : "\(s)×")
    }
}

// Episode player with manual prev/next (parity §3 "prev/next episode in player").
// Switching recreates the surface via .id, so each episode keeps its own resume
// position; the chevrons live in a small overlay capsule.
struct EpisodePlayer: View {
    let context: EpisodeContext
    @Environment(\.dismiss) private var dismiss
    @State private var episode: Episode
    @State private var speed = 1.0

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
                      subtitleHLS: nil,
                      speed: speed,
                      onEnded: { if let n = next { episode = n } })   // binge auto-advance
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
                ToolbarItem { SpeedMenu(speed: $speed) }
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
    var speed: Double = 1.0
    var onEnded: (() -> Void)? = nil

    @Environment(\.modelContext) private var ctx
    @State private var player: AVPlayer?
    @State private var loader: ResilientStreamLoader?     // retained for the asset's lifetime
    @State private var endObserver: NSObjectProtocol?

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
        .onDisappear(perform: teardown)
        .onChange(of: speed) { applySpeed() }
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
        p.defaultRate = Float(speed)   // the AVPlayerView play button resumes at this rate
        if let resume = savedProgress(), resume > 5 {
            p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        p.play()
        if speed != 1 { p.rate = Float(speed) }
        player = p
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            MainActor.assumeIsolated { onEnded?() }
        }
    }

    private func applySpeed() {
        guard let player else { return }
        player.defaultRate = Float(speed)
        if player.rate != 0 { player.rate = Float(speed) }   // change live only while playing
    }

    private func teardown() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        persist()
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

// MARK: - Channel lineup player (Channels tune-in)
//
// Plays an ordered lineup (programs + woven commercials) straight through, joining
// the first program in progress at `startOffset` (#92). Live TV semantics: NO resume,
// NO WatchProgress writes (persistsProgress=false on the other platforms). On
// end-of-item it swaps the next playable item onto the same player. Mirrors the iOS
// LineupQueue advance, AppKit-side.
struct ChannelPlayer: View {
    let lineup: [Catalog.Item]
    let startOffset: TimeInterval
    var muted: Bool = false           // Party Play starts muted (background eye-candy)
    @Environment(\.dismiss) private var dismiss
    @State private var engine = ChannelEngine()

    var body: some View {
        ZStack {
            Color.black
            if let player = engine.player {
                VideoPlayerNS(player: player).ignoresSafeArea()
            } else if engine.failed {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .onAppear { engine.start(lineup: lineup, startOffset: startOffset, muted: muted) }
        .onDisappear { engine.stop() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .navigation) {
                Text(engine.nowTitle).font(.headline).lineLimit(1)
            }
        }
    }
}

@MainActor
@Observable
final class ChannelEngine {
    var player: AVPlayer?
    var nowTitle = ""
    var failed = false

    private var items: [Catalog.Item] = []
    private var idx = 0
    private var loader: ResilientStreamLoader?   // retained for the asset's lifetime
    private var endObserver: NSObjectProtocol?

    func start(lineup: [Catalog.Item], startOffset: TimeInterval, muted: Bool = false) {
        guard player == nil else { return }   // onAppear can fire more than once
        items = lineup
        idx = lineup.firstIndex { $0.videoURLParsed != nil } ?? 0
        guard idx < items.count, let url = items[idx].videoURLParsed else { failed = true; return }
        let p = AVPlayer(playerItem: makeItem(for: url))
        p.isMuted = muted
        nowTitle = items[idx].title
        if startOffset > 5 { p.seek(to: CMTime(seconds: startOffset, preferredTimescale: 600)) }
        p.play()
        player = p
    }

    private func makeItem(for url: URL) -> AVPlayerItem {
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 300
        registerEnd(for: item)
        return item
    }

    private func registerEnd(for item: AVPlayerItem) {
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func advance() {
        guard let player else { return }
        idx += 1
        while idx < items.count {
            if let url = items[idx].videoURLParsed {
                player.replaceCurrentItem(with: makeItem(for: url))
                nowTitle = items[idx].title
                player.play()
                return
            }
            idx += 1
        }
        // Lineup exhausted — let it sit on the final frame; the user dismisses.
    }

    func stop() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        player?.pause()
        player = nil
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
