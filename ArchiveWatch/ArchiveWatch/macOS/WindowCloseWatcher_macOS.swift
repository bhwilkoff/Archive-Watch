#if os(macOS)
import SwiftUI
import AppKit

// WHAT THE RED BUTTON MEANS — macOS-DESIGN §D12.
//
// Owner, 2026-09-22: "I've encountered a couple of times where I was able to
// close a playing movie and then realize that I closed out of the app (without
// actually quitting it) by using the Red 'stop light' button in the top left
// corner rather than the X in the top right corner to exit out of the movie.
// The movie continued to play and then when I opened the interface back up, a
// new copy of the movie started playing."
//
// On macOS a closed window is not a quit, and SwiftUI keeps a `WindowGroup`
// scene's `@State` across the close so the app can restore it. That is the
// right default for a browser and the wrong one for a film: the state it keeps
// includes an `AVPlayer` that is still making sound, and nothing on screen to
// stop it with.
//
// SwiftUI has no scene-close callback, so the window says so itself.
// `NSWindow.willCloseNotification` scoped to THIS view's own window — not a
// global observer that would also fire for the Studio window, an inspector, or
// a Creation Studio document.
//
// WHY A REPRESENTABLE AND NOT `onDisappear`: `onDisappear` fires for a view
// leaving the hierarchy, which includes a great many things that are not a
// window closing, and does NOT reliably fire when a scene's window is closed
// while its state is preserved. The window is the thing being asked about, so
// the window is the thing observed.
struct AWWindowCloseWatcher: NSViewRepresentable {
    /// Called once, on the main actor, when this view's window closes.
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = WatcherView()
        v.onClose = onClose
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WatcherView)?.onClose = onClose
    }

    final class WatcherView: NSView {
        var onClose: (() -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose?() }
            }
        }

        // NO `deinit` CLEAN-UP, and that is correct rather than sloppy. Swift 6
        // will not let a nonisolated `deinit` touch a non-`Sendable` stored
        // property, and since iOS 9 / macOS 10.11 `NotificationCenter` holds
        // its block-based observers WEAKLY enough that a dropped token simply
        // stops firing — the closure already guards with `[weak self]`, so a
        // view that has gone away calls nothing. The token is removed on every
        // `viewDidMoveToWindow`, which is where a view can actually change
        // windows.
    }
}
#endif
