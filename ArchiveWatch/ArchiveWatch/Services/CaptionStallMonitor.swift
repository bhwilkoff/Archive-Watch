import AVFoundation
import QuartzCore

// Part (c) of the captioned-playback reliability work: captioned films play via
// AVFoundation's native HLS path (`AVPlayerItem(url: subtitleHLS)`) so they get
// the native CC menu — but that path BYPASSES ResilientStreamLoader, so it has
// no resume-on-reset / node-failover (Decisions 021/031/034) and stutters on
// Archive's idle-connection drops. The existing HLS->direct-MP4 fallback
// (`forceDirectPlayback`) only fires on a HARD load failure, so a film that
// merely STUTTERS never triggers it and stutters through the whole runtime with
// the resilient loader unused.
//
// This monitor watches AVFoundation's own stall signals and fires ONCE when a
// captioned item stalls PERSISTENTLY — the caller then rebuilds playback on the
// resilient MP4 (losing only the caption track: smooth-without-CC beats
// stutter-with-CC). It is deliberately gated so a single transient blip does NOT
// needlessly drop CC:
//   * ≥ `stallCountThreshold` playbackStalled events within `windowSeconds`, OR
//   * a single sustained "wants to play but can't" (`.waitingToPlayAtSpecifiedRate`)
//     lasting > `singleStallSeconds`, only after the film has actually started
//     (currentTime past `minPlayedSeconds`, so startup buffering never counts —
//     the hard-failure / load-timeout paths own the startup case).
// Fires at most once; re-arm by detach()+attach() on each new item.
@MainActor
final class CaptionStallMonitor {
    private weak var player: AVPlayer?
    private var stallObserver: NSObjectProtocol?
    private var timer: Timer?
    private var onPersistentStall: (() -> Void)?
    private var fired = false

    // Sliding window of playbackStalled event times.
    private var stallTimes: [CFTimeInterval] = []
    // When the player entered a sustained "waiting to play" (rebuffer) state.
    private var waitingSince: CFTimeInterval?

    private let windowSeconds: CFTimeInterval = 20
    private let stallCountThreshold = 2
    private let singleStallSeconds: CFTimeInterval = 8
    private let minPlayedSeconds: Double = 3

    func attach(player: AVPlayer, item: AVPlayerItem, onPersistentStall: @escaping () -> Void) {
        self.player = player
        self.onPersistentStall = onPersistentStall
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordStall() }
        }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func detach() {
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        timer?.invalidate(); timer = nil
        player = nil
        onPersistentStall = nil
        stallTimes.removeAll()
        waitingSince = nil
        fired = false
    }

    private func recordStall() {
        guard !fired else { return }
        let now = CACurrentMediaTime()
        stallTimes.append(now)
        stallTimes.removeAll { now - $0 > windowSeconds }
        if stallTimes.count >= stallCountThreshold { fire() }
    }

    private func tick() {
        guard !fired, let player else { return }
        // Sustained rebuffer: the player WANTS to play (not user-paused, not ended)
        // but can't. Only after real playback has begun, so startup buffering — which
        // legitimately sits in .waitingToPlayAtSpecifiedRate — never trips it.
        let wantsToPlay = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let played = player.currentItem.map { $0.currentTime().seconds } ?? 0
        guard wantsToPlay, played.isFinite, played > minPlayedSeconds else {
            waitingSince = nil
            return
        }
        let now = CACurrentMediaTime()
        if let since = waitingSince {
            if now - since > singleStallSeconds { fire() }
        } else {
            waitingSince = now
        }
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        let cb = onPersistentStall
        // Stop watching before handing control back; the caller tears down + rebuilds.
        detach()
        cb?()
    }
}
