// §8.64 — Twitch's hourly /oauth2/validate: due on first use, then hourly,
// and ONLY a 401 ends a sign-in.
//
// The live half asks Twitch itself: a bogus token must come back 401 and read
// as revoked. The negative control is an unreachable host — no status at all —
// which must NOT read as revoked, or a Wi-Fi hiccup would sign a host out.

import Foundation

@main
struct TwitchValidate {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 }
    }

    static func status(_ url: String, _ auth: String) async -> Int? {
        var r = URLRequest(url: URL(string: url)!)
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 8
        return (try? await URLSession.shared.data(for: r)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
    }

    static func main() async {
        let clock = StudioValidationClock()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        check(await clock.isDue("twitch", now: t0), "due before any validation")
        await clock.mark("twitch", at: t0)
        check(!(await clock.isDue("twitch", now: t0.addingTimeInterval(3599))), "not due inside the hour")
        check(await clock.isDue("twitch", now: t0.addingTimeInterval(3600)), "due at the hour")
        check(await clock.isDue("youtube", now: t0), "platforms are clocked separately")

        check(StudioValidationClock.verdict(status: 200) == .valid, "200 is valid")
        check(StudioValidationClock.verdict(status: 503) == .unknown, "a 5xx does not revoke")
        check(StudioValidationClock.verdict(status: nil) == .unknown, "no answer does not revoke")

        let live = await status("https://id.twitch.tv/oauth2/validate", "OAuth notarealtoken0000000000000")
        if live == nil {
            print("SKIP: Twitch unreachable from here")
        } else {
            check(StudioValidationClock.verdict(status: live) == .revoked,
                  "Twitch answers a dead token \(live!) and it reads as revoked")
        }
        let dead = await status("https://id.twitch.invalid/oauth2/validate", "OAuth x")
        check(dead == nil && StudioValidationClock.verdict(status: dead) != .revoked,
              "control: an unreachable host leaves the sign-in alone")

        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
