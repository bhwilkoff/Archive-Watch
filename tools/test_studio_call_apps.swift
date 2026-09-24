// §8.70 — which apps the Studio will capture (Decision 138): a call's apps and
// browsers; never a music or video player, which would carry its audio or its
// picture past the rights gate.
import Foundation

@main
struct CallApps {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 } }
        for id in ["us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams2", "com.hnc.Discord",
                   "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"] {
            check(StudioCallApps.kind(bundleID: id) == .call, "\(id) is a call")
        }
        for id in ["com.google.Chrome", "com.google.Chrome.helper", "com.apple.Safari", "org.mozilla.firefox"] {
            check(StudioCallApps.kind(bundleID: id) == .browser, "\(id) is a browser")
        }
        for id in ["com.apple.Music", "com.spotify.client", "org.videolan.vlc", "com.apple.TV",
                   "com.netflix.Netflix", "com.apple.QuickTimePlayerX"] {
            check(StudioCallApps.kind(bundleID: id) == .other, "\(id) is refused")
        }
        // Control: a look-alike prefix is not a match.
        check(StudioCallApps.kind(bundleID: "us.zoom.xosfake") == .other, "control: a look-alike prefix is refused")
        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
