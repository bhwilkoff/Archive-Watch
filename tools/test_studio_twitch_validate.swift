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

        // A refused REFRESH: only the platforms' own "the grant is gone"
        // answers clear a sign-in.
        check(StudioValidationClock.refreshWasRevoked(status: 400, json: ["error": "invalid_grant"]),
              "Google invalid_grant clears")
        check(StudioValidationClock.refreshWasRevoked(status: 400, json: ["status": 400, "message": "Invalid refresh token"]),
              "Twitch's invalid refresh token clears")
        check(!StudioValidationClock.refreshWasRevoked(status: 500, json: ["error": "invalid_grant"]),
              "a 500 keeps the sign-in")
        check(!StudioValidationClock.refreshWasRevoked(status: 400, json: ["error": "invalid_request"]),
              "a malformed request keeps the sign-in")
        check(!StudioValidationClock.refreshWasRevoked(status: nil, json: nil), "no answer keeps the sign-in")

        for (name, url, body) in [
            ("Google", "https://oauth2.googleapis.com/token", "client_id=\(ProcessInfo.processInfo.environment["AW_YOUTUBE_CLIENT_ID"] ?? "")&refresh_token=bogus0000&grant_type=refresh_token"),
            ("Twitch", "https://id.twitch.tv/oauth2/token", "client_id=\(ProcessInfo.processInfo.environment["AW_TWITCH_CLIENT_ID"] ?? "")&refresh_token=bogus0000&grant_type=refresh_token"),
        ] {
            // A REAL client id: with a made-up one Google answers 401
            // invalid_client, which is a different question (and must not
            // clear anyone's sign-in).
            let key = name == "Google" ? "AW_YOUTUBE_CLIENT_ID" : "AW_TWITCH_CLIENT_ID"
            if ProcessInfo.processInfo.environment[key] == nil {
                print("SKIP: \(name) refresh (set \(key))"); continue
            }
            var r = URLRequest(url: URL(string: url)!)
            r.httpMethod = "POST"; r.timeoutInterval = 8
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = body.data(using: .utf8)
            guard let (d, resp) = try? await URLSession.shared.data(for: r) else { print("SKIP: \(name) unreachable"); continue }
            let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            let st = (resp as? HTTPURLResponse)?.statusCode
            check(StudioValidationClock.refreshWasRevoked(status: st, json: j),
                  "\(name) refuses a dead refresh token (\(st ?? 0)) and it reads as revoked")
        }

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
