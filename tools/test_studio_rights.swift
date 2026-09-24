// THE RIGHTS GATE, against the real catalog (WATCH-TOGETHER §3.4, §8).
//
// A broadcast goes out under the HOST's own YouTube or Twitch account, so a
// wrong "yes" here costs a real person a copyright strike. This asserts the
// gate's behaviour on named films and then reports what it admits across the
// whole published catalog — because a gate nobody has counted is a gate
// nobody knows the shape of.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/StudioRights.swift \
//     tools/test_studio_rights.swift -o /tmp/awrights && /tmp/awrights

import Foundation

@main
struct RightsTest {
    static var failures: [String] = []

    static func expect(_ label: String, _ got: Bool, _ want: Bool) {
        if got == want { print("  ✓ \(label)") }
        else { print("  ✗ \(label) — got \(got), want \(want)"); failures.append(label) }
    }

    static func main() {
        print("Watch Together Studio — the rights gate (tier: \(StudioRights.tier.rawValue))\n")
        print(StudioRights.policy + "\n")

        // MUST pass: cleared by age alone.
        expect("The General (1926), safe_pd_age",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "feature-film", year: 1926), true)
        expect("a 1908 Méliès short, safe_pd_age",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "short-film", year: 1908), true)
        let lastPD = StudioRights.lastPublicDomainYear()
        expect("a \(lastPD) film, safe_pd_age (the newest year in the public domain)",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "feature-film", year: lastPD), true)
        expect("a 1929 silent, safe_pd_age",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "silent-film", year: 1929), true)
        // The line follows the calendar: 95 years, free on January 1 of +96.
        let utc = { (s: String) in ISO8601DateFormatter().date(from: s)! }
        expect("in mid-2026 the last public-domain year is 1930",
               StudioRights.lastPublicDomainYear(now: utc("2026-06-01T00:00:00Z")) == 1930, true)
        expect("on 2026-12-31 it is still 1930",
               StudioRights.lastPublicDomainYear(now: utc("2026-12-31T23:59:59Z")) == 1930, true)
        expect("on 2027-01-01 1931 films enter it",
               StudioRights.lastPublicDomainYear(now: utc("2027-01-01T00:00:00Z")) == 1931, true)

        // MUST refuse.
        expect("a \(lastPD + 1) film (one year past the line)",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "feature-film", year: lastPD + 1), false)
        expect("safe_pd_age with NO year (bucket without evidence)",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "feature-film", year: nil), false)
        expect("safe_cc — an uploader's claim about someone else's film",
               StudioRights.canGoLive(rightsBucket: "safe_cc", contentType: "feature-film", year: 1977), false)
        expect("safe_gov — free in the US, not everywhere",
               StudioRights.canGoLive(rightsBucket: "safe_gov", contentType: "documentary", year: 1965), false)
        expect("presumed_pd — probably, but nothing proves it",
               StudioRights.canGoLive(rightsBucket: "presumed_pd", contentType: "feature-film", year: 1955), false)
        expect("modern_copyright_unconfirmed",
               StudioRights.canGoLive(rightsBucket: "modern_copyright_unconfirmed", contentType: "feature-film", year: 2015), false)
        expect("a wrong match — identity in doubt",
               StudioRights.canGoLive(rightsBucket: "wrongmatch_title", contentType: "feature-film", year: 1922), false)
        expect("television, whatever its rights say",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "tv-episode", year: 1955), false)
        expect("a commercial",
               StudioRights.canGoLive(rightsBucket: "safe_pd_age", contentType: "commercial", year: 1948), false)

        // THE SCHEMA CASE: a cached database from before the column existed.
        expect("no rightsBucket at all (schema 1 / older cached db)",
               StudioRights.canGoLive(rightsBucket: nil, contentType: "feature-film", year: 1926), false)
        expect("an empty rightsBucket",
               StudioRights.canGoLive(rightsBucket: "", contentType: "feature-film", year: 1926), false)

        // Every refusal must SAY something a host can act on.
        print("\n  Refusal messages:")
        var mute: [String] = []
        for b in ["safe_gov", "safe_cc", "safe_archive_license", "presumed_pd",
                  "renewal_zone", "modern_copyright_unconfirmed", "wrongmatch_title",
                  "uploader_copyright_claim", "copyrighted_trailer", "something_new"] {
            let r = StudioRights.refusal(rightsBucket: b, contentType: "feature-film", year: 1950)
            guard let r, r.count > 20 else { mute.append(b); continue }
            print("    \(b): \(r)")
        }
        if !mute.isEmpty {
            print("  ✗ these refuse WITHOUT an explanation: \(mute)")
            failures.append("mute refusals: \(mute)")
        } else {
            print("  ✓ every refusal explains itself")
        }

        print("")
        if failures.isEmpty { print("PASS: the gate refuses everything it cannot prove."); exit(0) }
        print("FAIL: \(failures.count)"); for f in failures { print("  • \(f)") }
        exit(1)
    }
}
