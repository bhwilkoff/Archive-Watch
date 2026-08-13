import AVFoundation
import QuartzCore

// Recovers from the "video freezes but audio keeps playing" stall some Archive
// MP4s trigger on tvOS: the decoder stops emitting frames while the playback
// clock (and audio) keep advancing, so AVPlayer never reports an error and the
// only manual fix is to scrub. This watchdog does that scrub automatically.
//
// Detection: a tap AVPlayerItemVideoOutput. During healthy playback new pixel
// buffers arrive continuously; if NONE arrive for `freezeThreshold` seconds
// while the player is actively .playing (audio running, buffer not starved),
// the picture is frozen — so we seek to the current time with zero tolerance,
// which re-primes the decoder exactly like a manual scrub. Conservative
// thresholds + a cooldown keep it from nudging healthy playback.
//
// NOTE: validate on real Apple TV hardware — the freeze can't be reproduced in
// the simulator. Low-risk by design: it only acts after several seconds of
// genuinely-no-frames-while-playing, and a zero-distance seek is near-invisible.
@MainActor
final class PlaybackFreezeGuard {
    private weak var player: AVPlayer?
    private let output = AVPlayerItemVideoOutput(outputSettings: nil)
    private var timer: Timer?
    private var lastFrameHostTime: CFTimeInterval = 0
    private var lastNudgeHostTime: CFTimeInterval = 0

    private let freezeThreshold: CFTimeInterval = 3.5  // no frames this long → frozen
    private let nudgeCooldown: CFTimeInterval = 6.0    // don't re-nudge immediately

    func attach(to player: AVPlayer, item: AVPlayerItem) {
        self.player = player
        item.add(output)
        lastFrameHostTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        if let item = player?.currentItem { item.remove(output) }
        player = nil
    }

    private func tick() {
        guard let player, let item = player.currentItem else { return }
        let host = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: host)

        // A fresh frame is available → pipeline healthy; consume it and reset.
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            // macOS/iOS/tvOS 27 deprecate copyPixelBuffer(forItemTime:itemTimeForDisplay:) in favor of
            // pixelBufferAndDisplayTime(forItemTime:). That new symbol exists ONLY in the 27 SDK, so it
            // must be COMPILE-time guarded (#if compiler), not just runtime (#available): otherwise the
            // app (and the SHARED iOS/tvOS targets, which include this file) won't compile against the
            // GA 26 SDK and can't be submitted with a release Xcode (docs/mac-app-store-submission.md).
            // We discard the buffer either way (this tap only proves frames are flowing) — identical behavior.
            #if compiler(>=6.4)
            if #available(macOS 27, iOS 27, tvOS 27, *) {
                _ = output.pixelBufferAndDisplayTime(forItemTime: itemTime)
            } else {
                _ = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            }
            #else
            _ = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            #endif
            lastFrameHostTime = host
            return
        }

        // No new frame. Only treat it as a freeze when playback is genuinely
        // progressing — not a legitimate pause or a normal rebuffer stall
        // (those keep currentTime from advancing / report waitingToPlay).
        guard player.timeControlStatus == .playing,
              item.isPlaybackLikelyToKeepUp,
              !item.isPlaybackBufferEmpty else {
            lastFrameHostTime = host
            return
        }

        if host - lastFrameHostTime > freezeThreshold,
           host - lastNudgeHostTime > nudgeCooldown {
            lastNudgeHostTime = host
            lastFrameHostTime = host
            let now = player.currentTime()
            // A zero-distance seek is a decoder flush — if these fire in a rhythm
            // during normal viewing they ARE the "stutter with repeated lines",
            // so a nudge must never be silent under diagnostics.
            if PlaybackDiag.enabled { NSLog("AWNUDGE freeze-guard seek at t=%.0f", now.seconds) }
            player.seek(to: now, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
}
