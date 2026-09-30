// §8.72 — a scene's Camera and Call switches reach the PIXELS (macOS-DESIGN
// §D31, amended 2026-09-30).
//
// Owner: "the Watch Together studio on MacOS doesn't allow for the cameras and
// the call to come through on the different scenes. You should be able to
// turn on or off the video from each scene."
//
// Drives the real `ProgramRenderer` with SYNTHETIC sources — a solid green
// camera, a solid red call, a solid blue film — and reads the composited
// frame back, so the answer is what the audience would see rather than what
// a control says. Every positive check has its negative twin (the switch off,
// or nil on the platforms without scenes); a renderer that ignored the
// switches, or that still let a card own the whole frame, fails one of each
// pair. That pairing is the control.
//
// Compile (as test_studio_all.sh does):
//   xcrun swiftc -parse-as-library -O RTMPPublisher.swift StudioEngine.swift \
//     StudioRecorder.swift StudioChatFilter.swift StudioOutputSettings.swift \
//     StudioAudio.swift StudioOverlayRenderer.swift StudioChatTwitch.swift \
//     StudioChatYouTube.swift tools/harness_awdiag.swift \
//     tools/test_studio_scene_people.swift -o /tmp/people
import Foundation
import CoreVideo
import CoreImage

@main struct ScenePeopleTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "  ok  " : "  FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func solid(_ w: Int, _ h: Int, r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer {
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary] as CFDictionary,
                            &px)
        let p = px!
        CVPixelBufferLockBaseAddress(p, [])
        let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(p)
        for y in 0..<h { for x in 0..<w {
            let o = y * row + x * 4
            base[o] = b; base[o + 1] = g; base[o + 2] = r; base[o + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(p, [])
        return p
    }

    /// The colour at a point given in CORE IMAGE coordinates (origin
    /// bottom-left), which is what every layout rect is written in.
    static func color(_ p: CVPixelBuffer, at pt: CGPoint) -> (r: Int, g: Int, b: Int) {
        CVPixelBufferLockBaseAddress(p, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(p, .readOnly) }
        let h = CVPixelBufferGetHeight(p)
        let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(p)
        let x = Int(pt.x), y = h - 1 - Int(pt.y)
        let o = y * row + x * 4
        return (Int(base[o + 2]), Int(base[o + 1]), Int(base[o]))
    }
    static func isGreen(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.g > 180 && c.r < 80 && c.b < 80 }
    static func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 180 && c.g < 80 && c.b < 80 }
    static func mid(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    static func main() {
        let size = CGSize(width: 1280, height: 720)
        let camera = solid(1280, 720, r: 0, g: 230, b: 0)
        let call = solid(1280, 720, r: 230, g: 0, b: 0)
        let film = solid(1280, 720, r: 0, g: 0, b: 230)
        let a: CGFloat = 16.0 / 9.0
        let cornerCam = StudioLayout.corner.rects(in: size, cameraAspect: a).camera!
        let cornerCall = StudioLayout.corner.callRect(in: size, cameraAspect: a, guestAspect: a)!

        func frame(layout: StudioLayout, card: StudioOverlay.Card?, cam: Bool?, callOn: Bool?,
                   withCall: Bool = true) -> (CVPixelBuffer, ProgramRenderer) {
            let r = ProgramRenderer(size: size)
            r.layout = layout
            var o = StudioOverlay()
            o.title = ""; o.showLowerThird = false; o.card = card
            r.overlay = o
            r.showCamera = cam
            r.showCall = callOn
            r.guestFrame = withCall ? call : nil
            // Twice: a transition-free renderer draws the frame it was asked
            // for on the first call, and the second proves it is steady.
            _ = r.render(film: film, camera: camera)
            return (r.render(film: film, camera: camera)!, r)
        }

        print("=== 8.72 a scene's Camera and Call switches, 1280x720 program ===")

        // ---- On a card (Intermission): tiles over the card, right column.
        var (px, r) = frame(layout: .host, card: .intermission, cam: true, callOn: false)
        check("card + camera on: the host is in the right column", isGreen(color(px, at: mid(cornerCam))),
              "\(color(px, at: mid(cornerCam)))")
        check("card + camera on: lastCameraRect is published for the handles",
              r.lastCameraRect.map { abs($0.minX * size.width - cornerCam.minX) < 1 } ?? false)
        check("card + call off: no call tile", !isRed(color(px, at: mid(cornerCall))))
        check("card + call off: lastGuestRect is nil", r.lastGuestRect == nil)
        (px, r) = frame(layout: .host, card: .intermission, cam: false, callOn: false)
        check("card + camera off: no host", !isGreen(color(px, at: mid(cornerCam))))
        check("card + camera off: lastCameraRect is nil", r.lastCameraRect == nil)
        (px, r) = frame(layout: .corner, card: .ending, cam: true, callOn: true)
        check("card + call on: the call sits above the host",
              isRed(color(px, at: mid(cornerCall))) && isGreen(color(px, at: mid(cornerCam))))
        check("card + either: the card is still the ground (no film)",
              color(px, at: CGPoint(x: 200, y: 360)).b < 150)
        (px, _) = frame(layout: .corner, card: .intermission, cam: nil, callOn: nil)
        check("card, switches unset (iOS/tvOS): nobody over the card, as before",
              !isGreen(color(px, at: mid(cornerCam))) && !isRed(color(px, at: mid(cornerCall))))

        // ---- On the film, every placement.
        (px, r) = frame(layout: .corner, card: nil, cam: true, callOn: true)
        check("corner + call on: call tile above the host",
              isRed(color(px, at: mid(cornerCall))) && isGreen(color(px, at: mid(cornerCam))))
        check("corner + call on: lastGuestRect matches the drawn tile",
              r.lastGuestRect.map { abs($0.minY * size.height - cornerCall.minY) < 1 } ?? false)
        (px, r) = frame(layout: .corner, card: nil, cam: true, callOn: false)
        check("corner + call off: no call tile, film there instead",
              !isRed(color(px, at: mid(cornerCall))) && color(px, at: mid(cornerCall)).b > 180)
        check("corner + call off: lastGuestRect is nil", r.lastGuestRect == nil)
        (px, _) = frame(layout: .corner, card: nil, cam: false, callOn: false)
        check("corner + camera off: no host", !isGreen(color(px, at: mid(cornerCam))))
        (px, _) = frame(layout: .corner, card: nil, cam: nil, callOn: nil)
        check("corner, switches unset: host yes, call no (unchanged)",
              isGreen(color(px, at: mid(cornerCam))) && !isRed(color(px, at: mid(cornerCall))))
        (px, _) = frame(layout: .guests, card: nil, cam: nil, callOn: nil)
        check("guests, switches unset: call yes (unchanged)", isRed(color(px, at: mid(cornerCall))))
        (px, _) = frame(layout: .film, card: nil, cam: true, callOn: true)
        check("film only: nobody, whatever the switches say",
              !isGreen(color(px, at: mid(cornerCam))) && !isRed(color(px, at: mid(cornerCall))))

        for l in [StudioLayout.side, .theatre, .host] {
            let camR = l.rects(in: size, cameraAspect: a, withCall: true).camera!
            guard let callR = l.callRect(in: size, cameraAspect: a, guestAspect: a) else {
                check("\(l.rawValue) has a call placement", false); continue
            }
            check("\(l.rawValue): call tile does not overlap the host tile",
                  l == .host || !callR.intersects(camR.insetBy(dx: 2, dy: 2)))
            check("\(l.rawValue): call tile stays in frame",
                  CGRect(origin: .zero, size: size).contains(callR))
            (px, r) = frame(layout: l, card: nil, cam: true, callOn: true)
            check("\(l.rawValue) + call on: call drawn", isRed(color(px, at: mid(callR))),
                  "\(Int(callR.minX)),\(Int(callR.minY)) \(Int(callR.width))x\(Int(callR.height))")
            check("\(l.rawValue) + call on: host still drawn",
                  isGreen(color(px, at: l == .host ? CGPoint(x: 640, y: 300) : mid(camR))))
            (px, _) = frame(layout: l, card: nil, cam: true, callOn: false)
            check("\(l.rawValue) + call off: no call", !isRed(color(px, at: mid(callR))))
            // Chat must not land on the call on either side.
            for side in StudioChatSide.allCases {
                if let col = l.chatRect(in: size, cameraAspect: a, side: side,
                                        guestAspect: a, withCall: true) {
                    check("\(l.rawValue) chat \(side.rawValue) clears the call",
                          !col.intersects(callR.insetBy(dx: 4, dy: 4)))
                }
            }
        }

        print(failures == 0 ? "PASS" : "FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
