// §8.22 — the camera-position settings do what their NAMES say.
//
// Owner, 2026-09-20: "I'm not sure the different settings for where your
// camera will go on the livestream from iOS (which actually should be
// available on all platforms) are actually working as they should."
//
// `StudioLayout.rects` is SHARED by every Apple platform and is the only place
// the answer lives, so this asserts the geometry rather than photographing a
// screen: each layout must put the camera where its own label promises, the
// layouts must be DISTINGUISHABLE from one another, and none may sit on the
// lower third at bottom-left.
import Foundation
import CoreGraphics

@main
struct LayoutTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        let size = CGSize(width: 1280, height: 720)
        let camera16x9: CGFloat = 16.0 / 9.0
        print("=== 8.22 camera placement, 1280x720 program, 16:9 camera ===")

        var rects: [StudioLayout: (film: CGRect, camera: CGRect?)] = [:]
        for l in StudioLayout.allCases {
            let r = l.rects(in: size, cameraAspect: camera16x9)
            rects[l] = r
            let c = r.camera.map { "camera \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "no camera"
            print("        \(l.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) film \(Int(r.film.minX)),\(Int(r.film.minY)) \(Int(r.film.width))x\(Int(r.film.height))  \(c)")
        }

        // film — the only layout with no camera at all.
        check("8.22.1 film shows no camera", rects[.film]!.camera == nil)
        for l in StudioLayout.allCases where l != .film {
            check("8.22.2 \(l.rawValue) HAS a camera", rects[l]!.camera != nil)
        }

        // Every rect must be inside the frame.
        let frame = CGRect(origin: .zero, size: size)
        for (l, r) in rects {
            let inside = frame.contains(r.film) && (r.camera.map { frame.contains($0) } ?? true)
            check("8.22.3 \(l.rawValue) stays inside the frame", inside)
        }

        // The lower third lives at BOTTOM LEFT. No camera may land on it.
        let lowerThird = CGRect(x: 0, y: 0, width: size.width * 0.42, height: size.height * 0.22)
        for (l, r) in rects {
            // `host` is exempt BY DESIGN: the camera is the whole frame there,
            // so the lower third is composited over it like it is over the
            // film. An earlier version of this case failed host and the
            // assertion was wrong, not the product.
            guard let c = r.camera, l != .host else { continue }
            check("8.22.4 \(l.rawValue) keeps the camera off the lower third",
                  !c.intersects(lowerThird),
                  c.intersects(lowerThird) ? "overlaps \(lowerThird.intersection(c))" : "")
        }

        // side — the film takes the left two thirds, the camera the right third.
        let side = rects[.side]!
        check("8.22.5 side puts the film on the LEFT two thirds",
              side.film.minX == 0 && abs(side.film.width - size.width * 2 / 3) <= 1)
        check("8.22.6 side puts the camera in the RIGHT third",
              side.camera!.minX >= size.width * 2 / 3 - 1)

        // host — the camera IS the frame, the film is the inset.
        let host = rects[.host]!
        check("8.22.7 host gives the camera the whole frame", host.camera! == frame)
        check("8.22.8 host insets the film, top half", host.film.width < size.width / 2
              && host.film.minY > size.height / 2)

        // corner — bottom right, inset from both edges.
        let corner = rects[.corner]!.camera!
        check("8.22.9 corner sits bottom-right, inset from the edges",
              corner.minY > 0 && corner.maxX < size.width && corner.minX > size.width / 2)

        // THE ONE THE OWNER IS ASKING ABOUT. "Theatre row (you along the
        // bottom)" promises a ROW. A row is WIDE — otherwise it is `corner`
        // moved down, and a host who picks it sees no change worth the setting.
        let theatre = rects[.theatre]!.camera!
        check("8.22.10 theatre sits ON the bottom edge", theatre.minY == 0,
              "y=\(Int(theatre.minY))")
        check("8.22.11 theatre is a ROW — materially wider than corner",
              theatre.width >= corner.width * 1.35,
              "theatre \(Int(theatre.width))w vs corner \(Int(corner.width))w")
        check("8.22.12 theatre and corner are TELLABLE APART",
              abs(theatre.width - corner.width) > 1 || abs(theatre.height - corner.height) > 1,
              "theatre \(Int(theatre.width))x\(Int(theatre.height)) vs corner \(Int(corner.width))x\(Int(corner.height))")

        // Every camera rect distinct: a setting that changes nothing is not a setting.
        var seen: [String] = []
        for l in StudioLayout.allCases where l != .film {
            let c = rects[l]!.camera!
            let key = "\(Int(c.minX)),\(Int(c.minY)),\(Int(c.width)),\(Int(c.height))"
            check("8.22.13 \(l.rawValue) is a distinct placement", !seen.contains(key), key)
            seen.append(key)
        }

        print(failures == 0 ? "\n8.22 OK" : "\n8.22 \(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
