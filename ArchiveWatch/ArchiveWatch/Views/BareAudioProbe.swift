#if os(tvOS)
import SwiftUI
import AVKit
import AVFoundation

/// AW_BARE_PLAYER=<url> -- the whole app, removed.
///
/// The owner's audio dropout has now survived: the caption engine disabled,
/// the custom resource loader replaced by a plain AVURLAsset, PiP disabled,
/// and the 300s forward buffer returned to AVFoundation's automatic default.
/// That run was a stock AVPlayerViewController and it STILL lost audio after
/// ~3 minutes -- while other apps on the same Apple TV, same output, same OS
/// do not, and while Archive Watch on tvOS 26.6 does not.
///
/// So the trigger is not the player. What remains is everything ELSE this app
/// runs while a film plays and a typical video app does not: a CloudKit sync
/// timer, Top Shelf snapshot writes, SwiftData persistence, catalog refresh,
/// background-refresh registration. This scene starts NONE of it -- no
/// AppStore, no ModelContainer, no Router -- and plays one URL. It is the
/// control that says whether the app's background work is implicated or
/// whether the cause is at bundle level (Info.plist background modes,
/// entitlements), which no runtime flag can reach.
struct BareAudioProbe: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                BarePlayerContainer(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            guard player == nil else { return }
            // AW_FRAG=1 routes the SAME url through the on-the-fly
            // fragmenter, so the remote path can be judged on the glass
            // against the identical film.
            let p: AVPlayer
            if ProcessInfo.processInfo.environment["AW_FRAG"] == "1",
               let hls = LocalMediaServer.shared.hlsURL(for: url) {
                // The EXISTING loopback server (Decision 082), now serving the
                // film as HLS. Segments travel over real HTTP because a
                // custom-scheme HLS media segment is refused -12881.
                p = AVPlayer(playerItem: AVPlayerItem(url: hls))
                awdiag("AWBARE using LocalMediaServer HLS: %@", hls.absoluteString)
            } else {
                p = AVPlayer(url: url)      // plain asset, nothing attached
            }
            awdiag("AWBARE playing %@", url.absoluteString)
            p.play()
            player = p
            // RECOVERY TRIAL. tvOS 27.0 stops rendering audio for progressive
            // MP4 after ~3-5 minutes (HLS is immune; measured). The app cannot
            // DETECT it -- during a live dropout the track is enabled, the
            // route has 2 channels, rate is 1.0, the buffer is full and the
            // error log is empty -- so the only automatic remedy is to reset
            // the audio render on a timer, BEFORE the failure window. Which
            // reset is cheap enough to be imperceptible is an empirical
            // question, and this is the rig for answering it.
            //   AW_RECOVER=mute  -- toggle isMuted (should be instant)
            //   AW_RECOVER=seek  -- seek to the current time
            //   AW_RECOVER=rate  -- rate 0 then 1 (known to work; may hitch)
            let mode = ProcessInfo.processInfo.environment["AW_RECOVER"] ?? ""
            let every = Double(ProcessInfo.processInfo.environment["AW_RECOVER_EVERY"] ?? "") ?? 120
            if !mode.isEmpty {
                let t = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        let at = p.currentTime()
                        switch mode {
                        case "mute":
                            p.isMuted = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                p.isMuted = false
                            }
                        case "seek":
                            p.seek(to: at, toleranceBefore: .zero, toleranceAfter: .zero)
                        case "quick":
                            // Only a genuine STOP revives the render (mute and
                            // track re-select both failed), so make the stop as
                            // short as the runloop allows: rate 0, then rate 1
                            // on the very next turn -- single-digit
                            // milliseconds rather than the 50ms that was
                            // audible as a hitch.
                            p.rate = 0
                            DispatchQueue.main.async { p.rate = 1 }
                        case "wobble":
                            // Never stops playback: a rate change forces the
                            // time-pitch/audio unit to reconfigure while the
                            // film keeps running, so if THAT is what revives
                            // the render, the viewer sees and hears nothing.
                            p.rate = 0.99
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                p.rate = 1.0
                            }
                        case "track":
                            // Re-select the audible option: touches the AUDIO
                            // renderer only, never the rate or the video.
                            guard let item = p.currentItem else { break }
                            let asset = item.asset
                            Task { @MainActor in
                                guard let g = try? await asset.loadMediaSelectionGroup(
                                        for: .audible),
                                      let cur = item.currentMediaSelection
                                        .selectedMediaOption(in: g) else { return }
                                item.select(nil, in: g)
                                item.select(cur, in: g)
                            }
                        case "pitch":
                            // Flipping the algorithm rebuilds the audio
                            // processing chain in place.
                            guard let item = p.currentItem else { break }
                            item.audioTimePitchAlgorithm =
                                item.audioTimePitchAlgorithm == .timeDomain
                                ? .spectral : .timeDomain
                        default:
                            p.rate = 0
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                p.rate = 1
                            }
                        }
                        awdiag("AWRECOVER applied '%@' at t=%.0f", mode, at.seconds)
                    }
                }
                RunLoop.main.add(t, forMode: .common)
            }
            // A heartbeat so the console shows the film advancing even though
            // no diagnostics of ours are wired into this path.
            _ = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 10, preferredTimescale: 1),
                queue: .main) { t in
                    awdiag("AWBARE t=%.0f rate=%.2f", t.seconds, p.rate)
                }
        }
    }
}

private struct BarePlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        return vc                                // no PiP, no menu, no captions
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}
#endif
