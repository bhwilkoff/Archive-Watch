// §8.74 — the show's SOURCES and each scene's tiles reach the PIXELS
// (macOS-DESIGN §D40).
//
// Owner, 2026-09-30: "You should be able to have full control over which
// camera and call are on each scene, just as you can do in OBS." Chosen:
// any number, each its own tile; every added camera kept running; voices
// always heard.
//
// Drives the real `ProgramRenderer`, `StudioTileLayout`, `StudioComposition`
// and the mixer's call sum with SYNTHETIC sources — two cameras and two calls,
// each a distinct solid color, over a blue film — and reads the composited
// frame back. What is asserted is what an audience would see.
//
// THE CONTROL: the scene checks are run a second time on a frame rendered
// with the scene's selection IGNORED (every source shown). The checker must
// call that frame wrong, or it is not checking selection at all.
//
// Compile (as test_studio_all.sh does):
//   xcrun swiftc -parse-as-library -O RTMPPublisher.swift StudioEngine.swift \
//     StudioRecorder.swift StudioChatFilter.swift StudioOutputSettings.swift \
//     StudioAudio.swift StudioOverlayRenderer.swift StudioChatTwitch.swift \
//     StudioChatYouTube.swift StudioSources.swift tools/harness_awdiag.swift \
//     tools/test_studio_sources.swift -o /tmp/sources
import Foundation
import CoreVideo
import CoreImage

final class StillSource: GuestFrameSource, @unchecked Sendable {
    let px: CVPixelBuffer?
    init(_ px: CVPixelBuffer?) { self.px = px }
    func latest() -> CVPixelBuffer? { px }
}

