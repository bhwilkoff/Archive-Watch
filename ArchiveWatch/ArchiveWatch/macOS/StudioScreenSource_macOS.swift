#if os(macOS)
// The call's PICTURE, captured as one window (§D23).
//
// Decision 131's third mode already tapped the call's AUDIO; this is the other
// half. `SCContentFilter(desktopIndependentWindow:)` captures exactly one
// window as a live stream, whatever display it is on and whatever overlaps it
// — so the Zoom/Meet/FaceTime grid the host is already looking at becomes a
// source, and the app still never carries a guest's voice or video over a
// transport of ours. No relay, no NAT traversal, no monthly bill.
//
// TWO THINGS THIS DELIBERATELY DOES NOT DO.
//
// 1. IT CAPTURES NO AUDIO. `SCStreamConfiguration.capturesAudio` is
//    APP-level even behind a window filter, so switching it on would deliver
//    the same audio `StudioCallAudioTap` already has — and the call would
//    arrive twice, a moment apart, which is exactly the double-audio fault
//    §D18 exists for. Picture here, sound there.
// 2. IT NEVER CAPTURES OUR OWN WINDOW. A Studio that captured the Studio
//    would composite its own preview into the program, and the preview draws
//    the program: an infinite corridor, live, on somebody's channel.
//
// macOS only — ScreenCaptureKit does not exist elsewhere, which is the same
// reason Decision 131 makes the Mac the only host for this mode.

import Foundation
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit

@MainActor
public final class StudioScreenSource: NSObject, SCStreamOutput, SCStreamDelegate {

    /// One capturable window, as the host would name it.
    public struct Window: Identifiable, Sendable, Equatable {
        public let id: CGWindowID
        public let app: String
        public let title: String
        /// What the picker shows: the app, and the window only when the app
        /// has more than one worth telling apart.
        public var label: String { title.isEmpty ? app : "\(app) — \(title)" }
    }

    /// WHY THE REFUSAL IS A STRING AND NOT A BOOL. The one genuinely unknown
    /// thing here is what a SIGNED, SANDBOXED app gets from the Screen
    /// Recording TCC service, and Decision 130's answer to an unknown is to
    /// measure it and let the product SAY what it measured. A silent failure
    /// would leave a host looking at a black tile with no idea whose fault it
    /// is.
    public private(set) var problem: String?

    public private(set) var isRunning = false
    private var stream: SCStream?
    /// NOT main-actor isolated: this is called on the capture queue 30 times
    /// a second, and hopping to the main actor per frame would put the
    /// compositor behind whatever the UI is doing. A lock, because the start
    /// and the queue really do touch it from two threads.
    public let sink = FrameSink()

    /// HOLDS THE LATEST FRAME; the engine PULLS it, exactly as
    /// `CameraFrameTap` does. Pushing each frame into an actor would send a
    /// `CVPixelBuffer` across an isolation boundary 30 times a second, which
    /// Swift 6 correctly refuses, and hopping per frame would put the
    /// compositor behind whatever the UI is doing.
    ///
    /// The sample buffer that OWNS the pixels is retained beside it: releasing
    /// it returns the pixels to ScreenCaptureKit's pool, which can then draw
    /// into them while the compositor is reading. The same rule the program
    /// preview learned (§D5).
    public final class FrameSink: GuestFrameSource, @unchecked Sendable {
        private let lock = NSLock()
        private var frame: CVPixelBuffer?
        private var held: CMSampleBuffer?
        func store(_ px: CVPixelBuffer, from sb: CMSampleBuffer) {
            lock.lock(); frame = px; held = sb; lock.unlock()
        }
        func clear() { lock.lock(); frame = nil; held = nil; lock.unlock() }
        public func latest() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return frame }
    }

    /// Counted on the capture queue, read from anywhere — see `FrameSink`.
    private let frameCount = Counter()

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        func reset() { lock.lock(); n = 0; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    /// Counted so a caller can tell "no permission" from "permitted and the
    /// window is not drawing" — two states that look identical on screen.
    public var framesDelivered: Int { frameCount.value }

    /// Every window a host could pick, minus our own.
    ///
    /// `onScreenWindowsOnly: true` is the right filter and not merely a
    /// smaller one: a minimised window delivers nothing, so offering it would
    /// be offering a black tile.
    public static func windows() async -> [Window] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let mine = Bundle.main.bundleIdentifier
            return content.windows.compactMap { w in
                guard let app = w.owningApplication else { return nil }
                guard app.bundleIdentifier != mine else { return nil }   // never ourselves
                guard w.frame.width > 200, w.frame.height > 150 else { return nil }
                return Window(id: w.windowID,
                              app: app.applicationName,
                              title: w.title ?? "")
            }
            .sorted { ($0.app, $0.title) < ($1.app, $1.title) }
        } catch {
            return []
        }
    }

    /// Starts capturing one window. Frames land in `sink`, to be pulled.
    @discardableResult
    public func start(windowID: CGWindowID, size: CGSize) async -> Bool {
        stop()
        problem = nil
        frameCount.reset()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                problem = "That window has closed."
                return false
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(size.width)
            config.height = Int(size.height)
            // 30 fps to match the program; asking for more buys nothing a
            // broadcast can carry and costs the host's CPU.
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 5
            config.showsCursor = false        // a pointer in the guest tile is noise
            config.capturesAudio = false      // see the header: the tap owns sound

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen,
                                  sampleHandlerQueue: DispatchQueue(
                                    label: "org.archivewatch.screen", qos: .userInitiated))
            try await s.startCapture()
            stream = s
            isRunning = true
            return true
        } catch {
            // NAME IT. A `TCCError 3` here means the person has not granted
            // Screen Recording, and "the operation couldn't be completed" is
            // not something a host can act on.
            let ns = error as NSError
            if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                || "\(error)".contains("declined") || "\(error)".contains("TCC") {
                problem = "macOS has not granted Screen Recording to Archive Watch. "
                    + "System Settings ▸ Privacy & Security ▸ Screen Recording."
            } else {
                problem = "\(error.localizedDescription)"
            }
            return false
        }
    }

    public func stop() {
        guard let s = stream else { isRunning = false; return }
        stream = nil
        isRunning = false
        sink.clear()
        Task { try? await s.stopCapture() }
    }

    // MARK: SCStreamOutput

    public nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer,
                                   of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let px = CMSampleBufferGetImageBuffer(sb) else { return }
        // SCK DELIVERS FRAMES FOR UNCHANGED SCREENS TOO, marked as such, and
        // compositing those is pure cost. The status is in the attachment.
        if let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
           let raw = a.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        frameCount.bump()
        sink.store(px, from: sb)
    }

    public nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // DROP THE LAST FRAME. Without this the sink keeps handing out the
        // final picture forever and the broadcast shows a FROZEN STILL OF
        // PEOPLE WHO HAVE LEFT — which looks live, and is the worst of the
        // three states a tile can be in. A comment on `guestFrame` claimed
        // this already happened; it did not, and that is exactly the kind of
        // claim this project keeps finding in its own comments.
        //
        // Cleared on the delegate thread rather than hopped to the main
        // actor, because the compositor reads this sink from its own thread
        // and a hop would leave the stale frame on air for as long as the
        // main actor is busy.
        sink.clear()
        MainActor.assumeIsolated {
            self.isRunning = false
            self.problem = "The window you were showing has gone — pick another."
        }
    }
}
#endif
