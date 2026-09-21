// §8.25 — the host's OUTPUT settings (macOS-DESIGN §D4).
//
// Resolution, frame rate and bitrate were hardcoded at 1920x1080 / 30 / 6 Mbps
// inside `StudioEngine.Configuration`, chosen for the host with no way to see
// or change them. Owner: "which inputs/outputs are being managed."
//
// The defect this guards is not "the picker does not move" — it is a stored
// ZERO. `UserDefaults.integer(forKey:)` returns 0 for a key that was never
// written, and 0 is a perfectly good Int. Read naively, a fresh install would
// configure an encoder at 0x0 and 0 bits per second, which fails in a way that
// looks exactly like a network fault (WATCH-TOGETHER §9 has three of those).
import Foundation

@main
struct StudioOutputTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        print("=== §8.25 Studio output settings ===")

        let d = UserDefaults.standard
        let keys = ["AWStudioOutWidth", "AWStudioOutHeight",
                    "AWStudioOutFrameRate", "AWStudioOutBitrateKbps"]
        let saved = keys.map { d.object(forKey: $0) }
        defer {
            for (k, v) in zip(keys, saved) {
                if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
            }
        }

        // 1. A NEVER-SET KEY IS NOT ZERO. This is the whole point of the type.
        for k in keys { d.removeObject(forKey: k) }
        check("unset width is 1920, not 0", StudioOutputSettings.width == 1920,
              "\(StudioOutputSettings.width)")
        check("unset height is 1080, not 0", StudioOutputSettings.height == 1080,
              "\(StudioOutputSettings.height)")
        check("unset frame rate is 30, not 0", StudioOutputSettings.frameRate == 30,
              "\(StudioOutputSettings.frameRate)")
        check("unset bitrate is 6000 kbps, not 0", StudioOutputSettings.bitrateKbps == 6000,
              "\(StudioOutputSettings.bitrateKbps)")

        // 2. A written value survives and is read back.
        StudioOutputSettings.width = 1280
        StudioOutputSettings.height = 720
        StudioOutputSettings.frameRate = 24
        StudioOutputSettings.bitrateKbps = 3000
        check("a chosen size reads back",
              StudioOutputSettings.width == 1280 && StudioOutputSettings.height == 720)
        check("a chosen frame rate reads back", StudioOutputSettings.frameRate == 24)
        check("a chosen bitrate reads back", StudioOutputSettings.bitrateKbps == 3000)
        check("selectedSize finds the chosen entry in the list",
              StudioOutputSettings.selectedSize.id == "1280x720",
              StudioOutputSettings.selectedSize.id)

        // 3. THE CONTROL for the zero rule: a real 0 written by hand must
        //    still not be served as 0, or the guard is indistinguishable from
        //    "the key happened to be absent".
        d.set(0, forKey: "AWStudioOutBitrateKbps")
        check("a stored ZERO bitrate is refused and falls back",
              StudioOutputSettings.bitrateKbps == 6000,
              "\(StudioOutputSettings.bitrateKbps)")

        // 4. Every offered size is 16:9, because the program frame is composed
        //    at 16:9 — a mismatched output letterboxes the whole show.
        for s in StudioOutputSettings.sizes {
            let ratio = Double(s.width) / Double(s.height)
            check("\(s.label) is 16:9", abs(ratio - 16.0 / 9.0) < 0.01,
                  String(format: "%.3f", ratio))
        }

        // 5. The bitrate list stops where the EVIDENCE stops. An Apple TV 4K
        //    drops 13 frames at 8 Mbps and 552 at 10 (WATCH-TOGETHER §9), so
        //    offering those would be offering a broken broadcast.
        check("no bitrate above 6000 kbps is offered",
              StudioOutputSettings.bitratesKbps.allSatisfy { $0 <= 6000 },
              "\(StudioOutputSettings.bitratesKbps)")
        check("the default bitrate is one the list offers",
              StudioOutputSettings.bitratesKbps.contains(6000))

        print(failures == 0 ? "=== §8.25 OK ===" : "=== §8.25 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
