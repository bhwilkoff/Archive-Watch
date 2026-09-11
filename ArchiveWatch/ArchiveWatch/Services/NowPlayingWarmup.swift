#if os(tvOS)
import Foundation
import MediaPlayer

/// Finishes MediaPlayer's one-time Now Playing setup OFF the main thread,
/// before AVKit needs it on the main thread.
///
/// THE CRASH THIS EXISTS FOR (Fireplace TV, Apple TV 4K 2nd gen, tvOS 27.0,
/// 2026-09-11). Opening a film killed the app with `0x8BADF00D`:
///
///     scene-update watchdog transgression: app<app.archivewatch.tvos>:3497
///     exhausted real (wall clock) time allowance of 10.00 seconds
///
/// The triggered thread was the main thread, stopped inside `dispatch_once`:
///
///     dispatch_once
///     +[MPRemoteCommandCenter sharedCommandCenter]
///     -[AVMediaPlayerDelegate initWithPlayerViewController:]
///     -[AVMediaRemoteManager _updateNowPlayingSession]
///     -[AVPlayerViewController _becomeNowPlaying]
///     -[AVPlayerViewController _updateUXState]
///     -[_AVFocusContainerView didMoveToWindow]
///     ... _UIHostingView.swiftui_insertManagedSubview ...
///
/// We never call MediaPlayer ourselves — AVKit does, the instant the player
/// view enters the window, and `updatesNowPlayingInfoCenter` is
/// `API_UNAVAILABLE(tvos)`, so there is no opting out. That first call talks
/// to mediaremoted over XPC; when the daemon is slow to answer, the whole
/// scene update waits on a `dispatch_once` token and the watchdog kills us.
/// From the sofa that is indistinguishable from "the app crashed".
///
/// Warming the token at launch does not make the XPC round trip faster. It
/// moves it to a thread nobody is watching, and gives it the minutes between
/// opening the app and choosing a film — so by the time AVKit asks, the once
/// block has already run and the main thread takes the fast path.
enum NowPlayingWarmup {
    @MainActor private static var started = false

    @MainActor static func start() {
        guard !started else { return }
        started = true
        // .utility, not .main: the point is to be OFF the thread the watchdog
        // measures. A caller that later hits the same token will still wait,
        // but it waits for a head start measured in minutes, not for a cold
        // daemon reached from inside a scene update.
        DispatchQueue.global(qos: .utility).async {
            _ = MPRemoteCommandCenter.shared()
            _ = MPNowPlayingInfoCenter.default()
        }
    }
}
#endif