@main struct SourcesTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "  ok  " : "  FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    typealias RGB = (r: Int, g: Int, b: Int)

    static func image(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CVPixelBuffer {
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary] as CFDictionary,
                            &px)
        let p = px!
        CVPixelBufferLockBaseAddress(p, [])
        let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(p)
        for y in 0..<h { for x in 0..<w {
            let (r, g, b) = f(x, y)
            let o = y * row + x * 4
            base[o] = b; base[o + 1] = g; base[o + 2] = r; base[o + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(p, [])
        return p
    }
    static func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, w: Int = 1280, h: Int = 720) -> CVPixelBuffer {
        image(w, h) { _, _ in (r, g, b) }
    }

    /// Core Image coordinates (origin bottom-left), as every rect is written.
    static func color(_ p: CVPixelBuffer, at pt: CGPoint) -> RGB {
        CVPixelBufferLockBaseAddress(p, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(p, .readOnly) }
        let h = CVPixelBufferGetHeight(p)
        let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(p)
        let x = Int(pt.x), y = h - 1 - Int(pt.y)
        let o = y * row + x * 4
        return (Int(base[o + 2]), Int(base[o + 1]), Int(base[o]))
    }
    static func near(_ c: RGB, _ want: RGB) -> Bool {
        abs(c.r - want.r) < 40 && abs(c.g - want.g) < 40 && abs(c.b - want.b) < 40
    }
    static func mid(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    static func px(_ n: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: n.minX * size.width, y: n.minY * size.height,
               width: n.width * size.width, height: n.height * size.height)
    }

    /// The largest per-channel difference between two frames.
    static func maxDiff(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(a, .readOnly); CVPixelBufferLockBaseAddress(b, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(a, .readOnly); CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        let w = CVPixelBufferGetWidth(a), h = CVPixelBufferGetHeight(a)
        let pa = CVPixelBufferGetBaseAddress(a)!.assumingMemoryBound(to: UInt8.self)
        let pb = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
        let ra = CVPixelBufferGetBytesPerRow(a), rb = CVPixelBufferGetBytesPerRow(b)
        var m = 0
        for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) {
            for c in 0..<3 { m = max(m, abs(Int(pa[y * ra + x * 4 + c]) - Int(pb[y * rb + x * 4 + c]))) }
        } }
        return m
    }

    static func main() {
        let size = CGSize(width: 1280, height: 720)
        let blue: RGB = (0, 0, 230)
        let green: RGB = (0, 230, 0), yellow: RGB = (230, 230, 0)
        let red: RGB = (230, 0, 0), magenta: RGB = (230, 0, 230)
        let film = solid(0, 0, 230)
        let camA = solid(0, 230, 0), camB = solid(230, 230, 0)
        let callC = solid(230, 0, 0, w: 1024, h: 768)   // a 4:3 call window
        let callD = solid(230, 0, 230)
        let sources: [StudioSourceRef] = [
            StudioSourceRef(id: "camera-A", kind: .camera, deviceID: "dev-a"),
            StudioSourceRef(id: "camera-B", kind: .camera, deviceID: "dev-b"),
            StudioSourceRef(id: "call-C", kind: .call),
            StudioSourceRef(id: "call-D", kind: .call),
        ]
        let allFrames: [String: CVPixelBuffer] = ["camera-A": camA, "camera-B": camB,
                                                  "call-C": callC, "call-D": callD]
        let colorOf: [String: RGB] = ["camera-A": green, "camera-B": yellow,
                                      "call-C": red, "call-D": magenta]

        func render(layout: StudioLayout = .corner, card: StudioOverlay.Card? = nil,
                    tiles: [StudioTile], frames: [String: CVPixelBuffer] = allFrames)
            -> (CVPixelBuffer, ProgramRenderer) {
            let r = ProgramRenderer(size: size)
            r.layout = layout
            var o = StudioOverlay()
            o.showLowerThird = false; o.card = card
            r.overlay = o
            r.tiles = tiles
            r.sourceFrames = frames
            _ = r.render(film: film, camera: nil)
            return (r.render(film: film, camera: nil)!, r)
        }

        /// A scene is right when every source it shows is drawn in its own
        /// color at the rect the renderer published, and every source it does
        /// NOT show appears nowhere. "Nowhere" is sampled on a grid, so a
        /// source drawn anywhere at all is caught.
        func sceneIsRight(_ frame: CVPixelBuffer, _ r: ProgramRenderer, shows: Set<String>) -> (Bool, String) {
            for id in shows {
                guard let n = r.lastTileRects[id] else { return (false, "\(id) not drawn") }
                let c = color(frame, at: mid(px(n, size)))
                if !near(c, colorOf[id]!) { return (false, "\(id) center is \(c)") }
            }
            if Set(r.lastTileRects.keys) != shows { return (false, "published \(r.lastTileRects.keys.sorted())") }
            for id in Set(colorOf.keys).subtracting(shows) {
                for gx in stride(from: 8, to: Int(size.width), by: 24) {
                    for gy in stride(from: 8, to: Int(size.height), by: 24) {
                        if near(color(frame, at: CGPoint(x: gx, y: gy)), colorOf[id]!) {
                            return (false, "\(id) appears at \(gx),\(gy)")
                        }
                    }
                }
            }
            return (true, "")
        }

        print("=== 8.74 sources: two cameras, two calls, 1280x720 program ===")

        // ---- 1. A scene shows camera A and call D, and nothing else.
        let scene1Shown = ["call-D", "camera-A"]
        let scene1 = StudioComposition.tiles(shown: scene1Shown, framings: [:], sources: sources)
        check("scene 1 seats: A takes the host's seat, D the call's",
              scene1.map(\.slot) == [.call, .camera], "\(scene1.map(\.slot))")
        var (frame, r) = render(tiles: scene1)
        var verdict = sceneIsRight(frame, r, shows: ["camera-A", "call-D"])
        check("scene 1 draws exactly camera A and call D", verdict.0, verdict.1)
        let cornerCam = StudioLayout.corner.rects(in: size, cameraAspect: 16.0 / 9.0, withCall: true).camera!
        check("camera A sits in the placement's host seat",
              r.lastTileRects["camera-A"].map { abs(px($0, size).minX - cornerCam.minX) < 1 } ?? false)
        check("the film fills the rest", near(color(frame, at: CGPoint(x: 640, y: 360)), blue))

        // THE CONTROL: the same checker over a frame that ignored the scene's
        // selection must say it is wrong.
        let ignored = StudioComposition.tiles(shown: sources.map(\.id), framings: [:], sources: sources)
        (frame, r) = render(tiles: ignored)
        verdict = sceneIsRight(frame, r, shows: ["camera-A", "call-D"])
        check("CONTROL: a renderer that ignores the selection fails scene 1's check", !verdict.0,
              verdict.0 ? "the check could not tell" : verdict.1)

        // ---- 2. Another scene, another set: both cameras and call C.
        let scene2 = StudioComposition.tiles(shown: ["call-C", "camera-B", "camera-A"],
                                             framings: [:], sources: sources)
        check("scene 2 seats go by the Sources list, not by layer order",
              scene2.first { $0.source == "camera-A" }?.slot == .camera
              && scene2.first { $0.source == "camera-B" }?.slot == .free
              && scene2.first { $0.source == "call-C" }?.slot == .call)
        (frame, r) = render(tiles: scene2)
        verdict = sceneIsRight(frame, r, shows: ["camera-A", "camera-B", "call-C"])
        check("scene 2 draws exactly cameras A and B and call C", verdict.0, verdict.1)
        if let b = r.lastTileRects["camera-B"] {
            check("the second camera starts in its own column, in frame",
                  CGRect(x: 0, y: 0, width: 1, height: 1).contains(b)
                  && !b.intersects(r.lastTileRects["camera-A"] ?? .zero)
                  && !b.intersects(r.lastTileRects["call-C"] ?? .zero))
        }
        // Switching back: the same renderer, told the first scene again.
        r.tiles = scene1
        _ = r.render(film: film, camera: nil)
        let back = r.render(film: film, camera: nil)!
        verdict = sceneIsRight(back, r, shows: ["camera-A", "call-D"])
        check("switching back to scene 1 draws scene 1 again", verdict.0, verdict.1)

        // ---- 3. Layer order: two tiles in one place, the LAST is in front.
        var same = StudioCameraFraming()
        same.tile = CGRect(x: 0.40, y: 0.40, width: 0.25, height: 0.25)
        let stacked: [String: StudioCameraFraming] = ["camera-A": same, "camera-B": same]
        var order = ["camera-A", "camera-B"]
        (frame, _) = render(tiles: StudioComposition.tiles(shown: order, framings: stacked, sources: sources))
        let spot = mid(px(same.tile!, size))
        check("layer order: B after A puts B in front", near(color(frame, at: spot), yellow),
              "\(color(frame, at: spot))")
        order = StudioComposition.moving("camera-A", .front, in: order)
        check("Bring to Front moves A to the end", order == ["camera-B", "camera-A"])
        (frame, _) = render(tiles: StudioComposition.tiles(shown: order, framings: stacked, sources: sources))
        check("layer order: after Bring to Front, A is in front", near(color(frame, at: spot), green),
              "\(color(frame, at: spot))")
        check("Send Backward and Forward are one step each",
              StudioComposition.moving("c", .backward, in: ["a", "b", "c"]) == ["a", "c", "b"]
              && StudioComposition.moving("a", .forward, in: ["a", "b", "c"]) == ["b", "a", "c"]
              && StudioComposition.moving("c", .back, in: ["a", "b", "c"]) == ["c", "a", "b"])
        check("turning a source on puts it in front",
              StudioComposition.setting("a", shown: true, in: ["a", "b"]) == ["b", "a"]
              && StudioComposition.setting("b", shown: false, in: ["a", "b"]) == ["a"])

        // ---- 4. A source that is unplugged or removed draws NOTHING.
        var unplugged = allFrames
        unplugged["camera-A"] = nil
        (frame, r) = render(tiles: scene1, frames: unplugged)
        check("an unplugged camera draws nothing and nothing crashes",
              r.lastTileRects["camera-A"] == nil && !near(color(frame, at: mid(cornerCam)), green))
        check("the call it shared a scene with is still drawn", r.lastTileRects["call-D"] != nil)
        let pruned = StudioComposition.tiles(shown: scene1Shown, framings: [:],
                                             sources: sources.filter { $0.id != "call-D" })
        check("a source removed from the list drops out of the scene's tiles",
              pruned.map(\.source) == ["camera-A"])
        (frame, r) = render(tiles: [StudioTile(source: "gone", slot: .camera)] + scene1)
        check("a tile naming a source that never existed is ignored",
              r.lastTileRects["gone"] == nil && r.lastTileRects["camera-A"] != nil)
        // At the engine: removing a source leaves nothing attached for it.
        let engineSources: [String] = {
            let e = StudioEngine()
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var ids: [String] = []
            Task.detached {
                await e.attachSource("camera-A", StillSource(camA), call: false)
                await e.attachSource("call-D", StillSource(callD), call: true)
                await e.attachSource("call-D", nil, call: true)
                ids = await e.sourceIDs
                sem.signal()
            }
            sem.wait()
            return ids
        }()
        check("the engine drops a removed source", engineSources == ["camera-A"], "\(engineSources)")

        // ---- 5. A scene saved before §D40 composites exactly as it did.
        // The tiles part of a real pre-§D40 saved scene, as JSON.
        let oldJSON = #"""
        {"camera":{"tile":[[0.52,0.08],[0.30,0.34]],"zoom":1.6,"panX":0.4,"panY":-0.3},
         "guests":{"zoom":1.3,"panX":-0.5,"panY":0}}
        """#
        guard let oldTiles = try? JSONDecoder().decode(StudioSceneTiles.self, from: Data(oldJSON.utf8)) else {
            check("a pre-§D40 scene's tiles still decode", false); finish()
        }
        check("a pre-§D40 scene's tiles still decode (no bySource)", oldTiles.bySource == nil)
        // Pictures with DETAIL, so a crop or a displaced box shows up in the
        // comparison — a solid color would compare equal whatever the framing.
        let camPattern = image(1280, 720) { x, y in (UInt8(x % 256), UInt8(y % 256), 40) }
        let callPattern = image(1024, 768) { x, y in (200, UInt8((x / 3) % 256), UInt8((y / 2) % 256)) }
        for (camOn, callOn) in [(true, true), (true, false), (false, true)] {
            let m = StudioComposition.migrate(cameraOn: camOn, callOn: callOn, tiles: oldTiles,
                                              primaryCamera: "camera-A", primaryCall: "call-C")
            let migrated = StudioComposition.tiles(shown: m.shown, framings: m.framings, sources: sources)
            for (layout, card) in [(StudioLayout.corner, nil), (.side, nil), (.theatre, nil),
                                   (.host, nil), (.guests, nil),
                                   (.host, StudioOverlay.Card.intermission)] as [(StudioLayout, StudioOverlay.Card?)] {
                let legacy = ProgramRenderer(size: size)
                legacy.layout = layout
                var o = StudioOverlay(); o.showLowerThird = false; o.card = card
                legacy.overlay = o
                legacy.showCamera = camOn
                legacy.showCall = callOn
                legacy.framing = oldTiles.camera
                legacy.guestFraming = oldTiles.guests
                legacy.guestFrame = callPattern
                _ = legacy.render(film: film, camera: camPattern)
                let before = legacy.render(film: film, camera: camPattern)!
                let (after, _) = render(layout: layout, card: card, tiles: migrated,
                                        frames: ["camera-A": camPattern, "call-C": callPattern])
                let d = maxDiff(before, after)
                check("migrated \(layout.rawValue)\(card == nil ? "" : "+card") camera=\(camOn) call=\(callOn) is the same picture",
                      d <= 2, "max channel difference \(d)")
            }
        }
        // And the migration's control: forgetting the framing is NOT the same
        // picture, or the comparison above could not see a lost crop.
        do {
            let m = StudioComposition.migrate(cameraOn: true, callOn: true, tiles: StudioSceneTiles(),
                                              primaryCamera: "camera-A", primaryCall: "call-C")
            let lost = StudioComposition.tiles(shown: m.shown, framings: m.framings, sources: sources)
            let legacy = ProgramRenderer(size: size)
            var o = StudioOverlay(); o.showLowerThird = false
            legacy.overlay = o
            legacy.showCamera = true; legacy.showCall = true
            legacy.framing = oldTiles.camera; legacy.guestFraming = oldTiles.guests
            legacy.guestFrame = callPattern
            _ = legacy.render(film: film, camera: camPattern)
            let before = legacy.render(film: film, camera: camPattern)!
            let (after, _) = render(tiles: lost, frames: ["camera-A": camPattern, "call-C": callPattern])
            check("CONTROL: a migration that dropped the framing is visibly different",
                  maxDiff(before, after) > 40)
        }
        check("a migrated scene with both switches off shows nobody",
              StudioComposition.migrate(cameraOn: false, callOn: false, tiles: oldTiles,
                                        primaryCamera: "camera-A", primaryCall: "call-C").shown.isEmpty)

        // ---- 6. Voices always heard: a hidden call's audio is still mixed.
        let n = 2048
        let ringZoom = AudioRing(), ringMeet = AudioRing()
        let a = UnsafeMutablePointer<Float>.allocate(capacity: n); defer { a.deallocate() }
        for i in 0..<n { a[i] = 0.1 }
        ringZoom.write(a, count: n)
        for i in 0..<n { a[i] = 0.2 }
        ringMeet.write(a, count: n)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: n); defer { out.deallocate() }
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: n); defer { scratch.deallocate() }
        StudioAudioMixer.sumCalls([ringZoom, ringMeet], into: out, scratch: scratch, count: n)
        check("two calls are summed into the call channel", abs(out[0] - 0.3) < 1e-5 && abs(out[n - 1] - 0.3) < 1e-5,
              "\(out[0])")
        StudioAudioMixer.sumCalls([ringZoom], into: out, scratch: scratch, count: n)
        check("a starved call adds silence, not a repeat", out[0] == 0)
        let keys: [String] = {
            let e = StudioEngine()
            e.attachCallAudio(key: "us.zoom.xos", ring: AudioRing())
            e.attachCallAudio(key: "com.google.Chrome", ring: AudioRing())
            // The same app a second time REPLACES, never stacks: two windows
            // of one call app are one tap, or its voices arrive twice.
            e.attachCallAudio(key: "com.google.Chrome", ring: AudioRing())
            let sem = DispatchSemaphore(value: 0)
            Task.detached { await e.setTiles([StudioTile(source: "camera-A", slot: .camera)]); sem.signal() }
            sem.wait()
            return e.callAudioKeys.sorted()
        }()
        check("a scene that shows no call leaves every call's audio in the mix",
              keys == ["com.google.Chrome", "us.zoom.xos"], "\(keys)")

        // ---- 7. Chat yields to an extra tile on the left.
        do {
            let r = ProgramRenderer(size: size)
            var o = StudioOverlay(); o.showLowerThird = false; o.showChat = true
            o.chat = (0..<12).map { StudioOverlay.ChatLine(id: "l\($0)", author: "viewer\($0)", text: "a line of chat \($0)") }
            r.overlay = o
            r.tiles = StudioComposition.tiles(shown: ["camera-A", "camera-B"], framings: [:], sources: sources)
            r.sourceFrames = allFrames
            _ = r.render(film: film, camera: nil)
            let f = r.render(film: film, camera: nil)!
            if let b = r.lastTileRects["camera-B"] {
                check("the extra camera is not written over by chat", near(color(f, at: mid(px(b, size))), yellow))
            } else { check("the extra camera is drawn", false) }
        }
        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "PASS" : "FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
