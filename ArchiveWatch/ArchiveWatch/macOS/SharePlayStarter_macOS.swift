#if os(macOS)
import AppKit
import GroupActivities
import SwiftUI
import _GroupActivities_AppKit

// Starting a Watch Together session from the Mac when there is NO FaceTime call
// yet — the AppKit twin of SharePlayStarter_iOS.
//
// `prepareForActivation()` answers `.activationDisabled` outside a call, and the
// viewer must never be left with "nothing happened" (owner, 2026-09-01). Apple's
// `GroupActivitySharingController` presents the system's own sheet for picking
// people and PLACING the call, then activates the activity.
//
// On AppKit it is an NSViewController (verified against the macOS 27 SDK, where
// it carries loadView/viewDidLoad), so it is presented as a sheet rather than
// wrapped in a Representable the way UIKit's is. `result` is an async property
// that resolves once the system finishes setting the session up, so awaiting it
// directly is enough here — no dismissal delegate needed.
@MainActor
enum SharePlayStarter {
    /// true when a session actually started, so the caller can begin playback.
    static func present(_ activity: WatchTogetherActivity) async -> Bool {
        guard let host = NSApp.keyWindow?.contentViewController
                ?? NSApp.mainWindow?.contentViewController else { return false }
        guard let controller = try? GroupActivitySharingController(activity) else { return false }
        host.presentAsSheet(controller)
        return await controller.result == .success
    }
}
#endif
