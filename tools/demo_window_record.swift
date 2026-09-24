// Record ONE window to an mp4, for the OAuth demo video (docs/oauth).
//
// Window-only by construction (ScreenCaptureKit's desktopIndependentWindow
// filter): nothing else on the owner's screen can reach the file, which is
// the rule after a full-screen capture once caught personal documents.
//
//   swiftc -O tools/demo_window_record.swift -o /tmp/awrec
//   /tmp/awrec list                       # window ids, owning app, title, size
//   /tmp/awrec record <windowID> <out.mp4> <stopfile>
//
// Recording stops when <stopfile> exists. 30 fps, H.264, the window's own
// pixel size (Retina), no audio.
import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@available(macOS 14.0, *)
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    // A secure system dialog (Apple's "wants to use ... to Sign In") interrupts
    // capture; finish the file so the footage before it survives.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("stream stopped: \(error.localizedDescription)")
        input.markAsFinished()
        writer.finishWriting { print("done: \(self.frames) frames"); exit(0) }
    }
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0

    init(out: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: out)
        writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
                                              AVVideoExpectedSourceFrameRateKey: 30],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: sb.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb); frames += 1 }
    }
}

@main
struct Main {
    static func main() async throws {
        guard #available(macOS 14.0, *) else { print("needs macOS 14"); exit(1) }
        _ = NSApplication.shared  // a CLI must initialize the window server connection first
        let args = CommandLine.arguments
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if args.count >= 2, args[1] == "list" {
            for w in content.windows where w.frame.width > 200 && w.frame.height > 150 {
                print("\(w.windowID)\t\(w.owningApplication?.bundleIdentifier ?? "?")\t\(Int(w.frame.width))x\(Int(w.frame.height))\t\(w.title ?? "")")
            }
            return
        }
        guard args.count == 5, args[1] == "record", let id = UInt32(args[2]),
              let window = content.windows.first(where: { $0.windowID == id }) else {
            print("usage: awrec list | awrec record <windowID> <out.mp4> <stopfile>"); exit(2)
        }
        let scale = 2
        let w = Int(window.frame.width) * scale / 2 * 2, h = Int(window.frame.height) * scale / 2 * 2
        let rec = try Recorder(out: URL(fileURLWithPath: args[3]), width: w, height: h)
        let cfg = SCStreamConfiguration()
        cfg.width = w; cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.showsCursor = true
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                              configuration: cfg, delegate: rec)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
        try await stream.startCapture()
        setvbuf(stdout, nil, _IOLBF, 0)
        print("recording window \(id) \(w)x\(h) -> \(args[3])")
        while !FileManager.default.fileExists(atPath: args[4]) {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await stream.stopCapture()
        rec.input.markAsFinished()
        await rec.writer.finishWriting()
        print("done: \(rec.frames) frames")
    }
}
