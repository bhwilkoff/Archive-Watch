// Renders every Watch Together Studio overlay state to PNG so it can be LOOKED
// AT (docs/WATCH-TOGETHER.md §8; the project's rule that a feature is verified
// on the glass, never by "it compiled").
//
// Each frame is composited over a stand-in "film" — a mid-grey gradient with
// bright and dark bands — because a lower third is only legible if it survives
// the worst frame the film can put behind it, and a black test card proves
// nothing about white type.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     tools/render_studio_overlay.swift -o /tmp/awoverlay && /tmp/awoverlay

import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct RenderOverlay {
    static let size = CGSize(width: 1920, height: 1080)
    static let outDir = "build/qa/studio-overlay"

    /// A stand-in film frame: bands from near-black to near-white, so the
    /// scrim and the type are judged against the hardest ground.
    static func filmStandIn() -> CVPixelBuffer {
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &px)
        let buffer = px!
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bpr = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<Int(size.height) {
                // Bands, brightest across the bottom third where the lower
                // third lives — the worst case for white type.
                let band = Int(size.height) - y
                let v: UInt8
                switch band {
                case 0..<120: v = 240
                case 120..<200: v = 20
                case 200..<300: v = 200
                default: v = UInt8(40 + (y % 200) / 4)
                }
                let row = base.advanced(by: y * bpr)
                for x in 0..<Int(size.width) {
                    let p = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                    p[0] = v; p[1] = v; p[2] = v; p[3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// A 1280x720 "camera": teal ground, white border, centre cross. Any
    /// distortion or wrong inset shows up immediately.
    static func cameraStandIn() -> CVPixelBuffer {
        let w = 1280, h = 720
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &px)
        let buffer = px!
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bpr = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<h {
                let row = base.advanced(by: y * bpr)
                for x in 0..<w {
                    let p = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                    let border = x < 10 || x >= w - 10 || y < 10 || y >= h - 10
                    let cross = abs(x - w / 2) < 4 || abs(y - h / 2) < 4
                    if border || cross { p[0] = 255; p[1] = 255; p[2] = 255 }
                    else { p[0] = 190; p[1] = 150; p[2] = 60 }   // BGRA: a bright teal
                    p[3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    static func write(_ frame: CVPixelBuffer?, to name: String) {
        // render() returns nil only when no buffer could be had — fatal here.
        guard let px = frame else { print("no program buffer for \(name)"); exit(1) }
        let ci = CIImage(cvPixelBuffer: px)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { print("  ! no image for \(name)"); return }
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        let kb = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) ?? 0
        print("  wrote \(name) (\(kb / 1024) KB)")
    }

    static func main() {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let film = filmStandIn()
        let renderer = ProgramRenderer(size: size)

        // The lower third, with a real catalog record — the point of §2.1.
        var o = StudioOverlay()
        o.title = "The General"
        o.subtitle = "1926 · Buster Keaton, Clyde Bruckman"
        o.provenance = "Public domain since 1954"
        renderer.overlay = o

        // A stand-in camera tile, so the PiP geometry can be SEEN. 16:9 with a
        // border and a centre cross: a squashed or mis-inset tile is obvious.
        let camera = cameraStandIn()
        for layout in StudioLayout.allCases {
            renderer.layout = layout
            write(renderer.render(film: film, camera: camera), to: "layout-\(layout.rawValue).png")
        }

        renderer.layout = .film
        // A long title must not run off the frame or collide with the rule.
        var long = o
        long.title = "L'Arrivée d'un train en gare de La Ciotat"
        long.subtitle = "1896 · Auguste Lumière, Louis Lumière"
        long.provenance = "Public domain — published before 1930"
        renderer.overlay = long
        write(renderer.render(film: film, camera: nil), to: "lowerthird-long.png")

        // No provenance is a real case: plenty of items have no date of entry.
        var noProv = o
        noProv.provenance = ""
        renderer.overlay = noProv
        write(renderer.render(film: film, camera: nil), to: "lowerthird-no-provenance.png")

        // Hidden, which must leave the film completely untouched.
        var hidden = o
        hidden.showLowerThird = false
        renderer.overlay = hidden
        write(renderer.render(film: film, camera: nil), to: "lowerthird-hidden.png")

        for (name, card) in [("soon", StudioOverlay.Card.startingSoon(secondsRemaining: 95)),
                             ("soon-zero", .startingSoon(secondsRemaining: 0)),
                             ("intermission", .intermission),
                             ("ending", .ending),
                             // §D10 — the host's own words, in four ranks and
                             // in one. The one-line case is the one that
                             // matters: an editor with four empty slots must
                             // not reserve three bands of black, and the block
                             // must still be optically centred.
                             ("custom", .custom(lines: [
                                .init(id: 0, text: "Back in five", rank: .display),
                                .init(id: 1, text: "Stretch your legs \u{2014} the projectionist needs a minute", rank: .body),
                                .init(id: 2, text: "", rank: .body),
                                .init(id: 3, text: "archivewatch.org", rank: .caption)])),
                             ("custom-one-line", .custom(lines: [
                                .init(id: 0, text: "", rank: .display),
                                .init(id: 1, text: "Thanks for riffing along", rank: .heading),
                                .init(id: 2, text: "", rank: .body),
                                .init(id: 3, text: "", rank: .caption)]))] {
            var c = o
            c.card = card
            renderer.overlay = c
            write(renderer.render(film: film, camera: nil), to: "card-\(name).png")
        }

        // CHAT, with the awkward cases on purpose: a message longer than the
        // column, a platform event, scripts that are not Latin, an emoji, and
        // a one-word line. A chat renderer that only handles "nice lol" is a
        // renderer that breaks the first time a real audience turns up.
        var chatty = o
        chatty.chat = [
            .init(id: "1", author: "mothra_fan", text: "here for the train"),
            .init(id: "2", author: "silentera", text: "this is the best chase sequence ever committed to film and nobody can convince me otherwise"),
            .init(id: "3", author: "Twitch", text: "kinomaniac just subscribed!", isEvent: true),
            .init(id: "4", author: "河内さん", text: "キートンは天才だ"),
            .init(id: "5", author: "spool", text: "🚂🚂🚂"),
            .init(id: "6", author: "a_very_long_display_name_indeed", text: "hi"),
        ]
        for layout in StudioLayout.allCases {
            renderer.layout = layout
            renderer.overlay = chatty
            write(renderer.render(film: film, camera: camera), to: "chat-\(layout.rawValue).png")
        }
        // And the empty case, which must leave the film completely alone.
        var noChat = chatty
        noChat.chat = []
        renderer.layout = .corner
        renderer.overlay = noChat
        write(renderer.render(film: film, camera: camera), to: "chat-empty.png")

        print("\nWrote to \(outDir) — look at them.")
    }
}
