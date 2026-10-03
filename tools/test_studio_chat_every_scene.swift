// §8.77 — chat reaches EVERY scene the host turned it on in (macOS-DESIGN
// §D22b).
//
// Owner, 2026-10-02, after the first full show: "The chat that I put on the
// screen only worked on some of the scenes." A card returned before chat was
// drawn, so Starting soon, Intermission and Thanks never showed it; and a
// column a tile sat in was given up rather than moved. This drives the real
// `ProgramRenderer` on the macOS tiled path — a camera and a call, as the
// starter scenes show them — through every starter scene, both sides, and a
// tile dragged across the chosen column, and reads `lastChatRect` plus the
// pixels under it.
//
// Controls: chat switched off must draw nothing, and a shout-out on a card
// must change the card's pixels (the card cache once ignored it).
import Foundation
import CoreVideo
import CoreImage

@main struct ChatEverySceneTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "  ok  " : "  FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    static func solid(_ w: Int, _ h: Int, r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer {
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary] as CFDictionary, &px)
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
    static func checksum(_ p: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(p, .readOnly); defer { CVPixelBufferUnlockBaseAddress(p, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
        var s = 0
        for i in stride(from: 0, to: CVPixelBufferGetDataSize(p), by: 97) { s = s &+ Int(base[i]) &* (i % 251 + 1) }
        return s
    }

    static func main() {
        let size = CGSize(width: 1280, height: 720)
        let frames = ["cam": solid(1280, 720, r: 0, g: 230, b: 0),
                      "call": solid(1280, 720, r: 230, g: 0, b: 0)]
        let film = solid(1280, 720, r: 0, g: 0, b: 230)
        let chat = (1...4).map { StudioOverlay.ChatLine(id: "\($0)", author: "viewer\($0)", text: "a line of chat number \($0)") }

        func render(layout: StudioLayout, card: StudioOverlay.Card?, side: StudioChatSide,
                    showChat: Bool = true, camTile: CGRect? = nil,
                    shout: StudioOverlay.ShoutOut? = nil) -> (CVPixelBuffer, ProgramRenderer) {
            let r = ProgramRenderer(size: size)
            r.layout = layout
            r.chatSide = side
            var o = StudioOverlay()
            o.title = "A Film"; o.card = card; o.chat = chat; o.showChat = showChat
            o.shoutOut = shout
            r.overlay = o
            var camFraming = StudioCameraFraming()
            camFraming.tile = camTile
            r.tiles = [StudioTile(source: "call", slot: .call),
                       StudioTile(source: "cam", slot: .camera, framing: camFraming)]
            r.sourceFrames = frames
            _ = r.render(film: film, camera: nil)
            return (r.render(film: film, camera: nil)!, r)
        }

        print("=== 8.77 chat on every scene, 1280x720 program ===")
        let scenes: [(String, StudioLayout, StudioOverlay.Card?)] = [
            ("Starting soon", .host, .startingSoon(secondsRemaining: 30)),
            ("Film", .corner, nil),
            ("Intermission", .host, .intermission),
            ("Discussion", .side, nil),
            ("Thanks", .host, .ending),
            ("Theater row", .theatre, nil),
            ("You, film inset", .host, nil),
        ]
        for (name, layout, card) in scenes {
            for side in StudioChatSide.allCases {
                let (_, r) = render(layout: layout, card: card, side: side)
                check("\(name), chat \(side.rawValue): chat is drawn", r.lastChatRect != nil,
                      r.lastChatRect.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none")
                if let c = r.lastChatRect {
                    // A camera that fills the frame is the ground chat sits
                    // on; every other tile must be clear.
                    let people = r.lastTileRects.values.map {
                        CGRect(x: $0.minX * size.width, y: $0.minY * size.height,
                               width: $0.width * size.width, height: $0.height * size.height)
                    }.filter { $0.width < size.width * 0.99 }
                    check("\(name), chat \(side.rawValue): chat covers no one",
                          !people.contains { $0.insetBy(dx: 2, dy: 2).intersects(c) })
                }
            }
        }

        // A tile dragged across the left column: chat moves to the right.
        let blocking = CGRect(x: 0.03, y: 0.25, width: 0.32, height: 0.6)
        let (_, moved) = render(layout: .corner, card: nil, side: .left, camTile: blocking)
        check("a camera dragged over the left column: chat moves to the right",
              (moved.lastChatRect?.minX ?? 0) > size.width / 2,
              moved.lastChatRect.map { "x=\(Int($0.minX))" } ?? "none")

        // Controls.
        let (_, off) = render(layout: .corner, card: nil, side: .left, showChat: false)
        check("CONTROL: chat switched off draws nothing", off.lastChatRect == nil)
        let (plain, _) = render(layout: .host, card: .intermission, side: .left, showChat: false)
        let shout = StudioOverlay.ShoutOut(author: "viewer9", text: "hello from the intermission", shownAt: Date())
        let (withShout, _) = render(layout: .host, card: .intermission, side: .left, showChat: false, shout: shout)
        check("a shout-out on a card reaches the picture", checksum(plain) != checksum(withShout))

        print(failures == 0 ? "PASS" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
