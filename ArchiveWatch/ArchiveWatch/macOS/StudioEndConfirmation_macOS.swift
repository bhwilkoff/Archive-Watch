#if os(macOS)
import AppKit

/// §D37 — ONE KEYSTROKE MAY NOT END A LIVE SHOW.
///
/// ⇧⌘E works from any window, Esc was the projection window's ✕, ⌘W closed
/// the Studio and ⌘Q quit — each ended the broadcast an audience was
/// watching, with nothing asked (launch audit A10). Every host-initiated end
/// now comes through here. A PREVIEW is not asked about: nobody is watching.
@MainActor
enum StudioEndConfirmation {
    /// True when the show may end — immediately if nothing is on air.
    static func confirm() -> Bool {
        // Already ending: the host has answered once, and a second dialog
        // would start a second end.
        guard !StudioSession.shared.isEnding else { return false }
        guard StudioSession.shared.isOnAir else { return true }
        let alert = NSAlert()
        alert.messageText = "End the broadcast?"
        alert.alertStyle = .warning
        let end = alert.addButton(withTitle: "End Broadcast")
        end.hasDestructiveAction = true
        alert.addButton(withTitle: "Keep Streaming")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// ⌘Q during a show asks first, then ENDS the show properly — completing the
/// YouTube broadcast — before the process goes. `willTerminate` could only
/// close the room; a broadcast cut off by a quit was never completed.
final class ArchiveWatchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard StudioSession.shared.isLive else { return .terminateNow }
            guard StudioEndConfirmation.confirm() else { return .terminateCancel }
            Task { @MainActor in
                await StudioSession.shared.end()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
#endif
