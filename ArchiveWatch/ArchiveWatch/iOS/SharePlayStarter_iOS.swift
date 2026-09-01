#if os(iOS)
import GroupActivities
import SwiftUI
import UIKit

// Starting a Watch Together session when there is NO FaceTime call yet.
//
// `prepareForActivation()` answers `.activationDisabled` in that case, and our
// first implementation just returned false — so the film played and nothing
// else happened, with no way for the viewer to tell "not implemented" from
// "system declined" (owner, 2026-09-01).
//
// Apple ships the fix: `GroupActivitySharingController` presents the system's
// own sheet for picking people and STARTING THE CALL, then activates the
// activity. It is a cross-import overlay on GroupActivities + UIKit, iOS 15.4+.
// It does not exist on tvOS at all (checked in the 27.0 SDK), which is why the
// Apple TV explains the situation instead of offering this.
struct SharePlayStarter: UIViewControllerRepresentable {
    let activity: WatchTogetherActivity
    /// true when a session actually started, so the caller can begin playback.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        // The throwing initializer fails when the activity cannot be shared at
        // all; surface that as "did not start" rather than crashing on a `try!`.
        guard let controller = try? GroupActivitySharingController(activity) else {
            let vc = UIViewController()
            DispatchQueue.main.async { onFinish(false) }
            return vc
        }
        controller.presentationController?.delegate = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var controller: GroupActivitySharingController?
        private let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        // Dismissal is the only signal the sheet gives us; read its result then.
        // `result` is an ASYNC property — it resolves once the system finishes
        // setting the session up, which is after the sheet goes away.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard let controller else { onFinish(false); return }
            Task { @MainActor [onFinish] in
                onFinish(await controller.result == .success)
            }
        }
    }
}
#endif
